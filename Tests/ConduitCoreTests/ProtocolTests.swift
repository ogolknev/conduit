import Testing
import Foundation
@testable import ConduitCore

struct ProtocolTests {
    @Test func everyByteBoundaryAndUTF8() throws {
        let text = "Привет 👋\nsecond line"
        let payload = Data(text.utf8)
        var packet = Data([0, 0, 0, 0, UInt8(payload.count)])
        packet.append(payload)
        packet.append(contentsOf: [1, 0, 0, 0, 0, 0, 0, 0, 42])
        for boundary in 0...packet.count {
            var decoder = ScrcpyDecoder()
            let first = try decoder.append(packet.prefix(boundary))
            let last = try decoder.append(packet.dropFirst(boundary))
            #expect(first + last == [.clipboard(text), .acknowledgement(42)])
        }
    }
    @Test func rejectsOversizedPacketBeforeAllocation() {
        var decoder = ScrcpyDecoder()
        #expect(throws: ProtocolError.oversized) { try decoder.append(Data([0, 255, 255, 255, 255])) }
    }
    @Test func setClipboardUsesByteCountAndNeverPastes() throws {
        let packet = try ScrcpyEncoder.clipboard("я", sequence: 42)
        #expect(Array(packet) == [9, 0, 0, 0, 0, 0, 0, 0, 42, 0, 0, 0, 0, 2, 209, 143])
        #expect(throws: ProtocolError.oversized) { try ScrcpyEncoder.clipboard(String(repeating: "a", count: 1 << 18), sequence: 1) }
    }
    @Test func jsonStreamFragmentationAndMultipleMessages() throws {
        var decoder = JSONLineDecoder()
        #expect(try decoder.append(Data("{\"type\":\"rea".utf8)).isEmpty)
        let frames = try decoder.append(Data("dy\"}\n{\"type\":\"ping\"}\n".utf8))
        #expect(frames.compactMap { $0["type"] as? String } == ["ready", "ping"])
        #expect(throws: ProtocolError.oversized) { try decoder.append(Data(repeating: 65, count: JSONLineDecoder.maxLine + 1)) }
    }
    @Test func adbStatesAndDeviceNames() {
        let devices = AndroidDevice.parse("List of devices attached\nabc device product:x model:Pixel_9 device:x\ndef unauthorized\n* daemon started successfully\n")
        #expect(devices.count == 2)
        #expect(devices[0].name == "Pixel 9")
        #expect(devices[0].authorized)
        #expect(!devices[1].authorized)
    }
    @Test func remoteFilesStayInsideOutbox() {
        let base = FilePolicy.outboxPrefixes[0]
        #expect(FilePolicy.allowedRemoteFile(base + "random.jpg"))
        for leaf in ["../secret", "..", ".", "a/b", "a\nfile", "a\0file", ""] {
            #expect(!FilePolicy.allowedRemoteFile(base + leaf))
        }
        #expect(!FilePolicy.allowedRemoteFile("/sdcard/secrets.txt"))
    }
}
