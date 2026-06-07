import Foundation
import CryptoKit     // P-256 ECDH
import CommonCrypto
import CryptoSwift   // AES 128 CCM


// https://github.com/j-kaltes/Juggluco/blob/primary/Common/src/main/cpp/bcrypt/bcrypt.cpp
// https://github.com/LoopKit/OmniBLE/blob/dev/OmniBLE/Bluetooth/EnDecrypt/EnDecrypt.swift


extension Libre3 {

    // TODO
    public func initECDH() -> Data {
        // Generate ephemeral P-256 key pair
        ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        // Export uncompressed x9.63 public key (04 || X || Y)
        let ephemeralPublicKeyBytes = ephemeralPrivateKey.publicKey.x963Representation
        log("TEST: generated P-256 ECDH ephemeral private key: \(ephemeralPrivateKey.rawRepresentation.hex) (size: \(ephemeralPrivateKey.rawRepresentation.count) bytes), exported x9.63 public key: \(ephemeralPublicKeyBytes.hex) (size: \(ephemeralPublicKeyBytes.count) bytes)")
        return ephemeralPublicKeyBytes
    }

    // iOS Trident:
    // +[FSOpenSSL computeECDHSharedAES128:appEphemeralKeys:patchStaticPubOctets:patchEphemeralPubOctets:]
    // +[FSOpenSSL encryptUsingCcmAES128:key:iv:tag_len:]
    // +[FSOpenSSL decryptUsingCcmAES128:key:iv:tag:]

    // TODO: guess the right KDF...
    //
    // Claude:
    //
    // ANSI X9.63 / NIST SP 800-56A Single-Step KDF with SHA-256 (no OtherInfo, no salt):
    //   Zs = ECDH(appStaticPrivateKey,    patchStaticPublicKey)    // 32 bytes, raw x-coordinate
    //   Ze = ECDH(appEphemeralPrivateKey, patchEphemeralPublicKey) // 32 bytes, raw x-coordinate
    //   keyMaterial = SHA-256( 0x00000001 || Zs || Ze )            // 68-byte input → 32-byte output
    //   kEnc = keyMaterial[0 ..< 16]                               // first 16 bytes → AES-128-CCM key
    //
    // Verified by disassembly of +[FSOpenSSL computeECDHSharedAES128:...] at 0x10001284c:
    //   - ECDH_compute_key() called twice (raw, no built-in KDF)
    //   - buffer built as: w8=0x1000000 stored at [fp-0xb0] → bytes 00 00 00 01 (big-endian counter=1)
    //   - ldp q1,q0 from Zs → stur at [fp-0xb0+4] and [fp-0xb0+20]  (bytes 4–35)
    //   - ldp q1,q0 from Ze → stur at [fp-0xb0+36] and [fp-0xb0+52] (bytes 36–67)
    //   - SHA256_Init / SHA256_Update(ctx, buffer, 68=0x44) / SHA256_Final → 32-byte NSData returned
    //   - callers extract first 16 bytes as kEnc

    public func deriveSharedKey() -> Data {

        let sensorStaticPub = try! P256.KeyAgreement.PublicKey(x963Representation: patchCertificate!.patchStaticPublicKey)
        let sensorEphPub    = try! P256.KeyAgreement.PublicKey(x963Representation: patchEphemeral)

        // Raw ECDH shared secrets (x-coordinate only, 32 bytes each)
        let Zs = try! appStaticPrivateKey.sharedSecretFromKeyAgreement(with: sensorStaticPub)
            .withUnsafeBytes { Data($0) }
        let Ze = try! ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: sensorEphPub)
            .withUnsafeBytes { Data($0) }

        // ANSI X9.63 single-step: SHA-256( counter=1 || Zs || Ze ), counter as big-endian UInt32
        var counter = UInt32(1).bigEndian
        var hashInput = Data(bytes: &counter, count: 4)
        hashInput += Zs
        hashInput += Ze
        // hashInput is 4 + 32 + 32 = 68 bytes

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        hashInput.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(hashInput.count), &digest)
        }
        let keyMaterial = Data(digest)  // 32 bytes

        return keyMaterial.prefix(16)   // key = first 16 bytes
    }


    public func aesEncrypt(data: Data, nonce: Data) -> Data? {
        do {
            let aes = try AES(key: Array(kEnc),
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


    public func aesDecrypt(data: Data, nonce: Data) -> Data? {
        do {
            let aes = try AES(key: Array(kEnc),
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
        return aesEncrypt(data: data, nonce: nonce)
    }


    public func decryptPacket(data: Data, type: PacketType, ivEnc: Data) -> Data? {
        let nonce = data.suffix(2) + Data(Libre3.packetDescriptors[Int(type.rawValue)]) + ivEnc
        return aesDecrypt(data: data.dropLast(2), nonce: nonce)
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
