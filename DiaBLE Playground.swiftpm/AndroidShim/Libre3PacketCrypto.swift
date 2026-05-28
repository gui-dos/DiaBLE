import CommonCrypto
import Foundation

/// AES-128-CCM session crypto for the Libre 3 BLE protocol.
///
/// This is the **post-handshake** packet codec. It runs entirely on the iOS
/// device (no server round-trip). Inputs are `kEnc`/`ivEnc` which the
/// Android crypto server returns from `challengeDecrypt` (opcode 8).
///
/// Verified against captures from the official iOS Libre 3 app on
/// 2026-05-03 (kEnc=08D1BE34..., ivEnc=00000000 9849F0AF).
///
/// Nonce layout (13 bytes):
///   `[0..2)`  sequence (LE uint16)
///   `[2..5)`  packet descriptor (3 bytes, picked by `kind`)
///   `[5..13)` ivEnc (8 bytes)
///
/// Wire encoding for *outgoing* packets:
///   `ciphertext || tag(4) || sequence(2 LE)`
///
/// Implementation note: CryptoKit doesn't expose AES-CCM, and the
/// CommonCrypto AES-CCM API is in the private SPI header. So we implement
/// RFC 3610 AES-CCM in Swift on top of a public AES-128 ECB primitive
/// (`CCCrypt`). All Libre 3 traffic uses a 13-byte nonce + 4-byte tag,
/// so we hard-code those parameters.
enum Libre3PacketCrypto {
    /// Per-kind 3-byte packet descriptors. Index = kind. Layout matches
    /// Juggluco's `bcrypt.cpp`.
    static let packetDescriptors: [Data] = [
        Data([0x00, 0x00, 0x00]), // kind 0: outgoing patch-control encryption
        Data([0x00, 0x00, 0x0F]), // kind 1: patch-control notification decrypt
        Data([0x00, 0x00, 0xF0]), // kind 2: patch-status notification decrypt
        Data([0x00, 0x0F, 0x00]), // kind 3: one-minute glucose decrypt
        Data([0x00, 0xF0, 0x00]), // kind 4: historic data decrypt
        Data([0x0F, 0x00, 0x00]), // kind 5: clinical/fast data decrypt
        Data([0xF0, 0x00, 0x00]), // kind 6: event log decrypt
        Data([0x44, 0x00, 0x00])  // kind 7: factory data decrypt
    ]

    static let nonceLength = 13
    static let tagLength = 4
    static let kEncLength = 16
    static let ivEncLength = 8
    static let sequenceFieldLength = 2

    enum CryptoError: Error, LocalizedError {
        case invalidKindOrParameter(String)
        case operationFailed(operation: String, status: CCCryptorStatus)
        case truncatedInput(expectedAtLeast: Int, got: Int)
        case authenticationFailed

        var errorDescription: String? {
            switch self {
            case .invalidKindOrParameter(let why): return "Invalid argument: \(why)"
            case .operationFailed(let op, let status): return "\(op) failed with CCCryptorStatus \(status)"
            case .truncatedInput(let need, let got): return "Input truncated: needed >= \(need) bytes, got \(got)"
            case .authenticationFailed: return "AES-CCM tag mismatch (decrypt failed)"
            }
        }
    }

    static func makeNonce(sequence: UInt16, kind: Int, ivEnc: Data) throws -> Data {
        guard kind >= 0, kind < packetDescriptors.count else {
            throw CryptoError.invalidKindOrParameter("kind=\(kind) out of range 0..<\(packetDescriptors.count)")
        }
        guard ivEnc.count == ivEncLength else {
            throw CryptoError.invalidKindOrParameter("ivEnc must be \(ivEncLength) bytes, got \(ivEnc.count)")
        }
        var nonce = Data(capacity: nonceLength)
        nonce.append(UInt8(sequence & 0xFF))
        nonce.append(UInt8((sequence >> 8) & 0xFF))
        nonce.append(packetDescriptors[kind])
        nonce.append(ivEnc)
        precondition(nonce.count == nonceLength)
        return nonce
    }

    static func encrypt(
        plaintext: Data,
        sequence: UInt16,
        kind: Int,
        kEnc: Data,
        ivEnc: Data
    ) throws -> Data {
        guard kEnc.count == kEncLength else {
            throw CryptoError.invalidKindOrParameter("kEnc must be \(kEncLength) bytes, got \(kEnc.count)")
        }
        let nonce = try makeNonce(sequence: sequence, kind: kind, ivEnc: ivEnc)
        return try ccmEncrypt(plaintext: plaintext, key: kEnc, nonce: nonce, tagLength: tagLength)
    }

    static func decrypt(
        ciphertextAndTag: Data,
        sequence: UInt16,
        kind: Int,
        kEnc: Data,
        ivEnc: Data
    ) throws -> Data {
        guard kEnc.count == kEncLength else {
            throw CryptoError.invalidKindOrParameter("kEnc must be \(kEncLength) bytes, got \(kEnc.count)")
        }
        guard ciphertextAndTag.count >= tagLength else {
            throw CryptoError.truncatedInput(expectedAtLeast: tagLength, got: ciphertextAndTag.count)
        }
        let nonce = try makeNonce(sequence: sequence, kind: kind, ivEnc: ivEnc)
        let split = ciphertextAndTag.count - tagLength
        let ciphertext = Data(ciphertextAndTag.prefix(split))
        let tag = Data(ciphertextAndTag.suffix(tagLength))
        return try ccmDecrypt(ciphertext: ciphertext, tag: tag, key: kEnc, nonce: nonce)
    }

    static func encodeOutgoingForCharacteristic(
        plaintext: Data,
        sequence: UInt16,
        kEnc: Data,
        ivEnc: Data
    ) throws -> Data {
        var encoded = try encrypt(
            plaintext: plaintext,
            sequence: sequence,
            kind: 0,
            kEnc: kEnc,
            ivEnc: ivEnc
        )
        encoded.append(UInt8(sequence & 0xFF))
        encoded.append(UInt8((sequence >> 8) & 0xFF))
        return encoded
    }

    static func splitIncomingFromCharacteristic(_ wire: Data) throws -> (ciphertextAndTag: Data, sequence: UInt16) {
        guard wire.count >= sequenceFieldLength + tagLength else {
            throw CryptoError.truncatedInput(
                expectedAtLeast: sequenceFieldLength + tagLength,
                got: wire.count
            )
        }
        let split = wire.count - sequenceFieldLength
        let inner = Data(wire.prefix(split))
        let seqBytes = Data(wire.suffix(sequenceFieldLength))
        let lo = UInt16(seqBytes[seqBytes.startIndex])
        let hi = UInt16(seqBytes[seqBytes.startIndex.advanced(by: 1)])
        let sequence = lo | (hi << 8)
        return (inner, sequence)
    }

    // MARK: - RFC 3610 AES-CCM

    private static let ccmM = 4
    private static let ccmL = 2

    private static func ccmEncrypt(
        plaintext: Data,
        key: Data,
        nonce: Data,
        tagLength: Int
    ) throws -> Data {
        precondition(tagLength == ccmM, "Libre 3 always uses a 4-byte tag")
        precondition(nonce.count == 15 - ccmL, "Libre 3 always uses a 13-byte nonce")
        precondition(plaintext.count <= 0xFFFF, "L=2 caps plaintext at 65535 bytes")

        let mac = try ccmCbcMac(plaintext: plaintext, key: key, nonce: nonce)
        let s0 = try ccmCounterBlock(0, key: key, nonce: nonce)

        var ciphertext = Data(count: plaintext.count)
        var counter = 1
        var offset = 0
        while offset < plaintext.count {
            let s = try ccmCounterBlock(counter, key: key, nonce: nonce)
            let chunk = min(16, plaintext.count - offset)
            for i in 0 ..< chunk {
                ciphertext[offset + i] = plaintext[plaintext.startIndex + offset + i] ^ s[i]
            }
            offset += chunk
            counter += 1
        }

        var encryptedTag = Data(count: ccmM)
        for i in 0 ..< ccmM {
            encryptedTag[i] = mac[i] ^ s0[i]
        }

        var output = Data(capacity: ciphertext.count + ccmM)
        output.append(ciphertext)
        output.append(encryptedTag)
        return output
    }

    private static func ccmDecrypt(
        ciphertext: Data,
        tag: Data,
        key: Data,
        nonce: Data
    ) throws -> Data {
        precondition(tag.count == ccmM, "Libre 3 always uses a 4-byte tag")
        precondition(nonce.count == 15 - ccmL, "Libre 3 always uses a 13-byte nonce")

        let s0 = try ccmCounterBlock(0, key: key, nonce: nonce)

        var plaintext = Data(count: ciphertext.count)
        var counter = 1
        var offset = 0
        while offset < ciphertext.count {
            let s = try ccmCounterBlock(counter, key: key, nonce: nonce)
            let chunk = min(16, ciphertext.count - offset)
            for i in 0 ..< chunk {
                plaintext[offset + i] = ciphertext[ciphertext.startIndex + offset + i] ^ s[i]
            }
            offset += chunk
            counter += 1
        }

        var receivedMac = Data(count: ccmM)
        for i in 0 ..< ccmM {
            receivedMac[i] = tag[tag.startIndex + i] ^ s0[i]
        }

        let computedMac = try ccmCbcMac(plaintext: plaintext, key: key, nonce: nonce)
        let expectedMac = Data(computedMac.prefix(ccmM))
        guard expectedMac == receivedMac else {
            throw CryptoError.authenticationFailed
        }
        return plaintext
    }

    private static func ccmCbcMac(plaintext: Data, key: Data, nonce: Data) throws -> Data {
        let flagsB0 = UInt8(((ccmM - 2) / 2) << 3) | UInt8(ccmL - 1)
        var b0 = Data(capacity: 16)
        b0.append(flagsB0)
        b0.append(nonce)
        let plaintextLen = plaintext.count
        for shift in stride(from: ccmL - 1, through: 0, by: -1) {
            b0.append(UInt8((plaintextLen >> (8 * shift)) & 0xFF))
        }
        precondition(b0.count == 16)

        var mac = try aes128EcbEncryptBlock(b0, key: key)

        var offset = 0
        while offset < plaintext.count {
            var block = Data(count: 16)
            let chunk = min(16, plaintext.count - offset)
            for i in 0 ..< chunk {
                block[i] = plaintext[plaintext.startIndex + offset + i]
            }
            for i in 0 ..< 16 {
                block[i] ^= mac[i]
            }
            mac = try aes128EcbEncryptBlock(block, key: key)
            offset += chunk
        }
        return mac
    }

    private static func ccmCounterBlock(_ counter: Int, key: Data, nonce: Data) throws -> Data {
        let flagsAi = UInt8(ccmL - 1)
        var ai = Data(capacity: 16)
        ai.append(flagsAi)
        ai.append(nonce)
        for shift in stride(from: ccmL - 1, through: 0, by: -1) {
            ai.append(UInt8((counter >> (8 * shift)) & 0xFF))
        }
        precondition(ai.count == 16)
        return try aes128EcbEncryptBlock(ai, key: key)
    }

    private static func aes128EcbEncryptBlock(_ block: Data, key: Data) throws -> Data {
        precondition(block.count == 16)
        precondition(key.count == 16)

        let blockCount = block.count
        let keyCount = key.count
        let outputCapacity = 16

        var output = Data(count: outputCapacity)
        var outMoved = 0
        let status = output.withUnsafeMutableBytes { outBuf -> CCCryptorStatus in
            block.withUnsafeBytes { inBuf -> CCCryptorStatus in
                key.withUnsafeBytes { keyBuf -> CCCryptorStatus in
                    CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuf.baseAddress, keyCount,
                        nil,
                        inBuf.baseAddress, blockCount,
                        outBuf.baseAddress, outputCapacity,
                        &outMoved
                    )
                }
            }
        }
        guard status == kCCSuccess, outMoved == outputCapacity else {
            throw CryptoError.operationFailed(operation: "AES-128-ECB block encrypt", status: status)
        }
        return output
    }
}

// MARK: - Per-session AES-CCM state

/// Stateful holder for a single BLE session's AES-CCM key/IV plus the
/// outgoing sequence counter. Mirrors the iOS app's
/// `Libre3.Libre3BCSecurityContext`.
///
/// In the server-backed architecture this is constructed from the 56-byte
/// plaintext that the Android server returns from `challengeDecrypt`
/// (`r2 || r1 || kEnc(16) || ivEnc(8)`).
///
/// `outCryptoSequence` starts at **1**, not 0, and is post-incremented
/// after each outgoing encrypt (per `bcrypt.cpp:79-92`).
final class Libre3SessionContext: Logging {

    // DiaBLE interconnection
    var main: MainDelegate!

    let kEnc: Data
    let ivEnc: Data
    private(set) var outCryptoSequence: UInt16 = 1

    enum SessionError: Error, LocalizedError {
        case invalidKeyLength(Int)
        case invalidIVLength(Int)

        var errorDescription: String? {
            switch self {
            case .invalidKeyLength(let n):
                return "kEnc must be \(Libre3PacketCrypto.kEncLength) bytes, got \(n)"
            case .invalidIVLength(let n):
                return "ivEnc must be \(Libre3PacketCrypto.ivEncLength) bytes, got \(n)"
            }
        }
    }

    init(kEnc: Data, ivEnc: Data) throws {
        guard kEnc.count == Libre3PacketCrypto.kEncLength else {
            throw SessionError.invalidKeyLength(kEnc.count)
        }
        guard ivEnc.count == Libre3PacketCrypto.ivEncLength else {
            throw SessionError.invalidIVLength(ivEnc.count)
        }
        self.kEnc = kEnc
        self.ivEnc = ivEnc
    }

    /// Constructs from the 56-byte challenge plaintext that
    /// `challengeDecrypt` returns: `r2(16) || r1(16) || kEnc(16) || ivEnc(8)`.
    /// The caller must verify the embedded r1/r2 match the values it sent
    /// before constructing the session.
    convenience init(fromChallengePlaintext plaintext: Data) throws {
        guard plaintext.count == 56 else {
            throw SessionError.invalidKeyLength(plaintext.count)
        }
        let start = plaintext.startIndex
        let kEnc = plaintext.subdata(in: start.advanced(by: 32) ..< start.advanced(by: 48))
        let ivEnc = plaintext.subdata(in: start.advanced(by: 48) ..< start.advanced(by: 56))
        try self.init(kEnc: kEnc, ivEnc: ivEnc)
    }

    func resetOutgoingSequence() {
        outCryptoSequence = 1
    }

    func encryptOutgoingPatchControl(plaintext: Data) throws -> Data {
        let seq = outCryptoSequence
        let wire = try Libre3PacketCrypto.encodeOutgoingForCharacteristic(
            plaintext: plaintext,
            sequence: seq,
            kEnc: kEnc,
            ivEnc: ivEnc
        )
        outCryptoSequence &+= 1
        return wire
    }

    func decryptIncoming(wire: Data, kind: Int) throws -> Data {
        let parts = try Libre3PacketCrypto.splitIncomingFromCharacteristic(wire)
        debugLog("Shim/session: decrypting incoming packet: kind: \(kind) (\(Libre3.PacketType(rawValue: UInt8(kind))!)), sequential id: \(parts.sequence), ciphertext+tag: \(parts.ciphertextAndTag.hex) (\(parts.ciphertextAndTag.count) bytes), kEnc: \(kEnc.hex), ivEnc: \(ivEnc.hex)")
        return try Libre3PacketCrypto.decrypt(
            ciphertextAndTag: parts.ciphertextAndTag,
            sequence: parts.sequence,
            kind: kind,
            kEnc: kEnc,
            ivEnc: ivEnc
        )
    }

    func decryptOneMinute(wire: Data) throws -> Libre3Payloads.OneMinute {
        let plaintext = try decryptIncoming(wire: wire, kind: 3)
        return try Libre3Payloads.OneMinute.decode(plaintext)
    }

    func decryptPatchStatus(wire: Data) throws -> Libre3Payloads.PatchStatus {
        let plaintext = try decryptIncoming(wire: wire, kind: 2)
        return try Libre3Payloads.PatchStatus.decode(plaintext)
    }
}
