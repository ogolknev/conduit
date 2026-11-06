import Foundation
import Testing
@testable import ConduitCore

struct AndroidDiagnosticArchiveTests {
    @Test func storesOnlyTwoSnapshotsAndUsesPrivatePermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try AndroidDiagnosticArchive.save("Conduit Android 0.2.6\nfirst", in: root)
        try AndroidDiagnosticArchive.save("Conduit Android 0.2.6\nsecond", in: root)
        #expect(try String(contentsOf:root.appendingPathComponent("android-latest.log"),encoding:.utf8).hasSuffix("second"))
        #expect(try String(contentsOf:root.appendingPathComponent("android-previous.log"),encoding:.utf8).hasSuffix("first"))
        #expect(try FileManager.default.contentsOfDirectory(atPath:root.path).count == 2)
        let attributes = try FileManager.default.attributesOfItem(atPath:root.appendingPathComponent("android-latest.log").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
    @Test func rejectsOversizedOrUnidentifiedContentBeforeWriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for text in ["not a report", "Conduit Android " + String(repeating:"a",count:AndroidDiagnosticArchive.maxBytes)] {
            #expect(throws:(any Error).self) { try AndroidDiagnosticArchive.save(text,in:root) }
        }
        #expect(!FileManager.default.fileExists(atPath:root.path))
    }
}
