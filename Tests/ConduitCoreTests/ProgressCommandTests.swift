import Foundation
import Testing
@testable import ConduitCore

private final class Percentages: @unchecked Sendable {
    private let lock = NSLock(); private var values = [Int]()
    func add(_ value: Int) { lock.lock(); values.append(value); lock.unlock() }
    var snapshot: [Int] { lock.lock(); defer { lock.unlock() }; return values }
}
struct ProgressCommandTests {
    @Test func parsesFragmentedMonotonicPercentagesWithoutGuessingCompletion() {
        var parser = CommandProgressParser()
        #expect(parser.append(Data("\r[  0%] name\r[ 4".utf8)) == [0])
        #expect(parser.append(Data("2%] name\u{1B}[K\r[ 42%] name".utf8)) == [42])
        #expect(parser.append(Data("\r[ 20%] old\r[101%] invalid\r[ 95%] last\nSuccess\n".utf8)) == [95])
    }
    @Test func terminalOutputIsCapturedAndNonzeroExitDoesNotComplete() async throws {
        let values = Percentages()
        let result = try await ProgressCommand.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "test -t 1 || exit 90; printf '\\r[ 25%%] file\\033[K'; printf '\\r[ 95%%] file\\nFailure\\n' >&2; exit 7"], timeout: 3) { values.add($0) }
        #expect(result.status == 7 && result.error.contains("Failure"))
        #expect(values.snapshot == [25,95])
        #expect(!result.output.contains("\u{1B}"))
    }
    @Test func cancellationStopsTheTransferCommand() async throws {
        let task = Task { try await ProgressCommand.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 20) { _ in } }
        try await Task.sleep(nanoseconds: 100_000_000); let start = ProcessInfo.processInfo.systemUptime
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled command returned success") }
        catch is CancellationError {}
        #expect(ProcessInfo.processInfo.systemUptime - start < 2)
    }
    @Test func commandTimeoutStopsTheTransfer() async throws {
        do {
            _ = try await ProgressCommand.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1) { _ in }
            Issue.record("Timed-out command returned success")
        } catch CommandError.timedOut {}
    }
}
