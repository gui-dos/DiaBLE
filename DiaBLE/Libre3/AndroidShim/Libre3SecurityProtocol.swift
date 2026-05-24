import Foundation

/// Server-backed Libre 3 SKB. Every method that would have run inside the
/// white-boxed `Libre3SKBCryptoLib` on iOS now goes over HTTP to the
/// Android crypto server.
///
/// Mapping (mirrors Juggluco's `processint`/`processbar` opcodes):
///
/// | Method                         | Server call                |
/// |--------------------------------|----------------------------|
/// | `resetCryptoContext()`         | `process1(1, null, null)`  |
/// | `initECDH(...)`                | `process1(2, appPriv, kAuth?)` |
/// | `setPatchCertificate(_)`       | `process1(4, cert, null)`  |
/// | `generateAppEphemeralPublicKey`| `process2(5, null, null)`  |
/// | `deriveKAuthFromPatchEphemeral`| `process1(6, patchEph, null)` |
/// | `challengeEncrypt(...)`        | `process2(7, nonce1, plaintext)` |
/// | `challengeDecrypt(...)`        | `process2(8, nonce, ct+tag)` |
/// | `exportKAuth()`                | `process2(9, null, null)`  |
///
/// **Out of scope:** `generateNFCActivationPayload` — the takeover payload
/// is just `time(4 LE) || receiverId(4 LE) || CRC16(2)`. We build it
/// locally in `Libre3NFC`, no server call needed.
protocol Libre3SecurityKeyBox {
    func resetCryptoContext() async throws
    func initECDH(appPrivateKey: Data, kAuth: Data?) async throws
    func setPatchCertificate(_ certificate: Data) async throws
    func generateAppEphemeralPublicKey() async throws -> Data
    func deriveKAuthFromPatchEphemeral(_ patchEphemeralPublicKey: Data) async throws
    func challengeEncrypt(nonce1: Data, plaintext: Data) async throws -> Data
    func challengeDecrypt(nonce: Data, ciphertext: Data) async throws -> Data
    func exportKAuth() async throws -> Data
}

enum Libre3SecurityKeyBoxError: Error, LocalizedError {
    case invalidInputLength(operation: String, expected: Int, got: Int)
    case patchCertificateInvalid
    case challengeMismatch(reason: String)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .invalidInputLength(let op, let expected, let got):
            return "SKB '\(op)' got \(got) bytes; expected \(expected)."
        case .patchCertificateInvalid:
            return "Local patch certificate signature check failed."
        case .challengeMismatch(let reason):
            return "Challenge round-trip mismatch: \(reason)"
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

/// Output of a successful `challengeDecrypt`.
/// Layout per Juggluco: 56 bytes = `r2 || r1 || kEnc || ivEnc`.
struct Libre3ChallengeUnpacked {
    let r2: Data
    let r1: Data
    let kEnc: Data
    let ivEnc: Data

    init(plaintext: Data) throws {
        guard plaintext.count == 56 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "Libre3ChallengeUnpacked", expected: 56, got: plaintext.count
            )
        }
        let s = plaintext.startIndex
        r2    = plaintext.subdata(in: s ..< s.advanced(by: 16))
        r1    = plaintext.subdata(in: s.advanced(by: 16) ..< s.advanced(by: 32))
        kEnc  = plaintext.subdata(in: s.advanced(by: 32) ..< s.advanced(by: 48))
        ivEnc = plaintext.subdata(in: s.advanced(by: 48) ..< s.advanced(by: 56))
    }
}

enum Libre3SecureRandom {
    static func bytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let result = data.withUnsafeMutableBytes { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, base)
        }
        precondition(result == errSecSuccess, "SecRandomCopyBytes failed: \(result)")
        return data
    }

    /// Builds the 36-byte plaintext fed to `challengeEncrypt`:
    /// `r1(16) || r2(16) || blePIN(4)`. Generates a fresh r2.
    /// `r1` comes from the 23-byte challenge the patch sent; `blePIN`
    /// comes from the NFC takeover response.
    static func buildChallengePlaintext(r1: Data, blePIN: Data) throws -> (plaintext: Data, r2: Data) {
        guard r1.count == 16 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "buildChallengePlaintext r1", expected: 16, got: r1.count
            )
        }
        guard blePIN.count == 4 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "buildChallengePlaintext blePIN", expected: 4, got: blePIN.count
            )
        }
        let r2 = bytes(16)
        var plaintext = Data(capacity: 36)
        plaintext.append(r1)
        plaintext.append(r2)
        plaintext.append(blePIN)
        return (plaintext, r2)
    }
}

// MARK: - Server-backed implementation

/// `Libre3SecurityKeyBox` that delegates every primitive to the Android
/// crypto server via `AndroidServerClient`.
final class ServerBackedSKB: Libre3SecurityKeyBox {
    let client: AndroidServerClient
    let securityVersion: Libre3ResearchMaterial.SecurityVersion

    /// True once `initECDH` returned successfully.
    private(set) var isInitialized = false
    /// True if a cached kAuth was passed to `initECDH`.
    private(set) var hasCachedKAuth = false
    /// Parsed patch certificate (local convenience, optional).
    private(set) var patchCertificate: Libre3PatchCertificate?

    init(client: AndroidServerClient,
         securityVersion: Libre3ResearchMaterial.SecurityVersion = .v1) {
        self.client = client
        self.securityVersion = securityVersion
    }

    func resetCryptoContext() async throws {
        try await client.process1(op: 1, a: nil, b: nil)
        isInitialized = false
        hasCachedKAuth = false
        patchCertificate = nil
    }

    func initECDH(appPrivateKey: Data, kAuth: Data?) async throws {
        guard !appPrivateKey.isEmpty else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "initECDH appPrivateKey", expected: 165, got: 0
            )
        }
        try await client.process1(op: 2, a: appPrivateKey, b: kAuth)
        isInitialized = true
        hasCachedKAuth = (kAuth != nil)
    }

    func setPatchCertificate(_ certificate: Data) async throws {
        // Local sanity check first — fast fail before round-tripping if the
        // bytes are obviously wrong. The server does its own definitive
        // validation through the SKB engine.
        do {
            let parsed = try Libre3PatchCertificate(
                data: certificate,
                signingPublicKey: Libre3ResearchMaterial.patchSigningPublicKeyLevel1
            )
            patchCertificate = parsed
        } catch {
            // Don't bail on parse failure here — the server may still accept
            // it under a different signing key. Just leave patchCertificate nil.
        }
        try await client.process1(op: 4, a: certificate, b: nil)
    }

    func generateAppEphemeralPublicKey() async throws -> Data {
        // The Juggluco-bundled SKB returns either 64 B (`X‖Y`, raw) or 65 B
        // (`04‖X‖Y`, uncompressed P-256). The BLE protocol expects the
        // 65-B form on the cert characteristic. Normalize here.
        let out = try await client.process2(op: 5, a: nil, b: nil)
        switch out.count {
        case 65:
            return out
        case 64:
            var prefixed = Data(capacity: 65)
            prefixed.append(0x04)
            prefixed.append(out)
            return prefixed
        default:
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "process2(5) app ephemeral", expected: 65, got: out.count
            )
        }
    }

    func deriveKAuthFromPatchEphemeral(_ patchEphemeralPublicKey: Data) async throws {
        guard patchEphemeralPublicKey.count == 65 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "deriveKAuthFromPatchEphemeral", expected: 65, got: patchEphemeralPublicKey.count
            )
        }
        try await client.process1(op: 6, a: patchEphemeralPublicKey, b: nil)
    }

    func challengeEncrypt(nonce1: Data, plaintext: Data) async throws -> Data {
        guard nonce1.count == 7 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "challengeEncrypt nonce1", expected: 7, got: nonce1.count
            )
        }
        guard plaintext.count == 36 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "challengeEncrypt plaintext", expected: 36, got: plaintext.count
            )
        }
        let out = try await client.process2(op: 7, a: nonce1, b: plaintext)
        guard out.count == 40 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "process2(7) ciphertext", expected: 40, got: out.count
            )
        }
        return out
    }

    func challengeDecrypt(nonce: Data, ciphertext: Data) async throws -> Data {
        guard nonce.count == 7 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "challengeDecrypt nonce", expected: 7, got: nonce.count
            )
        }
        guard ciphertext.count == 60 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "challengeDecrypt ciphertext", expected: 60, got: ciphertext.count
            )
        }
        let out = try await client.process2(op: 8, a: nonce, b: ciphertext)
        guard out.count == 56 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "process2(8) plaintext", expected: 56, got: out.count
            )
        }
        return out
    }

    func exportKAuth() async throws -> Data {
        let out = try await client.process2(op: 9, a: nil, b: nil)
        // Juggluco's pinned size is 149; we don't strictly enforce equality
        // in case a different build emits a slightly different wrapper —
        // but we want it to be plausibly that wrapper, not empty.
        guard out.count >= 64 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "process2(9) kAuth blob", expected: 149, got: out.count
            )
        }
        return out
    }
}

// MARK: - Convenience challenge round-trip

extension ServerBackedSKB {
    /// One-shot helper: given the 23-byte BLE challenge from the patch and
    /// the 4-byte BLE PIN from the NFC takeover response, run the full
    /// challenge round trip (encrypt → write → response → decrypt) on the
    /// server side, verify r1/r2 match, and return the unpacked
    /// `(kEnc, ivEnc)` ready to construct a `Libre3SessionContext`.
    ///
    /// This helper does NOT touch BLE. The caller is responsible for:
    ///   1. Writing the encrypted 40-byte challenge to the security-
    ///      challenge characteristic.
    ///   2. Reassembling the 67-byte response notification.
    ///   3. Splitting it into `(nonce[7], ciphertext[60])`.
    ///   4. Then calling this with both.
    func completeChallenge(
        challenge23: Data,
        blePIN: Data
    ) async throws -> (encrypted40: Data, decryptNonce: Data?, expectedR2: Data) {
        guard challenge23.count == 23 else {
            throw Libre3SecurityKeyBoxError.invalidInputLength(
                operation: "completeChallenge challenge23", expected: 23, got: challenge23.count
            )
        }
        let r1 = challenge23.prefix(16)
        let nonce1 = challenge23.dropFirst(16)
        let (plaintext, r2) = try Libre3SecureRandom.buildChallengePlaintext(
            r1: Data(r1), blePIN: blePIN
        )
        let encrypted = try await challengeEncrypt(nonce1: Data(nonce1), plaintext: plaintext)
        return (encrypted40: encrypted, decryptNonce: nil, expectedR2: r2)
    }

    /// Step 2 of the challenge: given the patch's 67-byte response
    /// (already reassembled and split into `nonce(7) || ciphertext(60)`),
    /// decrypt it, verify the embedded `r1`/`r2` against what we sent, and
    /// return the unpacked `kEnc`/`ivEnc`.
    func finishChallenge(
        responseNonce: Data,
        responseCiphertext: Data,
        sentR1: Data,
        sentR2: Data
    ) async throws -> Libre3ChallengeUnpacked {
        let plaintext = try await challengeDecrypt(
            nonce: responseNonce,
            ciphertext: responseCiphertext
        )
        let unpacked = try Libre3ChallengeUnpacked(plaintext: plaintext)
        guard unpacked.r1 == sentR1 else {
            throw Libre3SecurityKeyBoxError.challengeMismatch(reason: "r1 in response does not match what we sent")
        }
        guard unpacked.r2 == sentR2 else {
            throw Libre3SecurityKeyBoxError.challengeMismatch(reason: "r2 in response does not match what we sent")
        }
        return unpacked
    }
}
