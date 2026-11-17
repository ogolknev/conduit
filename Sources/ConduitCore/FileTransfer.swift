import Foundation

public struct FileTransfer: Identifiable, Equatable, Sendable {
    public enum Direction: String, Sendable { case sending, receiving }
    public enum Phase: String, Sendable {
        case preparing, waiting, transferring, verifying, completed, failed
        public var isActive: Bool { self != .completed && self != .failed }
    }
    public let id: UUID
    public let name: String
    public let direction: Direction
    public let transport: String
    public private(set) var phase: Phase
    public private(set) var totalBytes: Int64?
    public private(set) var transferredBytes: Int64?
    public private(set) var error: String?
    public private(set) var startedAt: TimeInterval?
    public private(set) var endedAt: TimeInterval?
    public private(set) var lastProgressAt: TimeInterval

    public init(id: UUID = UUID(), name: String, direction: Direction, transport: String,
                totalBytes: Int64?, measurable: Bool = true, phase: Phase = .preparing, now: TimeInterval) {
        self.id = id; self.name = name; self.direction = direction; self.transport = transport
        self.totalBytes = totalBytes.flatMap { $0 >= 0 ? $0 : nil }
        transferredBytes = measurable ? 0 : nil
        self.phase = phase; lastProgressAt = now
        if phase == .transferring { startedAt = now }
    }
    public mutating func setPhase(_ phase: Phase, now: TimeInterval) {
        guard self.phase.isActive, phase.isActive else { return }
        self.phase = phase
        if phase == .transferring && startedAt == nil { startedAt = now; lastProgressAt = now }
    }
    public mutating func setTotal(_ bytes: Int64) {
        guard phase.isActive, bytes >= 0, bytes >= (transferredBytes ?? 0) else { return }
        totalBytes = bytes
    }
    public mutating func advance(to bytes: Int64, now: TimeInterval) {
        guard phase.isActive, bytes >= 0, bytes >= (transferredBytes ?? 0),
              totalBytes.map({ bytes <= $0 }) ?? true else { return }
        if bytes > (transferredBytes ?? 0) { lastProgressAt = now }
        transferredBytes = bytes
    }
    @discardableResult public mutating func complete(now: TimeInterval) -> Bool {
        guard phase.isActive, totalBytes.map({ transferredBytes == $0 }) ?? (transferredBytes != nil) else { return false }
        phase = .completed; endedAt = now; return true
    }
    public mutating func fail(_ message: String, now: TimeInterval) {
        guard phase.isActive else { return }
        phase = .failed; error = message; endedAt = now
    }
    public func isStalled(at now: TimeInterval) -> Bool { phase == .transferring && now - lastProgressAt >= 5 }
    public func elapsed(at now: TimeInterval) -> TimeInterval {
        guard let startedAt else { return 0 }; return max(0, (endedAt ?? now) - startedAt)
    }
    public func bytesPerSecond(at now: TimeInterval) -> Double? {
        guard let bytes = transferredBytes, bytes > 0, let startedAt else { return nil }
        if isStalled(at: now) { return 0 }
        let seconds = (endedAt ?? now) - startedAt
        return seconds > 0 ? Double(bytes) / seconds : nil
    }
    public var fraction: Double? {
        if phase == .completed { return 1 }
        guard phase == .transferring, let bytes = transferredBytes, let total = totalBytes, total > 0 else { return nil }
        return min(1, Double(bytes) / Double(total))
    }
}
