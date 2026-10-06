import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var store: MonitorStore?
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.store?.stopAll(); Self.store?.saveNow(); return .terminateNow
    }
}

struct NopingyApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = MonitorStore()
    var body: some Scene {
        Window("nopingy", id: "monitor") {
            RootView().environmentObject(store).onAppear { AppDelegate.store = store }
        }.defaultSize(width: 1160, height: 860)
            .commands {
                CommandGroup(replacing: .newItem) {
                    Button("Add hosts…") { store.openAddHosts() }.keyboardShortcut("n")
                    Button("Import host list…") { store.importHosts() }.keyboardShortcut("o")
                    Button("Export hosts…") { store.exportHosts() }.keyboardShortcut("e", modifiers: [.command, .shift])
                    Button("Save host group…") { store.showSaveFavorite = true }.keyboardShortcut("s").disabled(store.demo || store.hosts.isEmpty)
                }
                CommandGroup(replacing: .appSettings) { Button("Settings…") { store.showSettings = true }.keyboardShortcut(",") }
                CommandMenu("Monitor") {
                    Button("Start all") { store.startAll() }.keyboardShortcut("r").disabled(store.demo)
                    Button("Stop all") { store.stopAll() }.keyboardShortcut(".")
                    Divider()
                    Button("Show monitor") { NotificationCenter.default.post(name: .showBoard, object: nil) }.keyboardShortcut("1")
                    Button("Status history") { NotificationCenter.default.post(name: .showHistory, object: nil) }.keyboardShortcut("2")
                    Button("Network tools…") { store.openTools() }.keyboardShortcut("t")
                }
            }
        MenuBarExtra { MenuBarView().environmentObject(store) } label: {
            Image(systemName: store.menuSymbol)
            if store.downCount > 0 { Text("\(store.downCount)") }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var store: MonitorStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("nopingy · \(store.runningCount) monitoring")
        Text("\(store.upCount) up · \(store.downCount) down · \(store.errorCount) errors")
        Divider()
        ForEach(store.hosts.prefix(20)) { host in
            Button("\(host.status.label) · \(host.definition.name)") { showWindow() }
        }
        Divider()
        Button("Open nopingy") { showWindow() }
        Button("Start all") { store.startAll() }.disabled(store.demo)
        Button("Stop all") { store.stopAll() }
        Divider()
        Button("Quit nopingy") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
    private func showWindow() { openWindow(id: "monitor"); NSApp.activate(ignoringOtherApps: true) }
}
