import Testing
import Foundation
@testable import ConduitCore

struct BluetoothFileTests {
    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("conduit-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    @Test func streamsFileWithKnownDigest() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let payload = Data("hello".utf8)
        let receiver = try BluetoothFileReceiver(url: dir.appendingPathComponent("partial"), size: 5,
            sha256: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        try receiver.append(payload.prefix(2), at: 0); try receiver.append(payload.dropFirst(2), at: 2)
        try receiver.finish()
        #expect(try Data(contentsOf: receiver.url) == payload)
        #expect(try BluetoothFilePolicy.sha256(receiver.url) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }
    @Test func acceptsEmptyFile() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let receiver = try BluetoothFileReceiver(url: dir.appendingPathComponent("empty"), size: 0,
            sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        try receiver.finish(); #expect(receiver.offset == 0)
    }
    @Test func rejectsWrongOffsetsOverflowAndTruncatedFile() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let receiver = try BluetoothFileReceiver(url: dir.appendingPathComponent("partial"), size: 2, sha256: String(repeating: "0", count: 64))
        #expect(throws: BluetoothFileError.invalidChunk) { try receiver.append(Data([1]), at: 1) }
        #expect(throws: BluetoothFileError.invalidChunk) { try receiver.append(Data([1,2,3]), at: 0) }
        #expect(throws: BluetoothFileError.invalidSize) { try receiver.finish() }
        #expect(receiver.offset == 0)
    }
    @Test func rejectsBadDigestAndRemovesPartialFile() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("partial")
        do {
            let receiver = try BluetoothFileReceiver(url: target, size: 1, sha256: String(repeating: "0", count: 64))
            try receiver.append(Data([1]), at: 0)
            #expect(throws: BluetoothFileError.incorrectHash) { try receiver.finish() }
        }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }
    @Test func rejectsOversizedFileAndNonHexHash() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("partial")
        #expect(throws: BluetoothFileError.invalidSize) { try BluetoothFileReceiver(url: url, size: BluetoothFilePolicy.maxSize + 1, sha256: String(repeating:"0", count:64)) }
        #expect(throws: BluetoothFileError.invalidSize) { try BluetoothFileReceiver(url: url, size: 0, sha256: String(repeating:"z", count:64)) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
    @Test func validatesOutboxIDsWithoutPathInterpretation() {
        let id = "e673824d-eab9-4cb9-b615-395f0c68fc6e"
        #expect(BluetoothFilePolicy.validID(id)); #expect(BluetoothFilePolicy.validID(id + ".bin"))
        for invalid in ["../" + id, id + ".bin.bin", id + "/x", id + "\n", "{\(id)}", ""] { #expect(!BluetoothFilePolicy.validID(invalid)) }
    }
}
