import Testing
@testable import ConduitCore

struct ConnectionLivenessTests {
    @Test func idleConnectionGetsARealProbeBeforeTimeout() {
        var heartbeat = ConnectionHeartbeat()
        #expect(heartbeat.tick(at: 0) == .ping)
        for time in [10.0, 20, 30] { #expect(heartbeat.tick(at: time) == .wait) }
        #expect(heartbeat.tick(at: 35) == .timedOut)
    }
    @Test func appNapOrWakeStartsAFreshResponseWindow() {
        var heartbeat = ConnectionHeartbeat()
        #expect(heartbeat.tick(at: 0) == .ping)
        #expect(heartbeat.tick(at: 130) == .resumedPing)
        for time in [140.0, 150, 160] { #expect(heartbeat.tick(at: time) == .wait) }
        #expect(heartbeat.tick(at: 165) == .timedOut)
    }
    @Test func inboundTrafficAndNewSessionsClearOldProbes() {
        var heartbeat = ConnectionHeartbeat()
        #expect(heartbeat.tick(at: 10) == .ping)
        heartbeat.acknowledge()
        #expect(heartbeat.tick(at: 20) == .ping)
        heartbeat.reset()
        #expect(heartbeat.tick(at: 500) == .ping)
        #expect(heartbeat.tick(at: 490) == .resumedPing)
    }
    @Test func retriesBackOffAndRecoverAfterSuccess() {
        var policy = BluetoothReconnectPolicy()
        var now = 0.0
        for delay in [3.0, 5, 10, 20, 30, 30] {
            policy.failed(at: now)
            #expect(!policy.isDue(at: now + delay - 0.01))
            #expect(policy.isDue(at: now + delay))
            now += delay
        }
        policy.succeeded()
        #expect(policy.failures == 0)
        #expect(policy.isDue(at: now))
    }
    @Test func automaticRefreshIsBoundedAcrossAttemptsAndSuccesses() {
        var policy = BluetoothReconnectPolicy()
        #expect(policy.allowServiceRefresh(automatic: true, at: 0) == false)
        policy.failed(at: 0)
        #expect(policy.allowServiceRefresh(automatic: true, at: 3) == true)
        policy.failed(at: 4)
        #expect(policy.allowServiceRefresh(automatic: true, at: 10) == false)
        policy.succeeded()
        policy.failed(at: 20)
        #expect(policy.allowServiceRefresh(automatic: true, at: 30) == false)
        #expect(policy.allowServiceRefresh(automatic: true, at: 93) == true)
        #expect(policy.allowServiceRefresh(automatic: false, at: 94) == true)
    }
}
