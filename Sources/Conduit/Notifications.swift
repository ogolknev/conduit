import AppKit
import UserNotifications
import CryptoKit
import UniformTypeIdentifiers
import ConduitCore

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static var onAction: (([String: Any]) -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        if CommandLine.arguments.contains("--notification-test") {
            Task {
                let settings = await center.notificationSettings()
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
                let content = UNMutableNotificationContent()
                content.title = "Conduit"; content.subtitle = "Conduit UI test"
                content.body = "Проверка значка из каталога Xcode"
                do { try await center.add(UNNotificationRequest(identifier: "conduit.ui.icon.test", content: content, trigger: nil)) }
                catch { ConnectionDiagnostics.record("notification.test.failed", String(describing: type(of: error))) }
            }
        }
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

@MainActor enum PhoneNotifications {
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
        if let encoded = event["iconPNG"] as? String, let attachment = iconAttachment(encoded) { content.attachments = [attachment] }
        content.categoryIdentifier = (event["replyable"] as? Bool == true) ? "PHONE_REPLY" : "PHONE"
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier(key), content: content, trigger: nil))
            ConnectionDiagnostics.record("notification.accepted","attachments=\(content.attachments.count)")
        } catch {
            ConnectionDiagnostics.record("notification.failed",String(describing:type(of:error)))
            throw error
        }
    }
    private static func iconAttachment(_ encoded: String) -> UNNotificationAttachment? {
        guard let data=NotificationIconPayload.decode(encoded), let bitmap=NSBitmapImageRep(data:data),
              bitmap.pixelsWide<=256, bitmap.pixelsHigh<=256 else { return nil }
        do {
            let directory=FileManager.default.temporaryDirectory.appendingPathComponent("Conduit-notification-icons",isDirectory:true)
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let previous=(try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.creationDateKey])) ?? []
            if previous.count>64 { for file in previous { try? FileManager.default.removeItem(at:file) } }
            let url=directory.appendingPathComponent(UUID().uuidString+".png")
            try data.write(to:url,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
            return try UNNotificationAttachment(identifier:"android-app-icon",url:url,options:[UNNotificationAttachmentOptionsTypeHintKey:UTType.png.identifier,UNNotificationAttachmentOptionsThumbnailHiddenKey:false])
        } catch { return nil }
    }
    static func remove(_ key: String) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier(key)])
    }
}
