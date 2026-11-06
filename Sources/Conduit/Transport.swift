import Foundation
import Network
import ConduitCore

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { L(message) }
    init(_ message: String) { self.message = message }
}

struct ADB {
    let executable: URL

    static func locate() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("platform-tools/adb").path,
            ProcessInfo.processInfo.environment["CONDUIT_ADB"],
            "/opt/homebrew/bin/adb", "/usr/local/bin/adb",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Android/sdk/platform-tools/adb").path
        ].compactMap { $0 }
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }

    func run(_ args: [String], serial: String? = nil, timeout: TimeInterval = 15) async throws -> String {
        let fullArgs = (serial.map { ["-s", $0] } ?? []) + args
        do {
            let result = try await CommandRunner.run(executable: executable, arguments: fullArgs, timeout: timeout)
            guard result.status == 0 else {
                throw AppError(String(result.error.prefix(600)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return result.output
        } catch CommandError.timedOut {
            throw AppError(L("Телефон не ответил вовремя. Проверь подключение."))
        }
    }

    func forward(socket: String, serial: String) async throws -> UInt16 {
        let answer = try await run(["forward", "tcp:0", "localabstract:" + socket], serial: serial)
        guard let port = UInt16(answer.trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 else {
            throw AppError(L("Не удалось открыть канал к телефону."))
        }
        return port
    }
}

// Callback configuration happens before connect(); connection state is confined to queue.
final class LocalChannel: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "dev.conduit.channel")
    var onData: ((Data) -> Void)?
    var onClose: ((String) -> Void)?
    private var pendingConnect: CheckedContinuation<Void, Error>?
    private var closed = false

    init(port: UInt16) {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    }
    func connect() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.pendingConnect = continuation
                self.connection.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.pendingConnect?.resume(); self.pendingConnect = nil
                        self.receive()
                    case .failed(let error): self.finish(error.localizedDescription)
                    case .cancelled: self.finish(L("Канал закрыт"))
                    default: break
                    }
                }
                self.connection.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 5) {
                    if self.pendingConnect != nil { self.finish(L("Не удалось подключиться к сервису телефона.")) }
                }
            }
        }
    }
    func send(_ bytes: Data) {
        queue.async {
            guard !self.closed else { return }
            self.connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
                if let error { self?.finish(error.localizedDescription) }
            })
        }
    }
    func sendJSON(_ value: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: value) else { return }
        data.append(10)
        send(data)
    }
    func cancel() { queue.async { self.finish(L("Канал закрыт"), notify: false) } }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            guard let self, !self.closed else { return }
            if let data, !data.isEmpty { self.onData?(data) }
            if let error { self.finish(error.localizedDescription) }
            else if complete { self.finish(L("Телефон отключился")) }
            else { self.receive() }
        }
    }
    private func finish(_ reason: String, notify: Bool = true) {
        guard !closed else { return }
        closed = true
        pendingConnect?.resume(throwing: AppError(reason)); pendingConnect = nil
        connection.cancel()
        if notify { onClose?(reason) }
        onData = nil; onClose = nil
    }
}
