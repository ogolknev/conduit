import Foundation

public enum AndroidDiagnosticArchive {
    public static let maxBytes = 196608
    public static func save(_ report: String, in directory: URL) throws {
        let bytes = Data(report.utf8)
        guard report.hasPrefix("Conduit Android "), bytes.count <= maxBytes else { throw ProtocolError.malformed }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let latest = directory.appendingPathComponent("android-latest.log")
        let previous = directory.appendingPathComponent("android-previous.log")
        if manager.fileExists(atPath: latest.path) {
            try? manager.removeItem(at: previous)
            try manager.copyItem(at: latest, to: previous)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: previous.path)
        }
        try bytes.write(to: latest, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: latest.path)
    }
}
