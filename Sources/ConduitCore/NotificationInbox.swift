import Foundation

public struct InboxNotification: Codable, Identifiable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case active, pending, removed, failed }
    public var id: String { source + ":" + key }
    public var source: String
    public var key: String
    public var instance: String
    public var app: String
    public var title: String
    public var body: String
    public var date: Date
    public var replyable: Bool
    public var dismissible: Bool
    public var state: State = .active
    public struct Action: Codable, Equatable, Identifiable, Sendable {
        public let id: String
        public let label: String
    }
    public var actions: [Action]?
    public var package: String?
    public var icon: Data?
    public init?(source: String, event: [String: Any]) {
        guard let key = event["key"] as? String, !key.isEmpty, key.utf8.count <= 2048,
              let instance = event["instance"] as? String, !instance.isEmpty, instance.count <= 19,
              let milliseconds = Double(instance), milliseconds.isFinite, milliseconds >= 0, milliseconds <= 253402300799000 else { return nil }
        self.source = source; self.key = key; self.instance = instance
        app = String((event["app"] as? String ?? "Android").prefix(128))
        title = String((event["title"] as? String ?? "").prefix(256))
        body = String((event["body"] as? String ?? "").prefix(4096))
        date = Date(timeIntervalSince1970: milliseconds / 1000)
        replyable = event["replyable"] as? Bool == true
        dismissible = event["dismissible"] as? Bool == true
        package = event["package"] as? String
        if let descriptors = event["actions"] as? [[String: Any]] {
            var ids = Set<String>()
            actions = descriptors.prefix(8).compactMap { value in
                guard let id = value["id"] as? String, !id.isEmpty, id.utf16.count <= 180,
                      let label = value["label"] as? String, label.utf16.count <= 100,
                      !label.isEmpty || ["play", "pause", "previous", "next"].contains(id),
                      ids.insert(id).inserted else { return nil }
                return Action(id: id, label: label)
            }
        }
        icon = (event["iconPNG"] as? String).flatMap(NotificationIconPayload.decode)
    }
}

public struct NotificationInbox: Codable, Sendable {
    public private(set) var items: [InboxNotification] = []
    public init() {}
    public mutating func upsert(_ item: InboxNotification) {
        var next = item
        if let old = items.first(where: { $0.id == item.id }), old.instance == item.instance {
            // A replay cannot undo a confirmed dismissal or an offline intent.
            next.state = old.state
        }
        items.removeAll { $0.id == next.id }; items.insert(next, at: 0)
        items.sort { $0.date > $1.date }
        if items.count > 500 { items = Array(items.prefix(500)) }
    }
    public mutating func state(_ state: InboxNotification.State, id: String, instance: String) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.instance == instance }) else { return }
        if items[index].state == .removed && state != .removed { return }
        items[index].state = state
    }
    public mutating func reconcile(source: String, seen: Set<String>) {
        for index in items.indices where items[index].source == source && !seen.contains(items[index].id) {
            items[index].state = .removed
        }
    }
    public mutating func hide(id: String, instance: String) -> Bool {
        guard let version = Int64(instance) else { return false }
        let previousCount = items.count
        items.removeAll { $0.id == id && (Int64($0.instance) ?? .max) <= version }
        return items.count != previousCount
    }
    public mutating func exclude(packages: Set<String>, source: String) -> [String] {
        guard !packages.isEmpty else { return [] }
        var removed = [String]()
        items.removeAll { item in
            // Older stores only retained the Android key (user|package|id|tag|uid).
            guard item.source == source, let package = item.package ?? item.key.split(separator: "|", maxSplits: 2).dropFirst().first.map(String.init),
                  packages.contains(package) else { return false }
            removed.append(item.id)
            return true
        }
        return removed
    }
    public mutating func clearHistory() { items.removeAll { $0.state == .removed } }
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func load(from url: URL) throws -> Self {
        let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= 40_000_000 else { throw CocoaError(.fileReadTooLarge) }
        var result = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        result.items = Array(result.items.prefix(500))
        return result
    }
}
