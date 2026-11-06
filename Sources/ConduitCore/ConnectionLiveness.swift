import Foundation

public enum HeartbeatDecision: Equatable { case ping, resumedPing, wait, timedOut }

/// A delayed timer is not evidence that a peer failed to answer a fresh probe.
public struct ConnectionHeartbeat {
    private var lastTick: TimeInterval?
    private var awaitingSince: TimeInterval?
    public init() { }
    public mutating func reset() { lastTick = nil; awaitingSince = nil }
    public mutating func acknowledge() { awaitingSince = nil }
    public mutating func tick(at now: TimeInterval) -> HeartbeatDecision {
        let resumed = lastTick.map { now < $0 || now - $0 > 20 } ?? false
        lastTick = now
        if resumed { awaitingSince = now; return .resumedPing }
        if let sent = awaitingSince { return now - sent >= 35 ? .timedOut : .wait }
        awaitingSince = now
        return .ping
    }
}

/// Bound both reconnect traffic and forced cache refreshes for the selected trusted phone.
public struct BluetoothReconnectPolicy {
    public private(set) var failures = 0
    private var nextAttempt: TimeInterval = 0
    private var nextRefresh: TimeInterval = 0
    public init() { }
    public func isDue(at now: TimeInterval) -> Bool { now >= nextAttempt }
    public mutating func succeeded() { failures = 0; nextAttempt = 0 }
    public mutating func failed(at now: TimeInterval) {
        let delays: [TimeInterval] = [3, 5, 10, 20, 30]
        nextAttempt = now + delays[min(failures, delays.count - 1)]
        failures = min(failures + 1, delays.count)
    }
    public mutating func allowServiceRefresh(automatic: Bool, at now: TimeInterval) -> Bool {
        if automatic && (failures == 0 || now < nextRefresh) { return false }
        nextRefresh = now + 90
        return true
    }
}
