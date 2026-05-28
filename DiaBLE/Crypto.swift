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

    /// TODO: the actual method needed to be implemented should be
    /// `deriveKAuthFromPatchEphemeral()`, a quite hairy task
    /// for the first pairing because of Trident's SKB use of WBAES
    /// (White-Box AES), which converts the standard AES algorithm into
    /// a network of precomputed T-tables (lookup tables).
    /// https://github.com/gui-dos/DiaBLE/commit/5c3cec7#commitcomment-184791786
    public func deriveSymmetricKey() -> Data {

        // Claude: TODO:

        let sensorStaticPub = try! P256.KeyAgreement.PublicKey(x963Representation: patchCertificate!.patchStaticPublicKey)
        let sensorEphPub    = try! P256.KeyAgreement.PublicKey(x963Representation: patchEphemeral)

        // LibreCRKit 3DH-style first-pairing:
        //
        ///// ECDH(phone_eph_priv, sensor_static_pub).
        // public let sharedEphStatic: Data
        ///// ECDH(phone_eph_priv, sensor_eph_pub).
        // public let sharedEphEph: Data
        // let Zs = try! ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: sensorStaticPub)

        let Zs = try! appStaticPrivateKey.sharedSecretFromKeyAgreement(with: sensorStaticPub)
            .withUnsafeBytes { Data($0) }
        let Ze = try! ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: sensorEphPub)
            .withUnsafeBytes { Data($0) }
        // let ikm = Zs + Ze
        let ikm = Ze + Zs
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ikm),
            salt:             Data(),
            info:             Data("".utf8), // TODO: from kAuth
            outputByteCount:  16
        ).withUnsafeBytes { Data($0) }
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
            debugLog("AES encryption error: \(error)")
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
            debugLog("AES decryption error: \(error)")
            return nil
        }
    }


    public func encryptPacket(data: Data, type: PacketType, ivEnc: Data, sequenceId: UInt16) -> Data? {
        let nonce = sequenceId.data + Data(Libre3.packetDescriptors[Int(type.rawValue)]) + ivEnc
        return aesEncrypt(data: data, nonce: nonce)
    }


    public func decryptPacket(data: Data, type: PacketType, ivEnc: Data) -> Data? {
        let nonce = data.suffix(2) + Data(Libre3.packetDescriptors[Int(type.rawValue)]) + ivEnc
        return aesDecrypt(data: data, nonce: nonce)
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
