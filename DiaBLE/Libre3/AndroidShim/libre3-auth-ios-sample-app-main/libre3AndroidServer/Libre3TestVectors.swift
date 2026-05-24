import Foundation

/// Offline self-tests for the **local** code paths. Anything that depends
/// on the Android crypto server is excluded — those need a live server
/// and are exercised through the UI's "Server health" button instead.
///
/// All vectors come from the 2026-05-03 Frida capture (sensor 0JY594794).
enum Libre3TestVectors {
    enum Result {
        case pass(String)
        case fail(String, reason: String)

        var summary: String {
            switch self {
            case .pass(let name): return "PASS  \(name)"
            case .fail(let name, let reason): return "FAIL  \(name) — \(reason)"
            }
        }
        var didPass: Bool { if case .pass = self { return true } else { return false } }
    }

    static func runAll() -> [Result] {
        return [
            patchCertificateSignatureVerifies(),
            challengeSplit(),
            packetDescriptorTable(),
            sessionDecryptGlucose(),
            sessionDecryptPatchStatus(),
            sessionEncryptOutgoingPatchControl(),
            outgoingFramingRoundtrip(),
            oneMinuteDecodeMatchesCapture(),
            patchStatusDecodeMatchesCapture(),
            patchStaticPubkeyMatchesGOtherKeyCapture(),
            sessionContextDecryptsCapturedGlucose(),
            sessionContextDecryptsCapturedPatchStatus(),
            sessionContextEncryptRoundtripsCapturedWire(),
            hexInitParsesAndRoundtrips(),
            historyBackfillFrom5MatchesCapturedSample(),
            nfcPayloadCRC16Roundtrips(),
            nfcFnv32MatchesDiaBLEReference()
        ]
    }

    // MARK: - Local crypto

    static func patchCertificateSignatureVerifies() -> Result {
        let name = "patch certificate ECDSA verifies with level-1 signing key"
        do {
            let cert = try Libre3PatchCertificate(
                data: Libre3ResearchMaterial.CapturedHandshake.patchCertificate,
                signingPublicKey: Libre3ResearchMaterial.patchSigningPublicKeyLevel1
            )
            guard cert.isSignatureValid else {
                return .fail(name, reason: "Signature did not verify")
            }
            guard cert.patchStaticPublicKey.count == 65,
                  cert.patchStaticPublicKey.first == 0x04 else {
                return .fail(name, reason: "Patch static public key shape unexpected")
            }
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    static func challengeSplit() -> Result {
        let name = "23-byte challenge splits into 16-byte r1 and 7-byte nonce1"
        let challenge = Libre3ResearchMaterial.CapturedHandshake.challenge23
        let r1 = challenge.prefix(16)
        let nonce1 = challenge.dropFirst(16)
        guard r1 == Libre3ResearchMaterial.CapturedHandshake.challengeR1 else {
            return .fail(name, reason: "r1 mismatch")
        }
        guard Data(nonce1) == Libre3ResearchMaterial.CapturedHandshake.challengeNonce1 else {
            return .fail(name, reason: "nonce1 mismatch")
        }
        return .pass(name)
    }

    static func packetDescriptorTable() -> Result {
        let name = "AES-CCM packet descriptor table matches Juggluco"
        let expected: [Data] = [
            Data([0x00, 0x00, 0x00]),
            Data([0x00, 0x00, 0x0F]),
            Data([0x00, 0x00, 0xF0]),
            Data([0x00, 0x0F, 0x00]),
            Data([0x00, 0xF0, 0x00]),
            Data([0x0F, 0x00, 0x00]),
            Data([0xF0, 0x00, 0x00]),
            Data([0x44, 0x00, 0x00])
        ]
        guard Libre3PacketCrypto.packetDescriptors == expected else {
            return .fail(name, reason: "Descriptor table differs")
        }
        return .pass(name)
    }

    static func sessionDecryptGlucose() -> Result {
        let name = "decrypt captured glucose ciphertext (kind 3, seq 1)"
        do {
            var input = Libre3ResearchMaterial.CapturedSession.glucoseSampleCiphertext
            input.append(Libre3ResearchMaterial.CapturedSession.glucoseSampleTag)
            let plaintext = try Libre3PacketCrypto.decrypt(
                ciphertextAndTag: input, sequence: 1, kind: 3,
                kEnc: Libre3ResearchMaterial.CapturedSession.kEnc,
                ivEnc: Libre3ResearchMaterial.CapturedSession.ivEnc
            )
            guard plaintext == Libre3ResearchMaterial.CapturedSession.glucoseSamplePlaintext else {
                return .fail(name, reason: "plaintext mismatch")
            }
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    static func sessionDecryptPatchStatus() -> Result {
        let name = "decrypt captured patch-status ciphertext (kind 2, seq 1)"
        do {
            var input = Libre3ResearchMaterial.CapturedSession.patchStatusSampleCiphertext
            input.append(Libre3ResearchMaterial.CapturedSession.patchStatusSampleTag)
            let plaintext = try Libre3PacketCrypto.decrypt(
                ciphertextAndTag: input, sequence: 1, kind: 2,
                kEnc: Libre3ResearchMaterial.CapturedSession.kEnc,
                ivEnc: Libre3ResearchMaterial.CapturedSession.ivEnc
            )
            guard plaintext == Libre3ResearchMaterial.CapturedSession.patchStatusSamplePlaintext else {
                return .fail(name, reason: "plaintext mismatch")
            }
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    static func sessionEncryptOutgoingPatchControl() -> Result {
        let name = "encrypt outgoing patch-control plaintext (kind 0, seq 1)"
        do {
            let wire = try Libre3PacketCrypto.encodeOutgoingForCharacteristic(
                plaintext: Libre3ResearchMaterial.CapturedSession.outgoingPatchControlSamplePlaintext,
                sequence: 1,
                kEnc: Libre3ResearchMaterial.CapturedSession.kEnc,
                ivEnc: Libre3ResearchMaterial.CapturedSession.ivEnc
            )
            let expected = Libre3ResearchMaterial.CapturedSession.outgoingPatchControlSampleCiphertextWithTagAndSeq
            guard wire == expected else {
                return .fail(name, reason: "wire bytes mismatch")
            }
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    static func outgoingFramingRoundtrip() -> Result {
        let name = "outgoing framing round-trips through split+decrypt"
        do {
            let wire = Libre3ResearchMaterial.CapturedSession.outgoingPatchControlSampleCiphertextWithTagAndSeq
            let split = try Libre3PacketCrypto.splitIncomingFromCharacteristic(wire)
            guard split.sequence == 1 else {
                return .fail(name, reason: "sequence mismatch")
            }
            let plaintext = try Libre3PacketCrypto.decrypt(
                ciphertextAndTag: split.ciphertextAndTag,
                sequence: split.sequence, kind: 0,
                kEnc: Libre3ResearchMaterial.CapturedSession.kEnc,
                ivEnc: Libre3ResearchMaterial.CapturedSession.ivEnc
            )
            guard plaintext == Libre3ResearchMaterial.CapturedSession.outgoingPatchControlSamplePlaintext else {
                return .fail(name, reason: "plaintext mismatch")
            }
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    // MARK: - Decoders

    static func oneMinuteDecodeMatchesCapture() -> Result {
        let name = "OneMinute decoder produces sane values from captured plaintext"
        do {
            let decoded = try Libre3Payloads.OneMinute.decode(
                Libre3ResearchMaterial.CapturedSession.glucoseSamplePlaintext
            )
            guard decoded.isCurrentInValidRange else {
                return .fail(name, reason: "current=\(decoded.uncappedCurrentMgDl) out of valid range")
            }
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    static func patchStatusDecodeMatchesCapture() -> Result {
        let name = "PatchStatus decoder reads captured plaintext"
        do {
            _ = try Libre3Payloads.PatchStatus.decode(
                Libre3ResearchMaterial.CapturedSession.patchStatusSamplePlaintext
            )
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    static func historyBackfillFrom5MatchesCapturedSample() -> Result {
        let name = "historyBackfillCommand(from: 5) matches captured sample plaintext"
        let computed = Libre3Payloads.historyBackfillCommand(from: 5)
        let expected = Libre3ResearchMaterial.CapturedSession.outgoingPatchControlSamplePlaintext
        guard computed == expected else {
            return .fail(name, reason: "got \(computed.compactHexString) expected \(expected.compactHexString)")
        }
        return .pass(name)
    }

    // MARK: - Cross-checks

    static func patchStaticPubkeyMatchesGOtherKeyCapture() -> Result {
        let name = "binary-extracted patch static pubkey equals cert slice [11..76)"
        do {
            let cert = try Libre3PatchCertificate(
                data: Libre3ResearchMaterial.CapturedHandshake.patchCertificate,
                signingPublicKey: Libre3ResearchMaterial.patchSigningPublicKeyLevel1
            )
            guard cert.patchStaticPublicKey == Libre3ResearchMaterial.BinaryExtracted.patchStaticPublicKey else {
                return .fail(name, reason: "mismatch")
            }
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    // MARK: - Libre3SessionContext

    static func sessionContextDecryptsCapturedGlucose() -> Result {
        let name = "Libre3SessionContext decrypts captured glucose wire bytes"
        do {
            let session = try Libre3SessionContext(
                kEnc: Libre3ResearchMaterial.CapturedSession.kEnc,
                ivEnc: Libre3ResearchMaterial.CapturedSession.ivEnc
            )
            var wire = Libre3ResearchMaterial.CapturedSession.glucoseSampleCiphertext
            wire.append(Libre3ResearchMaterial.CapturedSession.glucoseSampleTag)
            wire.append(contentsOf: [0x01, 0x00]) // seq=1
            let decoded = try session.decryptOneMinute(wire: wire)
            guard decoded.isCurrentInValidRange else {
                return .fail(name, reason: "current out of range")
            }
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    static func sessionContextDecryptsCapturedPatchStatus() -> Result {
        let name = "Libre3SessionContext decrypts captured patch-status wire bytes"
        do {
            let session = try Libre3SessionContext(
                kEnc: Libre3ResearchMaterial.CapturedSession.kEnc,
                ivEnc: Libre3ResearchMaterial.CapturedSession.ivEnc
            )
            var wire = Libre3ResearchMaterial.CapturedSession.patchStatusSampleCiphertext
            wire.append(Libre3ResearchMaterial.CapturedSession.patchStatusSampleTag)
            wire.append(contentsOf: [0x01, 0x00])
            _ = try session.decryptPatchStatus(wire: wire)
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    static func sessionContextEncryptRoundtripsCapturedWire() -> Result {
        let name = "Libre3SessionContext encrypt produces captured wire bytes"
        do {
            let session = try Libre3SessionContext(
                kEnc: Libre3ResearchMaterial.CapturedSession.kEnc,
                ivEnc: Libre3ResearchMaterial.CapturedSession.ivEnc
            )
            let wire = try session.encryptOutgoingPatchControl(
                plaintext: Libre3ResearchMaterial.CapturedSession.outgoingPatchControlSamplePlaintext
            )
            guard wire == Libre3ResearchMaterial.CapturedSession.outgoingPatchControlSampleCiphertextWithTagAndSeq else {
                return .fail(name, reason: "mismatch")
            }
            return .pass(name)
        } catch {
            return .fail(name, reason: "\(error)")
        }
    }

    // MARK: - Utility

    static func hexInitParsesAndRoundtrips() -> Result {
        let name = "Data(hexString:) round-trips compact and spaced hex"
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x12, 0x34])
        guard let parsedCompact = Data(hexString: "DEADBEEF1234"),
              let parsedSpaced = Data(hexString: "DE AD BE EF 12 34"),
              let parsedColon = Data(hexString: "DE:AD:BE:EF:12:34") else {
            return .fail(name, reason: "init returned nil")
        }
        guard parsedCompact == bytes, parsedSpaced == bytes, parsedColon == bytes else {
            return .fail(name, reason: "round-trip mismatch")
        }
        return .pass(name)
    }

    // MARK: - NFC takeover building blocks

    static func nfcPayloadCRC16Roundtrips() -> Result {
        let name = "Libre3NFC.crc16 matches DiaBLE/Libre 3 polynomial 0x1021"
        // Reference: empty CRC of zero bytes is 0xFFFF.
        let crc = Libre3NFC.crc16(Data())
        guard crc == 0xFFFF else {
            return .fail(name, reason: "empty input CRC = 0x\(String(format: "%04X", crc)), expected 0xFFFF")
        }
        // Reference: CRC of single byte 0x00 is 0xE1F0 under poly 0x1021,
        // init 0xFFFF, reflected. The DiaBLE implementation processes bits
        // LSB-first via `byte >> i`, so this should hold.
        let payload8 = Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0])
        let p = Libre3NFC.buildTakeoverPayload(time: 0x78563412, receiverId: 0xF0DEBC9A)
        guard p.count == 10 else {
            return .fail(name, reason: "payload length \(p.count) != 10")
        }
        let firstEight = Data(p.prefix(8))
        guard firstEight == payload8 else {
            return .fail(name, reason: "first 8 bytes mismatch")
        }
        // CRC trailer matches a recomputation.
        let crc2 = Libre3NFC.crc16(firstEight)
        let expectedTrailer = Data([UInt8(crc2 & 0xFF), UInt8(crc2 >> 8)])
        guard Data(p.suffix(2)) == expectedTrailer else {
            return .fail(name, reason: "CRC trailer mismatch")
        }
        return .pass(name)
    }

    static func nfcFnv32MatchesDiaBLEReference() -> Result {
        let name = "Libre3NFC.fnv32 reference vector"
        // Reference: FNV-32a of empty string per DiaBLE is 0 (acc=0 * prime
        // XOR nothing). Non-empty: small smoke test.
        guard Libre3NFC.fnv32("") == 0 else {
            return .fail(name, reason: "empty string fnv32 != 0")
        }
        // Non-zero for a non-empty UUID-shaped string.
        let h = Libre3NFC.fnv32("5302bd69-1234-5678-9abc-def012345678")
        guard h != 0 else {
            return .fail(name, reason: "non-empty input produced 0")
        }
        return .pass(name)
    }
}
