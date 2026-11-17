import Testing
@testable import ConduitCore

struct NotificationPresentationTests {
    @Test func independentBannerAndSound() {
        for banner in [false, true] {
            for sound in [false, true] {
                let policy = NotificationPresentation(event: ["alert": ["banner": banner, "sound": sound]])
                #expect(policy.deliver)
                #expect(policy.banner == banner)
                #expect(policy.sound == sound)
            }
        }
    }
    @Test func oldPeersKeepBannerOnlyAndIncompleteDescriptorsStaySilent() {
        let old = NotificationPresentation(event: [:])
        #expect(old.deliver && old.banner && !old.sound)
        let incomplete = NotificationPresentation(event: ["alert": ["unknown": true]])
        #expect(incomplete.deliver && !incomplete.banner && !incomplete.sound)
        let malformed = NotificationPresentation(event: ["alert": "invalid"])
        #expect(malformed.deliver && !malformed.banner && !malformed.sound)
    }
    @Test func snapshotsInternalUpdatesAndDuplicateInstancesNeverReplay() {
        let alert: [String: Any] = ["alert": ["banner": true, "sound": true]]
        var snapshot = alert; snapshot["snapshot"] = "request"
        var update = alert; update["quiet"] = true
        #expect(!NotificationPresentation(event: snapshot).deliver)
        #expect(!NotificationPresentation(event: update).deliver)
        #expect(!NotificationPresentation(event: alert, isNewInstance: false).deliver)
        #expect(NotificationPresentation(event: alert, isNewInstance: true).deliver)
    }
}
