import Testing
import Foundation
@testable import ConduitCore

struct NotificationIconPayloadTests {
    let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jscsAAAAASUVORK5CYII="
    @Test func acceptsSmallPNG() { #expect(NotificationIconPayload.decode(png) == Data(base64Encoded: png)) }
    @Test func rejectsMalformedAndOversizedInput() {
        #expect(NotificationIconPayload.decode("not base64") == nil)
        #expect(NotificationIconPayload.decode(Data(repeating: 0, count: 33).base64EncodedString()) == nil)
        #expect(NotificationIconPayload.decode(String(repeating: "A", count: 44_000)) == nil)
    }
    @Test func rejectsHugeDimensionsBeforeImageDecoding() {
        var data = Data(base64Encoded: png)!
        data.replaceSubrange(16..<20, with: [0,1,0,0])
        #expect(NotificationIconPayload.decode(data.base64EncodedString()) == nil)
    }
}
