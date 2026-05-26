import Combine
import CoreNFC
import Foundation

/// Core NFC takeover for an already-activated Libre 3 sensor.
///
/// This is the **only** NFC operation the server-backed app performs.
/// We don't do fresh activation (the Libre 3 app handles that). We send
/// `02 A8 7A` ("CMD_SWITCH_RECEIVER") with a 10-byte payload to a
/// sensor that's already active under another phone, and the sensor
/// responds with a new BLE address + BLE PIN for us.
///
/// ## Wire format
///
/// **Request** (per DiaBLE [Libre3.swift:877-894](DiaBLE/DiaBLE/Libre3.swift:877)
/// and the SKB reverse-engineering doc):
///
/// ```
/// requestFlags:      0x02 (.highDataRate)
/// customCommandCode: 0xA8
/// customRequestParameters (10 bytes):
///   [0..4)   activationTime - 1   (UInt32 LE)
///   [4..8)   receiverId           (UInt32 LE, FNV-32a hash of LibreView account id)
///   [8..10)  CRC16 of the previous 8 bytes (UInt16 LE, CCITT-FALSE polynomial 0x1021, seed 0xFFFF)
/// ```
///
/// **Response** (after stripping any leading `0xA5` padding bytes):
///
/// ```
/// [0..6)   bdAddress (6 bytes, reversed to get standard MAC)
/// [6..10)  BLE_PIN   (4 bytes — fed into the challenge plaintext later)
/// [10..14) activationTime (UInt32 LE)
/// [14..16) CRC16
/// ```
///
/// An error response is `01 <code>` where `code` is one of:
///   - `0xB0`: sensor expired
///   - `0xB1`: sensor was activated by the reader, not an app
///   - `0xB2`: sensor expired (newer firmware)
///   - `0xC1` / `0xC2`: malformed metcrc payload
///
/// ## Required project configuration
///
/// Add to **Info.plist**:
///
/// ```
/// <key>NFCReaderUsageDescription</key>
/// <string>Tap your Libre 3 sensor to take over from the Libre 3 app.</string>
/// <key>com.apple.developer.nfc.readersession.iso15693.tag-identifiers</key>
/// <array>
///   <string>E007A0</string>   <!-- Abbott Diabetes Care manufacturer code -->
/// </array>
/// ```
///
/// And enable the **Near Field Communication Tag Reading** capability in
/// Signing & Capabilities. Without the entitlement, `NFCTagReaderSession`
/// won't begin.
@MainActor
final class Libre3NFC: NSObject, ObservableObject, @MainActor Logging {

    var main: MainDelegate!  // DiaBLE interconnection

    struct TakeoverResult {
        /// 6-byte BLE peripheral address (MAC), already byte-reversed to the
        /// human-readable order.
        let bdAddress: Data

        /// 4-byte BLE PIN. Feeds into the challenge plaintext
        /// (`r1(16) || r2(16) || blePIN(4)`) during the BLE handshake.
        let blePIN: Data

        /// Activation Unix time the sensor reports.
        let activationTime: UInt32

        /// 24-byte patchInfo (after stripping the leading `0xA5 0x00` and
        /// trailing CRC). Includes serial bytes and security generation.
        let patchInfo: Data

        /// ISO-15693 tag identifier (used as `sensor.uid` in DiaBLE).
        let tagIdentifier: Data

        var bdAddressString: String {
            bdAddress.map { String(format: "%02X", $0) }.joined(separator: ":")
        }
    }

    enum NFCError: Error, LocalizedError {
        case readingNotAvailable
        case noTagDetected
        case wrongTagFormat
        case patchInfoUnavailable
        case patchInfoCRC
        case sensorNotActivated
        case sensorExpired
        case takeoverErrorCode(UInt8)
        case takeoverResponseTooShort(Int)
        case takeoverResponseCRC
        case underlying(Error)

        var errorDescription: String? {
            switch self {
            case .readingNotAvailable:
                return "Core NFC is not available on this device."
            case .noTagDetected:
                return "No NFC tag detected. Hold the top of the iPhone steady against the sensor."
            case .wrongTagFormat:
                return "Detected tag is not ISO-15693 (Libre 3 expected)."
            case .patchInfoUnavailable:
                return "Could not read patchInfo from sensor."
            case .patchInfoCRC:
                return "patchInfo CRC16 mismatch — sensor read corrupt."
            case .sensorNotActivated:
                return "This sensor is not yet activated. Activate it with the Libre 3 app first, then come back to take it over."
            case .sensorExpired:
                return "This sensor is expired."
            case .takeoverErrorCode(let code):
                return "Sensor returned takeover error code 0x\(String(code, radix: 16, uppercase: true))."
            case .takeoverResponseTooShort(let n):
                return "Takeover response is \(n) bytes; expected 16."
            case .takeoverResponseCRC:
                return "Takeover response CRC16 mismatch."
            case .underlying(let e):
                return e.localizedDescription
            }
        }
    }

    /// Patch state byte (`patchInfo[14]`):
    ///   0 = manufactured
    ///   1 = activated (= "in storage" per Abbott's terminology;
    ///                  matches DiaBLE's `State.storage.rawValue`)
    ///   2..n = warming up / running / expired / errored
    /// We treat **anything other than `manufactured`** as "OK to take over"
    /// because in practice the Libre 3 app's flow lands the sensor in the
    /// running state, not literal storage.
    nonisolated static let patchInfoPatchStateIndex = 14

    @Published private(set) var isScanning: Bool = false
    @Published private(set) var lastLog: String = ""

    private var session: NFCTagReaderSession?
    private var continuation: CheckedContinuation<TakeoverResult, Error>?
    private var receiverId: UInt32 = 0

    /// Performs the takeover NFC tap.
    ///
    /// - parameter receiverId: optional pre-computed receiver ID (FNV-32 hash
    ///   of your LibreView patient/account UUID string). If 0, the sensor
    ///   will reject the command — see `Libre3NFC.fnv32(_:)`.
    func performTakeover(receiverId: UInt32) async throws -> TakeoverResult {
        guard NFCTagReaderSession.readingAvailable else {
            throw NFCError.readingNotAvailable
        }
        self.receiverId = receiverId
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.session = NFCTagReaderSession(
                pollingOption: [.iso15693],
                delegate: self,
                queue: .main
            )
            self.session?.alertMessage = "Hold the top of your iPhone against the Libre 3 sensor."
            self.isScanning = true
            self.session?.begin()
        }
    }

    // MARK: - Helpers (also used by the UI and offline tests)
    //
    // These are pure functions — declared `nonisolated` so the offline
    // self-tests can call them without hopping to the main actor.

    /// FNV-32a hash matching DiaBLE's `fnv32Hash`. The LibreLinkUp client
    /// uses the lowercased UUID string of the patient ID.
    nonisolated static func fnv32(_ string: String) -> UInt32 {
        let initial: UInt64 = 0
        let prime: UInt64 = 0x811C9DC5
        let mask: UInt64 = 0xFFFFFFFF
        let value = string.utf8.reduce(initial) { acc, byte in
            mask & (acc * prime) ^ UInt64(byte)
        }
        return UInt32(value & mask)
    }

    /// Builds the 10-byte payload used after the `02 A8 7A` (or `02 A0 7A`)
    /// custom command prefix.
    nonisolated static func buildTakeoverPayload(time: UInt32, receiverId: UInt32) -> Data {
        var payload = Data(capacity: 10)
        payload.append(contentsOf: leUInt32(time))
        payload.append(contentsOf: leUInt32(receiverId))
        let crc = crc16(payload)
        payload.append(UInt8(crc & 0xFF))
        payload.append(UInt8((crc >> 8) & 0xFF))
        return payload
    }

    nonisolated private static func leUInt32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ]
    }

    /// CRC-16 CCITT-FALSE (poly 0x1021, init 0xFFFF). Matches DiaBLE's
    /// `Data.crc16` and the Libre 3 NFC protocol.
    nonisolated static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            for i in 0 ... 7 {
                let xor = (UInt8(crc >> 15 & 1) ^ (byte >> i & 1)) == 1
                crc = xor ? (crc << 1) ^ 0x1021 : (crc << 1)
            }
        }
        return crc
    }

    // MARK: - Internal

    private func log(_ message: String) {
        lastLog = message
        NSLog("Libre3NFC: %@", message)
        main?.log("Shim/NFC: \(message)")  // DiaBLE main.log()
    }

    private func finish(success: TakeoverResult) {
        let cont = continuation
        continuation = nil
        isScanning = false
        cont?.resume(returning: success)
    }

    private func finish(error: Error) {
        let cont = continuation
        continuation = nil
        isScanning = false
        cont?.resume(throwing: error)
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension Libre3NFC: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        // no-op
    }

    nonisolated func tagReaderSession(
        _ session: NFCTagReaderSession,
        didInvalidateWithError error: Error
    ) {
        Task { @MainActor in
            if let readerErr = error as? NFCReaderError,
               readerErr.code == .readerSessionInvalidationErrorUserCanceled {
                finish(error: NFCError.underlying(error))
            } else {
                finish(error: NFCError.underlying(error))
            }
        }
    }

    nonisolated func tagReaderSession(
        _ session: NFCTagReaderSession,
        didDetect tags: [NFCTag]
    ) {
        guard let firstTag = tags.first, case .iso15693(let tag) = firstTag else {
            session.invalidate(errorMessage: "Wrong tag type")
            Task { @MainActor in finish(error: NFCError.wrongTagFormat) }
            return
        }

        Task { @MainActor in
            do {
                try await session.connect(to: firstTag)
                let result = try await performExchange(session: session, tag: tag)
                session.alertMessage = "Sensor taken over."
                session.invalidate()
                finish(success: result)
            } catch {
                session.invalidate(errorMessage: "Takeover failed: \(error.localizedDescription)")
                finish(error: error)
            }
        }
    }

    private func performExchange(
        session: NFCTagReaderSession,
        tag: NFCISO15693Tag
    ) async throws -> TakeoverResult {
        // 1. Read patchInfo via custom command 0xA1 (no params).
        let patchInfoRaw: Data
        do {
            patchInfoRaw = try await tag.customCommand(
                requestFlags: .highDataRate,
                customCommandCode: 0xA1,
                customRequestParameters: Data()
            )
        } catch {
            throw NFCError.patchInfoUnavailable
        }
        log("patchInfo raw: \(patchInfoRaw.compactHexString) (\(patchInfoRaw.count) B)")

        // Libre 3 returns 28 bytes: leading 0xA5 padding + 0x00 flag + 24-B
        // patchInfo + 2-B CRC. Verify and unwrap.
        let patchInfo24: Data
        if patchInfoRaw.count >= 28 && patchInfoRaw.first == 0xA5 {
            let crcLE = UInt16(patchInfoRaw[patchInfoRaw.endIndex - 2]) |
                        (UInt16(patchInfoRaw[patchInfoRaw.endIndex - 1]) << 8)
            let body = patchInfoRaw.subdata(in: patchInfoRaw.endIndex - 26 ..< patchInfoRaw.endIndex - 2)
            let computed = Self.crc16(body)
            guard crcLE == computed else { throw NFCError.patchInfoCRC }
            patchInfo24 = body
        } else if patchInfoRaw.count == 24 {
            patchInfo24 = patchInfoRaw
        } else {
            throw NFCError.patchInfoUnavailable
        }
        log("patchInfo: \(patchInfo24.compactHexString)")

        // patchInfo[14] is the patch-state byte. 0 = manufactured (not
        // activated yet). Anything >= 1 means activation has occurred and
        // takeover is meaningful.
        let patchState = patchInfo24[patchInfo24.startIndex
            .advanced(by: Self.patchInfoPatchStateIndex)]
        if patchState == 0 {
            throw NFCError.sensorNotActivated
        }

        // 2. Build and send the takeover command (0xA8).
        // We use `activationTime - 1` to match DiaBLE / Abbott's convention.
        // Since we don't yet know the activationTime, use current time as a
        // best guess; the sensor uses this only as part of the CRC input.
        let nowMinusOne = UInt32(Date().timeIntervalSince1970) - 1
        let payload = Self.buildTakeoverPayload(time: nowMinusOne, receiverId: receiverId)
        log("takeover payload: \(payload.compactHexString)")

        let responseRaw: Data
        do {
            responseRaw = try await tag.customCommand(
                requestFlags: .highDataRate,
                // customCommandCode: 0xA8,
                customCommandCode: 0xA0, // in DiaBLE we always keep the current BLE PIN
                customRequestParameters: payload
            )
        } catch {
            throw NFCError.underlying(error)
        }
        log("takeover response raw: \(responseRaw.compactHexString) (\(responseRaw.count) B)")

        // 3. Parse response.
        // Strip leading 0xA5 padding bytes (Abbott's NFC stack uses 0xA5
        // as "no data yet"/filler).
        let stripped = Data(responseRaw.drop(while: { $0 == 0xA5 }))
        guard let flag = stripped.first else {
            throw NFCError.takeoverResponseTooShort(stripped.count)
        }
        let body = Data(stripped.dropFirst())

        if flag == 0x01 && body.count >= 1 {
            // Error path
            throw NFCError.takeoverErrorCode(body[body.startIndex])
        }
        guard flag == 0x00 && body.count == 16 else {
            throw NFCError.takeoverResponseTooShort(stripped.count)
        }

        let bdAddress = Data(body.subdata(in: body.startIndex ..< body.startIndex.advanced(by: 6)).reversed())
        let blePIN = body.subdata(in: body.startIndex.advanced(by: 6) ..< body.startIndex.advanced(by: 10))
        let activationTimeBytes = body.subdata(in: body.startIndex.advanced(by: 10) ..< body.startIndex.advanced(by: 14))
        let activationTime: UInt32 =
            UInt32(activationTimeBytes[activationTimeBytes.startIndex]) |
            (UInt32(activationTimeBytes[activationTimeBytes.startIndex.advanced(by: 1)]) << 8) |
            (UInt32(activationTimeBytes[activationTimeBytes.startIndex.advanced(by: 2)]) << 16) |
            (UInt32(activationTimeBytes[activationTimeBytes.startIndex.advanced(by: 3)]) << 24)
        let crcLE = UInt16(body[body.startIndex.advanced(by: 14)]) |
                    (UInt16(body[body.startIndex.advanced(by: 15)]) << 8)
        let computed = Self.crc16(body.subdata(in: body.startIndex ..< body.startIndex.advanced(by: 14)))
        guard crcLE == computed else { throw NFCError.takeoverResponseCRC }

        return TakeoverResult(
            bdAddress: bdAddress,
            blePIN: blePIN,
            activationTime: activationTime,
            patchInfo: patchInfo24,
            tagIdentifier: tag.identifier
        )
    }
}
