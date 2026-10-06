import AppKit
import Foundation
import NopingyCore

// Exercise our own view component and store without opening a window or
// contacting a host. Run with --check-interface after a build.
@MainActor enum InterfaceChecks {
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run() throws {
        var assertions = 0
        func check(_ condition: Bool, _ message: String) throws {
            assertions += 1
            if !condition { throw Failure(message: message) }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        var saved = SavedState()
        saved.hosts = try HostDefinition.parseList("My saved host = 127.0.0.2")
        try StateFile(url: url).save(saved)
        let original = try Data(contentsOf: url)
        let store = MonitorStore(demo: true, stateURL: url, arguments: [])
        try check(store.demo && store.hosts.count == 4, "Demo should show four sample cards")
        try check(store.runningCount == 0, "Sample hosts must never count as active monitors")
        let counts = store.hosts.map { $0.samples.count }
        store.startAll(); store.stopAll()
        try check(store.hosts.allSatisfy { $0.task == nil && !$0.running }, "Start/stop must not launch a network task in demo mode")
        try check(store.hosts.map { $0.samples.count } == counts, "Sample replies should remain unchanged")
        store.saveNow()
        try check(try Data(contentsOf: url) == original, "Demo must not overwrite saved hosts")
        try store.add(HostDefinition.parseList("New host = 127.0.0.1"), start: false)
        try check(!store.demo, "Adding a host must leave demo mode")
        try check(store.hosts.map { $0.definition.name } == ["My saved host", "New host"], "Live mode must restore user hosts and exclude sample hosts")
        try check(store.hosts.allSatisfy { $0.samples.isEmpty && $0.statistics.sent == 0 }, "Live mode must not inherit sample statistics")
        try check(store.activeGroup == "All hosts", "Live mode must remove the demo label")
        store.saveNow()
        try check(try StateFile(url: url).load().hosts.count == 2, "Live hosts should be persisted")

        let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 350, height: 180))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 350, height: 1200))
        outer.documentView = document
        let log = ReplyLogScrollView()
        log.frame = NSRect(x: 10, y: 400, width: 300, height: 80)
        document.addSubview(log)
        outer.contentView.scroll(to: NSPoint(x: 0, y: 240))
        let before = outer.contentView.bounds.origin
        log.textView.string = (0..<50).map { "Reply \($0) · 1.23 ms" }.joined(separator: "\n")
        log.layoutSubtreeIfNeeded(); log.resizeDocumentAndFollow()
        try check(log.contentView.bounds.origin.y > 0, "A full log should scroll to its latest reply")
        try check(outer.contentView.bounds.origin == before, "Following replies must not move the parent grid")
        log.followTail = false
        log.contentView.scroll(to: NSPoint(x: 0, y: 20))
        let paused = log.contentView.bounds.origin
        log.textView.string += "\nAnother reply"
        log.resizeDocumentAndFollow()
        try check(log.contentView.bounds.origin == paused, "Paused log scrolling must preserve the inspected position")
        log.followTail = true
        log.resizeDocumentAndFollow()
        try check(log.contentView.bounds.origin.y > paused.y, "Resuming should follow the log tail")
        try check(outer.contentView.bounds.origin == before, "Resuming must leave the parent grid stationary")
        print("Interface regressions · \(assertions) assertions · 0 failures")
    }
}
