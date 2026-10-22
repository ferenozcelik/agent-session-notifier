import Foundation
import UserNotifications

/// macOS notifications. Each session has a single notification; a new one replaces the old.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// Called with the session id when a notification is clicked.
    @MainActor var onOpen: ((String) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func setup() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(sessionID: String, title: String, subtitle: String?, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle { content.subtitle = subtitle }
        content.body = body
        content.threadIdentifier = sessionID
        content.userInfo = ["sessionID": sessionID]
        if Prefs.bool(Prefs.sound) { content.sound = .default }
        center.add(UNNotificationRequest(identifier: sessionID, content: content, trigger: nil))
    }

    func clear(sessionID: String) {
        center.removeDeliveredNotifications(withIdentifiers: [sessionID])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        completionHandler()
        guard let sessionID else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onOpen?(sessionID) }
        }
    }
}
