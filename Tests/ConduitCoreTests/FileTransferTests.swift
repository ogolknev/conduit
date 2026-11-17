import Testing
@testable import ConduitCore

struct FileTransferTests {
    @Test func progressTracksActualBytesAndRequiresSuccessfulFinalization() {
        var transfer = FileTransfer(name: "Example.bin", direction: .sending, transport: "Bluetooth", totalBytes: 100, now: 0)
        transfer.setPhase(.transferring, now: 1)
        transfer.advance(to: 40, now: 2)
        #expect(transfer.fraction == 0.4)
        let early = transfer.complete(now: 2)
        #expect(!early)
        transfer.advance(to: 100, now: 3)
        transfer.setPhase(.verifying, now: 3)
        #expect(transfer.phase.isActive && transfer.fraction == nil)
        let completed = transfer.complete(now: 4)
        #expect(completed)
        #expect(transfer.phase == .completed && transfer.fraction == 1)
        #expect(transfer.elapsed(at: 50) == 3)
    }
    @Test func progressRejectsRewindsOverflowAndLateUpdates() {
        var transfer = FileTransfer(name: "Example.bin", direction: .receiving, transport: "Bluetooth", totalBytes: 100, phase: .transferring, now: 0)
        transfer.advance(to: 40, now: 1)
        for invalid in [-1, 30, 101] { transfer.advance(to: Int64(invalid), now: 2) }
        #expect(transfer.transferredBytes == 40)
        transfer.fail("Disconnected", now: 3)
        transfer.advance(to: 100, now: 4); transfer.setPhase(.transferring, now: 4)
        let late = transfer.complete(now: 4)
        #expect(!late)
        #expect(transfer.phase == .failed && transfer.error == "Disconnected")
    }
    @Test func unknownProgressAndEmptyFilesAreNotPrematurelyComplete() {
        var unknown = FileTransfer(name: "Example.bin", direction: .sending, transport: "USB / Wi-Fi", totalBytes: nil, measurable: false, now: 0)
        let early = unknown.complete(now: 1)
        #expect(unknown.fraction == nil && !early)
        unknown.setTotal(20); unknown.advance(to: 20, now: 2)
        let completed = unknown.complete(now: 2)
        #expect(completed)
        var empty = FileTransfer(name: "Empty.bin", direction: .sending, transport: "Bluetooth", totalBytes: 0, now: 0)
        #expect(empty.fraction == nil && empty.phase.isActive)
        let emptyCompleted = empty.complete(now: 1)
        #expect(emptyCompleted)
    }
    @Test func rateUsesTransferTimeAndStallsRemainActiveUntilFailure() {
        var transfer = FileTransfer(name: "Example.bin", direction: .sending, transport: "Bluetooth", totalBytes: 1000, now: 0)
        transfer.setPhase(.transferring, now: 10); transfer.advance(to: 400, now: 12)
        #expect(transfer.bytesPerSecond(at: 12) == 200)
        #expect(!transfer.isStalled(at: 16.9))
        #expect(transfer.isStalled(at: 17) && transfer.bytesPerSecond(at: 17) == 0)
        #expect(transfer.phase.isActive)
        transfer.advance(to: 800, now: 18)
        #expect(!transfer.isStalled(at: 18))
    }
}
