import AppKit
import UserNotifications
import CryptoKit

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var onAction: (([String: Any]) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(identifier: "REPLY", title: "Ответить", options: [], textInputButtonTitle: "Отправить", textInputPlaceholder: "Сообщение")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "PHONE_REPLY", actions: [reply], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: "PHONE", actions: [], intentIdentifiers: [], options: [.customDismissAction])
        ])
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void) {
        completion([.banner, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completion: @escaping () -> Void) {
        defer { completion() }
        guard let key = response.notification.request.content.userInfo["phoneKey"] as? String else { return }
        if let reply = response as? UNTextInputNotificationResponse {
            DispatchQueue.main.async { Self.onAction?(["type": "reply", "key": key, "text": String(reply.userText.prefix(4096))]) }
        } else if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            DispatchQueue.main.async { Self.onAction?(["type": "dismiss", "key": key]) }
        }
    }
}

enum PhoneNotifications {
    static func identifier(_ key: String) -> String {
        "phone." + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func show(_ event: [String: Any]) async throws {
        guard let key = event["key"] as? String else { return }
        let content = UNMutableNotificationContent()
        content.title = String((event["app"] as? String ?? "Телефон").prefix(128))
        content.subtitle = String((event["title"] as? String ?? "").prefix(256))
        content.body = String((event["body"] as? String ?? "").prefix(4096))
        content.userInfo = ["phoneKey": key]
        content.categoryIdentifier = (event["replyable"] as? Bool == true) ? "PHONE_REPLY" : "PHONE"
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier(key), content: content, trigger: nil))
    }
    static func remove(_ key: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier(key)])
    }
}
