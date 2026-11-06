import Foundation
import CryptoKit

public enum BluetoothFileError: Error { case invalidSize, invalidChunk, incorrectHash }

public enum BluetoothFilePolicy {
    public static let maxSize = 100 * 1024 * 1024
    public static let chunkSize = 16384
    public static func validID(_ id: String) -> Bool {
        let stem = id.hasSuffix(".bin") ? String(id.dropLast(4)) : id
        return stem.count == 36 && UUID(uuidString: stem)?.uuidString.lowercased() == stem.lowercased()
    }
    public static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var digest = SHA256()
        while let bytes = try file.read(upToCount: 65536), !bytes.isEmpty { digest.update(data: bytes) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Stream a download to a staging file, with strict offsets and a final digest.
public final class BluetoothFileReceiver {
    public let url: URL
    public let size: Int
    private let expectedHash: String
    private let file: FileHandle
    private var hash = SHA256()
    public private(set) var offset = 0
    private var finished = false
    public init(url: URL, size: Int, sha256: String) throws {
        guard size >= 0, size <= BluetoothFilePolicy.maxSize, sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw BluetoothFileError.invalidSize }
        self.url = url; self.size = size; expectedHash = sha256.lowercased()
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw BluetoothFileError.invalidChunk }
        file = try FileHandle(forWritingTo: url)
    }
    public func append(_ bytes: Data, at position: Int) throws {
        guard !finished, position == offset, !bytes.isEmpty, bytes.count <= BluetoothFilePolicy.chunkSize,
              bytes.count <= size - offset else { throw BluetoothFileError.invalidChunk }
        try file.write(contentsOf: bytes); hash.update(data: bytes); offset += bytes.count
    }
    public func finish() throws {
        guard !finished, offset == size else { throw BluetoothFileError.invalidSize }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expectedHash else { throw BluetoothFileError.incorrectHash }
        try file.close(); finished = true
    }
    deinit { if !finished { try? file.close(); try? FileManager.default.removeItem(at: url) } }
}
