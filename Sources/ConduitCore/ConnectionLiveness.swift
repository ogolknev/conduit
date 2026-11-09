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
    public mutating func retryNow() { nextAttempt = 0 }
    public mutating func succeeded() { failures = 0; nextAttempt = 0 }
    public mutating func failed(at now: TimeInterval) {
        let delays: [TimeInterval] = [3, 5, 10, 20, 30]
        nextAttempt = now + delays[min(failures, delays.count - 1)]
        failures = min(failures + 1, delays.count)
    }
    public mutating func allowServiceRefresh(automatic: Bool, at now: TimeInterval) -> Bool {
        if automatic && now < nextRefresh { return false }
        nextRefresh = now + 90
        return true
    }
}

public enum BluetoothLinkAction: Equatable { case connect, wait, ready, failed }

/// An accepted native command/callback is not proof that a Bluetooth link exists.
/// Pace completed-but-disconnected requests instead of exhausting retries in one tick.
public struct BluetoothLinkEstablishment {
    public private(set) var requests = 0
    private var awaitingResponse = false
    private var nextRequest: TimeInterval
    private let deadline: TimeInterval
    public init(at now: TimeInterval) { nextRequest = now; deadline = now + 30 }
    public mutating func next(at now: TimeInterval, connected: Bool) -> BluetoothLinkAction {
        if connected { return .ready }
        if now >= deadline { return .failed }
        if awaitingResponse || now < nextRequest { return .wait }
        if requests >= 4 { return .failed }
        requests += 1; awaitingResponse = true
        return .connect
    }
    public mutating func completed(at now: TimeInterval) {
        guard awaitingResponse else { return }
        awaitingResponse = false
        nextRequest = now + Double(min(requests, 3))
    }
}
