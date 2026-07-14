import Foundation
import CryptoKit     // P-256 ECDH
import CommonCrypto
import CryptoSwift   // AES 128 CCM


extension Libre3 {

    public func initECDH() {
        ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        ephemeralPublicKey = ephemeralPrivateKey.publicKey.x963Representation
        log("Crypto: generated P-256 ECDH ephemeral private key: \(ephemeralPrivateKey.rawRepresentation.hex) (size: \(ephemeralPrivateKey.rawRepresentation.count) bytes), exported x9.63 public key: \(ephemeralPublicKey.hex) (size: \(ephemeralPublicKey.count) bytes)")
    }

    // iOS Trident (com.abbott.libre3):
    // +[FSOpenSSL computeECDHSharedAES128:appEphemeralKeys:patchStaticPubOctets:patchEphemeralPubOctets:]
    // +[FSOpenSSL encryptUsingCcmAES128:key:iv:tag_len:]
    // +[FSOpenSSL decryptUsingCcmAES128:key:iv:tag:]

    //
    // Claude:
    //
    // "Libre by Abbott" (com.abbott.adc.freestyle.libre.us v1.3.0) ECDHCryptoLib at 0x1015BB99C:
    //   Ze = ECDH(appEphemeralPrivateKey, patchEphemeralPublicKey) // 32 bytes, raw x-coordinate
    //   Zs = ECDH(appStaticPrivateKey,    patchStaticPublicKey)    // 32 bytes, raw x-coordinate
    //   key = SHA-256( 0x00000001 || Ze || Zs )[0 ..< 16]          // ANSI X9.63 single-step KDF
    //
    // Disassembly evidence:
    //   - Ze computed first at 0x1015BBA80 ("Compute Secret (Ze) error 0x%X" at 0x101F315EA)
    //   - Zs computed second at 0x1015BBB18 ("Compute Secret (Zs) error 0x%X" at 0x101F31609)
    //   - counter 0x00000001 (big-endian) loaded from __const at 0x101E84A7C
    //   - SHA256 called with 68-byte input: {counter(4)} || Ze(32) || Zs(32)
    //   - first 16 bytes returned as the key; identical logic in 3 SKB variants (MA/L3Security/LingoSecurity)

    public func deriveSharedKey() async throws -> Data {
        let sensorStaticPub = try P256.KeyAgreement.PublicKey(x963Representation: patchCertificate!.patchStaticPublicKey)
        let sensorEphPub    = try P256.KeyAgreement.PublicKey(x963Representation: patchEphemeral)

        // Raw ECDH shared secrets (x-coordinate only, 32 bytes each)
        let Ze = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: sensorEphPub)
            .withUnsafeBytes { Data($0) }
        // FIXME: cannot work because we know only the app static public key sent with the app certificate
        var Zs = try appStaticPrivateKey.sharedSecretFromKeyAgreement(with: sensorStaticPub)
            .withUnsafeBytes { Data($0) }

        // Retry by using Messina server:
        // https://github.com/awowogei/Messina/blob/master/app/src/commonMain/kotlin/messina/sensors/libre3/Security.kt
        if settings.usingMessinaSharedKeyServer {
            Zs = try await getSharedStaticKey()
        }

        // ANSI X9.63 single-step: SHA-256( counter=1 || Ze || Zs ), counter as big-endian UInt32
        let counter = "00000001".bytes
        let hashInput = counter + Ze + Zs // 68 bytes
        let digest = Data(CryptoKit.SHA256.hash(data: hashInput))
        debugLog("Crypto: SHA256(\(hashInput.hex) (\(hashInput.count) bytes)) = \(digest.hex) (\(digest.count) bytes)")
        return Data(digest.prefix(16)) // key = first 16 of 32 bytes
    }


    public func aesEncrypt(data: Data, key: Data, nonce: Data) -> Data? {
        do {
            let aes = try AES(key: Array(key),
                              blockMode: CCM(iv: Array(nonce),
                                             tagLength: 4,
                                             messageLength: data.count,
                                             additionalAuthenticatedData: Array(Data())),
                              padding: .noPadding)
            let encrypted = try aes.encrypt(Array(data))
            return Data(encrypted)
        } catch {
            debugLog("Crypto: AES CCM encryption error: \(error)")
            return nil
        }
    }


    public func aesDecrypt(data: Data, key: Data, nonce: Data) -> Data? {
        do {
            let aes = try AES(key: Array(key),
                              blockMode: CCM(iv: Array(nonce),
                                             tagLength: 4,
                                             messageLength: data.count - 4,
                                             additionalAuthenticatedData: Array(Data())),
                              padding: .noPadding)
            let decrypted = try aes.decrypt(Array(data))
            return Data(decrypted)
        } catch {
            debugLog("Crypto: AES CCM decryption error: \(error)")
            return nil
        }
    }


    public func encryptPacket(data: Data, type: PacketType, ivEnc: Data, sequenceId: UInt16) -> Data? {
        let nonce = sequenceId.data + Data(Libre3.packetDescriptors[Int(type.rawValue)]) + ivEnc
        return aesEncrypt(data: data, key: kEnc, nonce: nonce)
    }


    public func decryptPacket(data: Data, type: PacketType, ivEnc: Data) -> Data? {
        let nonce = data.suffix(2) + Data(Libre3.packetDescriptors[Int(type.rawValue)]) + ivEnc
        return aesDecrypt(data: data.dropLast(2), key: kEnc, nonce: nonce)
    }


    // https://github.com/awowogei/Messina/blob/master/app/src/commonMain/kotlin/messina/sensors/libre3/Security.kt
    // https://github.com/j-kaltes/Juggluco/blob/primary/Common/src/libre3/java/tk/glucodata/KEYSCrypto.java
    // use Juggluco's 65-byte whiteCryption SKB blob wrapping the app private key
    func getSharedStaticKey() async throws -> Data {
        let payload: [String: String] = [
            "private_key": "1D 85 8F 06 02 00 00 00 01 00 00 01 00 00 00 00 00 96 95 77 4B 9A 04 53 51 FB 16 0B EC 5F 49 DB DF 0D C0 CE 52 FB 56 5F 84 E6 13 B8 19 AE D3 DF 91 9C E3 0A 3D D4 C0 12 EA EA 70 C8 CC E2 89 58 40 00 00 00 01 9B C7 79 12 3D 86 60 B3 7E 99 B4 BF 10 C1 C4 2C 11 35 B3 02 5B C9 B2 EF 00 00 00 20 E3 A1 FB 17 80 A1 63 80 2A A0 FE B1 F2 00 AC 26 9A 42 B2 29 03 8C A6 E1 4D 40 EF BC 6B 7B 6A E8 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 CE C6 67 E6 C0 9D 20 F5 C0 33 D0 61 B5 FC A1 8B 39 92 06 8B".replacingOccurrences(of: " ", with: ""),
            "public_key": patchCertificate!.patchStaticPublicKey.hex,
        ]
        var request = URLRequest(url: URL(string: "https://149.28.60.85.nip.io")!)
        request.httpMethod = "POST"
        // request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        debugLog("Libre 3: posting to \(request.url!.absoluteString) JSON payload:\(request.httpBody!.string)")
        let (body, response) = try await URLSession(configuration: .ephemeral)
            .data(for: request)
        debugLog("Libre 3: shared key response body: \(body.string.trimmingCharacters(in: .newlines))")
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SharedKeyError.httpStatus(http.statusCode,
                                            body: String(data: body, encoding: .utf8),
                                            headers: http.allHeaderFields as! [String: String])
        }
        let hexString = String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = hexString.bytes
        if key.count < 16 {
            throw SharedKeyError.malformedResponse(hexString)
        }
        return key
    }

    public enum SharedKeyError: Error, LocalizedError {
        case httpStatus(Int, body: String?, headers: [String: String])
        case malformedResponse(String)

        public var errorDescription: String? {
            switch self {
            case .httpStatus(let code, let body, let headers):
                return "Shared-key server returned HTTP status \(code), body: \(body ?? "<empty>"), headers: \(headers)"
            case .malformedResponse(let s):
                return "Shared-key response is not valid hex or is too short: \(s)"
            }
        }
    }
}



// https://github.com/LoopKit/CGMBLEKit/blob/dev/CGMBLEKit/AESCrypt.m
// https://github.com/Faifly/xDrip/blob/develop/xDrip/Services/Bluetooth/DexcomG6/Logic/Messages/Outgoing/DexcomG6AuthChallengeTxMessage.swift


extension Data {

    func aes128Encrypt(keyData: Data) -> Data? {
        guard keyData.count == kCCKeySizeAES128 else { return nil }

        let cryptLength = size_t(count + kCCBlockSizeAES128)
        var cryptData = Data(count: cryptLength)

        var numBytesEncrypted: size_t = 0
        let options = CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode)

        let cryptStatus: CCCryptorStatus = cryptData.withUnsafeMutableBytes {
            guard let cryptBytes = $0.baseAddress else {
                return CCCryptorStatus(kCCMemoryFailure)
            }
            let cryptStatus: CCCryptorStatus = self.withUnsafeBytes {
                guard let dataBytes = $0.baseAddress else {
                    return CCCryptorStatus(kCCMemoryFailure)
                }
                return keyData.withUnsafeBytes {
                    guard let keyBytes = $0.baseAddress else {
                        return CCCryptorStatus(kCCMemoryFailure)
                    }
                    return CCCrypt(
                        CCOperation(kCCEncrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        options,
                        keyBytes,
                        kCCKeySizeAES128,
                        nil,
                        dataBytes,
                        self.count,
                        cryptBytes,
                        cryptLength,
                        &numBytesEncrypted
                    )
                }
            }
            return cryptStatus
        }

        if UInt32(cryptStatus) == UInt32(kCCSuccess) {
            cryptData.count = numBytesEncrypted
        } else {
            return nil
        }
        return cryptData
    }
}
