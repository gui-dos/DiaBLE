import Foundation

extension Data {
    /// Parses a hex string into bytes. Tolerates spaces, colons, hyphens,
    /// newlines, and tabs between byte pairs.
    init?(hexString: String) {
        let cleaned = hexString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\r", with: "")
        guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }

    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var compactHexString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    var previewHexString: String {
        let limit = 48
        guard count > limit else { return hexString }
        let prefix = self.prefix(limit).hexString
        return "\(prefix) ... (\(count) bytes)"
    }

    /// Base64 wrapper used when packing payloads for the Android server.
    var base64: String { base64EncodedString() }
}

extension UInt8 {
    var twoDigitHexString: String {
        let digits = Array("0123456789ABCDEF")
        let high = digits[Int(self >> 4)]
        let low = digits[Int(self & 0x0F)]
        return String([high, low])
    }
}
