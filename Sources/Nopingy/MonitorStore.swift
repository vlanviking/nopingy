import AppKit
import SwiftUI
import UserNotifications
import NopingyCore

@MainActor final class HostMonitor: ObservableObject, Identifiable {
    let id: UUID
    @Published var definition: HostDefinition
    @Published var status: ProbeStatus = .idle
    @Published var lastStatus: ProbeStatus = .idle
    @Published var running = false
    @Published var samples: [Sample] = []
    @Published var statistics = ProbeStatistics()
    @Published var started: Date?
    @Published var changed: Date?
    @Published var autoScroll = true
    var task: Task<Void, Never>?
    var generation = UUID()
    init(_ definition: HostDefinition) { self.definition = definition; id = definition.id }
    var latency: Double? { samples.last?.result.latency }
    func reset() { samples = []; statistics = ProbeStatistics() }
}

@MainActor final class MonitorStore: ObservableObject {
    @Published var hosts: [HostMonitor] = []
    @Published var settings = Settings()
    @Published var favorites: [Favorite] = []
    @Published var history: [HistoryEvent] = []
    @Published var error: String?
    @Published var activeGroup = "All hosts"
    @Published var revision = 0
    @Published var showAdd = false
    @Published var editing: HostMonitor?
    @Published var showSettings = false
    @Published var settingsTab = "probes"
    @Published private(set) var notificationRequestInProgress = false
    @Published var showSaveFavorite = false
    @Published var showTools = false
    @Published var toolHost = ""
    private let file: StateFile
    private var saveTask: Task<Void, Never>?
    private var persistenceEnabled = true
    private var logErrorReported = false
    private var notificationErrorReported = false
    private let notificationSender: StatusNotificationSending
    @Published private(set) var demo: Bool

    init(demo demoOverride: Bool? = nil, stateURL: URL? = nil, arguments argumentOverride: [String]? = nil,
         notificationSender: StatusNotificationSending? = nil) {
        self.notificationSender = notificationSender ?? MacStatusNotifications()
        demo = demoOverride ?? CommandLine.arguments.contains("--demo")
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("nopingy")
        file = StateFile(url: stateURL ?? directory.appendingPathComponent("state.json"))
        if demo { makeDemo(); persistenceEnabled = false; return }
        restoreSavedState()
        let arguments = argumentOverride ?? Array(CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") })
        if !arguments.isEmpty {
            var definitions: [HostDefinition] = []
            do {
                for argument in arguments {
                    if FileManager.default.fileExists(atPath: argument) {
                        definitions += try HostDefinition.parseList(String(contentsOfFile: argument, encoding: .utf8))
                    } else { definitions += try HostDefinition.parseList(argument) }
                }
                try add(definitions, start: true)
            } catch { self.error = error.localizedDescription }
        } else if settings.launchMonitoring {
            Task { startAll() }
        }
    }

    private func restoreSavedState() {
        do {
            let saved = try file.load()
            settings = saved.settings; favorites = saved.favorites; history = saved.history
            hosts = saved.hosts.map(HostMonitor.init)
        } catch {
            // Preserve an unreadable file rather than overwriting the user's data.
            persistenceEnabled = false
            self.error = "Your saved configuration could not be read. It is preserved at \(file.url.path). This session will not overwrite it. \(error.localizedDescription)"
        }
    }

    func enterLiveMode() {
        guard demo else { return }
        hosts.forEach { $0.task?.cancel() }
        hosts = []; history = []; favorites = []; settings = Settings()
        activeGroup = "All hosts"; demo = false; persistenceEnabled = true
        restoreSavedState()
        if settings.launchMonitoring { startAll() }
        revision += 1
    }
    func openAddHosts() { enterLiveMode(); showAdd = true }
    func openSettings(tab: String = "probes") { settingsTab = tab; showSettings = true }

    var runningCount: Int { hosts.filter(\.running).count }
    var upCount: Int { hosts.filter { $0.status == .up }.count }
    var downCount: Int { hosts.filter { $0.status == .down }.count }
    var errorCount: Int { hosts.filter { $0.status == .error }.count }
    var menuSymbol: String { downCount > 0 ? "network.slash" : errorCount > 0 ? "exclamationmark.circle" : "waveform.path" }

    func add(_ definitions: [HostDefinition], start: Bool) throws {
        enterLiveMode()
        guard hosts.count + definitions.count <= 128 else { throw TargetError.invalid("The board supports up to 128 hosts") }
        for definition in definitions {
            let host = HostMonitor(HostDefinition(target: definition.target, alias: definition.alias))
            hosts.append(host)
            if start { self.start(host) }
        }
        save()
    }

    func update(_ host: HostMonitor, definition: HostDefinition, start: Bool) {
        stop(host)
        host.definition = HostDefinition(id: host.id, target: definition.target, alias: definition.alias)
        host.reset(); host.status = .idle; host.lastStatus = .idle; host.changed = nil
        if start { self.start(host) }
        save()
    }

    func start(_ host: HostMonitor) {
        guard !demo, !host.running else { return }
        host.running = true; host.status = .checking; host.started = Date()
        host.generation = UUID()
        let generation = host.generation
        record(host, event: "started", detail: "Monitoring started")
        host.task = Task { [weak self, weak host] in
            guard let self, let host else { return }
            while !Task.isCancelled && host.running && host.generation == generation {
                let configuration = self.settings
                let beginning = Date()
                do {
                    let result = try await ProbeEngine.probe(host.definition.target, settings: configuration)
                    try Task.checkCancellation()
                    guard host.generation == generation else { return }
                    self.receive(result, host: host)
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled, host.generation == generation else { return }
                    self.receive(ProbeResult(status: .error, detail: error.localizedDescription), host: host)
                }
                if host.definition.target.kind == .traceroute {
                    host.running = false; host.task = nil
                    self.record(host, event: "finished", detail: "Traceroute completed")
                    self.revision += 1
                    return
                }
                let remaining = max(0.05, configuration.interval - Date().timeIntervalSince(beginning))
                do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
            }
        }
        revision += 1
    }

    func stop(_ host: HostMonitor) {
        guard !demo, host.running else { return }
        host.generation = UUID(); host.task?.cancel(); host.task = nil
        host.running = false; host.status = .idle
        record(host, event: "stopped", detail: "Monitoring stopped")
        revision += 1
    }
    func startAll() { hosts.forEach(start) }
    func stopAll() { hosts.forEach(stop) }
    func remove(_ host: HostMonitor) { stop(host); hosts.removeAll { $0.id == host.id }; save() }
    func move(_ host: HostMonitor, offset: Int) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }), hosts.indices.contains(index + offset) else { return }
        hosts.swapAt(index, index + offset); save()
    }

    func receive(_ result: ProbeResult, host: HostMonitor) {
        let previous = host.lastStatus
        host.status = result.status
        host.samples.append(Sample(result: result))
        if host.samples.count > 200 { host.samples.removeFirst(host.samples.count - 200) }
        host.statistics.record(result)
        if previous != result.status {
            host.changed = Date()
            record(host, event: result.status.rawValue, detail: result.detail)
            if [.up, .down, .error].contains(previous) && [.up, .down, .error].contains(result.status) {
                alert(host, previous: previous, result: result)
            }
        }
        host.lastStatus = result.status
        if settings.logMode == "all" { writeLog(host, event: "sample", detail: result.detail) }
        revision += 1
    }

    private func record(_ host: HostMonitor, event: String, detail: String) {
        history.append(HistoryEvent(name: host.definition.name, target: host.definition.target.address, event: event, detail: detail))
        if history.count > 2000 { history.removeFirst(history.count - 2000) }
        if settings.logMode != "off" { writeLog(host, event: event, detail: detail) }
        save()
    }

    private func writeLog(_ host: HostMonitor, event: String, detail: String) {
        guard !demo, !settings.logDirectory.isEmpty else { return }
        do {
            let directory = URL(fileURLWithPath: settings.logDirectory)
            let day = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
            let url = directory.appendingPathComponent("nopingy-\(day).csv")
            let row = HistoryEvent(name: host.definition.name, target: host.definition.target.address, event: event, detail: detail)
            let csv = CSV.history([row])
            if !FileManager.default.fileExists(atPath: url.path) { try Data(csv.utf8).write(to: url, options: .atomic) }
            else {
                let handle = try FileHandle(forWritingTo: url); defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(csv.components(separatedBy: "\r\n").dropFirst().joined(separator: "\r\n").utf8))
            }
            logErrorReported = false
        } catch {
            if !logErrorReported { self.error = "Log could not be written: \(error.localizedDescription)"; logErrorReported = true }
        }
    }

    private func alert(_ host: HostMonitor, previous: ProbeStatus, result: ProbeResult) {
        if settings.sound && !demo { NSSound(named: result.status == .up ? "Glass" : "Basso")?.play() }
        guard settings.notifications, !demo else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(host.definition.name) is \(result.status.rawValue)"
        content.body = "\(host.definition.target.address) · \(previous.label) → \(result.status.label)\n\(result.detail.prefix(160))"
        content.threadIdentifier = host.id.uuidString
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        sendNotification(request)
    }

    private func sendNotification(_ request: UNNotificationRequest) {
        notificationSender.send(request) { [weak self] failure in
            guard let self else { return }
            if let failure {
                if !self.notificationErrorReported {
                    self.error = "Notification could not be delivered: \(failure.localizedDescription)"
                    self.notificationErrorReported = true
                }
            } else { self.notificationErrorReported = false }
        }
    }

    func requestNotifications(completion: (@MainActor (Bool) -> Void)? = nil) {
        guard !demo else { return }
        guard !notificationRequestInProgress else { return }
        notificationRequestInProgress = true
        notificationSender.requestAuthorization { [weak self] granted, failure in
            guard let self else { return }
            self.notificationRequestInProgress = false
            if let failure { self.error = "Notifications could not be enabled: \(failure.localizedDescription)" }
            else if !granted { self.error = "Notifications are disabled. Enable nopingy in System Settings → Notifications, then turn on status notifications again." }
            if !granted || failure != nil {
                self.settings.notifications = false
                self.save()
            }
            completion?(granted && failure == nil)
        }
    }

    func sendTestNotification() {
        requestNotifications { [weak self] granted in
            guard let self, granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "nopingy notifications are ready"
            content.body = "You'll be notified when a monitored host changes between Up, Down, and Error."
            self.sendNotification(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    func applySettings(_ settings: NopingyCore.Settings) {
        var validated = settings; validated.validate()
        let enabling = !self.settings.notifications && validated.notifications
        self.settings = validated
        NSApp.windows.filter { $0.identifier?.rawValue == "nopingy-main" }.forEach { $0.level = validated.alwaysOnTop ? .floating : .normal }
        if enabling { requestNotifications() }
        save()
    }

    func save() {
        guard persistenceEnabled else { return }
        saveTask?.cancel()
        saveTask = Task {
            do { try await Task.sleep(nanoseconds: 300_000_000); try Task.checkCancellation(); saveNow() } catch { }
        }
    }
    func saveNow() {
        guard persistenceEnabled else { return }
        var state = SavedState()
        state.settings = settings; state.hosts = hosts.map(\.definition); state.favorites = favorites; state.history = history
        do { try file.save(state) } catch { self.error = "Configuration could not be saved: \(error.localizedDescription)" }
    }

    func saveFavorite(name: String) {
        guard !demo else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = favorites.firstIndex(where: { $0.name == trimmed }) { favorites[index].hosts = hosts.map(\.definition); favorites[index].columns = settings.columns }
        else { favorites.append(Favorite(name: trimmed, hosts: hosts.map(\.definition), columns: settings.columns)) }
        activeGroup = trimmed; save()
    }

    func loadFavorite(_ favorite: Favorite) {
        enterLiveMode()
        stopAll(); hosts = favorite.hosts.map { HostMonitor(HostDefinition(target: $0.target, alias: $0.alias)) }
        settings.columns = favorite.columns; settings.validate(); activeGroup = favorite.name
        startAll(); save()
    }
    func deleteFavorite(_ favorite: Favorite) { favorites.removeAll { $0.id == favorite.id }; save() }
    func clearHistory() { history = []; save() }

    func importHosts() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { importURL(url) }
    }
    func importURL(_ url: URL) {
        do { try add(HostDefinition.parseList(String(contentsOf: url, encoding: .utf8)), start: true) }
        catch { self.error = error.localizedDescription }
    }
    func export(text: String, filename: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = filename
        if panel.runModal() == .OK, let url = panel.url {
            do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = error.localizedDescription }
        }
    }
    func exportHosts() { export(text: hosts.map { $0.definition.inputLine }.joined(separator: "\n") + "\n", filename: "nopingy-hosts.txt") }
    func openTools(host: String = "") { enterLiveMode(); toolHost = host; showTools = true }

    private func makeDemo() {
        let definitions = try! HostDefinition.parseList("Gateway = 192.0.2.1\nCloudflare = 1.1.1.1\nWeb server = example.com:443\nLab switch = 192.0.2.20")
        hosts = definitions.map(HostMonitor.init)
        for (index, host) in hosts.enumerated() {
            host.running = false
            for tick in 0..<40 {
                let down = index == 3 && tick > 30
                let latency = index == 0 ? 1.2 + Double(tick % 5) * 0.2 : 14 + Double((tick * 7 + index) % 18)
                let result = ProbeResult(status: down ? .down : .up, latency: down ? nil : latency,
                                         detail: down ? "No reply before timeout" : "Reply received · \(String(format: "%.2f", latency)) ms")
                host.samples.append(Sample(date: Date().addingTimeInterval(Double(tick - 40)), result: result)); host.statistics.record(result)
            }
            host.status = index == 3 ? .down : .up; host.lastStatus = host.status; host.changed = Date().addingTimeInterval(-10)
        }
        activeGroup = "Example network · demo"
    }
}

extension Color {
    init(hex: String) {
        let number = UInt32(hex, radix: 16) ?? 0x36C98F
        self.init(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
    var hex: String {
        guard let color = NSColor(self).usingColorSpace(.deviceRGB) else { return "36C98F" }
        return String(format: "%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }
}

extension MonitorStore {
    func color(_ status: ProbeStatus) -> Color {
        switch status { case .up: return Color(hex: settings.upColor); case .down: return Color(hex: settings.downColor); case .error: return Color(hex: settings.errorColor); case .checking: return .cyan; case .idle: return .secondary }
    }
}
