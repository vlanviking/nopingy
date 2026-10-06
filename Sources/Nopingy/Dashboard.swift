import SwiftUI
import AppKit
import NopingyCore
import UniformTypeIdentifiers

// Explicit alias keeps the macOS 13 property wrapper when newer SDKs also
// export a same-named State macro that requires the full Xcode toolchain.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Theme {
    static let background = Color(hex: "11151B")
    static let panel = Color(hex: "1A2029")
    static let line = Color.white.opacity(0.08)
    static let accent = Color(hex: "36C98F")
}

struct RootView: View {
    @EnvironmentObject var store: MonitorStore
    @ViewState private var page = "board"
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 195)
            Rectangle().fill(Theme.line).frame(width: 1)
            VStack(spacing: 0) {
                if page == "history" { HistoryView() } else { BoardView() }
                footer
            }
        }
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 800, minHeight: 600)
        .background(WindowConfigurator(alwaysOnTop: store.settings.alwaysOnTop))
        .sheet(isPresented: $store.showAdd) { HostEditor() }
        .sheet(item: $store.editing) { host in HostEditor(host: host) }
        .sheet(isPresented: $store.showSettings) { SettingsView() }
        .sheet(isPresented: $store.showSaveFavorite) { SaveFavoriteView() }
        .sheet(isPresented: $store.showTools) { ToolsView(initialHost: store.toolHost) }
        .alert("nopingy", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .showHistory)) { _ in page = "history" }
        .onReceive(NotificationCenter.default.publisher(for: .showBoard)) { _ in page = "board" }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in store.importURL(url) } }
            }
            return true
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "waveform.path").font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.accent)
                Text("nopingy").font(.system(size: 22, weight: .bold, design: .rounded))
            }.padding(.top, 30).padding(.bottom, 6)
            Text("A little network peace of mind.").font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 32)
            sideButton("Monitor", icon: "square.grid.2x2", selected: page == "board") { page = "board" }
            sideButton("Status history", icon: "clock.arrow.circlepath", selected: page == "history") { page = "history" }
            sideButton("Network tools", icon: "wrench.and.screwdriver", selected: false) { store.openTools() }
            HStack {
                Text("SAVED GROUPS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { store.showSaveFavorite = true } label: { Image(systemName: "plus") }.buttonStyle(.plain).help("Save current hosts as a group").disabled(store.demo)
            }.padding(.top, 30).padding(.bottom, 12).padding(.horizontal, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    if store.favorites.isEmpty {
                        Text("Save a group to bring your\nhosts back in one click.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4).padding(10)
                    }
                    ForEach(store.favorites) { favorite in
                        Button { store.loadFavorite(favorite); page = "board" } label: {
                            HStack { Image(systemName: "folder"); Text(favorite.name).lineLimit(1); Spacer(); Text("\(favorite.hosts.count)").foregroundStyle(.secondary) }
                                .font(.system(size: 12)).padding(10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Load group") { store.loadFavorite(favorite); page = "board" }
                                Button("Export hosts…") { store.export(text: favorite.hosts.map(\.inputLine).joined(separator: "\n"), filename: "\(favorite.name).txt") }
                                Button("Delete group", role: .destructive) { store.deleteFavorite(favorite) }
                            }
                    }
                }
            }
            Spacer(minLength: 10)
            sideButton("Settings", icon: "slider.horizontal.3", selected: false) { store.showSettings = true }
            HStack(spacing: 6) {
                Circle().fill(store.runningCount > 0 ? Theme.accent : .secondary).frame(width: 5, height: 5)
                Text(store.demo ? "DEMO · SAMPLE DATA" : "\(store.runningCount) ACTIVE MONITORS").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 24)
        }.padding(.horizontal, 16).background(Color(hex: "151A22"))
    }

    private func sideButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) { Image(systemName: icon).frame(width: 17); Text(title); Spacer() }
                .font(.system(size: 12, weight: selected ? .semibold : .regular)).padding(.horizontal, 10).padding(.vertical, 11)
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
                .background(selected ? Theme.accent.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private var footer: some View {
        HStack(spacing: 16) {
            Text(store.demo ? "Demo data · no live probes" : "\(store.hosts.count) hosts · \(store.runningCount) monitoring")
            Spacer()
            Text("Interval \(store.settings.interval.formatted())s").help("Time between probe starts; a slow probe finishes before the next begins")
            Text("Timeout \(store.settings.timeout.formatted())s")
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

struct BoardView: View {
    @EnvironmentObject var store: MonitorStore
    @ViewState private var search = ""
    @ViewState private var filter = "all"
    private var filtered: [HostMonitor] {
        store.hosts.filter { host in
            (filter == "all" || host.status.rawValue == filter) &&
            (search.isEmpty || "\(host.definition.name) \(host.definition.target.address)".localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Network monitor").font(.system(size: 25, weight: .semibold))
                    Text(store.activeGroup).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.openAddHosts() } label: { Label("Add hosts", systemImage: "plus") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(Color.black).controlSize(.large)
            }.padding(.bottom, 24)
            if store.demo {
                HStack {
                    Text("Sample network · no live probes").foregroundStyle(.secondary)
                    Spacer()
                    Button("Use live monitoring") { store.enterLiveMode() }
                }.font(.system(size: 11)).padding(12)
                    .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 7)).padding(.bottom, 18)
            }
            HStack(spacing: 16) {
                countBadge("Up", count: store.upCount, status: .up)
                countBadge("Down", count: store.downCount, status: .down)
                countBadge("Error", count: store.errorCount, status: .error)
                Spacer()
                Button { store.startAll() } label: { Label("Start all", systemImage: "play.fill") }.disabled(store.demo || store.hosts.isEmpty || store.runningCount == store.hosts.count)
                Button { store.stopAll() } label: { Label("Stop all", systemImage: "pause.fill") }.disabled(store.runningCount == 0)
                Menu {
                    ForEach(1...4, id: \.self) { count in
                        Button("\(count) column\(count == 1 ? "" : "s")") { var settings = store.settings; settings.columns = count; store.applySettings(settings) }
                    }
                } label: { Image(systemName: "rectangle.split.2x2") }.menuStyle(.borderlessButton).frame(width: 24).help("Choose columns")
            }.font(.system(size: 11)).buttonStyle(.borderless).padding(.bottom, 22)
            HStack {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a host", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(9).background(Theme.panel, in: RoundedRectangle(cornerRadius: 6)).frame(maxWidth: 260)
                Spacer()
                Picker("Status", selection: $filter) {
                    Text("All statuses").tag("all")
                    ForEach(ProbeStatus.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }.labelsHidden().frame(width: 135)
            }.font(.system(size: 11)).padding(.bottom, 18)
            if store.hosts.isEmpty { emptyState }
            else if filtered.isEmpty {
                VStack(spacing: 12) { Image(systemName: "magnifyingglass").font(.largeTitle); Text("No matching hosts"); Button("Clear filters") { search = ""; filter = "all" } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.secondary)
            } else {
                GeometryReader { geometry in
                    let count = max(1, min(store.settings.columns, Int((geometry.size.width + 14) / 320)))
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: count), spacing: 14) {
                            ForEach(filtered) { host in HostCard(host: host) }
                        }.padding(.bottom, 20)
                    }
                }
            }
        }.padding(.horizontal, 24).padding(.top, 27)
    }
    private func countBadge(_ title: String, count: Int, status: ProbeStatus) -> some View {
        HStack(spacing: 6) { Circle().fill(store.color(status)).frame(width: 6, height: 6); Text("\(count)").fontWeight(.semibold); Text(title).foregroundStyle(.secondary) }
    }
    private var emptyState: some View {
        VStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(Theme.accent.opacity(0.06)).frame(width: 95, height: 95)
                Image(systemName: "waveform.path").font(.system(size: 37, weight: .light)).foregroundStyle(Theme.accent)
            }
            Text("Every host, at a glance.").font(.system(size: 20, weight: .medium))
            Text("Add an IP address, hostname, or TCP port.\nWatch replies, latency, and outages as they happen.")
                .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Button("Add your first hosts") { store.openAddHosts() }.buttonStyle(.borderedProminent).tint(Theme.accent).foregroundStyle(.black).padding(.top, 6)
            Button("Import a host list…") { store.importHosts() }.buttonStyle(.borderless).font(.system(size: 12))
            Text("Try 127.0.0.1 · example.com:443 · [::1]:80").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary).padding(.top, 10)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HostCard: View {
    @EnvironmentObject var store: MonitorStore
    @ObservedObject var host: HostMonitor
    private var color: Color { store.color(host.status) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(host.definition.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                    Text(host.definition.target.address).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Text(host.definition.target.kind.label).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 4).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                Menu {
                    Button(host.running ? "Stop" : "Start") { host.running ? store.stop(host) : store.start(host) }
                    Button("Edit host…") { store.editing = host }
                    Button("Reset statistics") { host.reset() }
                    Button("Network tools…") { store.openTools(host: host.definition.target.host) }
                    Button("Copy address") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(host.definition.target.address, forType: .string) }
                    Button("Export replies…") { store.export(text: host.samples.map { "\($0.date.formatted())\t\($0.result.status.rawValue)\t\($0.result.detail)" }.joined(separator: "\n"), filename: "nopingy-replies.txt") }
                    Divider()
                    Button("Move earlier") { store.move(host, offset: -1) }
                    Button("Move later") { store.move(host, offset: 1) }
                    Divider()
                    Button("Remove host", role: .destructive) { store.remove(host) }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 16).help("Host actions").disabled(store.demo)
            }.padding(16)
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) { Circle().fill(color).frame(width: 7, height: 7); Text(host.status.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(color) }
                Spacer()
                Text(host.latency.map { String(format: "%.2f", $0) } ?? "—").font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                Text("ms").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16)
            Sparkline(samples: Array(host.samples.suffix(50)), color: color).frame(height: 37).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 13)
            HStack {
                statistic("Sent", value: "\(host.statistics.sent)")
                Spacer()
                statistic("Lost", value: "\(host.statistics.lost)")
                Spacer()
                statistic("Loss", value: String(format: "%.1f%%", host.statistics.loss))
                Spacer()
                statistic("Avg", value: host.statistics.average.map { String(format: "%.1f ms", $0) } ?? "—")
            }.padding(.horizontal, 16).padding(.bottom, 13)
            Rectangle().fill(Theme.line).frame(height: 1)
            ReplyLogView(samples: Array(host.samples.suffix(50)), autoScroll: host.autoScroll,
                         emptyMessage: host.running ? "Waiting for the first reply…" : "Ready when you are.",
                         downColor: NSColor(store.color(.down)), errorColor: NSColor(store.color(.error)))
                .frame(height: 80).background(Color.black.opacity(0.13))
            HStack {
                Button { host.running ? store.stop(host) : store.start(host) } label: {
                    Label(store.demo ? "Sample replies" : host.running ? "Pause" : "Start", systemImage: store.demo ? "eye" : host.running ? "pause.fill" : "play.fill")
                }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(store.demo)
                Spacer()
                Button { host.autoScroll.toggle() } label: { Image(systemName: host.autoScroll ? "arrow.down.to.line" : "hand.raised") }.buttonStyle(.plain).foregroundStyle(host.autoScroll ? Color.secondary : Theme.accent).help(host.autoScroll ? "Pause automatic scrolling to inspect replies" : "Resume automatic scrolling")
                if let changed = host.changed { Text(changed, style: .relative).foregroundStyle(.tertiary).lineLimit(1) }
            }.font(.system(size: 9)).padding(.horizontal, 14).padding(.vertical, 10)
        }.fixedSize(horizontal: false, vertical: true)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(host.status == .idle ? 0.15 : 0.35), lineWidth: 1) }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func statistic(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 9)).foregroundStyle(.secondary); Text(value).font(.system(size: 11, weight: .medium, design: .monospaced)) }
    }
}

struct Sparkline: View {
    let samples: [Sample]
    let color: Color
    var body: some View {
        Canvas { context, size in
            var baseline = Path(); baseline.move(to: CGPoint(x: 0, y: size.height - 1)); baseline.addLine(to: CGPoint(x: size.width, y: size.height - 1))
            context.stroke(baseline, with: .color(.white.opacity(0.06)), lineWidth: 1)
            guard samples.count > 1 else { return }
            let maximum = max(1, samples.compactMap { $0.result.latency }.max() ?? 1) * 1.2
            var path = Path(); var connected = false
            for (index, sample) in samples.enumerated() {
                let x = Double(index) / Double(samples.count - 1) * size.width
                if let latency = sample.result.latency {
                    let point = CGPoint(x: x, y: size.height - 3 - latency / maximum * (size.height - 5))
                    if connected { path.addLine(to: point) } else { path.move(to: point); connected = true }
                } else {
                    connected = false
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.5, y: size.height - 4, width: 3, height: 3)), with: .color(color.opacity(0.7)))
                }
            }
            context.stroke(path, with: .color(color.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }.accessibilityLabel("Latency history, last \(samples.count) checks")
    }
}

struct HistoryView: View {
    @EnvironmentObject var store: MonitorStore
    @ViewState private var search = ""
    @ViewState private var filter = "all"
    @ViewState private var confirmClear = false
    private var events: [HistoryEvent] {
        store.history.reversed().filter { event in
            (filter == "all" || event.event == filter) && (search.isEmpty || "\(event.name) \(event.target) \(event.detail)".localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text("Status history").font(.system(size: 25, weight: .semibold)); Text("Starts, stops, and state changes · last 2,000 events").font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
                Button("Export CSV…") { store.export(text: CSV.history(events.reversed()), filename: "nopingy-history.csv") }.disabled(events.isEmpty)
                Button { confirmClear = true } label: { Image(systemName: "trash") }.disabled(store.history.isEmpty).help("Clear history")
            }
            HStack {
                TextField("Filter by name, address, or message", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 340)
                Spacer()
                Picker("Event", selection: $filter) {
                    Text("All events").tag("all")
                    ForEach(["up", "down", "error", "started", "stopped", "finished"], id: \.self) { Text($0.capitalized).tag($0) }
                }.frame(width: 150)
            }.font(.system(size: 12))
            if events.isEmpty {
                VStack(spacing: 14) { Image(systemName: "clock.arrow.circlepath").font(.system(size: 35)); Text("No events to show"); Text("Host state changes will appear here.").font(.system(size: 12)) }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 16) {
                                Text(event.date.formatted(.dateTime.month().day().hour().minute().second())).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                                Text(event.event.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(store.color(ProbeStatus(rawValue: event.event) ?? .idle)).frame(width: 60, alignment: .leading)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(event.name).font(.system(size: 12, weight: .medium))
                                    Text("\(event.target) · \(event.detail)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.vertical, 14).padding(.horizontal, 16).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
                        }
                    }
                }.background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(24)
            .confirmationDialog("Clear all status history?", isPresented: $confirmClear) { Button("Clear history", role: .destructive) { store.clearHistory() } }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    var alwaysOnTop: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier("nopingy-main")
            window.title = "nopingy"
            window.level = alwaysOnTop ? .floating : .normal
            window.backgroundColor = NSColor(Theme.background)
        }
    }
}

extension Notification.Name {
    static let showHistory = Notification.Name("nopingy.showHistory")
    static let showBoard = Notification.Name("nopingy.showBoard")
}
