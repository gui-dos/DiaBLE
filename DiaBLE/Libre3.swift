import Foundation


// https://insulinclub.de/index.php?thread/33795-free-three-ein-xposed-lsposed-modul-f%C3%BCr-libre-3-aktueller-wert-am-sperrbildschir/&postID=655055#post655055

extension String {
    /// Converts a LibreView account ID string into a receiverID
    /// i.e. "2977dec2-492a-11ea-9702-0242ac110002" -> 524381581
    var fnv32Hash: UInt32 { UInt32(self.reduce(0) { 0xFFFFFFFF & (UInt64($0) * 0x811C9DC5) ^ UInt64($1.asciiValue!) }) }
}


@Observable class Libre3: Libre {


    enum State: UInt8, CustomStringConvertible {
        case manufacturing      = 0

        /// out of package, not activated yet
        case storage            = 1

        case insertionDetection = 2
        case insertionFailed    = 3

        /// advertising via BLE already 10/15 minutes after activation
        case paired             = 4

        /// if Trident is not run on the final day, still advertising for further 24 hours
        case expired            = 5

        /// Trident sent the shutdown command as soon as run on the final day or
        /// the sensor stopped advertising via BLE by itself on the following day anyway
        case terminated         = 6

        /// detected for a sensor that fell off
        case error              = 7

        case errorTerminated    = 8

        var description: String {
            switch self {
            case .manufacturing:      "Manufacturing"
            case .storage:            "Not activated"
            case .insertionDetection: "Insertion detection"
            case .insertionFailed:    "Insertion failed"
            case .paired:             "Paired"
            case .expired:            "Expired"
            case .terminated:         "Terminated"
            case .error:              "Error"
            case .errorTerminated:    "Terminated (error)"
            }
        }
    }


    enum Condition: Int, CustomStringConvertible {
        case ok      = 0
        case invalid = 1

        /// Early Signal Attenuation
        case esa     = 2

        var description: String {
            switch self {
            case .ok:      "OK"
            case .invalid: "invalid"
            case .esa:     "ESA"
            }
        }
    }


    enum ProductType: Int, CustomStringConvertible {
        case others = 1
        case sensor = 4    // Libre 3's product family
        case lingo  = 9

        var description: String {
            switch self {
            case .others: "others"  // OTHERS
            case .sensor: "sensor"  // SENSOR
            case .lingo:  "Lingo"
            }
        }
    }


    enum ResultRange: Int, CustomStringConvertible {
        case `in`    = 0
        case below   = 1
        case above   = 2
        case noRange = 3

        var description: String {
            switch self {
            case .in:      "in range"
            case .below:   "below range"
            case .above:   "above range"
            case .noRange: "no range"
            }
        }
    }


    // TODO: var members, struct references, enums


    struct PatchInfo {
        let NFC_Key: Int
        let localization: Int  // 1: Europe, 2: US
        let generation: Int    // 0: Libre 3, 1: Libre 3+
        let wearDuration: Int
        let warmupTime: Int
        let productType: ProductType
        let state: State
        let fwVersion: Data
        let compressedSN: Data
        let securityVersion: Int
    }


    struct ErrorData {
        let errorCode: Int
        let data: Data
    }


    struct GlucoseData {
        let lifeCount: UInt16
        let readingMgDl: UInt16
        let dqError: UInt16
        let historicalLifeCount: UInt16
        let historicalReading: UInt16
        let projectedGlucose: UInt16
        let historicalReadingDQError: UInt16
        let rateOfChange: Int16
        let trend: TrendArrow
        let esaDuration: UInt16
        let temperatureStatus: Int
        let actionableStatus: Int
        let glycemicAlarmStatus: GlycemicAlarm
        let glucoseRangeStatus: ResultRange
        let sensorCondition: Condition
        let uncappedCurrentMgDl: Int
        let uncappedHistoricMgDl: Int
        let temperature: Int
        let fastData: Data

        // 062DEE00FCFF0000945CF12CF0000BEE00F000010C530E72482F130000 (29 bytes):
        //   062D: lifeCount 11526 (0x2D06)
        //   EE00: readingMgDl 238
        //   FCFF: rateOfChange -4 (2**16 - 0xFFFC)
        //   0000: esaDuration
        //   945C: projectedGlucose 23700 (0x5C94)
        //   F12C: historicalLifeCount 11505 (0x2CF1)
        //   F000: historicalReading 240
        //   0B: 00001 011 (bitfields 3: trend, 5: rest)
        //   EE00: uncappedCurrentMgDl 238
        //   F000: uncappedHistoricMgDl 240
        //   010C: temperature 3073 (0x0C01)
        //   530E72482F130000: fastData
    }


    struct HistoricalData {
        let reading: Int
        let dqError: Int
        let lifeCount: Int
    }


    struct ActivationResponse {
        let bdAddress: Data         // 6 bytes
        let BLE_Pin: Data           // 4 bytes
        let activationTime: UInt32  // 4 bytes
    }


    struct EventLog {
        let lifeCount: Int
        let errorData: Int
        let eventData: Int
        let index: Int

        // struct EventLog {
        //     int16_t lifeCount;
        //     int16_t errorData;
        //     int16_t eventData;
        //     int8_t index;  // 255: no data
        // }
    }


    struct FastData {
        let lifeCount: Int
        let uncappedReadingMgdl: Int
        let uncappedHistoricReadingMgDl: Int
        let dqError: Int
        let temperature: Int
        let rawData: Data

        // struct fastData {
        //     uint16_t lifeCount;
        //     uint8_t rawData[8];
        //     uint16_t readingMgDl;
        //     uint16_t historicMgDl;
        //     int getHistoricLifeCount() const {
        //         return round((lifeCount-19.0)/5.0)*5; //  - 17-minute latency?
        //     };
        // }
        //
        // B43E7E091F4071140000B600B500 (14 bytes):
        //   B43E: lifeCount 16052 (0x3EB4)
        //   7E091F4071140000: rawData
        //   B600: readingMgDl 182
        //   B500: historicMgDl 181
    }


    struct PatchStatus {
        let patchState: State
        let totalEvents: Int
        let lifeCount: Int
        let errorData: Int
        let eventData: Int
        let index: UInt8
        let currentLifeCount: Int
        let stackDisconnectReason: UInt8
        let appDisconnectReason: UInt8

        // FC2C00000D002104FC2C1603 (12 bytes):
        //   FC2C: lifeCount 11516 (0x2CFC)
        //   0000: errorData
        //   000D: eventData 4013 (?)
        //   21: index 33
        //   04: patchState 4
        //   FC2C: currentLlifeCount 11516 (0x2CFC)
        //   16: stackDisconnectReason 22
        //   03: appDisconnectReason 3
    }


    struct InitParam {
        let activationTime: UInt32
        var firstConnect: Bool
        let serialNumber: String
        var lastLifeCountReceived: Int
        let hybridModeEnabled: Bool
        let dataFile: Any
        let blePIN: Data
        var lastEventReceived: Int
        let deviceAddress: Data
        let warmupDuration: Int
        let wearDuration: Int
        var lastHistoricLifeCountReceived: Int
        let exportedKAuth: Data
        let securityVersion: Int
    }


    enum PacketType: UInt8 {
        case controlCommand   = 0
        case controlResponse  = 1
        case patchStatus      = 2
        case currentGlucose   = 3
        case backfillHistoric = 4
        case backfillClinical = 5
        case eventLog         = 6
        case factoryData      = 7
    }

    static let packetDescriptors: [[UInt8]] = [
        [0x00, 0x00, 0x00],
        [0x00, 0x00, 0x0F],
        [0x00, 0x00, 0xF0],
        [0x00, 0x0F, 0x00],
        [0x00, 0xF0, 0x00],
        [0x0F, 0x00, 0x00],
        [0xF0, 0x00, 0x00],
        [0x44, 0x00, 0x00]
    ]


    struct BCSecurityContext {
        let packetDescriptorArray: [[UInt8]] = packetDescriptors
        var key: Data    = Data(count: 16)
        var iv_enc: Data = Data(count: 8)
        var nonce: Data  = Data(count: 13)
        var outCryptoSequence: UInt16 = 0

        // when decrypting initialize:
        // nonce[0...1]: outCryptoSequence
        // nonce[2...4]: packetDesciptors(packetType)
        // nonce[5...12]: iv_enc
        // taglen = 4
    }


    struct CGMSensor {
        var sensor: Sensor
        var deviceType: Int
        var cryptoLib: Any
        var securityContext: BCSecurityContext
        var patchEphemeral: Data
        var r1: Data
        var r2: Data
        var nonce1: Data
        var kEnc: Data
        var ivEnc: Data
        var exportedkAuth: Data
        var securityLibInitialized: Bool
        var isPreAuthorized: Bool
        var initParam: InitParam
        var securityVersion: Int
    }


    enum UUID: String, CustomStringConvertible, CaseIterable {

        case data             = "089810CC-EF89-11E9-81B4-2A2AE2DBCCE4"
        case patchControl     = "08981338-EF89-11E9-81B4-2A2AE2DBCCE4"
        case patchStatus      = "08981482-EF89-11E9-81B4-2A2AE2DBCCE4"
        case oneMinuteReading = "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4"
        case historicalData   = "0898195A-EF89-11E9-81B4-2A2AE2DBCCE4"
        case clinicalData     = "08981AB8-EF89-11E9-81B4-2A2AE2DBCCE4"
        case eventLog         = "08981BEE-EF89-11E9-81B4-2A2AE2DBCCE4"
        case factoryData      = "08981D24-EF89-11E9-81B4-2A2AE2DBCCE4"

        case security         = "0898203A-EF89-11E9-81B4-2A2AE2DBCCE4"
        case securityCommands = "08982198-EF89-11E9-81B4-2A2AE2DBCCE4"
        case challengeData    = "089822CE-EF89-11E9-81B4-2A2AE2DBCCE4"
        case certificateData  = "089823FA-EF89-11E9-81B4-2A2AE2DBCCE4"

        case debug            = "08982400-EF89-11E9-81B4-2A2AE2DBCCE4"
        case bleLogin         = "F001"

        var description: String {
            switch self {
            case .data:             "data service"
            case .patchControl:     "patch control"
            case .patchStatus:      "patch status"
            case .oneMinuteReading: "one-minute reading"
            case .historicalData:   "historical data"
            case .clinicalData:     "clinical data"
            case .eventLog:         "event log"
            case .factoryData:      "factory data"
            case .security:         "security service"
            case .securityCommands: "security commands"
            case .challengeData:    "challenge data"
            case .certificateData:  "certificate data"
            case .debug:            "debug service"
            case .bleLogin:         "BLE login"
            }
        }
    }

    class var knownUUIDs: [String] { UUID.allCases.map(\.rawValue) }


    // TODO: rename commands and events enums expressively

    // CMD_ECDH_START              = 0x01
    // CMD_LOAD_CERT_DATA          = 0x02
    // CMD_LOAD_CERT_DONE          = 0x03
    // CMD_CERT_ACCEPTED           = 0x04
    // CMD_AUTHORIZED              = 0x05
    // CMD_AUTHORIZE_ECDSA         = 0x06
    // CMD_AUTHORIZATION_CHALLENGE = 0x07
    // CMD_CHALLENGE_LOAD_DONE     = 0x08
    // CMD_SEND_CERT               = 0x09
    // CMD_CERT_READY              = 0x0A
    // CMD_IV_AUTHENTICATED_SEND   = 0x0B
    // CMD_IV_READY                = 0x0C
    // CMD_KEY_AGREEMENT           = 0x0D
    // CMD_EPHEMERAL_LOAD_DONE     = 0x0E
    // CMD_EPHEMERAL_KEY_READY     = 0x0F
    // CMD_ECDH_COMPLETE           = 0x10
    // CMD_AUTHORIZE_SYMMETRIC     = 0x11
    // CMD_MODE_SWITCH             = 0x12
    // CMD_VERIFICATION_FAILURE    = 0x13


    // - maximum packet size is 20
    // - notified packets are prefixed by 00, 01, 02, ...
    // - written packets are prefixed by 00 00, 12 00, 24 00, 36 00, ...
    // - data packets end in a sequential Int: 01 00, 02 00, ...
    //
    // Connection:
    // enable notifications for 2198, 23FA and 22CE
    // write  2198  11
    // notify 2198  08 17
    // notify 22CE  20 + 5 bytes        // 23-byte challenge
    // write  22CE  20 + 20 + 6 bytes   // 40-byte challenge response
    // write  2198  08
    // notify 2198  08 43
    // notify 22CE  20 * 3 + 11 bytes   // 67-byte encrypted KAuth
    // enable notifications for 1338, 1BEE, 195A, 1AB8, 1D24, 1482
    // notify 1482  18-byte packets     // patch status
    // enable notifications for 177A
    // write  1338  13 bytes            // command ending in 01 00
    // notify 177A  15 + 20 bytes       // one-minute reading
    // notify 195A  20-byte packets     // historical data
    // notify 1338  10 bytes            // ending in 01 00
    // write  1338  13 bytes            // command ending in 02 00
    // notify 1AB8  20-byte packets     // clinical data
    // notify 1338  10 bytes            // ending in 02 00
    //
    // Activation:
    // enable notifications for 2198, 23FA and 22CE
    // write  2198  01
    // write  2198  02
    // write  23FA  20 * 9 bytes        // 162-byte fixed certificate data
    // write  2198  03
    // notify 2198  04                  // certificate accepted event
    // write  2198  09
    // notify 2198  0A 8C               // certificate ready event
    // notify 23FA  20 * 7 + 8 bytes    // 140-byte patch certificate
    // write  2198  0D
    // write  23FA  20 * 3 + 13 bytes   // 65-byte ephemeral key
    // write  2198  0E
    // notify 2198  0F 41               // ephemeral ready event
    // notify 23FA  20 * 3 + 9 bytes    // 65-byte ephemeral key
    // write  2198  11
    // notify 2198  08 17
    // notify 22CE  20 + 5 bytes        // 23-byte challenge
    // write  22CE  20 * 2 + 6 bytes    // 40-byte challenge response
    // write  2198  08
    // notify 2198  08 43
    // notify 22CE  20 * 3 + 11 bytes   // 67-byte encrypted KAuth
    // enable notifications for 1338, 1BEE, 195A, 1AB8, 1D24, 1482
    // notify 1482  18 bytes            // patch status
    // enable notifications for 177A
    // write  1338  13 bytes            // command ending in 01 00
    // notify 1BEE  20 + 20 bytes       // event log
    // notify 1338  10 bytes            // ending in 01 00
    // write  1338  13 bytes            // command ending in 02 00
    // notify 1D24  20 * 11 + 12 bytes  // factory data (with latest firmwares, otherwise 10/11 varying packets)
    //                                  // 20 * 10 + 17 bytes when reactivating (195-byte factory data)
    // notify 1338  10 bytes            // ending in 02 00
    //
    // Shutdown:
    // write  1338  13 bytes            // command ending in 03 00
    // notify 1BEE  20 bytes            // event log
    // notify 1338  10 bytes            // ending in 03 00
    // write  1338  13 bytes            // command ending in 04 00


    enum SecurityCommand: UInt8, CustomStringConvertible {

        case security_01         = 0x01
        case security_02         = 0x02
        case certificateLoadDone = 0x03
        case challengeLoadDone   = 0x08
        case security_09         = 0x09
        case security_0D         = 0x0D
        case ephemeralLoadDone   = 0x0E
        case readChallenge       = 0x11

        var description: String {
            switch self {
            case .security_01:         "security 0x01 command"
            case .security_02:         "security 0x02 command"
            case .certificateLoadDone: "certificate load done"
            case .challengeLoadDone:   "challenge load done"
            case .security_09:         "security 0x09 command"
            case .security_0D:         "security 0x0D command"
            case .ephemeralLoadDone:   "ephemeral load done"
            case .readChallenge:       "read security challenge"
            }
        }
    }

    enum SecurityEvent: UInt8, CustomStringConvertible {

        case unknown             = 0x00
        case certificateAccepted = 0x04
        case challengeLoadDone   = 0x08
        case certificateReady    = 0x0A
        case ephemeralReady      = 0x0F

        var description: String {
            switch self {
            case .unknown:             "unknown [TODO]"
            case .certificateAccepted: "certificate accepted"
            case .challengeLoadDone:   "challenge load done"
            case .certificateReady:    "certificate ready"
            case .ephemeralReady:      "ephemeral ready"
            }
        }
    }

    /// 13 bytes written to .patchControl:
    /// - PATCH_CONTROL_COMMAND_SIZE = 7
    /// - a final sequential Int starting by 01 00 since it is enqueued
    enum ControlCommand {
        /// - 010001 EC2C 0000 requests historical data from lifeCount 11520 (0x2CEC)
        case historic(Data)       // type 1

        /// Requests past clinical data
        /// - 010101 9B48 0000 requests clinical data from lifeCount 18587 (0x489B)
        case backfill(Data)       // type 2

        /// - 040100 0000 0000
        case eventLog(Data)       // type 3

        /// - 060000 0000 0000
        case factoryData(Data)    // type 4

        case shutdownPatch(Data)  // type 5
    }

    // TODO
    //  struct RequestData {
    //      int8_t kind[2];
    //      int8_t arg;
    //      int32_t from;
    //  }

    var receiverId: UInt32 = 0    // fnv32Hash of LibreView ID string

    var blePIN: Data = Data()    // 4 bytes returned by the activation command

    var buffer: Data = Data()
    var currentControlCommand:  ControlCommand?
    var currentSecurityCommand: SecurityCommand?
    var lastSecurityEvent: SecurityEvent = .unknown
    var expectedStreamSize = 0

    var outCryptoSequence: UInt16 = 0

    var currentLifeCount: Int = 0
    var lastHistoricLifeCount: Int = 0
    var lastHistoricReadingDate: Date = .distantPast


    func parsePatchInfo() {

        let productType = Int(patchInfo[12])
        type = [4: SensorType.libre3, 9: SensorType.lingo][productType] ?? .libre3
        log("\(type): product type: \(ProductType(rawValue: productType)?.description ?? "unknown") (0x\(productType.hex))")

        let securityVersion = UInt16(patchInfo[0...1])
        let localization    = UInt16(patchInfo[2...3])
        let generation      = UInt16(patchInfo[4...5])
        log("\(type): security version: \(securityVersion) (0x\(securityVersion.hex)), localization: \(localization) (0x\(localization.hex)), generation: \(generation) (0x\(generation.hex))")

        self.generation = Int(generation)  // 1: Libre 3+
        region = SensorRegion(rawValue: Int(localization)) ?? .unknown

        let wearDuration = patchInfo[6...7]
        maxLife = Int(UInt16(wearDuration))
        log("\(type): wear duration: \(maxLife) minutes (\(maxLife.formattedInterval), 0x\(maxLife.hex))")

        let fwVersion = patchInfo.subdata(in: 8 ..< 12)
        firmware = "\(fwVersion[3]).\(fwVersion[2]).\(fwVersion[1]).\(fwVersion[0])"
        log("\(type): firmware version: \(firmware)")

        let warmupTime = patchInfo[13]
        log("\(type): warmup time: \(warmupTime * 5) minutes (0x\(warmupTime.hex) * 5)")

        let sensorState = patchInfo[14]
        // TODO: manage specific Libre 3 states
        state = SensorState(rawValue: sensorState <= 2 ? sensorState: sensorState - 1) ?? .unknown
        log("\(type): specific state: \(State(rawValue: sensorState)!.description.lowercased()) (0x\(sensorState.hex)), state: \(state.description.lowercased()) ")

        let serialNumber = Data(patchInfo[15...23])
        serial = (productType == 9 ? "9" : "") + serialNumber.string  // prepend `9` family to a Lingo serial
        log("\(type): serial number: \(serial) (0x\(serialNumber.hex))")

    }


    func send(securityCommand cmd: SecurityCommand) {
        log("Bluetooth: sending to \(type) \(transmitter!.peripheral!.name ?? "(unnamed)") `\(cmd.description)` command 0x\(cmd.rawValue.hex)")
        currentSecurityCommand = cmd
        transmitter!.write(Data([cmd.rawValue]), for: UUID.securityCommands.rawValue, .withResponse)
    }


    func parsePackets(_ data: Data) -> (Data, String) {
        var payload = Data()
        var str = ""
        var offset = data.startIndex
        var offsetEnd = offset
        let endIndex = data.endIndex
        while offset < endIndex {
            str += data[offset].hex + "  "
            _ = data.formIndex(&offsetEnd, offsetBy: 20, limitedBy: endIndex)
            str += data[offset + 1 ..< offsetEnd].hexBytes
            payload += data[offset + 1 ..< offsetEnd]
            _ = data.formIndex(&offset, offsetBy: 20, limitedBy: endIndex)
            if offset < endIndex { str += "\n" }
        }
        return (payload, str)
    }


    func write(_ data: Data, for uuid: UUID = .challengeData) {
        let packets = (data.count - 1) / 18 + 1
        for i in 0 ... packets - 1 {
            let offset = i * 18
            let id = Data([UInt8(offset & 0xFF), UInt8(offset >> 8)])
            let packet = id + data[offset ... min(offset + 17, data.count - 1)]
            debugLog("Bluetooth: writing packet \(packet.hexBytes) to \(transmitter!.peripheral!.name!)'s \(uuid.description) characteristic")
            transmitter!.write(packet, for: uuid.rawValue, .withResponse)
        }
    }


    /// called by Abbott Transmitter class
    func read(_ data: Data, for uuid: String) {

        switch UUID(rawValue: uuid) {

        case .patchControl:
            if data.count == 10 {
                let suffix = data.suffix(2).hex
                // TODO: manage enqueued id
                if buffer.count % 20 == 0 {
                    if suffix == "0100" {
                        log("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count/20) packets of historical data")
                        // TODO
                    } else if suffix == "0200" {
                        log("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count/20) packets of clinical data")
                        // TODO
                    }
                } else {
                    var packets = [Data]()
                    for i in 0 ..< (buffer.count + 19) / 20 {
                        packets.append(Data(buffer[i * 20 ... min(i * 20 + 17, buffer.count - 3)]))
                    }
                    // TODO:
                    // when reactivating a sensor received 20 * 10 + 17 bytes
                    // otherwise receiving 20 * 11 + 12 bytes with the latest firmwares
                    if buffer.count == 217 || buffer.count == 232 {
                        log("\(type) \(transmitter!.peripheral!.name!): received \(packets.count) packets of factory data (\(buffer.count) bytes), payload: \(Data(packets.joined()).hexBytes)")
                    }
                }
                buffer = Data()
                currentControlCommand = nil
            }

            // The Libre 3 sends every minute 35 bytes as two packets of 15 + 20 bytes
            // The final Int is a sequential id
        case .oneMinuteReading:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
                if buffer.count == 35 {
                    let payload = buffer.prefix(33)
                    let id = UInt16(buffer.suffix(2))
                    log("\(type) \(transmitter!.peripheral!.name!): received \(buffer.count) bytes of \(UUID(rawValue: uuid)!) (payload: \(payload.count) bytes): \(payload.hex), id: \(id.hex)")
                    buffer = Data()
                    if settings.onlineInterval > 0 && settings.selectedService == .libreLinkUp {
                        Task { @MainActor in
                            try await Task.sleep(nanoseconds: 2_000_000_000)
                            await main.libreLinkUp?.reload()
                        }
                    }
                }
            }

        case .historicalData, .clinicalData, .eventLog, .factoryData:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
            }
            let payload = data.prefix(18)
            let id = UInt16(data.suffix(2))
            log("\(type) \(transmitter!.peripheral!.name!): received \(data.count) bytes of \(UUID(rawValue: uuid)!) (payload: \(payload.count) bytes): \(payload.hex), id: \(id.hex)")

        case .patchStatus:
            if buffer.count == 0 {
                let payload = data.prefix(16)
                let id = UInt16(data.suffix(2))
                log("\(type) \(transmitter!.peripheral!.name!): received \(data.count) bytes of \(UUID(rawValue: uuid)!) (payload: \(payload.count) bytes): \(payload.hex), id: \(id.hex)")
            }
            // TODO


        case .securityCommands:
            lastSecurityEvent = SecurityEvent(rawValue: data[0]) ?? .unknown
            log("\(type) \(transmitter!.peripheral!.name ?? "(unnamed)"): security event: \(lastSecurityEvent)\(lastSecurityEvent == .unknown ? " (" + data[0].hex + ")" : "")")
            if data.count == 2 {
                expectedStreamSize = Int(data[1] + data[1] / 20 + 1)
                log("\(type) \(transmitter!.peripheral!.name ?? "(unnamed)"): expected response size: \(expectedStreamSize) bytes (payload: \(data[1]) bytes)")
                // TEST: when eavesdropping Trident:
                if data[1] == 23 {
                    currentSecurityCommand = .readChallenge
                } else if data[1] == 67 {  // encrypted KAuth
                    currentSecurityCommand = .challengeLoadDone
                } else if data[1] == 140 { // patchCertificate
                    currentSecurityCommand = .security_09
                } else if data[1] == 65 { // patchEphemeral
                    currentSecurityCommand = .ephemeralLoadDone
                }
            }
            if currentSecurityCommand == .certificateLoadDone && lastSecurityEvent == .certificateAccepted {
                if settings.userLevel < .test { // not eavesdropping Trident
                    send(securityCommand: .security_09)
                }
            }


        case .challengeData, .certificateData:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
            }

            if buffer.count == expectedStreamSize {

                let (payload, hexDump) = parsePackets(buffer)
                log("\(type) \(transmitter!.peripheral!.name ?? "(unnamed)"): received \(buffer.count) bytes of \(UUID(rawValue: uuid)!) (payload: \(payload.count) bytes):\n\(hexDump)")

                switch currentSecurityCommand {

                case .security_09:
                    if settings.userLevel < .test { // not eavesdropping Trident
                        log("\(type) \(transmitter!.peripheral!.name ?? "(unnamed)"): patch certificate: \(payload.hex)")
                        send(securityCommand: .security_0D)
                        // TODO:
                        // write 65-byte ephemeral key
                        let ephemeralKey = Data((0 ..< 65 ).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })  // TEST random ephemeral
                        write(ephemeralKey, for: .certificateData)
                        send(securityCommand: .ephemeralLoadDone)
                    }

                case .ephemeralLoadDone:
                    if settings.userLevel < .test { // not eavesdropping Trident
                        log("\(type) \(transmitter!.peripheral!.name ?? "(unnamed)"): patch ephemeral: \(payload.hex)")
                        send(securityCommand: .readChallenge)
                        // TODO
                    }

                case .readChallenge:

                    // getting: df4bd2f783178e3ab918183e5fed2b2b c201 0000 e703a7
                    //                                        increasing

                    outCryptoSequence = UInt16(payload[16...17])
                    log("\(type) \(transmitter!.peripheral!.name!): security challenge: \(payload.hex) (crypto sequence #: \(outCryptoSequence.hex))")

                    let r1 = payload.prefix(16)
                    let nonce1 = payload.suffix(7)
                    let r2 = Data((0 ..< 16).map { _ in UInt8.random(in: UInt8.min ... UInt8.max) })
                    debugLog("\(type): r1: \(r1.hex), r2: \(r2.hex), nonce1: \(nonce1.hex)")

                    // TODO:
                    // let response = process2(command: 7, nonce1, Data(r1 + r2 + blePIN)) // CRYPTO_EXTENSION_ENCRYPT

                    if settings.userLevel < .test { // not eavesdropping Trident
                        log("\(type) \(transmitter!.peripheral!.name!): writing 40-zero challenge response")

                        let challengeData = Data(count: 40)
                        write(challengeData)
                        // writing .challengeLoadDone makes the Libre 3 disconnect
                        send(securityCommand: .challengeLoadDone)
                    }


                case .challengeLoadDone:
                    let first = payload.subdata(in:  0 ..< 60)
                    let nonce = payload.subdata(in: 60 ..< 67)
                    outCryptoSequence = UInt16(payload[60 ... 61])
                    log("\(type) \(transmitter!.peripheral!.name!): encrypted KAuth: \(first.hex), nonce: \(nonce.hex) (crypto sequence #: \(outCryptoSequence.hex))")
                    // TODO:
                    // https://github.com/j-kaltes/Juggluco/blob/primary/Common/src/libre3/java/tk/glucodata/Libre3GattCallback.java
                    // https://github.dev/j-kaltes/Juggluco/blob/primary/Common/src/main/cpp/bcrypt/bcrypt.cpp
                    // let decr = process2(8, nonce, first)     // CRYPTO_EXTENSION_DECRYPT
                    // let r2    = decr.subdata(in:  0 ..< 16)
                    // let r1    = decr.subdata(in: 16 ..< 32)
                    // let kEnc  = decr.subdata(in: 32 ..< 48)
                    // let ivEnc = decr.subdata(in: 48 ..< 56)
                    transmitter!.peripheral?.setNotifyValue(true, for: transmitter!.characteristics[UUID.patchStatus.rawValue]!)
                    log("\(type) \(transmitter!.peripheral!.name!): enabling notifications on the patch status characteristic")
                    currentSecurityCommand = nil


                default:
                    break // currentSecurityCommand
                }

                buffer = Data()
                expectedStreamSize = 0

            }

        default:
            break  // uuid
        }

    }


    func parseCurrentReading(_ data: Data) {  // -> GlucoseData
        // TODO
    }


    // TODO: separate CMD_ACTIVATE_SENSOR (0xA0) and CMD_SWITCH_RECEIVER (0xA8)
    var activationNFCCommand: NFCCommand {
        // TODO:
        if receiverId == 0 && settings.libreLinkUpUserId == "" {
            log("WARNING: the current receiverId and libreLinkUpUserId are null: a successful login to LibreLinkUp is very probably required first.")
        }
        var parameters: Data = Data()
        parameters += ((activationTime != 0 ? activationTime : UInt32(Date().timeIntervalSince1970)) - 1).data
        parameters += (receiverId != 0 ? receiverId : settings.libreLinkUpPatientId.fnv32Hash).data
        parameters += parameters.crc16.data

        // - A8 changes the BLE PIN on an activated sensor and returns the error 0x1B0 on an expired one.
        // - A0 returns the current BLE PIN on an activated sensor, the error 0x1B1 on a sensor activated
        //   by the reader, the error 0x1B2 on an expired one with a firmware like 1.1.13.30
        //   and a new BLE PIN with older firmwares like 1.0.25.30...
        let code = patchInfo[14] == State.storage.rawValue ? 0xA8 : 0xA0

        return NFCCommand(code: code, parameters: parameters, description: "activate")
    }


    func parseActivation(output: Data) {

        // let output = "A5002BC7291932189F36B26CD01E306209F0".bytes  // TEST

        let output = Data(output.drop(while: { $0 == 0xA5 }))

        if output[0] == 0x01 && output.count == 2 {
            log("NFC: \(type) activation error: 0x\(output.hex)")
            // getting 0x01b0 on an expired sensor
            // getting 0x01b1 on a sensor activated by the reader
            // getting error 0xc2 when altering crc16
            // getting error 0xc1 when omitting crc16
        }

        if output[0] == 0x00 && output.count == 17 {

            // i.e. 002BC7291932189F36B26CD01E306209F0 ->
            // BD_Addr = 2B C7 29 19 32 18 (18:32:19:29:C7:2B)
            // BLE_Key(BLE_Pin) = 9F36B26C
            // A_UTC = 1647320784 (0xD01E3062)
            // APP_CRC16 = 09 F0

            let activationResponse = ActivationResponse(
                bdAddress: Data(output[1 ..< 7].reversed()),
                BLE_Pin:   output.subdata(in: 7 ..< 11),
                activationTime: UInt32(output.subdata(in: 11 ..< 15))
            )
            let crc = UInt16(output[15 ... 16])
            let computedCrc = output[1 ... 14].crc16
            log("NFC: \(type) activation response: \(activationResponse), BLE address: \(activationResponse.bdAddress.hexAddress), BLE PIN: \(activationResponse.BLE_Pin.hex), activation time: \(Date(timeIntervalSince1970: Double(activationResponse.activationTime))), CRC: \(crc.hex), computed CRC: \(computedCrc.hex)")

            transmitter?.macAddress = activationResponse.bdAddress
            blePIN = activationResponse.BLE_Pin
            activationTime = activationResponse.activationTime
            lastReadingDate = Date()
            age = Int(Date().timeIntervalSince(Date(timeIntervalSince1970: Double(activationTime)))) / 60
        }
    }


    func pair() {
        send(securityCommand: .security_01)
        send(securityCommand: .security_02)
        let certificate = "03 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10 00 01 5F 14 9F E1 01 00 00 00 00 00 00 00 00 04 E2 36 95 4F FD 06 A2 25 22 57 FA A7 17 6A D9 0A 69 02 E6 1D DA FF 40 FB 36 B8 FB 52 AA 09 2C 33 A8 02 32 63 2E 94 AF A8 28 86 AE 75 CE F9 22 CD 88 85 CE 8C DA B5 3D AB 2A 4F 23 9B CB 17 C2 6C DE 74 9E A1 6F 75 89 76 04 98 9F DC B3 F0 C7 BC 1D A5 E6 54 1D C3 CE C6 3E 72 0C D9 B3 6A 7B 59 3C FC C5 65 D6 7F 1E E1 84 64 B9 B9 7C CF 06 BE D0 40 C7 BB D5 D2 2F 35 DF DB 44 58 AC 7C 46 15".bytes
        write(certificate, for: .certificateData)
        send(securityCommand: .certificateLoadDone)
        // TODO
    }


    // MARK: - Constants


    class Libre3BLESensor {
        static let STATE_NONE           = 0
        static let STATE_AUTHENTICATING = 5
        static let STATE_AUTHORIZING    = 8
        static let MAX_WRITE_OFFSET_DATA_LENGTH = 18
        static let HISTORIC_POINT_LATENCY = 17
    }


    enum SensorError: Int {
        case sensorTransmissionError = 0
        case sensorNotActive         = 1
        case sensorExpired           = 2
        case sensorInWarmup          = 3
        case sensorTerminated        = 4
        case sensorInsertionFailure  = 5
        case sensorNotCompatible     = 6
        case sensorRemoved           = 7
        case sensorAlreadyStarted    = 8
        case sensorTemporaryProblem  = 9
        case sensorHot               = 10
        case sensorCold              = 11
        case sensorResponseCorrupt   = 12
        case sensorESACheck          = 13
        case sensorNoError           = 14
    //  case sensorNotYours          = 15  // TODO: Android only?
        case invalidData             = 15
    }


    struct MSLibre3Constants {
        static let LIBRE3_HISTORIC_LIFECOUNT_INTERVAL = 5
        static let LIBRE3_MAX_HISTORIC_READING_IN_PACKET = 10
        static let LIBRE3_DQERROR_MAX = 0xFFFF
        static let LIBRE3_DQERROR_DQ              = 0x8000  // 32768
        static let LIBRE3_DQERROR_SENSOR_TOO_HOT  = 0xA000  // 40960
        static let LIBRE3_DQERROR_SENSOR_TOO_COLD = 0xC000  // 49152
        static let LIBRE3_DQERROR_OUTLIER_FILTER_DELTA = 2
    }


    class DPCRLInterface {
        static let ABT_NO_ERROR: Int = 0x0
        static let ABT_ERR0_BLE_TURNED_OFF: Int = 0x1f7
        static let ABT_ERR3_TIME_CHANGE: Int = 0x2e
        static let ABT_ERR3_SENSOR_EXPIRED: Int = 0x33
        static let ABT_ERR3_SENSOR_RSSI_ERROR: Int = 0x39
        static let ABT_ERR3_BLE_TURNED_OFF: Int = 0x4b
        static let ABT_ERR3_REPLACE_SENSOR_ERROR: Int = 0x16d
        static let ABT_ERR3_SENSOR_FALL_OUT_ERROR: Int = 0x16e
        static let ABT_ERR3_INCOMPATIBLE_SENSOR_TYPE_ERROR: Int = 0x16f
        static let ABT_ERR3_SENSOR_CAL_CODE_ERROR = 0x170
        static let ABT_ERR3_SENSOR_DYNAMIC_DATA_CRC_ERROR = 0x171
        static let ABT_ERR3_SENSOR_FACTORY_DATA_CRC_ERROR = 0x172
        static let ABT_ERR3_SENSOR_LOG_DATA_CRC_ERROR = 0x173
        static let ABT_ERR3_SENSOR_NOT_YOURS_ERROR: Int = 0x174
        static let ABT_ERR3_REALTIME_RESULT_DQ_ERROR: Int = 0x175
        static let ABT_ERR3_SENSOR_ESA_DETECTED: Int = 0x17c
        static let ABT_ERR3_SENSOR_NOT_IN_GLUCOSE_MEASUREMENT_STATE: Int = 0x181
        static let ABT_ERR3_BLE_PACKET_ERROR: Int = 0x182
        static let ABT_ERR3_INVALID_DATA_SIZE_ERROR: Int = 0x183
        static let ABT_ERR9_LIB_NOT_INITIALIZED_ERROR: Int = 0x3d6
        static let ABT_ERR9_MEMORY_SIZE_ERROR: Int = 0x3d7
        static let ABT_ERR9_NV_MEMORY_CRC_ERROR: Int = 0x3da
        static let ABT_ERR10_INVALID_USER: Int = 0x582
        static let ABT_ERR10_DUPLICATE_USER: Int = 0x596
        static let ABT_ERR10_INVALID_TOKEN: Int = 0x5a6
        static let ABT_ERR10_INVALID_DEVICE: Int = 0x5aa
        static let ABT_ERROR_DATA_BYTES = 0x8
        static let LIBRE3_DP_LIBRARY_PARSE_ERROR = ~0x0
        static let NFC_ACTIVATION_COMMAND_PAYLOAD_SIZE: Int = 10
        static let PATCH_CONTROL_BACKFILL_GREATER_SIZE = 11
        static let ABT_HISTORICAL_POINTS_PER_NOTIFICATION: Int = 6
        static let LIB3_RECORD_ORDER_NEWEST_TO_OLDEST: Int = 0
        static let LIB3_RECORD_ORDER_OLDEST_TO_NEWEST: Int = 1
        static let PATCH_CONTROL_COMMAND_SIZE: Int = 7
        static let PATCH_NFC_EVENT_LOG_NUM_EVENTS: Int = 3
        static let ABT_EVENT_LOGS_PER_NOTIFICATION: Int = 2
        static let SCRATCH_PAD_BUFFER_SIZE: Int = 0x400
        static let CRL_NV_MEMORY_SIZE: Int = 0x400
        static let LIBRE3_DEFAULT_WARMUP_TIME = 60
        static let MAX_SERIAL_NUMBER_SIZE = 15
        var lastError: Int = 0
        var scratchPadBuffer: UnsafeMutablePointer<UInt32>? = nil
    }


    // Android libre3SecurityConstants
    struct Libre3SecurityConstants {
        static let CERT_PATCH_DATE_STAMP_LENGTH: Int = 2
        static let CERT_PATCH_LENGTH: Int = 140
        static let CERT_PATCH_VERSION_LENGTH: Int = 1
        static let CERT_PUBLIC_KEY_LENGTH: Int = 65
        static let CERT_SERIAL_NUMBER_LENGTH: Int = 8
        static let CERT_SIGNATURE_LENGTH: Int = 64

        static let CMD_AUTHORIZATION_CHALLENGE: UInt8 = 0x07
        static let CMD_AUTHORIZED: UInt8 = 0x05
        static let CMD_AUTHORIZE_ECDSA: UInt8 = 0x06
        static let CMD_AUTHORIZE_SYMMETRIC: UInt8 = 0x11
        static let CMD_CERT_ACCEPTED: UInt8 = 0x04
        static let CMD_CERT_READY: UInt8 = 0x0A
        static let CMD_CHALLENGE_LOAD_DONE: UInt8 = 0x08
        static let CMD_ECDH_COMPLETE: UInt8 = 0x10
        static let CMD_ECDH_START: UInt8 = 0x01
        static let CMD_EPHEMERAL_KEY_READY: UInt8 = 0x0F
        static let CMD_EPHEMERAL_LOAD_DONE: UInt8 = 0x0E
        static let CMD_IV_AUTHENTICATED_SEND: UInt8 = 0x0B
        static let CMD_IV_READY: UInt8 = 0x0C
        static let CMD_KEY_AGREEMENT: UInt8 = 0x0D
        static let CMD_LOAD_CERT_DATA: UInt8 = 0x02
        static let CMD_LOAD_CERT_DONE: UInt8 = 0x03
        static let CMD_MODE_SWITCH: UInt8 = 0x12
        static let CMD_SEND_CERT: UInt8 = 0x09
        static let CMD_VERIFICATION_FAILURE: UInt8 = 0x13

        static let CRYPTO_KEY_LENGTH_BYTES: Int = 16
        static let CRYPTO_MAC_LENGTH_BYTES: Int = 4
        static let L3_SEC_ERROR_AUTHENTICATION_FAILED: Int = 902
        static let L3_SEC_ERROR_AUTHORIZATION_FAILED: Int = 903
        static let L3_SEC_ERROR_DECRYPTION_FAILED: Int = 904
        static let L3_SEC_ERROR_ENCRYPTION_FAILED: Int = 905
        static let L3_SEC_ERROR_INVALID_CERTIFICATE: Int = 901
        static let L3_SEC_ERROR_LIB_ERROR: Int = 906
    }


    // https://github.dev/j-kaltes/Juggluco/blob/primary/Common/src/libre3/java/tk/glucodata/ECDHCrypto.java

    let appCertificates = [
        "03 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 00 01 5f 14 9f e1 01 00 00 00 00 00 00 00 00 04 27 51 fd 1e f4 2b 14 5a 52 c5 93 ae 6b 5a 75 58 8a 9f 7e af 1c 0f 99 85 f9 93 d5 8f 14 7b b8 41 68 42 24 49 96 37 92 dc 43 f3 84 47 ef eb bb eb 4a 53 b3 25 5c 0b e0 fe 1f 23 58 44 a3 d3 29 9e ba 97 b8 e6 c3 17 09 39 f2 77 8f 64 86 6f 06 6d eb 91 5d d6 62 9e ee 47 30 a1 e1 4c ab 75 c1 8c 4f ec 53 f8 85 4c 87 64 3a 76 4f 40 87 ae c0 39 4c 21 0c 18 86 5a 8f f4 5a dc 37 27 f4 8b 53 a7",
        "03 03 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f 10 00 01 61 89 76 55 01 00 00 00 00 00 00 00 00 04 82 42 be 33 f1 a3 30 88 01 12 fa 62 cc 48 42 a4 3d 12 04 92 2a d2 01 d8 77 5b b2 26 f6 11 f7 5b 0e f3 d5 bc 6c c4 31 7c aa 45 75 84 ab 00 3f 17 12 33 60 89 d3 a4 f2 98 38 ed 0d c6 66 de ae a2 d6 5a 00 df ff 5d 7b ca e2 16 55 e3 02 e3 45 8e 77 4d aa aa ca 87 af 75 f1 b8 78 84 b1 8d 4c e8 75 d0 d1 08 c9 03 a8 34 47 1a 4f f6 74 b2 d3 0b cb a0 62 37 30 14 b7 78 6e 44 37 b1 77 ae c3 c8"
    ]

    let appPrivateKeys = [
        "43 F2 C5 3D 02 00 00 00 01 00 00 01 00 00 00 00 00 96 95 77 4B 9A 04 53 51 FB 16 0B EC 5F 49 DB DF 57 45 48 50 67 78 6C DE 13 08 83 D8 3D F6 96 81 4E A4 1E A7 D2 F8 D2 30 84 76 B4 9A 01 2C 4E BB 00 00 00 01 7D 4D 61 51 06 81 BF 22 31 67 6B 90 3B 17 ED 53 98 0D 98 FE 68 2E E4 4B 00 00 00 20 5B 7B 96 AA E3 FF 22 2D 4D 37 1E 7A A6 2C FA A0 9B F8 42 1C C1 DA 7B 7B 0D F9 34 33 CC 49 FB 0E 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 96 9E DB 28 BF 6F C0 FF 76 0A F0 95 92 1D 9F 1E 3B 16 77 B5",
        "1D 85 8F 06 02 00 00 00 01 00 00 01 00 00 00 00 00 96 95 77 4B 9A 04 53 51 FB 16 0B EC 5F 49 DB DF 0D C0 CE 52 FB 56 5F 84 E6 13 B8 19 AE D3 DF 91 9C E3 0A 3D D4 C0 12 EA EA 70 C8 CC E2 89 58 40 00 00 00 01 9B C7 79 12 3D 86 60 B3 7E 99 B4 BF 10 C1 C4 2C 11 35 B3 02 5B C9 B2 EF 00 00 00 20 E3 A1 FB 17 80 A1 63 80 2A A0 FE B1 F2 00 AC 26 9A 42 B2 29 03 8C A6 E1 4D 40 EF BC 6B 7B 6A E8 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 CE C6 67 E6 C0 9D 20 F5 C0 33 D0 61 B5 FC A1 8B 39 92 06 8B"
    ]

    let patchSingningKeys = [
        "04 B6 9D 17 34 F5 E4 25 BC C0 57 6A D1 F7 27 C1 31 1C 90 B6 EA 98 6F 00 6E 7E 9F 90 96 F6 A8 28 4F 12 BF 7D DF E1 54 A3 F1 D4 5A 0F 27 34 EC AB CA 6B 9E B5 6E E4 EC CA 87 85 3A D8 53 B6 A6 41 80",
        "04 A2 D8 47 89 90 94 5F 70 A9 57 0A DE 07 B1 55 BC 90 4D 2D 38 06 47 58 7B 12 39 17 01 30 9B D1 0B 59 90 C4 C4 7C 47 F1 F0 80 46 CB 6F 2D E0 74 8D 1F A7 F7 37 90 EC 9D 8D D6 37 21 27 78 52 88 38"
    ]


    /// whiteCryption Secure Key Box
    struct Libre3SKBCryptoLib {
        static let CRYPTO_RETURN_INVALID_COMMAND: Int = 0
        static let CRYPTO_RETURN_SUCCESS: Int = 1
        static let CRYPTO_RETURN_INVALID_PARAM: Int = -1
        static let CRYPTO_RETURN_LIB_ERROR: Int = -2
        static let CRYPTO_RETURN_LOW_MEMORY: Int = -3
        static let CRYPTO_RETURN_VERITY_FAILED: Int = -4

        static let CRYPTO_EXTENSION_INIT_LIB: Int = 1
        static let CRYPTO_EXTENSION_INIT_ECDH: Int = 2
        static let CRYPTO_EXTENSION_SET_PATCH_ATTRIB: Int = 3
        static let CRYPTO_EXTENSION_SET_CERTIFICATE: Int = 4
        static let CRYPTO_EXTENSION_GENERATE_EPHEMERAL: Int = 5
        static let CRYPTO_EXTENSION_GENERATE_KAUTH: Int = 6
        static let CRYPTO_EXTENSION_ENCRYPT: Int = 7
        static let CRYPTO_EXTENSION_DECRYPT: Int = 8
        static let CRYPTO_EXTENSION_EXPORT_KAUTH: Int = 9
        static let CRYPTO_EXTENSION_GENERATE_DB_KEY: Int = 10
        static let CRYPTO_EXTENSION_WRAP_DB_KEY: Int = 11
        static let CRYPTO_EXTENSION_UNWRAP_DB_KEY: Int = 12
        static let CRYPTO_EXTENSION_WRAP_DIAGNOSTIC_DATA: Int = 13

        let PUBLIC_KEY_TYPE_UNCOMPRESSED: UInt8 = 0x04
        let CRYPTO_PUBLIC_KEY_SIZE: Int = 64
        let patchSigningKey: Data
        let securityVersion: Int
        let max_key_index: Int = 2
        let app_private_key: Data
        let app_certificate: Data
    }


    // https://github.dev/j-kaltes/Juggluco/blob/primary/Common/src/libre3/java/tk/glucodata/Libre3GattCallback.java

    // Juggluco wrappers to Trident's process1() and process2() in liblibre3extension.so (processint() and processbar())
    //
    // public native boolean initECDH(byte[] bArr, int i):
    //     public boolean initECDH(byte[] exportedKAuth, int level) {
    //         if(level >= max_keys)
    //             return true;
    //         securityVersion = level;
    //         int resp1 = Natives.processint(1, null, null);
    //         byte[] privatekey= LIBRE3_APP_PRIVATE_KEYS[level];
    //         int resp2 = Natives.processint(2, privatekey, exportedKAuth);
    //         return true;
    //   }
    //
    // byte[] getAppCertificate() {
    //        return LIBRE3_APP_CERTIFICATES_B[securityVersion];
    //  }
    //
    // setPatchCertificate(byte[] bArr):
    //     Natives.processint(4, input, null);
    //
    // generateEphemeralKeys():
    //     var evikeys = Natives.processbar(5, null, null);
    //
    // boolean generateKAuth(byte[] bArr):
    //     var bool = Natives.processint(6, patchEphemeral, null);
    //     var uit = new byte[evikeys.length + 1];
    //     arraycopy(evikeys, 0, uit, 1, evikeys.length);
    //     uit[0] = (byte)0x4;
    //     return uit;
    //
    // encrypt challenge response:
    //     arraycopy(rdtData, 0, r1, 0, 16);
    //     arraycopy(rdtData, 16, nonce1, 0, 7);
    //     (new SecureRandom()).nextBytes(r2)
    //     byte[] uit = new byte[36];
    //     arraycopy(r1, 0, uit, 0, 16);
    //     arraycopy(r2, 0, uit, 16, 16);
    //     byte[] pin = Natives.getpin(sensorptr);
    //     arraycopy(pin, 0, uit, 32, 4);
    //     var encrypted = Natives.processbar(7, nonce1, uit);
    //
    // decrypt 67-byte encrypted KAuth:
    //     arraycopy(rdtData, 0, first, 0, 60);
    //     arraycopy(rdtData, 60, nonce, 0, 7);
    //     byte[] decr = Natives.processbar(8, nonce, first);
    //     var backr2 = copyOfRange(decr, 0, 16);
    //     var backr1 = copyOfRange(decr, 16, 32);
    //     var kEnc = copyOfRange(decr, 32, 48);
    //     var ivEnc = copyOfRange(decr, 48, 56);
    //
    // byte[] exportAuthorizationKey():
    //     byte[] AuthKey = Natives.processbar(9, null, null);  // 149 bytes
    //     cryptptr = initcrypt(cryptptr, kEnc, ivEnc);


    // Frida-> crypto_lib.getAppCertificate()     => 162 bytes
    // Frida-> crypto_lib.generateEphemeralKeys() => 65 bytes


    class SecureFile {
        static let CRYPTO_EXTENSION_OPEN_LOG_CREATE = 10
        static let CRYPTO_EXTENSION_OPEN_LOG_APPEND = 11
        static let CRYPTO_EXTENSION_CLOSE_LOG = 12
        static let CRYPTO_EXTENSION_WRITE_LOG = 13
        static let CRYPTO_EXTENSION_LOG_SIZE = 15
        static let CRYPTO_EXTENSION_LOG_ERROR = 16
        static let LOG_FILE_NAME = "diagnostics.elog"

        // void latchSkb(String absolutePath):
        //   byte[] bytes = str.getBytes(C6581d.UTF_8);
        //   int process1 = Libre3SKBCryptoLib.process1(11, bytes, null);
        //
        // Frida-> var buffer = Java.array('byte', new Array(256).fill(0))
        // Frida-> p = crypto_lib.process1(11, Array.from("/data/data/com.freestylelibre3.app.it/files/diagnotics.elog", c => c.charCodeAt(0)), buffer)
    }


    // https://github.dev/j-kaltes/Juggluco/blob/primary/Common/src/main/cpp/libre3/loadlibs.cpp

    func process1(command: Int, _ d1: Data?, _ d2: Data?) -> Int {
        return 0
    }

    func process2(command: Int, _ d1: Data?, _ d2: Data?) -> Data {
        return Data()
    }


}
