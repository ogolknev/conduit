import Foundation
import ConduitCore

extension ConduitModel {
    static var inboxURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Conduit/notifications.json") }
    func persistInbox() {
        do { try inbox.save(to: Self.inboxURL); inboxStorageError = false }
        catch { inboxStorageError = true }
    }
    func notificationSession(_ event: [String: Any]) {
        guard let source = event["notificationSource"] as? String, UUID(uuidString: source) != nil,
              event["notificationInbox"] as? Int == 1 else { return }
        if event["type"] as? String == "ready" || notificationSource != source {
            notificationSnapshot = nil
            notificationSynced = false
        }
        notificationSource = source
        if let packages = event["blockedPackages"] as? [String] {
            let removed = inbox.exclude(packages: Set(packages), source: source)
            removed.forEach(PhoneNotifications.remove)
            if !removed.isEmpty { persistInbox() }
        }
        guard notificationsEnabled else { return }
        if !notificationListenerConnected { notificationSynced = false; notificationSnapshot = nil; return }
        if notificationSnapshot == nil && !notificationSynced {
            let request = UUID().uuidString; notificationSnapshot = request; notificationSeen = []
            sendBridge(["type": "notificationSnapshot", "request": request, "notificationActions": true, "notificationPresentation": true])
            armNotificationSnapshotTimeout()
        }
    }
    func armNotificationSnapshotTimeout() {
        notificationSyncTimeout?.cancel()
        let session = sessionID; let request = notificationSnapshot
        notificationSyncTimeout = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
            guard let self, self.sessionID == session, self.notificationSnapshot == request else { return }
            self.notificationSnapshot = nil; self.notificationSyncError = true; self.persistInbox()
        }
    }
    func retryNotificationSnapshot() {
        guard let source = notificationSource else { return }
        notificationSession(["notificationSource": source, "notificationInbox": 1])
    }
    func canAct(on item: InboxNotification) -> Bool {
        notificationsEnabled && companionReady && notificationListenerConnected && notificationSynced
            && notificationSource == item.source && item.state == .active
    }
    func performNotificationAction(_ action: InboxNotification.Action, on item: InboxNotification) {
        guard canAct(on: item), notificationActionRequest == nil,
              inbox.items.first(where: { $0.id == item.id && $0.instance == item.instance && $0.state == .active })?.actions?.contains(action) == true else { return }
        let request = UUID().uuidString
        notificationActionRequest = request
        inboxActionResult = nil
        sendBridge(["type": "notificationAction", "key": item.key, "instance": item.instance,
                    "action": action.id, "label": action.label, "request": request])
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.notificationActionRequest == request else { return }
            self.notificationActionRequest = nil
            self.inboxActionResult = L("Телефон не подтвердил действие")
        }
    }
    func replyToNotification(_ item: InboxNotification, text: String) {
        guard canAct(on: item), item.replyable, inboxReplyRequest == nil, !text.isEmpty, text.utf16.count <= 4096 else { return }
        inboxActionResult = L("Отправка ответа…")
        let request = UUID().uuidString; inboxReplyRequest = request
        sendBridge(["type": "reply", "key": item.key, "instance": item.instance, "text": text, "request": request])
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.inboxReplyRequest == request else { return }
            self.inboxReplyRequest = nil; self.inboxActionResult = L("Телефон не подтвердил отправку ответа")
        }
    }
    func receiveInbox(_ event: [String: Any]) -> Bool {
        guard let source = notificationSource, let type = event["type"] as? String else { return false }
        switch type {
        case "notificationActionResult":
            guard let request = event["request"] as? String, request == notificationActionRequest else { return true }
            notificationActionRequest = nil
            inboxActionResult = event["ok"] as? Bool == true ? nil : L("Действие не выполнено на телефоне")
        case "notificationFiltersChanged":
            notificationSynced = false
            notificationSnapshot = nil
            retryNotificationSnapshot()
        case "notificationHidden":
            if let snapshot = event["snapshot"] as? String, snapshot != notificationSnapshot { return true }
            guard let key = event["key"] as? String, let instance = event["instance"] as? String else { return true }
            let id = source + ":" + key
            if inbox.hide(id: id, instance: instance) {
                PhoneNotifications.remove(id)
                if event["snapshot"] == nil { persistInbox() }
            }
        case "notificationReplyResult":
            guard event["request"] as? String == inboxReplyRequest else { return true }
            inboxReplyRequest = nil
            inboxActionResult = event["ok"] as? Bool == true ? L("Ответ отправлен") : L("Уведомление больше не принимает ответ")
        case "notification":
            guard notificationsEnabled, let item = InboxNotification(source: source, event: event) else { return true }
            let presentation = NotificationPresentation(event: event, isNewInstance: !inbox.items.contains { $0.id == item.id && $0.instance == item.instance })
            if let snapshot = event["snapshot"] as? String {
                guard snapshot == notificationSnapshot else { return true }
                notificationSeen.insert(item.id); armNotificationSnapshotTimeout()
            }
            inbox.upsert(item)
            if event["snapshot"] == nil { persistInbox() }
            if presentation.deliver, inbox.items.contains(where: { $0.id == item.id && $0.instance == item.instance && $0.state == .active }) {
                var banner = event; banner["key"] = item.id; banner["source"] = source; banner["originalKey"] = item.key
                Task { do { try await PhoneNotifications.show(banner) } catch { log(L("Проверь разрешение уведомлений macOS")) } }
            }
        case "removed", "notificationDismissed":
            guard let key = event["key"] as? String, let instance = event["instance"] as? String else { return true }
            let id = source + ":" + key
            inbox.state(type == "removed" || event["ok"] as? Bool == true ? .removed : .failed, id: id, instance: instance)
            if inbox.items.first(where: { $0.id == id })?.state == .removed { PhoneNotifications.remove(id) }
            persistInbox()
        case "notificationSnapshotEnd":
            guard event["request"] as? String == notificationSnapshot else { return true }
            notificationSnapshot = nil; notificationSyncTimeout?.cancel(); notificationSyncTimeout = nil
            guard event["ok"] as? Bool == true else { notificationSyncError = true; persistInbox(); return true }
            notificationSyncError = false; notificationSynced = true
            for item in inbox.items where item.source == source && !notificationSeen.contains(item.id) { PhoneNotifications.remove(item.id) }
            inbox.reconcile(source: source, seen: notificationSeen); persistInbox()
            for item in inbox.items where item.source == source && item.state == .pending { sendNotificationDismiss(item) }
        default: return false
        }
        return true
    }
    func dismissNotification(_ item: InboxNotification) {
        guard inbox.requestDismissal(id: item.id, instance: item.instance) else { return }
        persistInbox()
        if companionReady && notificationSynced && notificationSource == item.source { sendNotificationDismiss(item) }
    }
    func sendNotificationDismiss(_ item: InboxNotification) {
        sendBridge(["type": "notificationDismiss", "key": item.key, "instance": item.instance])
        let session = sessionID
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.sessionID == session, self.companionReady,
                  self.inbox.items.contains(where: { $0.id == item.id && $0.instance == item.instance && $0.state == .pending }) else { return }
            self.inbox.state(.failed, id: item.id, instance: item.instance); self.persistInbox()
        }
    }
    func clearNotificationHistory() { inbox.clearHistory(); persistInbox() }
}
