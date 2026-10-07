import SwiftUI
import AppKit
import NopingyCore

struct HostEditor: View {
    @EnvironmentObject var store: MonitorStore
    @Environment(\.dismiss) private var dismiss
    let host: HostMonitor?
    @ViewState private var text: String
    @ViewState private var start: Bool
    @ViewState private var error: String?
    init(host: HostMonitor? = nil) {
        self.host = host
        _text = State(initialValue: host?.definition.inputLine ?? "")
        _start = State(initialValue: host?.running ?? true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(host == nil ? "Add hosts" : "Edit host").font(.system(size: 22, weight: .semibold))
            Text("One host per line, or separate hosts with commas. Add a friendly name with “name = target”.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden)
                .padding(10).background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).stroke(Theme.line) }.frame(height: 180)
            VStack(alignment: .leading, spacing: 6) {
                Text("Example host = 192.0.2.1").font(.system(size: 11, design: .monospaced))
                Text("example.com:443   ·   [::1]:80   ·   D/example.com   ·   T/example.com").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.secondary)
            Toggle("Start monitoring immediately", isOn: $start).font(.system(size: 12))
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            HStack {
                if host == nil { Button("Import text file…") { dismiss(); store.importHosts() } }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(host == nil ? "Add hosts" : "Save") {
                    do {
                        let definitions = try HostDefinition.parseList(text)
                        guard !definitions.isEmpty else { return }
                        if let host {
                            guard definitions.count == 1 else { error = "Enter one host when editing."; return }
                            store.update(host, definition: definitions[0], start: start)
                        } else { try store.add(definitions, start: start) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 540).background(Theme.panel).preferredColorScheme(.dark)
    }
}

struct SaveFavoriteView: View {
    @EnvironmentObject var store: MonitorStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Save a host group").font(.system(size: 22, weight: .semibold))
            Text("Keep these \(store.hosts.count) hosts, their aliases, and your column layout.").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Group name", text: $name).textFieldStyle(.roundedBorder)
            if store.favorites.contains(where: { $0.name == name.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                Text("This will replace the existing group with this name.").font(.system(size: 11)).foregroundStyle(.orange)
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Button("Save group") { store.saveFavorite(name: name); dismiss() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.hosts.isEmpty) }
        }.padding(28).frame(width: 420).background(Theme.panel).preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: MonitorStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var settings = NopingyCore.Settings()
    @ViewState private var tab = "probes"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.system(size: 22, weight: .semibold))
            TabView(selection: $tab) {
                Form {
                    Section("Probe timing") {
                        numeric("Interval (seconds)", value: $settings.interval)
                        numeric("Timeout (seconds)", value: $settings.timeout)
                        Text("Interval: 0.25–60 seconds. Timeout: 0.25–30 seconds. Each host runs one probe at a time.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Section("ICMP packets") {
                        TextField("TTL / hop limit", value: $settings.ttl, format: .number.grouping(.never))
                        TextField("Payload (bytes)", value: $settings.packetSize, format: .number.grouping(.never))
                        Text("TTL: 1–255. Payload: 0–65,000 bytes. TCP and DNS checks use the timeout only.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Section("On launch") { Toggle("Start monitoring saved hosts", isOn: $settings.launchMonitoring) }
                }.formStyle(.grouped).tabItem { Text("Probes") }.tag("probes")
                Form {
                    Section("Display") {
                        Toggle("Keep monitor window on top", isOn: $settings.alwaysOnTop)
                        Picker("Columns", selection: $settings.columns) { ForEach(1...4, id: \.self) { Text("\($0)").tag($0) } }
                        ColorPicker("Up", selection: colorBinding(\.upColor), supportsOpacity: false)
                        ColorPicker("Down", selection: colorBinding(\.downColor), supportsOpacity: false)
                        ColorPicker("Error", selection: colorBinding(\.errorColor), supportsOpacity: false)
                    }
                }.formStyle(.grouped).tabItem { Text("Display") }.tag("display")
                Form {
                    Section("Status notifications") {
                        Toggle("Notify when a host changes status", isOn: $settings.notifications).disabled(store.demo)
                        Toggle("Play a sound", isOn: $settings.sound)
                        Text("Alerts show the host, target, and change between Up, Down, and Error. The first result, repeated results, and pausing do not trigger alerts.").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button(store.notificationRequestInProgress ? "Requesting permission…" : "Send test notification") { store.sendTestNotification() }
                            .disabled(store.demo || !settings.notifications || store.notificationRequestInProgress)
                    }
                    Section("Mac permission") {
                        Text("Click Apply, then allow notifications when macOS asks. If blocked, enable nopingy in System Settings → Notifications. Focus settings may silence banners.").font(.system(size: 11)).foregroundStyle(.secondary)
                        if store.demo { Text("Notifications are unavailable in demo mode. Switch to live monitoring first.").font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                }.formStyle(.grouped).tabItem { Text("Notifications") }.tag("notifications")
                Form {
                    Section("CSV files") {
                        Picker("Record", selection: $settings.logMode) {
                            Text("Off").tag("off"); Text("Status changes").tag("changes"); Text("Every result and status change").tag("all")
                        }
                        HStack {
                            Text(settings.logDirectory.isEmpty ? "Choose a log folder" : settings.logDirectory).font(.system(size: 11)).lineLimit(2).textSelection(.enabled)
                            Spacer(); Button("Choose…") { chooseLogFolder() }
                        }
                        Text("One CSV file per day. Status history is also saved automatically and can be exported from the history screen.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Section("About nopingy") {
                        Text("Version 1.0.2 · Native macOS network monitor").font(.system(size: 12))
                        Link("Inspired by Ryan Smith’s vmPing (MIT)", destination: URL(string: "https://github.com/r-smith/vmPing")!).font(.system(size: 11))
                        Text("Hosts and settings are stored in Application Support/nopingy. The app keeps monitoring when its window closes; quit from the menu to stop.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped).tabItem { Text("Logs & about") }.tag("logs")
            }.frame(height: 365)
            HStack {
                Button("Reset settings") { settings = Settings() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply") { store.applySettings(settings); dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black)
                    .disabled(settings.logMode != "off" && settings.logDirectory.isEmpty)
            }
        }.padding(24).frame(width: 560).background(Theme.panel).preferredColorScheme(.dark).onAppear { settings = store.settings; tab = store.settingsTab }
    }
    private func numeric(_ label: String, value: Binding<Double>) -> some View {
        TextField(label, value: value, format: .number.precision(.fractionLength(0...2)))
    }
    private func colorBinding(_ key: WritableKeyPath<NopingyCore.Settings, String>) -> Binding<Color> {
        Binding(get: { Color(hex: settings[keyPath: key]) }, set: { settings[keyPath: key] = $0.hex })
    }
    private func chooseLogFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { settings.logDirectory = url.path }
    }
}

struct ToolsView: View {
    @EnvironmentObject var store: MonitorStore
    @Environment(\.dismiss) private var dismiss
    let initialHost: String
    @ViewState private var host = ""
    @ViewState private var tool = "dns"
    @ViewState private var output = ""
    @ViewState private var running = false
    @ViewState private var count = 50
    @ViewState private var interval = 0.2
    @ViewState private var task: Task<Void, Never>?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Network tools").font(.system(size: 22, weight: .semibold)); Spacer(); if running { ProgressView().controlSize(.small) } }
            Picker("Tool", selection: $tool) { Text("DNS lookup").tag("dns"); Text("Traceroute").tag("trace"); Text("Ping burst").tag("burst") }.pickerStyle(.segmented).disabled(running)
            HStack { TextField("Hostname or IP address", text: $host).textFieldStyle(.roundedBorder).disabled(running); Button(running ? "Cancel" : "Run") { if running { cancel() } else { run() } }.disabled(host.isEmpty).keyboardShortcut(.defaultAction) }
            if tool == "burst" {
                HStack {
                    Picker("Packets", selection: $count) { ForEach([10, 50, 100, 500, 1000], id: \.self) { Text("\($0)").tag($0) } }.frame(width: 180)
                    Picker("Interval", selection: $interval) { Text("0.2 seconds").tag(0.2); Text("0.5 seconds").tag(0.5); Text("1 second").tag(1.0) }.frame(width: 200)
                }.disabled(running).font(.system(size: 12))
                Text("Send a finite series of ICMP packets and view loss and timing statistics. Uses your payload and TTL settings.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text(tool == "dns" ? "Forward A/AAAA records or reverse lookup for an IP address." : "One probe per hop, up to 30 hops. Stops after 45 seconds. Asterisks indicate hops that did not reply.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView {
                Text(output.isEmpty ? "Results will appear here." : output).font(.system(size: 12, design: .monospaced)).foregroundStyle(output.isEmpty ? .secondary : .primary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(14)
            }.frame(height: 270).background(Theme.background, in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("Export…") { store.export(text: output, filename: "nopingy-\(tool).txt") }.disabled(output.isEmpty || running)
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string) }.disabled(output.isEmpty)
                Spacer(); Button("Done") { cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(26).frame(width: 620).background(Theme.panel).preferredColorScheme(.dark)
            .onAppear { host = initialHost }.onDisappear { task?.cancel() }
    }
    private func cancel() { task?.cancel(); task = nil; running = false; output += "\nCancelled." }
    private func run() {
        do {
            let target = try Target.parse(host)
            running = true; output = "Running \(tool == "trace" ? "traceroute" : tool == "burst" ? "ping burst" : "DNS lookup") for \(target.host)…\n"
            let settings = store.settings
            task = Task {
                do {
                    let result: String
                    if tool == "dns" { result = try await ProbeEngine.dns(target.host, timeout: settings.timeout).detail }
                    else if tool == "trace" {
                        let response = try await ProbeEngine.trace(target.host)
                        result = response.text + (response.timedOut ? "\nStopped after 45 seconds." : "")
                    } else { result = try await ProbeEngine.burst(target.host, settings: settings, count: count, interval: interval).text }
                    try Task.checkCancellation(); output = result; running = false; task = nil
                } catch is CancellationError { }
                catch { output = error.localizedDescription; running = false; task = nil }
            }
        } catch { output = error.localizedDescription }
    }
}
