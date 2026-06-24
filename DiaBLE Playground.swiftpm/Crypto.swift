import Foundation
import CryptoKit     // P-256 ECDH
import CommonCrypto
import CryptoSwift   // AES 128 CCM
import LibreCRKit


extension Libre3 {

    // TODO
    public func initECDH() -> Data {

        if settings.usingLibreCRKit {
            nativeEphemeral = try! SessionKey.makeFirstPairNativeEphemeral { requestedCount in
                return Data((0 ..< requestedCount).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
            }
            let publicKey65 = nativeEphemeral!.keyPair.publicKey65
            log("LibreCRKit: generated P-256 ECDH native ephemeral key pair: public key: \(publicKey65.hex) (\(publicKey65.count) bytes), null attempts: \(nativeEphemeral!.attempts)")
            return publicKey65
        }

        // Generate ephemeral P-256 key pair
        ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        // Export uncompressed x9.63 public key (04 || X || Y)
        let ephemeralPublicKeyBytes = ephemeralPrivateKey.publicKey.x963Representation
        log("TEST: generated P-256 ECDH ephemeral private key: \(ephemeralPrivateKey.rawRepresentation.hex) (size: \(ephemeralPrivateKey.rawRepresentation.count) bytes), exported x9.63 public key: \(ephemeralPublicKeyBytes.hex) (size: \(ephemeralPublicKeyBytes.count) bytes)")
        return ephemeralPublicKeyBytes
    }

    // iOS Trident (com.abbott.libre3):
    // +[FSOpenSSL computeECDHSharedAES128:appEphemeralKeys:patchStaticPubOctets:patchEphemeralPubOctets:]
    // +[FSOpenSSL encryptUsingCcmAES128:key:iv:tag_len:]
    // +[FSOpenSSL decryptUsingCcmAES128:key:iv:tag:]

    // TODO: guess the right KDF...
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
    //
    // NOTE: older iOS Trident app used reversed order: SHA-256( 0x00000001 || Zs || Ze )

    public func deriveSharedKey() -> Data {

        if settings.usingLibreCRKit, let nativeEphemeral {
            let inputs = FirstPairPhase5KeyInputs(
                nullEntropy11A: nativeEphemeral.nullEntropy11A,
                sensorEphemeralPub65: patchEphemeral,
                sensorStaticPub65: patchCertificate!.patchStaticPublicKey,
                staticScalarWindow: FirstPairStaticScalarWindow.firstPairIndex1
            )
            let phase5Material = try! SessionKey.deriveFirstPairPhase5Material(inputs)
            log("LibreCRKit: derived Phase 5 raw key: \(phase5Material.rawKey.hex), null attempts: \(phase5Material.nullAttempts)")
            return phase5Material.rawKey
        }

        let sensorStaticPub = try! P256.KeyAgreement.PublicKey(x963Representation: patchCertificate!.patchStaticPublicKey)
        let sensorEphPub    = try! P256.KeyAgreement.PublicKey(x963Representation: patchEphemeral)

        // Raw ECDH shared secrets (x-coordinate only, 32 bytes each)
        let Ze = try! ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: sensorEphPub)
            .withUnsafeBytes { Data($0) }
        // FIXME: cannot work because we know only the app static public key sent with the app certificate
        let Zs = try! appStaticPrivateKey.sharedSecretFromKeyAgreement(with: sensorStaticPub)
            .withUnsafeBytes { Data($0) }

        // ANSI X9.63 single-step: SHA-256( counter=1 || Ze || Zs ), counter as big-endian UInt32
        var counter = UInt32(1).bigEndian
        var hashInput = Data(bytes: &counter, count: 4)
        hashInput += Ze
        hashInput += Zs
        // hashInput is 4 + 32 + 32 = 68 bytes

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        hashInput.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(hashInput.count), &digest)
        }
        let keyMaterial = Data(digest)  // 32 bytes
        return keyMaterial.prefix(16)   // key = first 16 bytes
    }


    public func aesEncrypt(data: Data, key: Data, nonce: Data) -> Data? {
        do {

            if settings.usingLibreCRKit && nonce.count == 7 {  // challenge data
                let encrypted = try AESCCM.encrypt(
                    nonce: nonce,
                    plaintext: data,
                    aad: Data(),
                    tagLength: 4,
                    aes: try LibAES.phase5BlockEncryptor(rawKey: key)
                )
                return encrypted.ciphertext + encrypted.tag
            }

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

            if settings.usingLibreCRKit && nonce.count == 7 {  // challenge data
                let decrypted = try AESCCM.decrypt(
                    nonce: nonce,
                    ciphertext: Data(data.dropLast(4)),
                    tag: Data(data.suffix(4)),
                    aad: Data(),
                    aes: try LibAES.phase5BlockEncryptor(rawKey: key)
                )
                return decrypted
            }

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
