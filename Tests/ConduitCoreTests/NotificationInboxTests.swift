import Foundation
import Testing
@testable import ConduitCore

struct NotificationInboxTests {
    func item(_ key: String = "key", source: String = "phone-a", instance: String = "1000") -> InboxNotification {
        InboxNotification(source: source, event: ["key": key, "instance": instance, "app": "Example", "title": "Test", "body": "Body", "dismissible": true])!
    }
    @Test func updatesReplaceOneEntryAndKeepOfflineDismissal() {
        var box = NotificationInbox(); let entry = item()
        box.upsert(entry); box.state(.pending, id: entry.id, instance: entry.instance)
        var update = entry; update.body = "Updated"; box.upsert(update)
        #expect(box.items.count == 1); #expect(box.items[0].body == "Updated"); #expect(box.items[0].state == .pending)
    }
    @Test func reusedKeyDoesNotInheritOldDismissalOrAcceptOldAcknowledgement() {
        var box = NotificationInbox(); let old = item(); box.upsert(old)
        box.state(.pending, id: old.id, instance: old.instance)
        box.upsert(item(instance: "2000")); box.state(.removed, id: old.id, instance: old.instance)
        #expect(box.items[0].state == .active)
    }
    @Test func phonesAreIsolatedAndMissingItemsBecomeHistory() {
        var box = NotificationInbox(); box.upsert(item()); box.upsert(item(source: "phone-b"))
        box.reconcile(source: "phone-a", seen: [])
        #expect(box.items.first { $0.source == "phone-a" }?.state == .removed)
        #expect(box.items.first { $0.source == "phone-b" }?.state == .active)
        box.clearHistory(); #expect(box.items.count == 1)
    }
    @Test func snapshotDoesNotResurrectDismissedInstance() {
        var box = NotificationInbox(); let entry = item(); box.upsert(entry)
        box.state(.removed, id: entry.id, instance: entry.instance); box.upsert(entry)
        box.state(.failed, id: entry.id, instance: entry.instance)
        #expect(box.items[0].state == .removed)
    }
    @Test func historyAndPendingActionsSurviveDiskRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("history.json")
        var box = NotificationInbox(); let entry = item(); box.upsert(entry)
        box.state(.pending, id: entry.id, instance: entry.instance); try box.save(to: url)
        #expect(try NotificationInbox.load(from: url).items == box.items)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
    @Test func hiddenInstanceDoesNotBecomeHistoryOrDeleteANewerPost() {
        var box = NotificationInbox()
        let entry = item(instance: "2000")
        box.upsert(entry)
        let stale = box.hide(id: entry.id, instance: "1000")
        #expect(!stale)
        #expect(box.items == [entry])
        let current = box.hide(id: entry.id, instance: "2000")
        #expect(current)
        box.reconcile(source: entry.source, seen: [])
        #expect(box.items.isEmpty)
    }

    @Test func localCloseOfOngoingCardSurvivesReplayRestartAndPhoneRemoval() throws {
        var box = NotificationInbox()
        var player = item()
        player.dismissible = false
        box.upsert(player)
        let closed = box.closeOnMac(id: player.id, instance: player.instance)
        #expect(closed)
        box = try JSONDecoder().decode(NotificationInbox.self, from: JSONEncoder().encode(box))
        box.upsert(player)
        #expect(box.items[0].state == .active)
        #expect(!box.items[0].visibleInActive)
        box.reconcile(source: player.source, seen: [])
        #expect(!box.items[0].visibleInHistory)
        box.upsert(item(instance: "2000"))
        let stale = box.closeOnMac(id: player.id, instance: player.instance)
        #expect(!stale)
        #expect(box.items[0].visibleInActive)
    }

    @Test func localCloseAlsoRemovesPastCardsFromHistory() {
        var box = NotificationInbox()
        let entry = item()
        box.upsert(entry)
        box.state(.removed, id: entry.id, instance: entry.instance)
        #expect(box.items[0].visibleInHistory)
        let closed = box.closeOnMac(id: entry.id, instance: entry.instance)
        #expect(closed)
        box.upsert(entry)
        #expect(!box.items[0].visibleInHistory)
        #expect(!box.items[0].visibleInActive)
    }

    @Test func exclusionsPurgeLegacyHistoryOnlyForTheMatchingPhone() throws {
        let key = "0|example.app|24|tag|1000"
        var box = NotificationInbox()
        let old = item(key)
        box.upsert(old)
        box.state(.removed, id: old.id, instance: old.instance)
        let other = item(key, source: "phone-b")
        box.upsert(other)
        box = try JSONDecoder().decode(NotificationInbox.self, from: JSONEncoder().encode(box))
        #expect(box.exclude(packages: ["example.app"], source: old.source) == [old.id])
        #expect(box.items == [other])
    }

    @Test func controlsKeepPhoneOrderAndRejectAmbiguousOrEmptyDescriptors() {
        let actions = [["id": "pause", "label": ""], ["id": "action:2", "label": "Archive"],
                       ["id": "action:2", "label": "Other"], ["id": "custom", "label": ""]]
        let entry = InboxNotification(source: "phone", event: ["key": "media", "instance": "1", "actions": actions])
        #expect(entry?.actions?.map(\.id) == ["pause", "action:2"])
        #expect(entry?.actions?.last?.label == "Archive")
        #expect(item().actions == nil)
    }

    @Test func historyIsBoundedAndMalformedIdentityIsRejected() {
        var box = NotificationInbox()
        for n in 0..<520 { box.upsert(item("\(n)", instance: "\(n)")) }
        #expect(box.items.count == 500)
        #expect(InboxNotification(source: "a", event: ["key": "", "instance": "1"]) == nil)
        #expect(InboxNotification(source: "a", event: ["key": "k", "instance": "NaN"]) == nil)
    }
}
