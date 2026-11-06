import Foundation

public enum ProtocolError: Error, Equatable {
    case oversized, unknownMessage(UInt8), invalidUTF8, malformed
}

public enum DeviceMessage: Equatable {
    case clipboard(String)
    case acknowledgement(UInt64)
}

/// scrcpy-server 5.0.1 control-only stream, with device metadata disabled.
/// TCP is a stream: a read may contain a fragment or several complete messages.
public struct ScrcpyDecoder {
    public static let maxTextBytes = (1 << 18) - 14
    private var buffer = Data()
    public init() {}

    public mutating func append(_ bytes: Data) throws -> [DeviceMessage] {
        buffer.append(bytes)
        var messages: [DeviceMessage] = []
        while !buffer.isEmpty {
            switch buffer[buffer.startIndex] {
            case 0:
                guard buffer.count >= 5 else { return messages }
                let length = Int(readUInt(buffer.dropFirst().prefix(4)))
                guard length <= (1 << 18) - 5 else { throw ProtocolError.oversized }
                guard buffer.count >= length + 5 else { return messages }
                let payload = buffer.dropFirst(5).prefix(length)
                guard let text = String(data: payload, encoding: .utf8) else { throw ProtocolError.invalidUTF8 }
                messages.append(.clipboard(text))
                buffer.removeFirst(length + 5)
            case 1:
                guard buffer.count >= 9 else { return messages }
                messages.append(.acknowledgement(readUInt(buffer.dropFirst().prefix(8))))
                buffer.removeFirst(9)
            case let type:
                // This client never creates UHID devices, so UHID output is invalid here.
                throw ProtocolError.unknownMessage(type)
            }
        }
        return messages
    }

    private func readUInt(_ bytes: Data.SubSequence) -> UInt64 {
        bytes.reduce(0) { ($0 << 8) | UInt64($1) }
    }
}

public enum ScrcpyEncoder {
    public static func clipboard(_ text: String, sequence: UInt64) throws -> Data {
        let payload = Data(text.utf8)
        guard payload.count <= ScrcpyDecoder.maxTextBytes else { throw ProtocolError.oversized }
        var result = Data([9])
        append(sequence, bytes: 8, to: &result)
        result.append(0) // Set clipboard; never inject a paste into the focused app.
        append(UInt64(payload.count), bytes: 4, to: &result)
        result.append(payload)
        return result
    }
    private static func append(_ value: UInt64, bytes: Int, to data: inout Data) {
        for shift in stride(from: (bytes - 1) * 8, through: 0, by: -8) {
            data.append(UInt8(truncatingIfNeeded: value >> shift))
        }
    }
}

public struct JSONLineDecoder {
    private var buffer = Data()
    public static let maxLine = 1 << 20
    public init() {}
    public mutating func append(_ data: Data) throws -> [[String: Any]] {
        buffer.append(data)
        var result: [[String: Any]] = []
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer[..<newline]
            guard line.count <= Self.maxLine else { throw ProtocolError.oversized }
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw ProtocolError.malformed
            }
            result.append(object)
            buffer.removeSubrange(...newline)
        }
        guard buffer.count <= Self.maxLine else { throw ProtocolError.oversized }
        return result
    }
}

public struct AndroidDevice: Identifiable, Equatable {
    public var id: String { serial }
    public let serial: String
    public let state: String
    public let name: String
    public var authorized: Bool { state == "device" }

    public static func parse(_ output: String) -> [AndroidDevice] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard fields.count >= 2, !line.hasPrefix("List of"), !line.hasPrefix("*"),
                  ["device", "offline", "unauthorized", "recovery", "sideload", "no"].contains(fields[1]) else { return nil }
            let model = fields.first(where: { $0.hasPrefix("model:") })?
                .dropFirst(6).replacingOccurrences(of: "_", with: " ") ?? fields[0]
            return AndroidDevice(serial: fields[0], state: fields[1], name: model)
        }
    }
}

public enum FilePolicy {
    public static let outboxPrefixes = [
        "/storage/emulated/0/Android/data/dev.conduit.bridge/files/outbox/",
        "/sdcard/Android/data/dev.conduit.bridge/files/outbox/"
    ]
    public static func safeName(_ value: String) -> String {
        let name = value.replacingOccurrences(of: "[^\\p{L}\\p{N}._ -]", with: "_", options: .regularExpression)
        let result = String(name.prefix(100)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty || result == "." || result == ".." ? "file" : result
    }
    public static func allowedRemoteFile(_ path: String) -> Bool {
        guard let prefix = outboxPrefixes.first(where: path.hasPrefix) else { return false }
        let leaf = String(path.dropFirst(prefix.count))
        return !leaf.isEmpty && leaf != "." && leaf != ".." && !leaf.contains("/") &&
            !leaf.contains("\\") && !leaf.contains("\0") && !leaf.contains("\n") && !leaf.contains("\r")
    }
}
