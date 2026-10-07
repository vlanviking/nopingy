import Foundation
import UserNotifications

@MainActor protocol StatusNotificationSending {
    func requestAuthorization(completion: @escaping @MainActor (Bool, Error?) -> Void)
    func send(_ request: UNNotificationRequest, completion: @escaping @MainActor (Error?) -> Void)
}

// macOS otherwise keeps notifications silent when the app is in the foreground.
private final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

@MainActor final class MacStatusNotifications: StatusNotificationSending {
    private let delegate = ForegroundNotificationDelegate()
    private struct BundleRequired: LocalizedError {
        var errorDescription: String? { "Open nopingy.app to enable macOS notifications." }
    }

    private func center() throws -> UNUserNotificationCenter {
        guard Bundle.main.bundleIdentifier != nil else { throw BundleRequired() }
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        return center
    }

    func requestAuthorization(completion: @escaping @MainActor (Bool, Error?) -> Void) {
        do {
            try center().requestAuthorization(options: [.alert, .sound]) { granted, error in
                Task { @MainActor in completion(granted, error) }
            }
        } catch { completion(false, error) }
    }

    func send(_ request: UNNotificationRequest, completion: @escaping @MainActor (Error?) -> Void) {
        do {
            try center().add(request) { error in
                Task { @MainActor in completion(error) }
            }
        } catch { completion(error) }
    }
}
