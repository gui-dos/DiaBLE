import CryptoKit
import Foundation
import Security

/// Parser + verifier for the 140-byte patch certificate the sensor sends
/// during the BLE handshake. The Android server also verifies this; we
/// keep a local verifier so we can sanity-check the bytes without a
/// round-trip and so the parsed `patchStaticPublicKey` is visible to UI.
struct Libre3PatchCertificate {
    let header: Data
    let patchStaticPublicKey: Data
    let signature: Data
    let isSignatureValid: Bool

    init(data: Data, signingPublicKey: Data) throws {
        guard data.count == 140 else {
            throw ParseError.invalidLength(data.count)
        }

        header = data.subdata(in: 0 ..< 11)
        patchStaticPublicKey = data.subdata(in: 11 ..< 76)
        signature = data.subdata(in: 76 ..< 140)

        let publicKey = try P256.Signing.PublicKey(x963Representation: signingPublicKey)
        let ecdsaSignature = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        let signedPayload = data.subdata(in: 0 ..< 76)
        isSignatureValid = publicKey.isValidSignature(ecdsaSignature, for: signedPayload)
    }

    enum ParseError: Error, LocalizedError {
        case invalidLength(Int)

        var errorDescription: String? {
            switch self {
            case .invalidLength(let length):
                return "Expected 140-byte patch certificate, got \(length) bytes"
            }
        }
    }
}

// MARK: - P-192 ECDSA verifier (Security.framework)

/// CryptoKit cannot verify P-192 (`secp192r1`) — `P256.Signing` is the
/// smallest curve it exposes. The iOS Libre 3 binary's `patchSigningKey[v]`
/// is a 49-byte P-192 uncompressed pubkey, used to verify the 162-byte
/// `app_certificate`.
enum Libre3ECDSAVerifier {
    enum VerifierError: Error, LocalizedError {
        case invalidPublicKeyLength(Int)
        case invalidSignatureLength(Int)
        case keyConstructionFailed(String)
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .invalidPublicKeyLength(let n):
                return "Expected 49-byte uncompressed P-192 public key, got \(n) bytes"
            case .invalidSignatureLength(let n):
                return "Expected raw 48-byte (r || s) P-192 signature, got \(n) bytes"
            case .keyConstructionFailed(let why):
                return "SecKeyCreateWithData failed: \(why)"
            case .underlying(let error):
                return error.localizedDescription
            }
        }
    }

    static func verifyP192(
        publicKey: Data,
        message: Data,
        rawSignature48: Data,
        algorithm: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA256
    ) throws -> Bool {
        guard publicKey.count == 49 else {
            throw VerifierError.invalidPublicKeyLength(publicKey.count)
        }
        guard rawSignature48.count == 48 else {
            throw VerifierError.invalidSignatureLength(rawSignature48.count)
        }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String:       kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String:      kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 192
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(publicKey as CFData, attrs as CFDictionary, &error) else {
            if let e = error?.takeRetainedValue() {
                throw VerifierError.keyConstructionFailed((e as Error).localizedDescription)
            }
            throw VerifierError.keyConstructionFailed("unknown")
        }
        let der = derEncode(rs: rawSignature48, componentSize: 24)
        var verifyError: Unmanaged<CFError>?
        let ok = SecKeyVerifySignature(
            key,
            algorithm,
            message as CFData,
            der as CFData,
            &verifyError
        )
        return ok
    }

    static func derEncode(rs: Data, componentSize: Int) -> Data {
        precondition(rs.count == componentSize * 2, "rs length must be 2× componentSize")
        let r = rs.prefix(componentSize)
        let s = rs.suffix(componentSize)
        func encodeInteger(_ value: Data) -> Data {
            var stripped = Data(value.drop(while: { $0 == 0x00 }))
            if stripped.isEmpty {
                stripped = Data([0x00])
            } else if let first = stripped.first, first >= 0x80 {
                stripped.insert(0x00, at: 0)
            }
            return Data([0x02, UInt8(stripped.count)]) + stripped
        }
        let body = encodeInteger(Data(r)) + encodeInteger(Data(s))
        return Data([0x30, UInt8(body.count)]) + body
    }
}
