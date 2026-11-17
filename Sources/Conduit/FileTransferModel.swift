import Foundation
import ConduitCore

extension ConduitModel {
    func beginFileTransfer(name: String, direction: FileTransfer.Direction, total: Int64?, measurable: Bool = true,
                           phase: FileTransfer.Phase = .preparing, remoteID: String? = nil) -> UUID {
        let item = FileTransfer(name: name, direction: direction, transport: transport.rawValue,
                                totalBytes: total, measurable: measurable, phase: phase, now: ProcessInfo.processInfo.systemUptime)
        fileTransfers.insert(item, at: 0)
        fileTransferSessions[item.id] = sessionID
        if let remoteID { remoteFileTransferIDs[item.id] = remoteID }
        while fileTransfers.count > 12, let index = fileTransfers.lastIndex(where: { !$0.phase.isActive }) {
            let removed = fileTransfers[index].id
            fileTransferUpdates.removeValue(forKey: removed); fileTransferSessions.removeValue(forKey: removed); remoteFileTransferIDs.removeValue(forKey: removed)
            fileTransfers.remove(at: index)
        }
        reportFileTransfer(item.id)
        return item.id
    }
    func fileTransferPhase(_ id: UUID, _ phase: FileTransfer.Phase, total: Int64? = nil) {
        guard let index = fileTransfers.firstIndex(where: { $0.id == id }) else { return }
        if let total { fileTransfers[index].setTotal(total) }
        fileTransfers[index].setPhase(phase, now: ProcessInfo.processInfo.systemUptime)
        reportFileTransfer(id)
    }
    func advanceFileTransfer(_ id: UUID, bytes: Int64, force: Bool = false) {
        guard let index = fileTransfers.firstIndex(where: { $0.id == id }), fileTransfers[index].phase.isActive else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || bytes == fileTransfers[index].totalBytes || now - (fileTransferUpdates[id] ?? 0) >= 0.1 else { return }
        fileTransferUpdates[id] = now; fileTransfers[index].advance(to: bytes, now: now)
        reportFileTransfer(id)
    }
    func completeFileTransfer(_ id: UUID) {
        guard let index = fileTransfers.firstIndex(where: { $0.id == id }) else { return }
        if !fileTransfers[index].complete(now: ProcessInfo.processInfo.systemUptime), fileTransfers[index].phase.isActive {
            fileTransfers[index].fail(L("Размер полученного файла не совпал."), now: ProcessInfo.processInfo.systemUptime)
        }
        fileTransferUpdates.removeValue(forKey: id)
        reportFileTransfer(id)
    }
    func failFileTransfer(_ id: UUID, _ message: String) {
        guard let index = fileTransfers.firstIndex(where: { $0.id == id }) else { return }
        fileTransfers[index].fail(message, now: ProcessInfo.processInfo.systemUptime)
        fileTransferUpdates.removeValue(forKey: id)
        reportFileTransfer(id)
    }
    func failActiveFileTransfers() {
        let ids = fileTransfers.filter { $0.phase.isActive }.map(\.id)
        for index in fileTransfers.indices where fileTransfers[index].phase.isActive {
            fileTransfers[index].fail(L("Соединение закрыто"), now: ProcessInfo.processInfo.systemUptime)
        }
        fileTransferUpdates.removeAll()
        for id in ids { reportFileTransfer(id) }
    }
    func reportFileTransfer(_ id: UUID) {
        guard transport == .adb, companionReady, fileTransferSessions[id] == sessionID,
              let item = fileTransfers.first(where: { $0.id == id }), item.transport == ConnectionKind.adb.rawValue else { return }
        var event: [String: Any] = ["type":"fileTransferProgress","id":remoteFileTransferIDs[id] ?? id.uuidString.lowercased(),"name":item.name,
                                    "direction":item.direction.rawValue,"phase":item.phase.rawValue]
        if let total = item.totalBytes { event["size"] = total }
        if let bytes = item.transferredBytes { event["bytes"] = bytes }
        if let error = item.error { event["error"] = error }
        sendBridge(event)
    }
    func runFileTransferCommand(_ id: UUID, adb: ADB, serial: String, arguments: [String]) async throws {
        let session = sessionID
        let task = Task {
            try await adb.transfer(arguments, serial: serial) { [weak self] percent in
                Task { @MainActor in
                    guard let self, self.sessionID == session,
                          let item = self.fileTransfers.first(where: { $0.id == id }), item.phase.isActive,
                          let total = item.totalBytes else { return }
                    self.advanceFileTransfer(id, bytes: total * Int64(percent) / 100)
                }
            }
        }
        fileTransferCommands[id] = task
        defer { fileTransferCommands.removeValue(forKey: id) }
        _ = try await task.value
        guard sessionID == session else { throw CancellationError() }
    }
}
