import Foundation
import Darwin

public struct CommandProgressParser {
    private var buffer = Data()
    private var previous = -1
    public init() {}
    public mutating func append(_ bytes: Data) -> [Int] {
        buffer.append(bytes)
        let text = String(decoding: buffer, as: UTF8.self)
        let expression = try! NSRegularExpression(pattern: #"\[\s*(\d{1,3})%\]"#)
        var result = [Int]()
        for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text), let percent = Int(text[range]),
                  percent <= 100, percent > previous else { continue }
            previous = percent; result.append(percent)
        }
        buffer = Data(buffer.suffix(256)); return result
    }
}

/// ADB emits intermediate percentages only to a terminal. Capture that output
/// without inventing timer-based progress; success remains the command's exit.
public enum ProgressCommand {
    public static func run(executable: URL, arguments: [String], timeout: TimeInterval,
                           progress: @escaping @Sendable (Int) -> Void) async throws -> CommandResult {
        let cancellation = ProgressCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        var master: Int32 = -1, slave: Int32 = -1
                        var size = winsize(ws_row: 24, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
                        guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw POSIXError(.EIO) }
                        let terminal = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
                        defer { try? terminal.close(); Darwin.close(master) }
                        let process = Process()
                        process.executableURL = executable; process.arguments = arguments
                        process.environment = ProcessInfo.processInfo.environment.merging(["TERM": "xterm-256color"]) { _, new in new }
                        process.standardInput = FileHandle.nullDevice; process.standardOutput = terminal; process.standardError = terminal
                        if cancellation.cancelled { throw CancellationError() }
                        try process.run(); cancellation.install(process)
                        defer { cancellation.clear() }
                        try? terminal.close()
                        let captured = ProgressOutput(), readers = DispatchGroup(), descriptor = master
                        readers.enter()
                        DispatchQueue.global(qos: .utility).async {
                            defer { readers.leave() }
                            var parser = CommandProgressParser(), buffer = [UInt8](repeating: 0, count: 16384)
                            while true {
                                let count = buffer.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
                                if count < 0 && errno == EINTR { continue }
                                if count <= 0 { break } // PTYs report EIO when their last writer closes.
                                let bytes = Data(buffer.prefix(count)); captured.append(bytes)
                                for percent in parser.append(bytes) { progress(percent) }
                            }
                        }
                        let deadline = ProcessInfo.processInfo.systemUptime + timeout
                        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline && !cancellation.cancelled {
                            Thread.sleep(forTimeInterval: 0.05)
                        }
                        let timedOut = process.isRunning && !cancellation.cancelled
                        if process.isRunning {
                            process.terminate(); Thread.sleep(forTimeInterval: 0.1)
                            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        }
                        process.waitUntilExit(); readers.wait()
                        if cancellation.cancelled { throw CancellationError() }
                        if timedOut { throw CommandError.timedOut }
                        let output = captured.text
                        continuation.resume(returning: CommandResult(output: output, error: String(output.suffix(4096)), status: process.terminationStatus))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }
}

private final class ProgressCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    private var process: Process?
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func install(_ process: Process) {
        lock.lock(); self.process = process; let stop = stopped; lock.unlock()
        if stop && process.isRunning { process.terminate() }
    }
    func clear() { lock.lock(); process = nil; lock.unlock() }
    func cancel() {
        lock.lock(); stopped = true; let current = process; lock.unlock()
        if let current, current.isRunning { current.terminate() }
    }
}
private final class ProgressOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    func append(_ data: Data) { lock.lock(); defer { lock.unlock() }; bytes.append(data); if bytes.count > 65536 { bytes = Data(bytes.suffix(65536)) } }
    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: #"\u001B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
