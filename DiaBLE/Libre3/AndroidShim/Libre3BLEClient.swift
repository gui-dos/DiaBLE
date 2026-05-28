import Combine
import CoreBluetooth
import Foundation

struct Libre3PeripheralRow: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let advertisementSummary: String
}

struct ProtocolLogEntry: Identifiable {
    let id: Int
    let message: String
}

private struct PendingOffsetWrite {
    let uuid: CBUUID
    let chunks: [Data]
    /// Command byte to send on the command/response characteristic after
    /// the final chunk write ACK. Optional.
    let completionCommand: UInt8?
    var nextChunkIndex: Int
}

/// BLE state machine for the Libre 3 takeover-then-read flow, backed by
/// the Android crypto server.
///
/// The state machine follows the SKB doc's "Full security-command sequence"
/// (see SKB_REVERSE_ENGINEERING.md → Wire protocol details):
///
/// ```
///   01 → 02 → [app cert chunks] → 03 → patch cert (140 B)
///   → server op 4 (setPatchCertificate)
///   → 0D → server op 5 (generateAppEphemeralPublicKey)
///   → [app ephemeral chunks] → 0E
///   → patch ephemeral (65 B)
///   → server op 6 (deriveKAuthFromPatchEphemeral)
///   → 17 → challenge (23 B = r1 || nonce1)
///   → server op 7 (challengeEncrypt)
///   → [challenge ct chunks] → 08
///   → patch challenge response (67 B = nonce || ct)
///   → server op 8 (challengeDecrypt) → kEnc, ivEnc
///   → server op 9 (exportKAuth) → persist for next time
///   → enable data notifications → live glucose decode
/// ```
///
/// The BLE PIN that goes into the challenge plaintext comes from the
/// NFC takeover response (see `Libre3NFC`). Without an NFC tap first,
/// the handshake fails at the challenge step.
@MainActor
final class Libre3BLEClient: NSObject, ObservableObject, @MainActor Logging {

    var main: MainDelegate!  // DiaBLE interconnection

    enum ConnectionState: String {
        case idle = "Idle"
        case waitingForBluetooth = "Waiting for Bluetooth"
        case scanning = "Scanning"
        case connecting = "Connecting"
        case discovering = "Discovering"
        case notifications = "Notifications enabled"
        case handshaking = "Handshake in progress"
        case streaming = "Streaming"
        case disconnected = "Disconnected"
        case failed = "Failed"
    }

    enum HandshakeStage: String {
        case notStarted
        case sentStartAuth
        case wroteAppCert
        case waitingPatchCert
        case verifyingPatchCert
        case generatingAppEphemeral
        case writingAppEphemeral
        case waitingPatchEphemeral
        case derivingKAuth
        case waitingChallenge
        case encryptingChallenge
        case writingEncryptedChallenge
        case waitingChallengeResponse
        case decryptingChallenge
        case exportingKAuth
        case done
        case error
    }

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var bluetoothState = "Unknown"
    @Published private(set) var peripherals: [Libre3PeripheralRow] = []
    @Published private(set) var selectedPeripheralID: UUID?
    @Published private(set) var logs: [ProtocolLogEntry] = []
    @Published private(set) var hasSession: Bool = false
    @Published private(set) var handshakeStage: HandshakeStage = .notStarted
    @Published private(set) var latestGlucose: Libre3Payloads.OneMinute?
    @Published private(set) var latestGlucoseReceivedAt: Date?
    @Published private(set) var latestPatchStatus: Libre3Payloads.PatchStatus?
    @Published private(set) var latestPatchStatusReceivedAt: Date?

    /// One 5-minute historical glucose sample (decoded from the historic-data
    /// characteristic). `lifeCount` is the sensor age in minutes at the time
    /// of the reading; absolute time = activationTime + lifeCount × 60s.
    struct HistoricSample: Identifiable, Equatable {
        let lifeCount: UInt16
        let mgDl: UInt16
        var id: UInt16 { lifeCount }
    }

    /// All decoded 5-minute historical samples for this sensor, kept sorted
    /// by `lifeCount` ascending and deduplicated. Persists across disconnects
    /// so the reconnect backfill only needs to fetch the gap since
    /// `lastAcceptedGlucoseLifeCount`. Reset only when the sensor MAC changes.
    @Published private(set) var historicSamples: [HistoricSample] = []
    @Published private(set) var latestHistoryReceivedAt: Date?

    /// LifeCount of the most recent usable 1-min realtime glucose reading we
    /// have accepted. Used as the lower bound of the next reconnect backfill,
    /// mirroring LibreCRKit's `lastAcceptedGlucoseLifeCount`. Persisted per
    /// sensor MAC in `UserDefaults`.
    @Published private(set) var lastAcceptedGlucoseLifeCount: UInt16?

    @Published var autoEnableDataNotifications = true

    /// Sensor activation time (Unix seconds), captured from the NFC takeover.
    /// Used to convert sensor `lifeCount` (minutes since activation) into
    /// absolute wall-clock dates for graph x-axis labels.
    var activationDate: Date? {
        guard let t = takeover?.activationTime else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t))
    }

    /// Converts a sensor `lifeCount` (minutes since activation) to an
    /// absolute `Date`. Returns nil if no NFC takeover has happened yet.
    func date(forLifeCount lifeCount: UInt16) -> Date? {
        guard let activation = activationDate else { return nil }
        return activation.addingTimeInterval(TimeInterval(lifeCount) * 60)
    }

    /// How far back (in minutes) the auto-fired backfill asks the patch to
    /// stream historical 5-min samples. Default is 6 hours to match the
    /// canonical Libre graph window. Set to `nil` to request the **entire**
    /// history since sensor activation (Juggluco's default).
    ///
    /// The patch only retains a finite history buffer, so very old requests
    /// will simply return whatever it still has.
    var historyLookbackMinutes: Int? = 360

    /// NFC takeover result. Must be set before `startHandshake()` —
    /// `blePIN` feeds the challenge plaintext.
    ///
    /// **Side-effect:** assigning a non-nil takeover automatically clears
    /// any cached kAuth for that sensor MAC, because `0xA8` SWITCH_RECEIVER
    /// rotates the patch's BLE PIN, which invalidates the prior kAuth.
    /// Without this, the next handshake would take the cached path with a
    /// stale kAuth and the patch would disconnect after we send `0x08`.
    var takeover: Libre3NFC.TakeoverResult? {
        didSet {
            guard let r = takeover, r.bdAddress != oldValue?.bdAddress else { return }
            let mac = r.bdAddressString
            if kAuthStore.load(mac) != nil {
                _ = kAuthStore.remove(mac)
                exportedKAuth = nil
                log("NFC takeover landed for \(mac); cleared stale cached kAuth (BLE PIN rotated).")
            }
            // New sensor MAC → drop in-memory history and reload the
            // last-accepted lifeCount for this sensor (if any).
            if oldValue?.bdAddress != nil {
                historicSamples.removeAll()
                latestHistoryReceivedAt = nil
            }
            lastAcceptedGlucoseLifeCount = Self.loadLastAcceptedLifeCount(mac: mac)
            if let lc = lastAcceptedGlucoseLifeCount {
                log("Restored lastAcceptedGlucoseLifeCount=\(lc) for \(mac).")
            }
        }
    }

    private static func defaultsKey(for mac: String) -> String {
        "Libre3.lastAcceptedGlucoseLifeCount.\(mac)"
    }

    private static func loadLastAcceptedLifeCount(mac: String) -> UInt16? {
        let key = defaultsKey(for: mac)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        let stored = UserDefaults.standard.integer(forKey: key)
        guard stored > 0, stored <= Int(UInt16.max) else { return nil }
        return UInt16(stored)
    }

    private static func saveLastAcceptedLifeCount(_ lifeCount: UInt16, mac: String) {
        UserDefaults.standard.set(Int(lifeCount), forKey: defaultsKey(for: mac))
    }

    /// Optional cached kAuth from a previous successful handshake.
    /// When present, the server can short-circuit the ECDH/cert exchange
    /// (cached path: skips 02/0D/0E flow, jumps to 0x11 + challenge).
    var cachedKAuth: Data?

    /// The 162-byte v1 app certificate sent on command `0x02`. Must pair
    /// with `appPrivateKey` — the SKB ties the two together.
    private let appCertificate: Data

    /// The 165-byte wrapped app private key passed as the `a` parameter
    /// of `process1(op=2, …)` (initECDH) at handshake start.
    private let appPrivateKey: Data

    /// Persistent kAuth-blob store. Auto-populated on successful pairing
    /// and reused on subsequent reconnects to short-circuit ECDH.
    private let kAuthStore: Libre3KAuthStore

    /// Latest exported kAuth blob (149 B). Surfaced for the UI; the store
    /// holds the canonical persisted copy.
    @Published private(set) var exportedKAuth: Data?

    /// Debounce for the auto-fired fillHistory+fillClinical on first
    /// patch-status. Reset on disconnect.
    private var firedJugglucoBackfill: Bool = false

    /// Fragment accumulator for the glucose-data characteristic. The patch
    /// often splits each 35-B one-minute reading across two notifications
    /// (BLE ATT MTU is typically 23 → 20 payload bytes). We collect bytes
    /// here, decrypt every 35-B window, and reset. Mirrors Juggluco's
    /// `oneMinuteRawData[35]` in `Libre3GattCallback.glucose_data(...)`.
    private var glucoseAccumulator: Data = Data()
    private static let glucosePacketSize = 35

    /// Same pattern for the other data streams. Sizes for clinical (kind 5)
    /// and patch-status (kind 2) are fixed; historic/event-log are variable
    /// but typically arrive whole. Set up accumulators anyway in case the
    /// MTU is small.
    private var clinicalAccumulator: Data = Data()
    private static let clinicalPacketSize = 20  // 14 plaintext + 4 tag + 2 seq

    private var patchStatusAccumulator: Data = Data()
    private static let patchStatusPacketSize = 18  // 12 + 4 + 2

    private let server: AndroidServerClient
    private let skb: ServerBackedSKB

    private var session: Libre3SessionContext? {
        didSet {
            hasSession = (session != nil)
            // DiaBLE interconnection:
            main.shimSession = session
        }
    }

    private var central: CBCentralManager!
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var certificateBuffer = Libre3SecurityFrameBuffer()
    private var challengeBuffer = Libre3SecurityFrameBuffer()
    private var pendingNotificationOrder: [CBUUID] = []
    private var nextLogID = 0
    private var lastNotificationByCharacteristic: [CBUUID: Data] = [:]
    private var pendingOffsetWrite: PendingOffsetWrite?
    private var pendingSecurityCommandAfterAck: UInt8?

    /// FIFO of patch-control writes waiting for the patch to ACK the
    /// in-flight one. The patch processes patch-control writes serially —
    /// firing three back-to-back yields "Unknown ATT error" on the 2nd/3rd.
    /// We dequeue + write the next one in `didWriteValueFor` for the
    /// patchControl characteristic.
    private var patchControlQueue: [(label: String, wire: Data)] = []
    private var patchControlInFlight: Bool = false

    /// Captured during the handshake; needed to verify the challenge response.
    private var capturedChallenge23: Data?
    private var sentR1: Data?
    private var sentR2: Data?

    init(server: AndroidServerClient,
         main: MainDelegate? = nil,  // DiaBLE interconnection
         appCertificate: Data? = nil,
         appPrivateKey: Data? = nil,
         kAuthStore: Libre3KAuthStore? = nil) {
        self.server = server
        self.skb = ServerBackedSKB(client: server, securityVersion: .v1)
        // Defaults dereferenced inside the @MainActor init body to avoid
        // Swift 6 "main-actor-isolated default" warnings.
        self.appCertificate = appCertificate ?? Libre3ResearchMaterial.appCertificateV1Juggluco
        self.appPrivateKey  = appPrivateKey  ?? Libre3ResearchMaterial.appPrivateKeyV1Full
        self.kAuthStore     = kAuthStore     ?? .keychain
        super.init()
        // FIXME: substitutes itself to main BluetoothDelegate
        central = CBCentralManager(delegate: self, queue: nil)
        log("BLE client initialized (appCert=\(self.appCertificate.count) B, appPriv=\(self.appPrivateKey.count) B)")
    }

    // MARK: - Public surface

    func startScan() {
        guard central.state == .poweredOn else {
            state = .waitingForBluetooth
            log("Bluetooth is not powered on yet: \(bluetoothState)")
            return
        }
        peripherals.removeAll()
        discoveredPeripherals.removeAll()
        selectedPeripheralID = nil

        // First, see if iOS already has a connected/bonded handle for a
        // peripheral exposing the Libre 3 data service. After a successful
        // pairing this is the fastest reconnect path.
        let alreadyKnown = central.retrieveConnectedPeripherals(
            withServices: [Libre3BLEUUIDs.dataService, Libre3BLEUUIDs.securityService]
        )
        for p in alreadyKnown {
            ingestDiscovered(
                peripheral: p,
                advertisementData: [:],
                rssi: 0
            )
            log("Found already-connected peripheral: \(p.name ?? "?") (\(p.identifier))")
        }

        // Libre 3 sensors DON'T advertise the data service UUID, so a
        // filtered scan never matches. Scan everything; the UI shows all
        // peripherals so the user picks the right one.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        state = .scanning
        log("Scanning for nearby BLE peripherals (no service filter — Libre 3 doesn't advertise the data service UUID)")
    }

    func stopScan() {
        central.stopScan()
        if state == .scanning { state = .idle }
        log("Scan stopped")
    }

    func connect(to row: Libre3PeripheralRow) {
        guard let peripheral = discoveredPeripherals[row.id] else {
            log("Cannot connect: peripheral \(row.id) is no longer known")
            return
        }
        central.stopScan()
        selectedPeripheralID = row.id
        connectedPeripheral = peripheral
        peripheral.delegate = self
        state = .connecting
        log("Connecting to \(row.name)")
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let connectedPeripheral {
            central.cancelPeripheralConnection(connectedPeripheral)
        }
        stopScan()
        connectedPeripheral = nil
        characteristics.removeAll()
        state = .disconnected
        handshakeStage = .notStarted
        session = nil
        firedJugglucoBackfill = false
        glucoseAccumulator.removeAll(keepingCapacity: true)
        clinicalAccumulator.removeAll(keepingCapacity: true)
        patchStatusAccumulator.removeAll(keepingCapacity: true)
        // Keep historicSamples and lastAcceptedGlucoseLifeCount so the next
        // reconnect can backfill only the gap.
        patchControlQueue.removeAll()
        patchControlInFlight = false
        Task { await server.closeSession() }
        log("Disconnected by user")
    }

    /// Kick off the BLE handshake. Requires a successful NFC takeover and
    /// a configured server (`server.configure(...)`).
    func startHandshake() {
        guard takeover != nil else {
            log("Cannot start handshake: no NFC takeover result. Run the takeover NFC tap first.")
            return
        }
        guard characteristics[Libre3BLEUUIDs.securityCommandResponse] != nil else {
            log("Cannot start handshake: security characteristics not discovered yet. Connect to a peripheral first.")
            return
        }

        certificateBuffer.reset()
        challengeBuffer.reset()
        lastNotificationByCharacteristic.removeAll()
        capturedChallenge23 = nil
        sentR1 = nil
        sentR2 = nil
        pendingOffsetWrite = nil
        pendingSecurityCommandAfterAck = nil
        state = .handshaking

        // Pick up cached kAuth keyed by sensor MAC (from the NFC takeover
        // response). Falls back to caller-supplied `cachedKAuth` if set.
        let kauthFromStore: Data? = {
            if let explicit = cachedKAuth { return explicit }
            guard let mac = takeover?.bdAddressString else { return nil }
            return kAuthStore.load(mac)
        }()

        Task { @MainActor in
            do {
                try await server.openSession()
                log("Server session opened: \(await server.currentSessionId ?? "?")")
                try await skb.resetCryptoContext()
                // Op 2 (initECDH): pass the 165-B wrapped app_private_key
                // blob; second arg is the cached kAuth blob if we have one,
                // else null for the fresh path.
                try await skb.initECDH(
                    appPrivateKey: appPrivateKey,
                    kAuth: kauthFromStore
                )
                log("Server initialized SKB (cached kAuth: \(kauthFromStore != nil))")

                if kauthFromStore != nil {
                    // Cached path: command 0x11 jumps straight to challenge.
                    handshakeStage = .waitingChallenge
                    sendSecurityCommand(Libre3ResearchMaterial.SecurityCommand.preauthorizedOrChallengeStart)
                } else {
                    // Fresh path: command 0x01 starts the ECDH exchange.
                    handshakeStage = .sentStartAuth
                    sendSecurityCommand(Libre3ResearchMaterial.SecurityCommand.startAuth)
                }
            } catch {
                handshakeStage = .error
                state = .failed
                log("Handshake init failed: \(error.localizedDescription)")
            }
        }
    }

    func clearLog() {
        logs.removeAll()
    }

    // MARK: - BLE primitives

    private func sendSecurityCommand(_ byte: UInt8) {
        write(Data([byte]), to: Libre3BLEUUIDs.securityCommandResponse, type: .withResponse)
    }

    private func writeOffsetPayload(_ payload: Data, to uuid: CBUUID, completion: UInt8?) {
        let chunks = Libre3SecurityFrameBuffer.chunksForOffsetWrite(payload)
        log("Writing \(payload.count)-byte payload to \(Libre3BLEUUIDs.name(for: uuid)) in \(chunks.count) chunks")
        pendingOffsetWrite = PendingOffsetWrite(
            uuid: uuid, chunks: chunks, completionCommand: completion, nextChunkIndex: 0
        )
        writeNextOffsetChunk()
    }

    private func writeNextOffsetChunk() {
        guard var pending = pendingOffsetWrite else { return }
        guard pending.nextChunkIndex < pending.chunks.count else {
            pendingOffsetWrite = nil
            log("Offset payload complete → \(Libre3BLEUUIDs.name(for: pending.uuid))")
            if let completion = pending.completionCommand {
                log("Sending completion command: \(completion.twoDigitHexString)")
                sendSecurityCommand(completion)
            }
            return
        }
        let chunk = pending.chunks[pending.nextChunkIndex]
        pending.nextChunkIndex += 1
        pendingOffsetWrite = pending
        write(chunk, to: pending.uuid, type: .withResponse)
    }

    private func write(_ data: Data, to uuid: CBUUID, type: CBCharacteristicWriteType) {
        guard let peripheral = connectedPeripheral else {
            log("Write skipped — no peripheral"); return
        }
        guard let characteristic = characteristics[uuid] else {
            log("Write skipped — missing characteristic \(Libre3BLEUUIDs.name(for: uuid))"); return
        }
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    private func enableNextNotification() {
        guard let peripheral = connectedPeripheral else {
            pendingNotificationOrder.removeAll(); return
        }
        while let nextUUID = pendingNotificationOrder.first {
            pendingNotificationOrder.removeFirst()
            guard let characteristic = characteristics[nextUUID] else {
                log("Notification target missing: \(Libre3BLEUUIDs.name(for: nextUUID))"); continue
            }
            peripheral.setNotifyValue(true, for: characteristic)
            return
        }
        state = .notifications
        log("Notification chain complete")
    }

    private func enableSecurityNotifications() {
        pendingNotificationOrder = Libre3BLEUUIDs.securityNotifyOrder
        enableNextNotification()
    }

    private func enableDataNotifications() {
        pendingNotificationOrder = Libre3BLEUUIDs.dataNotifyOrder
        enableNextNotification()
    }

    // MARK: - Security command/response handling

    private func handleSecurityCommandResponse(_ data: Data) {
        // First byte is the signal; second is the expected reassembly length
        // (only present for signals 8/10/15).
        if data.count >= 2, let signal = data.first, [8, 10, 15].contains(signal) {
            let expected = Int(data[data.startIndex.advanced(by: 1)])
            certificateBuffer.setExpectedLength(expected)
            challengeBuffer.setExpectedLength(expected)
            log("Security signal \(signal) — expecting \(expected) bytes")
        }
        if data == Data([4]) {
            log("Certificate accepted (signal 4) — sending 0x09 to request patch cert")
            sendSecurityCommand(Libre3ResearchMaterial.SecurityCommand.requestPatchCertificate)
        }
    }

    private func handleSecurityFragment(_ data: Data, uuid: CBUUID) {
        let result: Libre3SecurityFrameBuffer.AppendResult?
        if uuid == Libre3BLEUUIDs.securityCertificateData {
            result = certificateBuffer.appendFragment(data)
        } else {
            result = challengeBuffer.appendFragment(data)
        }
        guard let result, let assembled = result.completedPayload else { return }

        log("Assembled \(assembled.count) B from \(Libre3BLEUUIDs.name(for: uuid))")

        switch (uuid, assembled.count) {
        case (Libre3BLEUUIDs.securityCertificateData, 140):
            handlePatchCertificate(assembled)
        case (Libre3BLEUUIDs.securityCertificateData, 65):
            handlePatchEphemeral(assembled)
        case (Libre3BLEUUIDs.securityChallengeData, 23):
            handleChallenge23(assembled)
        case (Libre3BLEUUIDs.securityChallengeData, 67):
            handleChallengeResponse67(assembled)
        default:
            log("Unhandled assembled payload (\(assembled.count) B) from \(Libre3BLEUUIDs.name(for: uuid))")
        }
    }

    // MARK: - Handshake step handlers

    private func handlePatchCertificate(_ cert: Data) {
        handshakeStage = .verifyingPatchCert
        // Local smoke check: cert verifies under the level-1 signing key.
        if let parsed = try? Libre3PatchCertificate(
            data: cert,
            signingPublicKey: Libre3ResearchMaterial.patchSigningPublicKeyLevel1
        ) {
            log("Local patch cert ECDSA verifies: \(parsed.isSignatureValid)")
        }
        Task { @MainActor in
            do {
                try await skb.setPatchCertificate(cert)
                log("Server accepted patch certificate")
                handshakeStage = .generatingAppEphemeral
                let ephemeral = try await skb.generateAppEphemeralPublicKey()
                log("Server generated app ephemeral: \(ephemeral.compactHexString)")
                handshakeStage = .writingAppEphemeral
                // Send 0x0D, then write the ephemeral, then 0x0E.
                pendingSecurityCommandAfterAck = nil
                sendSecurityCommand(Libre3ResearchMaterial.SecurityCommand.sendAppEphemeral)
                // After 0x0D ack we'll start the offset write of the ephemeral
                // with 0x0E as the completion command. Set up a one-shot
                // pending state for that.
                pendingAppEphemeralPayload = ephemeral
            } catch {
                fail("Patch cert / ephemeral step failed: \(error.localizedDescription)")
            }
        }
    }

    private var pendingAppEphemeralPayload: Data?

    private func handlePatchEphemeral(_ ephemeral: Data) {
        handshakeStage = .derivingKAuth
        Task { @MainActor in
            do {
                try await skb.deriveKAuthFromPatchEphemeral(ephemeral)
                log("Server derived kAuth")
                handshakeStage = .waitingChallenge
                sendSecurityCommand(Libre3ResearchMaterial.SecurityCommand.requestChallenge)
            } catch {
                fail("deriveKAuthFromPatchEphemeral failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleChallenge23(_ challenge: Data) {
        capturedChallenge23 = challenge
        handshakeStage = .encryptingChallenge
        let r1 = Data(challenge.prefix(16))
        let nonce1 = Data(challenge.dropFirst(16))
        log("Challenge23: r1=\(r1.compactHexString) nonce1=\(nonce1.compactHexString)")

        guard let blePIN = takeover?.blePIN else {
            fail("No NFC takeover BLE PIN available — cannot form challenge plaintext")
            return
        }

        Task { @MainActor in
            do {
                let (plaintext, r2) = try Libre3SecureRandom.buildChallengePlaintext(
                    r1: r1, blePIN: blePIN
                )
                self.sentR1 = r1
                self.sentR2 = r2
                let encrypted = try await skb.challengeEncrypt(nonce1: nonce1, plaintext: plaintext)
                log("Server encrypted challenge: \(encrypted.compactHexString)")
                handshakeStage = .writingEncryptedChallenge
                writeOffsetPayload(
                    encrypted,
                    to: Libre3BLEUUIDs.securityChallengeData,
                    completion: Libre3ResearchMaterial.SecurityCommand.challengeResponseDone
                )
            } catch {
                fail("challengeEncrypt failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleChallengeResponse67(_ response: Data) {
        handshakeStage = .decryptingChallenge
        // Confirmed wire framing from Juggluco's Libre3GattCallback.challenge67():
        //   bytes [0..60)  = ciphertext + tag
        //   bytes [60..67) = AES-CCM nonce
        // Then op 8 is called as `process2(8, nonce, ct)`.
        let ct = Data(response.prefix(60))
        let nonce = Data(response.dropFirst(60))
        log("Challenge response: ct(\(ct.count) B)=\(ct.previewHexString) nonce=\(nonce.compactHexString)")

        guard let r1 = sentR1, let r2 = sentR2 else {
            fail("Missing sent r1/r2 — internal state error")
            return
        }

        Task { @MainActor in
            do {
                let unpacked = try await skb.finishChallenge(
                    responseNonce: nonce, responseCiphertext: ct,
                    sentR1: r1, sentR2: r2
                )
                log("Challenge round-trip verified. kEnc=\(unpacked.kEnc.compactHexString) ivEnc=\(unpacked.ivEnc.compactHexString)")
                let session = try Libre3SessionContext(kEnc: unpacked.kEnc, ivEnc: unpacked.ivEnc)
                self.session = session

                handshakeStage = .exportingKAuth
                let exported = try await skb.exportKAuth()
                self.exportedKAuth = exported
                log("Exported kAuth (\(exported.count) B). Persisting…")
                if let mac = takeover?.bdAddressString {
                    let ok = kAuthStore.save(mac, exported)
                    log("kAuth persisted to Keychain for sensor \(mac): \(ok)")
                } else {
                    log("No sensor MAC available; kAuth not persisted (won't auto-reconnect).")
                }
                handshakeStage = .done
                state = .streaming

                if autoEnableDataNotifications {
                    enableDataNotifications()
                }
            } catch {
                fail("Challenge round-trip / kAuth export failed: \(error.localizedDescription)")
            }
        }
    }

    /// Removes the cached kAuth for the currently-connected sensor (if
    /// any). Useful manually after suspecting the sensor was re-paired by
    /// another app, and used internally on handshake failure to ensure the
    /// next attempt takes the fresh path.
    @discardableResult
    func clearCachedKAuth() -> Bool {
        guard let mac = takeover?.bdAddressString else {
            log("clearCachedKAuth: no takeover MAC available; nothing to clear.")
            return false
        }
        let had = kAuthStore.load(mac) != nil
        _ = kAuthStore.remove(mac)
        exportedKAuth = nil
        log(had
            ? "Cleared cached kAuth for sensor \(mac). Next handshake will take the fresh path."
            : "No cached kAuth for sensor \(mac); nothing to clear.")
        return had
    }

    private func fail(_ message: String) {
        log("HANDSHAKE FAILED: \(message)")
        // If we got past `waitingChallenge` on the cached path and then
        // failed, the most likely cause is that the cached kAuth doesn't
        // match the patch's current BLE PIN (someone else re-paired). Wipe
        // it so the next attempt takes the fresh path.
        if let mac = takeover?.bdAddressString, kAuthStore.load(mac) != nil {
            _ = kAuthStore.remove(mac)
            exportedKAuth = nil
            log("Auto-cleared stale cached kAuth for sensor \(mac) after failure.")
        }
        handshakeStage = .error
        state = .failed
    }

    // MARK: - Live decode helpers

    /// Appends `fragment` to `acc`, then while `acc` has at least
    /// `fixedSize` bytes, slices off a window and hands it to `handle`.
    /// Mirrors Juggluco's `oneMinuteRawData[35]` accumulation pattern.
    private func accumulateAndDecode(
        fragment: Data,
        into acc: inout Data,
        fixedSize: Int,
        label: String,
        handle: (Data) -> Void
    ) {
        acc.append(fragment)
        log("RX \(label) fragment: \(fragment.count) B, acc=\(acc.count)/\(fixedSize)")
        while acc.count >= fixedSize {
            let wire = acc.prefix(fixedSize)
            acc.removeSubrange(acc.startIndex ..< acc.startIndex.advanced(by: fixedSize))
            handle(Data(wire))
        }
    }

    fileprivate func liveDecodeGlucoseIfSessionLoaded(wire: Data) {
        guard let session else { return }
        do {
            let decoded = try session.decryptOneMinute(wire: wire)
            latestGlucose = decoded
            latestGlucoseReceivedAt = Date()
            log("Glucose: lifeCount=\(decoded.lifeCount) current=\(decoded.uncappedCurrentMgDl) mg/dL rate=\(String(format: "%.2f", decoded.rateOfChangePerMinute))")

            // Track the last usable reading's lifeCount so the next reconnect
            // backfill can start from here instead of `currentLife - lookback`.
            if Libre3Payloads.OneMinute.validRangeMgDl.contains(Int(decoded.uncappedCurrentMgDl)),
               decoded.lifeCount > (lastAcceptedGlucoseLifeCount ?? 0) {
                lastAcceptedGlucoseLifeCount = decoded.lifeCount
                if let mac = takeover?.bdAddressString {
                    Self.saveLastAcceptedLifeCount(decoded.lifeCount, mac: mac)
                }
            }

            // Each 1-min glucose packet also carries the matching 5-min
            // historical sample (~17 min behind current). Harvesting these
            // is how the 5-min graph stays current without re-requesting a
            // backfill every few minutes. Mirrors Juggluco's
            // `saveLibre3Historyel(sens, minptr->historicalLifeCount, histval)`
            // in `bluetooth.cpp:171`.
            let histLife = decoded.historicalLifeCount
            let histVal = decoded.uncappedHistoricMgDl
            if histLife > 0,
               Libre3Payloads.OneMinute.validRangeMgDl.contains(Int(histVal)) {
                let sample = HistoricSample(lifeCount: histLife, mgDl: histVal)
                let preLen = historicSamples.count
                mergeHistoricSamples([sample])
                if historicSamples.count > preLen {
                    latestHistoryReceivedAt = Date()
                    log("History (from 1-min): lifeCount=\(histLife) value=\(histVal) total=\(historicSamples.count)")
                }
            }
        } catch {
            log("Glucose decode failed: \(error.localizedDescription)")
        }
    }

    /// Decrypts and merges a historic-data notification.
    ///
    /// Each notification is a complete encrypted block — no fragment
    /// reassembly (mirrors Juggluco's `save_history`, which passes the raw
    /// characteristic value straight to `intDecrypt(cryptptr, 4, value)` in
    /// `Libre3GattCallback.java:502`). Plaintext layout (`bluetooth.cpp:397`):
    ///
    ///     struct HistoryData { uint16 lifeCount; uint16 values[]; };
    ///
    /// `lifeCount` is the sensor age in minutes of `values[0]`; subsequent
    /// values are at `lifeCount + 5`, `+10`, … The number of values is
    /// `(plaintext.count / 2) - 1`. Values are already in mg/dL.
    fileprivate func liveDecodeHistoricIfSessionLoaded(wire: Data) {
        guard let session else { return }
        do {
            let plaintext = try session.decryptIncoming(wire: wire, kind: 4)
            let history = try Libre3Payloads.History.decode(plaintext)
            var newSamples: [HistoricSample] = []
            newSamples.reserveCapacity(history.valuesMgDl.count)
            for (i, val) in history.valuesMgDl.enumerated() {
                guard Libre3Payloads.OneMinute.validRangeMgDl.contains(Int(val)) else { continue }
                let lc = history.lifeCount &+ UInt16(i * 5)
                newSamples.append(HistoricSample(lifeCount: lc, mgDl: val))
            }
            mergeHistoricSamples(newSamples)
            latestHistoryReceivedAt = Date()
            let preview = newSamples.prefix(3)
                .map { "(\($0.lifeCount), \($0.mgDl))" }
                .joined(separator: " ")
            log("History: startLifeCount=\(history.lifeCount) values=\(history.valuesMgDl.count) kept=\(newSamples.count) total=\(historicSamples.count) preview=\(preview)")
        } catch {
            log("History decode failed (\(wire.count) B): \(error.localizedDescription)")
        }
    }

    /// Merges new samples into `historicSamples`, deduplicating on lifeCount
    /// (later writes win) and keeping the array sorted ascending.
    private func mergeHistoricSamples(_ incoming: [HistoricSample]) {
        guard !incoming.isEmpty else { return }
        var byLife: [UInt16: UInt16] = Dictionary(
            uniqueKeysWithValues: historicSamples.map { ($0.lifeCount, $0.mgDl) }
        )
        for s in incoming { byLife[s.lifeCount] = s.mgDl }
        historicSamples = byLife
            .map { HistoricSample(lifeCount: $0.key, mgDl: $0.value) }
            .sorted { $0.lifeCount < $1.lifeCount }
    }

    fileprivate func liveDecodePatchStatusIfSessionLoaded(wire: Data) {
        guard let session else { return }
        do {
            let decoded = try session.decryptPatchStatus(wire: wire)
            latestPatchStatus = decoded
            latestPatchStatusReceivedAt = Date()
            log("Patch status: state=\(decoded.patchState) lifeCount=\(decoded.lifeCount)")
        } catch {
            log("Patch status decode failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Logging

    fileprivate func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let entry = ProtocolLogEntry(
            id: nextLogID,
            message: "[\(formatter.string(from: Date()))] \(message)"
        )
        nextLogID += 1
        logs.insert(entry, at: 0)
        if logs.count > 500 {
            logs.removeLast(logs.count - 500)
        }
        main?.log("Shim/BLE: \(message)")  // DiaBLE main.log()
    }

    private static func bluetoothStateName(_ state: CBManagerState) -> String {
        switch state {
        case .unknown: return "Unknown"
        case .resetting: return "Resetting"
        case .unsupported: return "Unsupported"
        case .unauthorized: return "Unauthorized"
        case .poweredOff: return "Powered off"
        case .poweredOn: return "Powered on"
        @unknown default: return "Future state"
        }
    }

    private static func advertisementSummary(_ advertisementData: [String: Any]) -> String {
        var parts: [String] = []
        if let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String {
            parts.append("name=\(localName)")
        }
        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            parts.append("mfg=\(mfg.compactHexString)")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " | ")
    }
}

// MARK: - CBCentralManagerDelegate

extension Libre3BLEClient: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            bluetoothState = Self.bluetoothStateName(central.state)
            log("Bluetooth state: \(bluetoothState)")
            if central.state != .poweredOn, state == .scanning {
                state = .waitingForBluetooth
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            ingestDiscovered(peripheral: peripheral,
                             advertisementData: advertisementData,
                             rssi: RSSI.intValue)
        }
    }

    /// Shared between the scan callback and the `retrieveConnectedPeripherals`
    /// fallback in `startScan`.
    fileprivate func ingestDiscovered(peripheral: CBPeripheral,
                                      advertisementData: [String: Any],
                                      rssi: Int) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        let name = peripheral.name
            ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? "(unnamed)"
        let row = Libre3PeripheralRow(
            id: peripheral.identifier,
            name: name,
            rssi: rssi,
            advertisementSummary: Self.advertisementSummary(advertisementData)
        )
        if let i = peripherals.firstIndex(where: { $0.id == row.id }) {
            peripherals[i] = row
        } else {
            peripherals.append(row)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            state = .discovering
            log("Connected; discovering services")
            peripheral.discoverServices(Libre3BLEUUIDs.servicesToDiscover)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            state = .failed
            log("Failed to connect: \(error?.localizedDescription ?? "unknown")")
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectedPeripheral = nil
            characteristics.removeAll()
            state = .disconnected
            handshakeStage = .notStarted
            session = nil
            firedJugglucoBackfill = false
            glucoseAccumulator.removeAll(keepingCapacity: true)
            clinicalAccumulator.removeAll(keepingCapacity: true)
            patchStatusAccumulator.removeAll(keepingCapacity: true)
            // Keep historicSamples and lastAcceptedGlucoseLifeCount so the
            // next reconnect can backfill only the gap.
            patchControlQueue.removeAll()
            patchControlInFlight = false
            await server.closeSession()
            log("Disconnected: \(error?.localizedDescription ?? "no error")")
        }
    }
}

// MARK: - Outgoing patch-control commands
//
// These mirror what Juggluco's Libre3GattCallback does after handshake to
// wake the sensor's data streams. The wire bytes are:
//
//   plaintext = `01 00 01 <fromLE32>`            historyBackfill
//   plaintext = `01 01 01 <fromLE32>`            clinicalBackfill
//   plaintext = `04 <indexLE32> 00 00`           eventLogRequest
//
// then AES-CCM encrypt with kEnc/ivEnc and the auto-incrementing
// outCryptoSequence (handled inside Libre3SessionContext), and write to
// the patch-control characteristic.

extension Libre3BLEClient {
    /// Fires Juggluco's standard post-handshake command sequence. Safe to
    /// call multiple times; uses the session's auto-incrementing sequence
    /// counter so each command has a unique nonce.
    ///
    /// **Critical:** the `from` parameter in the history-backfill command is
    /// "the last lifeCount you already have", not "the lifeCount you want to
    /// start at". The patch returns entries strictly newer than `from`. So a
    /// small `from` produces a long history; a `from` close to
    /// `currentLifeCount` produces almost nothing. (See Juggluco
    /// `Libre3GattCallback.java:1139` — `takelast = max(lastReceived, 5)`.)
    func sendJugglucoBackfill() {
        guard let session = self.session else {
            log("sendJugglucoBackfill: no session loaded; skipping.")
            return
        }
        let currentLife = Int32(latestPatchStatus?.currentLifeCount ?? 0)

        // History lower bound. Prefer LibreCRKit's "resume from last accepted
        // reading" strategy when we have one (zero-gap reconnect). Otherwise
        // fall back to the lookback window.
        let historyFrom: Int32 = {
            if let last = lastAcceptedGlucoseLifeCount {
                let aligned = (Int32(last) / 5) * 5
                return max(5, aligned)
            }
            guard let lookback = historyLookbackMinutes else { return 5 }
            let target = currentLife - Int32(lookback)
            let aligned = (target / 5) * 5
            return max(5, aligned)
        }()

        // Clinical (1-min) backfill: resume from the last accepted reading if
        // we have one; otherwise just lifeCount-1 (Juggluco's behavior, since
        // live 1-min readings already arrive on the glucose-data char).
        let clinicalFrom: Int32 = {
            if let last = lastAcceptedGlucoseLifeCount {
                return Int32(last)
            }
            return max(0, currentLife - 1)
        }()

        let cmds: [(String, Data)] = [
            ("historyBackfill   from=\(historyFrom) (current=\(currentLife))",
             Libre3Payloads.historyBackfillCommand(from: historyFrom)),
            ("clinicalBackfill  from=\(clinicalFrom)",
             Libre3Payloads.clinicalBackfillCommand(from: clinicalFrom)),
            ("eventLogRequest   idx=0",
             Libre3Payloads.eventLogCommand(index: 0x00))
        ]
        for (label, plaintext) in cmds {
            do {
                let wire = try session.encryptOutgoingPatchControl(plaintext: plaintext)
                patchControlQueue.append((label, wire))
            } catch {
                log("TX patch-control [\(label)] encrypt failed: \(error.localizedDescription)")
            }
        }
        sendNextPatchControl()
    }

    /// Pops the next queued patch-control write and dispatches it. No-op if
    /// one is already in flight (we wait for the ACK in `didWriteValueFor`).
    fileprivate func sendNextPatchControl() {
        guard !patchControlInFlight else { return }
        guard !patchControlQueue.isEmpty else { return }
        let next = patchControlQueue.removeFirst()
        patchControlInFlight = true
        log("TX patch-control [\(next.label)] wire=\(next.wire.compactHexString)")
        write(next.wire, to: Libre3BLEUUIDs.patchControl, type: .withResponse)
    }
}

// MARK: - CBPeripheralDelegate

extension Libre3BLEClient: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                state = .failed
                log("Service discovery failed: \(error.localizedDescription)")
                return
            }
            for service in peripheral.services ?? [] {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                log("Char discovery failed for \(Libre3BLEUUIDs.name(for: service.uuid)): \(error.localizedDescription)")
                return
            }
            for characteristic in service.characteristics ?? [] {
                characteristics[characteristic.uuid] = characteristic
            }
            let requiredSecurity = Set(Libre3BLEUUIDs.securityNotifyOrder)
            if requiredSecurity.isSubset(of: Set(characteristics.keys)) {
                enableSecurityNotifications()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                log("Notification enable failed for \(Libre3BLEUUIDs.name(for: characteristic.uuid)): \(error.localizedDescription)")
            }
            enableNextNotification()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid
        let data = characteristic.value ?? Data()
        Task { @MainActor in
            if let error {
                log("RX error \(Libre3BLEUUIDs.name(for: uuid)): \(error.localizedDescription)")
                return
            }
            if lastNotificationByCharacteristic[uuid] == data { return }
            lastNotificationByCharacteristic[uuid] = data

            switch uuid {
            case Libre3BLEUUIDs.securityCommandResponse:
                handleSecurityCommandResponse(data)
            case Libre3BLEUUIDs.securityCertificateData, Libre3BLEUUIDs.securityChallengeData:
                handleSecurityFragment(data, uuid: uuid)
            case Libre3BLEUUIDs.glucoseData:
                accumulateAndDecode(
                    fragment: data,
                    into: &glucoseAccumulator,
                    fixedSize: Self.glucosePacketSize,
                    label: "Glucose data"
                ) { wire in
                    liveDecodeGlucoseIfSessionLoaded(wire: wire)
                }
            case Libre3BLEUUIDs.patchStatus:
                accumulateAndDecode(
                    fragment: data,
                    into: &patchStatusAccumulator,
                    fixedSize: Self.patchStatusPacketSize,
                    label: "Patch status"
                ) { wire in
                    liveDecodePatchStatusIfSessionLoaded(wire: wire)
                    // Juggluco mirrors fillHistory + fillClinical on every
                    // patch-status. Without this, some patch firmwares don't
                    // start streaming current glucose readings. Fire once per
                    // session (debounced via firedJugglucoBackfill).
                    if hasSession && !firedJugglucoBackfill {
                        firedJugglucoBackfill = true
                        log("First patch-status received; firing Juggluco-style backfill to wake glucose stream.")
                        sendJugglucoBackfill()
                    }
                }
            case Libre3BLEUUIDs.historicData:
                // Historic 5-min backfill: each notification is one complete
                // encrypted history block (variable length). No fragment
                // accumulation — Juggluco decrypts the raw value directly.
                liveDecodeHistoricIfSessionLoaded(wire: data)
            case Libre3BLEUUIDs.clinicalData:
                accumulateAndDecode(
                    fragment: data,
                    into: &clinicalAccumulator,
                    fixedSize: Self.clinicalPacketSize,
                    label: "Clinical data"
                ) { wire in
                    if let session = self.session,
                       let plain = try? session.decryptIncoming(wire: wire, kind: 5),
                       let fast = try? Libre3Payloads.FastData.decode(plain) {
                        log("Clinical: lifeCount=\(fast.lifeCount) reading=\(fast.readingMgDl) historic=\(fast.historicMgDl) mg/dL")
                        let histLife = fast.estimatedHistoricLifeCount
                        if histLife > 0,
                           Libre3Payloads.OneMinute.validRangeMgDl.contains(Int(fast.historicMgDl)) {
                            mergeHistoricSamples([HistoricSample(
                                lifeCount: histLife, mgDl: fast.historicMgDl
                            )])
                        }
                    }
                }
            default:
                // Surface everything else so we can see whether glucose
                // is arriving at a different size or on a characteristic
                // we don't recognize.
                log("RX \(Libre3BLEUUIDs.name(for: uuid)): \(data.count) B \(data.previewHexString)")
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        let uuid = characteristic.uuid
        Task { @MainActor in
            if let error {
                log("Write failed (\(Libre3BLEUUIDs.name(for: uuid))): \(error.localizedDescription)")
                // Free the in-flight slot so queued patch-control writes can
                // continue even after an ATT error on one of them.
                if uuid == Libre3BLEUUIDs.patchControl {
                    patchControlInFlight = false
                    sendNextPatchControl()
                }
                return
            }
            // Drive offset-write chain forward.
            if uuid == pendingOffsetWrite?.uuid {
                writeNextOffsetChunk()
                return
            }

            // Stage transitions driven by command/response ACKs.
            if uuid == Libre3BLEUUIDs.securityCommandResponse {
                handleCommandAck()
            }

            // Pop the next queued patch-control write, if any.
            if uuid == Libre3BLEUUIDs.patchControl {
                patchControlInFlight = false
                sendNextPatchControl()
            }
        }
    }

    private func handleCommandAck() {
        switch handshakeStage {
        case .sentStartAuth:
            // After 0x01 ack, send 0x02 then write app certificate.
            handshakeStage = .wroteAppCert
            // 0x02 ack is what triggers the cert write. So pipeline:
            // 0x02 → ack → start cert write → after final chunk send 0x03.
            sendSecurityCommand(Libre3ResearchMaterial.SecurityCommand.sendAppCertificate)
        case .wroteAppCert:
            // 0x02 acked → kick off cert offset write with 0x03 completion.
            writeOffsetPayload(
                appCertificate,
                to: Libre3BLEUUIDs.securityCertificateData,
                completion: Libre3ResearchMaterial.SecurityCommand.appCertificateChunksDone
            )
            handshakeStage = .waitingPatchCert
        case .writingAppEphemeral:
            // 0x0D acked → write ephemeral with 0x0E completion.
            if let ephemeral = pendingAppEphemeralPayload {
                pendingAppEphemeralPayload = nil
                writeOffsetPayload(
                    ephemeral,
                    to: Libre3BLEUUIDs.securityCertificateData,
                    completion: Libre3ResearchMaterial.SecurityCommand.appEphemeralChunksDone
                )
                handshakeStage = .waitingPatchEphemeral
            }
        default:
            // No-op for other ACKs (command-response signal handling already
            // dispatched the next step from `handleSecurityCommandResponse`).
            break
        }
    }
}
