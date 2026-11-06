import Foundation

public struct CommandResult {
    public let output: String
    public let error: String
    public let status: Int32
}
public enum CommandError: Error { case timedOut }

public enum CommandRunner {
    /// Drain both pipes concurrently and join the readers before returning.
    /// Otherwise long transfers can deadlock, or short adb results can race EOF.
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable; process.arguments = arguments
                let output = Pipe(), error = Pipe()
                process.standardOutput = output; process.standardError = error
                let collected = OutputCollector()
                do {
                    try process.run()
                    let readers = DispatchGroup()
                    for (handle, isError) in [(output.fileHandleForReading, false), (error.fileHandleForReading, true)] {
                        readers.enter()
                        DispatchQueue.global(qos: .utility).async {
                            defer { readers.leave() }
                            while true {
                                let data = handle.readData(ofLength: 16384)
                                if data.isEmpty { break }
                                collected.append(data, error: isError)
                            }
                        }
                    }
                    let deadline = Date().addingTimeInterval(timeout)
                    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                    let timedOut = process.isRunning
                    if timedOut {
                        process.terminate(); Thread.sleep(forTimeInterval: 0.1)
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                    process.waitUntilExit(); readers.wait()
                    if timedOut { throw CommandError.timedOut }
                    continuation.resume(returning: CommandResult(output: collected.outputText, error: collected.errorText, status: process.terminationStatus))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data(), error = Data()
    func append(_ data: Data, error isError: Bool) {
        lock.lock(); defer { lock.unlock() }
        if isError { error.append(data.prefix(max(0, 65536 - error.count))) }
        else { output.append(data.prefix(max(0, 1_048_576 - output.count))) }
    }
    var outputText: String { lock.lock(); defer { lock.unlock() }; return String(decoding: output, as: UTF8.self) }
    var errorText: String { lock.lock(); defer { lock.unlock() }; return String(decoding: error, as: UTF8.self) }
}
