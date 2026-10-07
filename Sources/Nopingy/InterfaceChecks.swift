import AppKit
import Foundation
import NopingyCore
import UserNotifications

@MainActor private final class RecordingNotifications: StatusNotificationSending {
    var requests: [UNNotificationRequest] = []
    var authorizationRequests = 0
    var granted = true
    var authorizationError: Error?
    var deliveryError: Error?
    var deferAuthorization = false
    var pendingAuthorization: (@MainActor (Bool, Error?) -> Void)?

    func requestAuthorization(completion: @escaping @MainActor (Bool, Error?) -> Void) {
        authorizationRequests += 1
        if deferAuthorization { pendingAuthorization = completion }
        else { completion(granted, authorizationError) }
    }
    func send(_ request: UNNotificationRequest, completion: @escaping @MainActor (Error?) -> Void) {
        requests.append(request)
        completion(deliveryError)
    }
}

// Exercise our own view component and store without opening a window or
// contacting a host. Run with --check-interface after a build.
@MainActor enum InterfaceChecks {
    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func run() throws {
        _ = NSApplication.shared
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

        // Capture the requests at the macOS boundary: these checks never ask for
        // system permission, send a real notification, or contact a host.
        let notifications = RecordingNotifications()
        let alertURL = directory.appendingPathComponent("notification-state.json")
        let alertStore = MonitorStore(demo: false, stateURL: alertURL, arguments: [], notificationSender: notifications)
        try alertStore.add(HostDefinition.parseList("Example host = 127.0.0.1"), start: false)
        let host = alertStore.hosts[0]
        var settings = alertStore.settings; settings.notifications = true
        alertStore.applySettings(settings)
        try check(notifications.authorizationRequests == 1 && alertStore.settings.notifications, "Enabling notifications should request permission")
        alertStore.openSettings(tab: "notifications")
        try check(alertStore.showSettings && alertStore.settingsTab == "notifications", "The board control should open notification settings")
        alertStore.receive(ProbeResult(status: .up, latency: 1, detail: "Reply received"), host: host)
        try check(notifications.requests.isEmpty, "The initial result should establish a baseline without an alert")
        alertStore.receive(ProbeResult(status: .down, detail: "No reply before timeout"), host: host)
        try check(notifications.requests.count == 1, "Up to Down should send one notification")
        let outage = notifications.requests[0]
        try check(outage.content.title == "Example host is down", "A notification should identify the host and current status")
        try check(outage.content.body.contains("127.0.0.1 · Up → Down") && outage.content.body.contains("No reply before timeout"), "A notification should include the target, transition, and result")
        try check(outage.trigger == nil && outage.content.threadIdentifier == host.id.uuidString, "Status notifications should be immediate and grouped by host")
        alertStore.receive(ProbeResult(status: .down, detail: "No reply before timeout"), host: host)
        try check(notifications.requests.count == 1, "Repeated failures should not duplicate notifications")
        alertStore.receive(ProbeResult(status: .error, detail: "Could not resolve host"), host: host)
        alertStore.receive(ProbeResult(status: .up, latency: 2, detail: "Reply received"), host: host)
        try check(notifications.requests.count == 3, "Error and recovery transitions should each notify")
        try check(notifications.requests[2].content.body.contains("Error → Up"), "Recovery should show the previous and new states")
        try check(Set(notifications.requests.map(\.identifier)).count == 3, "Each transition should have its own notification identifier")
        host.running = true; alertStore.stop(host)
        try check(notifications.requests.count == 3, "Manual pausing should not send an outage alert")
        settings.notifications = false; alertStore.applySettings(settings)
        alertStore.receive(ProbeResult(status: .down, detail: "No reply"), host: host)
        try check(notifications.requests.count == 3, "Turning notifications off should suppress status alerts")
        notifications.granted = false; settings.notifications = true; alertStore.applySettings(settings)
        try check(!alertStore.settings.notifications && alertStore.error?.contains("System Settings → Notifications") == true, "Denied permission should turn alerts off and explain how to enable them")
        alertStore.saveNow()
        try check(try !StateFile(url: alertURL).load().settings.notifications, "Denied permission should not persist an enabled notification setting")
        alertStore.sendTestNotification()
        try check(notifications.requests.count == 3, "A denied test request must not send a notification")
        notifications.granted = true; alertStore.error = nil
        alertStore.sendTestNotification()
        try check(notifications.requests.last?.content.title == "nopingy notifications are ready", "The test button should send a recognizable notification after authorization")
        notifications.authorizationError = NSError(domain: "nopingy-checks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission service unavailable"])
        alertStore.applySettings(settings)
        try check(!alertStore.settings.notifications && alertStore.error?.contains("Permission service unavailable") == true, "Permission errors should be visible and leave alerts disabled")
        notifications.authorizationError = nil; notifications.deferAuthorization = true
        alertStore.applySettings(settings)
        let beforePermission = notifications.authorizationRequests
        alertStore.sendTestNotification()
        try check(alertStore.notificationRequestInProgress && notifications.authorizationRequests == beforePermission, "A pending authorization should prevent duplicate permission requests")
        notifications.pendingAuthorization?(true, nil); notifications.pendingAuthorization = nil
        try check(!alertStore.notificationRequestInProgress, "Completing authorization should clear the busy state")
        notifications.deliveryError = NSError(domain: "nopingy-checks", code: 2, userInfo: [NSLocalizedDescriptionKey: "Delivery unavailable"])
        alertStore.receive(ProbeResult(status: .up, detail: "Reply received"), host: host)
        try check(alertStore.error?.contains("Delivery unavailable") == true, "Delivery failures must not be silently ignored")
        alertStore.error = nil
        alertStore.receive(ProbeResult(status: .down, detail: "No reply"), host: host)
        try check(alertStore.error == nil, "Repeated delivery failures should not create repeated error dialogs")
        let demoNotifications = RecordingNotifications()
        let demoStore = MonitorStore(demo: true, stateURL: directory.appendingPathComponent("demo.json"), arguments: [], notificationSender: demoNotifications)
        demoStore.settings.notifications = true
        demoStore.receive(ProbeResult(status: .down, detail: "Sample timeout"), host: demoStore.hosts[0])
        demoStore.sendTestNotification()
        try check(demoNotifications.requests.isEmpty && demoNotifications.authorizationRequests == 0, "Demo mode must neither notify nor request permission")

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
