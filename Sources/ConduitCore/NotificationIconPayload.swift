import Foundation

public enum NotificationIconPayload {
    public static let maximumBytes = 32_768
    /// Only small PNG application icons are accepted from the phone.
    public static func decode(_ base64: String) -> Data? {
        guard base64.utf8.count <= 43_692, let data = Data(base64Encoded: base64),
              data.count >= 33, data.count <= maximumBytes,
              Array(data.prefix(8)) == [137,80,78,71,13,10,26,10],
              Array(data[8..<16]) == [0,0,0,13,73,72,68,82] else { return nil }
        func integer(_ offset: Int) -> UInt32 { data[offset..<(offset+4)].reduce(0) { ($0 << 8) | UInt32($1) } }
        guard (1...256).contains(integer(16)), (1...256).contains(integer(20)) else { return nil }
        return data
    }
}
