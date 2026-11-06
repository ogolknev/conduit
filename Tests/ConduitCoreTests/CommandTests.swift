import Testing
import Foundation
@testable import ConduitCore

struct CommandTests {
    @Test func drainsBothPipesAndKeepsExitStatus() async throws {
        let result = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf hello; printf failure >&2; exit 7"], timeout: 5)
        #expect(result.output == "hello")
        #expect(result.error == "failure")
        #expect(result.status == 7)
    }
    @Test func largeOutputDoesNotBlockAndDiagnosticsAreBounded() async throws {
        let result = try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-c", "import os; os.write(1,b'a'*262144); os.write(2,b'b'*262144)"], timeout: 10)
        #expect(result.status == 0)
        #expect(result.output.utf8.count == 262144)
        #expect(result.error.utf8.count == 65536)
    }
    @Test func timeoutStopsTheChild() async {
        do {
            _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.1)
            Issue.record("Expected the child process to be stopped")
        } catch CommandError.timedOut { }
        catch { Issue.record("Unexpected error: \(error)") }
    }
}
