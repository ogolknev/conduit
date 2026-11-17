import Foundation

public struct NotificationPresentation: Equatable, Sendable {
    public let banner: Bool
    public let sound: Bool
    public let deliver: Bool

    public init(event: [String: Any], isNewInstance: Bool = true) {
        deliver = isNewInstance && event["snapshot"] == nil && event["quiet"] as? Bool != true
        if let descriptor = event["alert"] {
            let alert = descriptor as? [String: Any] ?? [:]
            // An incomplete new descriptor must not turn a silent notification into an alert.
            banner = alert["banner"] as? Bool ?? false
            sound = alert["sound"] as? Bool ?? false
        } else {
            // Preserve banner-only behavior with older Android companions.
            banner = true
            sound = false
        }
    }
}
