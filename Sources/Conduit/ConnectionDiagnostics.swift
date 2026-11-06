import Foundation
import CoreBluetooth
import IOBluetooth
import OSLog
import ConduitCore

@MainActor enum ConnectionDiagnostics {
    static let logger = Logger(subsystem: "dev.conduit.mac", category: "Connection")
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Conduit", isDirectory: true).appendingPathComponent("connection.log")
    }
    static var permission: BluetoothPermission {
        switch CBManager.authorization {
        case .allowedAlways: return .allowed
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .unknown
        }
    }
    static var androidDirectory: URL { url.deletingLastPathComponent().appendingPathComponent("diagnostics",isDirectory:true) }
    static var poweredOn: Bool? {
        guard permission == .allowed else { return nil }
        return IOBluetoothHostController.default()?.powerState.rawValue == 1
    }
    static func record(_ stage: String, _ detail: String = "") {
        // Call sites pass only stages and fixed errors, never codes, tokens or payloads.
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(stage)] \(detail.replacingOccurrences(of: "\n", with: " ").prefix(1500))\n"
        logger.notice("\(line, privacy: .public)")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 262144 {
                try Data().write(to: url, options: .atomic)
            }
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            let file = try FileHandle(forWritingTo: url); defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: Data(line.utf8))
        } catch { logger.error("Connection log unavailable") }
    }
    static func report() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n").suffix(160).joined(separator: "\n") ?? L("Нет записей")
        let android = (try? String(contentsOf:androidDirectory.appendingPathComponent("android-latest.log"),encoding:.utf8)) ?? L("Журнал Android ещё не получен")
        return "Conduit \(version)\nBluetooth permission: \(permission.rawValue)\nBluetooth power: \(poweredOn.map(String.init) ?? "unknown")\n\n--- Mac ---\n\(lines)\n\n--- Last Android report ---\n\(android)"
    }
}
