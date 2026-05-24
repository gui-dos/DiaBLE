import Foundation

/// Reassembles fragmented BLE notifications on the security characteristics.
///
/// Each fragment carries a leading sequence byte; the payload of multi-fragment
/// reads is announced earlier on the command/response characteristic via a
/// `(signal, expectedLength)` pair. We collect fragments until the
/// concatenated payload reaches `expectedLength`, then deliver it.
struct Libre3SecurityFrameBuffer {
    struct AppendResult {
        let sequence: UInt8
        let payloadLength: Int
        let assembledLength: Int
        let expectedLength: Int?
        let replacedExistingFragment: Bool
        let completedPayload: Data?
    }

    private(set) var expectedLength: Int?
    private var fragments: [UInt8: Data] = [:]

    mutating func reset(expectedLength: Int? = nil) {
        self.expectedLength = expectedLength
        fragments.removeAll()
    }

    mutating func setExpectedLength(_ length: Int) {
        expectedLength = length
        fragments.removeAll()
    }

    mutating func appendFragment(_ data: Data) -> AppendResult? {
        guard let sequence = data.first else { return nil }

        let payload = data.dropFirst()
        let replacedExistingFragment = fragments[sequence] != nil
        fragments[sequence] = payload

        let assembled = assembledPayload()
        let completedPayload: Data?
        if let expectedLength, assembled.count >= expectedLength {
            completedPayload = assembled.prefix(expectedLength)
        } else {
            completedPayload = nil
        }

        return AppendResult(
            sequence: sequence,
            payloadLength: payload.count,
            assembledLength: assembled.count,
            expectedLength: expectedLength,
            replacedExistingFragment: replacedExistingFragment,
            completedPayload: completedPayload
        )
    }

    private func assembledPayload() -> Data {
        var data = Data()
        for key in fragments.keys.sorted() {
            data.append(fragments[key] ?? Data())
        }
        return data
    }

    /// Chunks an outbound large payload (162-B cert, 65-B ephemeral, 40-B
    /// challenge response) into 20-byte BLE writes:
    /// `[offsetLE16][up to 18 bytes payload]`.
    static func chunksForOffsetWrite(_ payload: Data) -> [Data] {
        var chunks: [Data] = []
        var offset = 0

        while offset < payload.count {
            let remaining = payload.count - offset
            let payloadLength = min(18, remaining)
            var chunk = Data()
            chunk.append(UInt8(offset & 0xFF))
            chunk.append(UInt8((offset >> 8) & 0xFF))
            chunk.append(payload.subdata(in: offset ..< offset + payloadLength))
            chunks.append(chunk)
            offset += payloadLength
        }

        return chunks
    }
}
