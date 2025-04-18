import Foundation
import CoreBluetooth


// https://github.com/LoopKit/G7SensorKit


// TODO:
// enum G7.SensorType {
//     case g710Day
//     case g710DayAlgo2
//     case g715DayNonDrug
// }


@Observable class DexcomG7: Sensor {

    // com.dexcom.coresdk.transmitterG7.command CmdRequest$Opcode class
    enum Opcode: UInt8 {
        case unknown                    = 0x00

        case batteryStatus              = 0x22
        case stopSession                = 0x28
        case egv                        = 0x4e
        case calibrationBounds          = 0x32
        case calibrate                  = 0x34
        case transmitterVersion         = 0x4a
        case transmitterVersionExtended = 0x52
        case encryptionInfo             = 0x38
        case backfill                   = 0x59
        case diagnosticData             = 0x51
        case bleControl                 = 0xea
        case encryptionStatus           = 0x0f
        case authStatus                 = 0x0d
        case disconnect                 = 0x09
        // AuthOpCodes
        case txIdChallenge              = 0x01
        case appKeyChallenge            = 0x02
        case challengeReply             = 0x03
        case hashFromDisplay            = 0x04
        case statusReply                = 0x05
        case keepConnectionAlive        = 0x06
        case requestBond                = 0x07
        case requestBondResponse        = 0x08
        case exchangePakePayload        = 0x0a
        case certificateExchange        = 0x0b  // keks: certInfo
        case proofOfPossession          = 0x0c  // keks: signChallenge

        var data: Data { Data([rawValue]) }
    }


    // Connection:
    // write  3535  01 00
    // write  3535  02 + 8 bytes + 02
    // notify 3535  03 + 16 bytes
    // write  3535  04 + 8 bytes
    // notify 3535  05 01 01           // statusReply
    // enable notifications for 3534
    // write  ....  01 00
    // write  3534  4E                 // EGV
    // notify 3534  4E + 18 bytes
    // write  3534  32
    // notify 3534  32 + 19 bytes      // calibrationBounds
    // write  3534  EA 00              // BLE Whitelist
    // notify 3534  EA + 16 bytes
    // write  ....  01 00
    // enable notifications for 3536
    // write  3534  59 + 8 bytes       // backfill startTime-endTime
    // notify 3536  9-byte packets
    // notify 3534  59 + 18 bytes
    // write  3534  51 + 9 bytes       // diagnostic 00 startTime-endTime
    // notify 3536  20-byte packets
    // notify 3534  51 + 16 bytes
    // [...]
    // write  3534  09
    //
    // Pairing:
    // enable notifications for 3535 and 3538
    // write  3535  0A 00
    // notify 3538  20 * 6 bytes
    // notify 3535  0A 00 00
    // notify 3538  20 * 2 bytes
    // write  3538  20 * 8 bytes
    // write  3535  0A 01
    // notify 3538  20 * 6 bytes
    // notify 3535  0A 00 01
    // notify 3538  20 * 2 bytes
    // write  3538  20 * 8 bytes
    // write  3535  0A 02
    // notify 3538  20 * 6 bytes
    // notify 3535  0A 00 02
    // notify 3538  20 * 2 bytes
    // write  3538  20 * 8 bytes
    // write  3535  02 + 8 bytes + 02
    // notify 3535  03 + 16 bytes
    // write  3535  04 + 8 bytes
    // notify 3535  05 01 02
    // write  3535  0B00 + 4 bytes     // certificateExchange phase 0
    // notify 3538  20 * 6 bytes
    // notify 3535  0B0000 + 4 bytes
    // notify 3538  20 * 18 + 12 bytes
    // write  3538  20 * 24 + 14 bytes
    // write  3535  0B01 + 4 bytes
    // notify 3538  20 * 6 bytes
    // notify 3535  0B0001 + 4 bytes
    // notify 3538  20 * 16 + 17/18 bytes // *15+7 when repairing
    // write  3538  20 * 23/22 + 6 bytes  // *21+14 when repairing
    // write  3535  0B02 0000 0000
    // notify 3535  0B00 0200 0000 00
    // write  3535  0C + 16 bytes      // proofOfPossession challenge
    // notify 3538  20 * 3 + 4 bytes
    // notify 3535  0C00 + 16 bytes
    // write  3538  20 * 3 + 4 bytes   // proofOfPossession signature
    // write  3535  06 19              // keepConnectionAlive 25
    // notify 3535  06 00
    // write  3535  07
    // notify 3535  07 00
    // notify 3535  08 01
    // enable notifications for 3534
    // write  3534  4A
    // notify 3534  4A00 + 18 bytes    // transmitterVersion
    // write  3534  52
    // notify 3534  5200 + 13 bytes    // transmitterVersionExtended
    // write  3534  EA02 01            // BLE StreamSpeed (1: fast)
    // notify 3534  EA00 01
    // write  3534  EA03 7017 0000     // BLE StreamSize (6000)
    // notify 3534  EA00 7017 0000
    // [4E 32 EA00 59 51 like for a connection]
    // when repairing:
    // write  3534  38
    // notify 3538  20 * 6 + 12 bytes  // encryptionInfo
    // notify 3534  3800 8400 0000     // 132-byte stream end


    // class G7TxController.TxResponse {
    //     let txFailure: Swift.Bool
    //     let txResponse: G7TxController.TransmitterResponseCode
    // }


    enum TransmitterResponseCode: Int, Decamelizable {
        case unknown         = -1
        case success         = 0
        case notPermitted    = 1
        case notFound        = 2
        case ioError         = 3
        case badHandle       = 4
        case tryLater        = 5
        case outOfMemory     = 6
        case noAccess        = 7
        case segfault        = 8
        case busy            = 9
        case badArgument     = 10
        case noSpace         = 11
        case badRange        = 12
        case notImplemented  = 13
        case timeout         = 14
        case protocolError   = 15
        case unexpectedError = 16
    }


    /// called by Dexcom Transmitter class
    func read(_ data: Data, for uuid: String) {

        let opCode = Opcode(rawValue: data[0]) ?? .unknown
        let tx = transmitter as! Dexcom
        let txResponseCode = TransmitterResponseCode(rawValue: Int(data[1])) ?? .unknown

        switch Dexcom.UUID(rawValue: uuid) {


        case .authentication:

            switch opCode {

            case .statusReply:

                if tx.authenticated {

                    let transmitterVersionCmd = Opcode.transmitterVersion.data
                    log("DEBUG: sending \(tx.name) the 'transmitterVersion' command 0x\(transmitterVersionCmd.hex)")
                    tx.write(transmitterVersionCmd, .withResponse)

                    let transmitterVersionExtendedCmd = Opcode.transmitterVersionExtended.data
                    log("DEBUG: sending \(tx.name) the 'transmitterVersionExtended' command 0x\(transmitterVersionExtendedCmd.hex)")
                    tx.write(transmitterVersionExtendedCmd, .withResponse)

                    let batteryStatusCmd = Opcode.batteryStatus.data
                    log("DEBUG: sending \(tx.name) the 'batteryStatus' command 0x\(batteryStatusCmd.hex)")
                    tx.write(batteryStatusCmd, .withResponse)

                    // FIXME: just 02 replies
                    let authStatusCmd = Opcode.authStatus.data + Data([2, 2])
                    log("TEST: sending \(tx.name) the 'authStatus' command 0x\(authStatusCmd.hex)")
                    tx.write(authStatusCmd, .withResponse)
                    let encryptionInfoCmd = Opcode.encryptionInfo.data
                    log("TEST: sending \(tx.name) the 'encryptionInfo' command 0x\(encryptionInfoCmd.hex)")
                    tx.write(encryptionInfoCmd, .withResponse)
                    let encryptionStatusCmd = Opcode.encryptionStatus.data
                    log("TEST: sending \(tx.name) the 'encryptionStatus' command 0x\(encryptionStatusCmd.hex)")
                    tx.write(encryptionStatusCmd, .withResponse)
                    let whitelistCmd = Opcode.bleControl.data + Data([0])
                    log("TEST: sending \(tx.name) the 'BLE whitelist' command 0x\(whitelistCmd.hex)")
                    tx.write(whitelistCmd, .withResponse)
                    let streamSizeCmd = Opcode.bleControl.data + Data([3])
                    log("TEST: sending \(tx.name) the 'BLE stream size' command 0x\(streamSizeCmd.hex)")
                    tx.write(streamSizeCmd, .withResponse)
                }


            // TODO: Dexcom ONE/G7 J-PAKE
            // https://github.com/Mbed-TLS/mbedtls/blob/development/tf-psa-crypto/drivers/builtin/include/mbedtls/ecjpake.h
            // https://github.com/j-kaltes/Juggluco/blob/primary/Common/src/dex/java/tk/glucodata/DexGattCallback.java
            // https://github.com/j-kaltes/Juggluco/blob/primary/Common/src/main/cpp/dexcom/
            // https://github.com/NightscoutFoundation/xDrip/commit/7ee3473 ("Add keks library")
            // https://github.com/NightscoutFoundation/xDrip/blob/master/libkeks/src/main/java/jamorham/keks/Calc.java
            // https://github.com/particle-iot/iOSBLEExample/blob/main/iOSBLEExample/ParticleBLECode/ECJPake.swift

            case .exchangePakePayload:
                // TODO
                let status = data[1]
                let phase = data[2]
                var packets = [Data]()
                for i in 0 ..< (tx.buffer.count + 19) / 20 {
                    packets.append(Data(tx.buffer[i * 20 ..< min((i + 1) * 20, tx.buffer.count)]))
                }
                log("\(tx.name): J-PAKE payload (TODO): status: \(status), phase: \(phase), current buffer length: \(tx.buffer.count), current 20-byte packets received: \(packets.count)")

            default:
                break

            }


        case .control:

            switch opCode {

            case .egv:

                // https://github.com/LoopKit/G7SensorKit/blob/main/G7SensorKit/Messages/G7GlucoseMessage.swift

                //  0  1  2 3 4 5  6 7  8  9 1011 1213 14 15 1617 18
                //       TTTTTTTT SQSQ       AGAG BGBG SS TR PRPR C
                // 4e 00 d5070000 0900 00 01 0500 6100 06 01 ffff 0e
                // TTTTTTTT = timestamp
                //     SQSQ = sequence
                //     AGAG = age
                //     BGBG = glucose
                //       SS = algorithm state
                //       TR = trend
                //     PRPR = predicted
                //        C = calibration

                // TODO:
                // class G7TxController.EGVResponse {
                //     let txTime: Swift.UInt32
                //     let sequenceNumber: Swift.UInt32
                //     let sessionNumber: Swift.UInt8
                //     let egvAge: Swift.UInt16
                //     let value: Swift.UInt16
                //     let algorithmState: Swift.UInt8
                //     let secondaryalgorithmState: Swift.UInt8
                //     let rate: Swift.Int8
                //     let predictiveValue: Swift.UInt16
                //     var timeStamp: Swift.UInt32
                // }

                let txTime = UInt32(data[2..<6])
                tx.activationDate = Date.now - TimeInterval(txTime)
                activationTime = UInt32(tx.activationDate.timeIntervalSince1970)
                let sensorAge = Int(Date().timeIntervalSince(tx.activationDate)) / 60
                age = sensorAge
                state = .active
                if maxLife == 0 { maxLife = 14400 }
                let sequenceNumber = UInt16(data[6..<8])
                let egvAge = UInt16(data[10..<12])
                let timestamp = txTime - UInt32(egvAge)
                let date = tx.activationDate + TimeInterval(timestamp)
                let glucoseData = UInt16(data[12..<14])
                let value: UInt16? = glucoseData != 0xffff ? glucoseData & 0xfff : nil
                let algorithmState = data[14]  // TODO
                let rate: Double? = data[15] != 0x7f ? Double(Int8(bitPattern: data[15])) / 10 : nil
                let glucoseIsDisplayOnly: Bool? = glucoseData != 0xffff ? (data[18] & 0x10) > 0 : nil
                let predictionData = UInt16(data[16..<18])
                let predictedValue: UInt16? = predictionData != 0xffff ? predictionData & 0xfff : nil
                let calibration = data[18]
                log("\(tx.name): glucose value (EGV): response code: \(txResponseCode.decamelized), message timestamp: \(txTime.formattedInterval), sensor activation date: \(tx.activationDate.local), sensor age: \(sensorAge.formattedInterval), sequence number: \(sequenceNumber), reading age: \(egvAge) seconds, timestamp: \(timestamp.formattedInterval) (0x\(UInt32(timestamp).hex)), date: \(date.local), glucose value: \(value != nil ? String(value!) : "nil"), is display only: \(glucoseIsDisplayOnly != nil ? String(glucoseIsDisplayOnly!) : "nil"), algorithm state: \(Dexcom.AlgorithmState(rawValue: algorithmState)?.description ?? "unknown") (0x\(algorithmState.hex)), rate: \(rate != nil ? String(rate!) : "nil"), predicted value: \(predictedValue != nil ? String(predictedValue!) : "nil"), calibration: 0x\(calibration.hex)")
                // TODO: merge last three hours; move to bluetoothDelegata main.didParseSensor(app.transmitter.sensor!)
                let backfillMinutes = UInt32(main.settings.backfillMinutes)
                if main.settings.userLevel >= .test && backfillMinutes > 0 {
                    let startTime = timestamp > backfillMinutes * 60 ? timestamp - backfillMinutes * 60 : 5 * 60
                    let endTime = timestamp - 5 * 60
                    let backfillCmd = Opcode.backfill.data + startTime.data + endTime.data
                    log("TEST: sending \(tx.name) backfill \(backfillMinutes) minutes command 0x\(backfillCmd.hex)")
                    tx.write(backfillCmd, .withResponse)
                }
                let item = Glucose(value != nil ? Int(value!) : -1, trendRate: Double(rate ?? 0), id: Int(Double(timestamp) / 60 / 5), date: date)
                self.trend.insert(item, at: 0)
                Task { @MainActor in
                    app.currentGlucose = item.value
                    app.lastReadingDate = item.date
                    lastReadingDate = item.date
                    main.history.factoryTrend.insert(item, at: 0)
                    if main.history.factoryValues.count == 0 || main.history.factoryValues[0].id < item.id {
                        main.history.factoryValues = [item] + main.history.factoryValues
                    }
                    await main.healthKit?.write([item])
                    main.healthKit?.read()
                }


            case .calibrationBounds:

                // TODO: i.e. 32 00 01 4E000000 0000 00000000 01 01 00 E4000000 (20 bytes) (no calibration)
                //            32 00 01 4D000000 AA00 344D0200 03 01 02 754E0200 (AA00: 170)

                // class G7TxController.CalibrationBoundsResponse {
                //     let sessionNumber: Swift.UInt8
                //     let sessionSignature: Swift.UInt32
                //     let lastBGvalue: Swift.UInt16
                //     let lastCalibrationTime: Swift.UInt32
                //     let calibrationProcessingStatus: G7TxController.G7CalibrationProcessingStatus
                //     let calibrationsPermitted: Swift.Bool
                //     let lastBGDisplay: G7TxController.G7DisplayType
                //     let lastProcessingUpdateTime: Swift.UInt32
                // }

                let sessionNumber = data[2]
                let sessionSignature = UInt32(data[3...6])
                let lastBGValue = UInt16(data[7...8])
                let lastCalibrationTime = TimeInterval(UInt32(data[9...12]))
                let calibrationProcessingStatus = CalibrationProcessingStatus(rawValue: Int(data[13]))!
                let calibrationsPermitted = data[14] != 0
                let lastBGDisplay = Dexcom.DisplayType(rawValue: Int(data[15]))!
                let lastProcessingUpdateTime = TimeInterval(UInt32(data[16...19]))
                log("\(tx.name): calibration bounds: response code: \(txResponseCode.decamelized), session number: \(sessionNumber), session signature: \(sessionSignature.hex), last BG value: \(lastBGValue), last calibration time: \(lastCalibrationTime.formattedInterval), calibration processing status: \(calibrationProcessingStatus.decamelized), calibrations permitted: \(calibrationsPermitted), last BG display: \(String(describing: lastBGDisplay)), last processing update time: \(lastProcessingUpdateTime.formattedInterval)")


            case .diagnosticData:
                // TODO: i. e. 51 00 00 a0160000 9a44 ea430200 ec5f0200 (17 bytes)
                // TODO: DataStreamType and DataStreamFilterType first bytes
                enum DiagnosticDataResult: UInt8 { case success, empty, truncated }
                let backfillStatus = DiagnosticDataResult(rawValue: data[2])!
                let bufferLength = UInt32(data[3...6])
                let bufferCRC = UInt16(data[7...8])
                let startTime = TimeInterval(UInt32(data[9...12]))
                let endTime = TimeInterval(UInt32(data[13...16]))
                // TODO
                log("\(tx.name): backfill: response code: \(txResponseCode.decamelized), backfill status: \(String(describing: backfillStatus)), buffer length: \(bufferLength), buffer CRC: \(bufferCRC.hex), start time: \(startTime.formattedInterval), end time: \(endTime.formattedInterval)")
                var packets = [Data]()
                for i in 0 ..< (tx.buffer.count + 19) / 20 {
                    packets.append(Data(tx.buffer[i * 20 ..< min((i + 1) * 20, tx.buffer.count)]))
                }
                log("\(tx.name): backfilled stream (TODO): buffer length: \(tx.buffer.count), valid CRC: \(bufferCRC == tx.buffer.crc), 20-byte packets: \(packets.count)")
                tx.buffer = Data()
                // TODO


            case .backfill:
                // TODO: i. e. 59 00 00 3F000000 AB93 3802 E2960200 EA9D0200 (19 bytes)
                enum EGVBackfillResult: UInt8 { case success, noRecord, oversized }
                let backfillStatus = EGVBackfillResult(rawValue: data[2])!
                let length = UInt32(data[3...6])
                let crc = UInt16(data[7...8])
                let firstSequenceNumber = UInt16(data[9...10])
                let firstTimestamp = TimeInterval(UInt32(data[11...14]))
                let lastTimestamp = TimeInterval(UInt32(data[15...18]))
                log("\(tx.name): backfill: response code: \(txResponseCode.decamelized), backfill status: \(String(describing: backfillStatus)), buffer length: \(length), buffer CRC: \(crc.hex), valid CRC: \(crc == tx.buffer.crc), first sequence number: \(firstSequenceNumber), first timestamp: \(firstTimestamp.formattedInterval), last timestamp: \(lastTimestamp.formattedInterval)")
                var packets = [Data]()
                for i in 0 ..< (tx.buffer.count / 9) {
                    packets.append(Data(tx.buffer[i * 9 ..< min((i + 1) * 9, tx.buffer.count)]))
                }
                var history = [Glucose]()
                for data in packets {

                    // TODO

                    // https://github.com/LoopKit/G7SensorKit/blob/main/G7SensorKit/G7CGMManager/G7BackfillMessage.swift
                    //
                    //    0 1 2  3  4 5  6  7  8
                    //   TTTTTT    BGBG SS    TR
                    //   45a100 00 9600 06 0f fc

                    let timestamp = UInt32(data[0..<3] + [(UInt8)(0)]) // seconds since pairing
                    let date = tx.activationDate + TimeInterval(timestamp)
                    let glucoseBytes = UInt16(data[4..<6])
                    let glucose = glucoseBytes != 0xffff ? Int(glucoseBytes & 0xfff) : nil
                    let glucoseIsDisplayOnly = data[7] & 0x10 != 0
                    let algorithmState = data[6]
                    let rate: Double? = data[8] != 0x7f ? Double(Int8(bitPattern: data[8])) / 10 : nil
                    log("\(tx.name): backfilled glucose: timestamp: \(timestamp.formattedInterval), date: \(date.local), glucose: \(glucose != nil ? String(glucose!) : "nil"), is display only: \(glucoseIsDisplayOnly), algorithm state: \(Dexcom.AlgorithmState(rawValue: algorithmState)?.description ?? "unknown") (0x\(algorithmState.hex)), rate: \(rate != nil ? String(rate!) : "nil")")
                    if let glucose {
                        let item = Glucose(glucose, trendRate: rate ?? 0, id: Int(Double(timestamp) / 60 / 5), date: date)
                        // TODO: manage trend and state
                        history.append(item)
                    }
                }
                log("\(tx.name): backfilled history (\(history.count) values): \(history)")
                // TODO: merge last three hours; move to bluetoothDelegata main.didParseSensor(app.transmitter.sensor!)
                main.history.factoryValues = history.reversed()
                tx.buffer = Data()


            case .batteryStatus:
                let voltageA = Int(UInt16(data[2...3]))
                let voltageB = Int(UInt16(data[4...5]))
                let runtimeDays = Int(data[6])
                let temperature = Int(Int8(bitPattern: data[7]))
                log("\(tx.name): battery status: response code: \(txResponseCode.decamelized), static voltage A: \(voltageA), dynamic voltage B: \(voltageB), run time: \(runtimeDays) days, temperature: \(temperature)")


            // struct G7TxController.G7StaticInfo {
            //     let apiVersion: Swift.UInt
            //     var firmwareVersion: Swift.String
            //     var softwareNumber: Swift.UInt
            //     var siliconVersion: Swift.UInt
            //     var algorithmVersion: Swift.UInt
            //     var hardwareVersion: Swift.UInt
            //     var maxRuntime: Swift.UInt
            //     var sessionLength: Swift.UInt
            //     var warmupLength: Swift.UInt
            // }


            case .transmitterVersion:
                // TODO: i.e. 4a 00 20c06852 2a340000 30454141 443499bb8c00 (20 bytes)
                let versionMajor = data[2]
                let versionMinor = data[3]
                let versionRevision = data[4]
                let versionBuild = data[5]
                let firmwareVersion = "\(versionMajor).\(versionMinor).\(versionRevision).\(versionBuild)"
                firmware = firmwareVersion
                let swNumber = UInt32(data[6...9])
                let siliconVersion = UInt32(data[10...13])
                let serialNumber: UInt64 = UInt64(data[14]) + UInt64(data[15]) << 8 + UInt64(data[16]) << 16 + UInt64(data[17]) << 24 + UInt64(data[18]) << 32 + UInt64(data[19]) << 40
                serial = String(serialNumber)
                log("\(tx.name): transmitter version: response code: \(txResponseCode.decamelized), firmware: \(firmwareVersion), software number: \(swNumber), silicon version: \(siliconVersion) (0x\(siliconVersion.hex)), serial number: \(serialNumber)")


            case .transmitterVersionExtended:
                // TODO: i.e. 52 00 c0d70d00 5406 02010404 ff 0c00 (15 bytes)
                let sessionLength = TimeInterval(UInt32(data[2...5]))
                maxLife = Int(UInt32(data[2...5]) / 60)  // inlcuding 12h grace period
                let warmupLength = TimeInterval(UInt16(data[6...7]))
                let algorithmVersion = UInt32(data[8...11])
                let hardwareVersion = Int(data[12])
                let maxLifetimeDays = UInt16(data[13...14])
                log("\(tx.name): extended transmission version: response code: \(txResponseCode.decamelized), session length: \(sessionLength.formattedInterval), warmup length: \(warmupLength.formattedInterval), algorithm version: 0x\(algorithmVersion.hex), hardware version: \(hardwareVersion), max lifetime days: \(maxLifetimeDays)")


            case .encryptionInfo:
                // i.e. 38 00 84000000
                let bufferLength = UInt32(data[2...5])
                // TODO: buffer starting with 02000000
                let dataStreamType = Dexcom.DataStreamType(rawValue: Int(tx.buffer[0]))!
                log("\(tx.name): encryption info: response code: \(txResponseCode.decamelized), buffer length: \(bufferLength), stream type: \(String(describing: dataStreamType)), encryption info: \(tx.buffer.hex)")
                tx.buffer = Data()


            case .bleControl:
                // TODO: commands 00: WhitelistResponse, 0201: StreamSpeedResponse, 03: StreamSizeResponse
                //
                // WhitelistResponse i.e. ea 00 03 0100000000000200000045ffffff
                //                        ea 00 03 010200000000620000004dffffff
                //                        ea 00 03 020100000000430000004dffffff
                // StreamSizeResponse     ea 00 70170000
                //
                // class G7TxController.DeviceListResponse {
                //     let maxDevices: Swift.UInt8
                //     let displayIds: [Swift.UInt8]
                //     let displayTypes: [G7TxController.G7DisplayType]
                //     let restrictions: Swift.UInt32
                // }
                //
                // class G7TxController.StreamSizeResponse {
                //     let size: Swift.UInt32
                // }

                // TODO: store the BLE pending user commands queue

                switch data.count {

                case 17:
                    let maxDevices = data[2]
                    // TODO
                    log("\(tx.name): BLE whitelist: response code: \(txResponseCode.decamelized), max devices: \(maxDevices)")

                case 6:
                    let streamSize = UInt32(data[2...5])
                    log("\(tx.name): BLE stream size: response code: \(txResponseCode.decamelized), stream size: \(streamSize)")

                case 3:
                    let streamSpeed = data[2]
                    log("\(tx.name): BLE stream speed: response code: \(txResponseCode.decamelized), stream speed: \(streamSpeed)\(streamSpeed == 1 ? " (fast)" : "")")

                default:
                    break
                }


            default:
                break

            }


        case .jPake:
            if tx.buffer.count == 0 {
                tx.buffer = Data(data)
            } else {
                tx.buffer += data
            }
            let index = Int(ceil(Double(tx.buffer.count) / 20))
            log("\(tx.name): J-PAKE exchange: received packet # \(index), partial buffer size: \(tx.buffer.count)")
            if tx.buffer.count == 160 {
                log("\(tx.name): 160-byte J-PAKE payload: \(tx.buffer.hex)")
                // TODO
                tx.buffer = Data()
            }


        default:
            break

        }

    }


    // G7TxController.G7CalibrationProcessingStatus
    enum CalibrationProcessingStatus: Int, Decamelizable {
        case none
        case factoryCalibrated
        case inProgress
        case completeHigh
        case completeLow
    }


    // TODO: secondary states, enum TxControllerG7.G7CalibrationStatus
    //
    // enum G7TxController.G7AlgorithmState {
    //     case warmupG7TxControllerG7AlgorithmState.WarmupSecondary
    //     case inSessionG7TxControllerG7AlgorithmState.InSessionSecondary
    //     case inSessionInvalidG7TxControllerG7AlgorithmState.InSessionInvalidSecondary
    //     case sessionExpiredG7TxControllerG7AlgorithmState.SessionExpiredSecondary
    //     case sessionFailedG7TxControllerG7AlgorithmState.SessionFailedSecondary
    //     case manuallyStoppedG7TxControllerG7AlgorithmState.ManuallyStoppedSecondary
    //     case none
    //     case deployed
    //     case transmitterFailed
    //     case sivFailed
    //     case sessionFailedOutOfRange
    // }
    //
    // enum G7TxController.G7AlgorithmState.WarmupSecondary {
    //     case sivPassed
    //     case parametersUpdated
    //     case signalProcessing
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.InSessionSecondary {
    //     case low
    //     case lowNoPrediction
    //     case lowNoTrend
    //     case lowNoTrendOrPrediction
    //     case inRange
    //     case inRangeNoPrediction
    //     case inRangeNoTrend
    //     case inRangeNoTrendOrPrediction
    //     case high
    //     case highNoPrediction
    //     case highNoTrend
    //     case highNoTrendOrPrediction
    //     case bgTriggered
    //     case bgTriggeredNoPrediction
    //     case bgTriggeredNoTrend
    //     case bgTriggeredNoTrendOrPrediction
    //     case bgTriggeredLow
    //     case bgTriggeredLowNoPrediction
    //     case bgTriggeredLowNoTrend
    //     case bgTriggeredLowNoTrendOrPrediction
    //     case bgTriggeredHigh
    //     case bgTriggeredHighNoPrediction
    //     case bgTriggeredHighNoTrend
    //     case bgTriggeredHighNoTrendOrPrediction
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.InSessionInvalidSecondary {
    //     case invalid
    //     case validPrediction
    //     case validTrend
    //     case validTrendAndPrediction
    //     case bgInvalid
    //     case bgInvalidValidPrediction
    //     case bgInvalidValidTrend
    //     case bgInvalidValidTrendAndPrediction
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.SessionExpiredSecondary {
    //     case validEgv
    //     case validEgvNoPrediction
    //     case validEgvNoTrend
    //     case validEgvNoTrendOrPrediction
    //     case invalidEgv
    //     case invalidEgvNoPrediction
    //     case invalidEgvNoTrend
    //     case invalidEgvNoTrendOrPrediction
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.SessionFailedSecondary {
    //     case unspecified
    //     case sensorFailure
    //     case algorithmFailure
    //     case unexpectedAlgorithmFailure
    //     case noData
    //     case error
    // }
    //
    // enum G7TxController.G7AlgorithmState.ManuallyStoppedSecondary {
    //     case none
    //     case skip
    //     case other
    //     case bestTimingForMe
    //     case inaccurate
    //     case noReadings
    //     case sensorFellOff
    //     case discomfort
    //     case error
    // }


    // TODO:
    //
    // class G7TxController.G7DiagnosticReading {
    //     let startTime: Swift.UInt32
    //     let endTime: Swift.UInt32
    //     let data: Foundation.Data
    // }    //

    // class G7TxKit.TxRecordAggregator {
    //     let pairingCode: Swift.String
    //     var txId: Swift.String?
    //     let communicationStartTime: CgmFoundation.CalculatedTime
    //     var txTimeOffsetInfo: G7TxKit.TxTimeOffsetInfo?
    //     var encryptionInfo: Foundation.Data?
    //     var diagnosticData: [G7TxController.G7DiagnosticReading]?
    //     var calibrationBounds: G7TxController.G7CalibrationBounds?
    //     var sensorReadings: [G7TxKit.G7SensorReading]?
    //     var authenticationErrors: s0(null)XY
    //     var communicationErrors: [G7TxController.G7CommunicationError]?
    //     var stopCommandResponse: G7TxController.G7StopSensorStatus?
    //     var calibrationCommandResponse: G7TxController.G7CalibrationStatus?
    //     var deviceList: G7TxController.G7DeviceList?
    //     var txFailed: Swift.Bool
    //     var state: G7TxKit.TxCommState
    //     let dataSource: CgmKit.SourceStream
    //     var txSW: Swift.String?
    //     var status: Swift.String?
    // }

}


@Observable class DexcomONEPlus: DexcomG7 {

    /// called by Dexcom Transmitter class
    override func read(_ data: Data, for uuid: String) {

        switch Dexcom.UUID(rawValue: uuid) {

        default:
            break

        }

        super.read(data, for: uuid)

    }

}


@Observable class Stelo: DexcomG7 {

    /// called by Dexcom Transmitter class
    override func read(_ data: Data, for uuid: String) {

        switch Dexcom.UUID(rawValue: uuid) {

        default:
            break

        }

        super.read(data, for: uuid)

    }

}


class DexcomSecurity {

    // struct P256Curve {
    //     let size: Swift.Int
    //     let order: BigInt
    //     let prime: BigInt
    // }


    // class ECPoint {
    //     let x: BigInt
    //     let y: BigInt
    //     let curve: CurveXY_p
    // }


    // class ECKeyPair {
    //     let publicPoint: ECPoint
    //     let privatePoint: BigInt
    // }


    // class ECJPakePayload {
    //     let publicKey: ECPoint
    //     let epherealKey: ECPoint
    //     let schnorrSignature: BigInt
    // }


    //  class ECJPakePhase {
    //      let createPayload: ECJPakePayloadXY_pyKc
    //      let verifyPayload: ECJPakePayloadXY_pKc
    //      let verifyPayloadData: (Foundation.Data) throws -> Swift.Bool
    //  }


    // enum ECJPakeRole {
    //     case transmitter
    //     case display
    // }


    // class ECJPakePayloadFactory {
    //     let curve: CurveXY_p
    // }


    // class ECJPake {
    //     let curve: CurveXY_p
    //     let payloadFactory: ECJPakePayloadFactoryXY_p
    // }


    // class ECKeyPairFactory {
    //     var curve: CurveXY_p
    // }


    // class ECJPakeParticipant {
    //     let participantName: Foundation.Data
    //     let otherParticipantName: Foundation.Data
    //     let password: Foundation.Data
    //     var round2PayloadCreated: Swift.Bool
    //     var round2PayloadVerified: Swift.Bool
    //     let curve: CurveXY_p
    //     let payloadFactory: ECJPakePayloadFactoryXY_p
    //     let ecjpake: ECJPake
    //     let keyPairFactory: ECKeyPairFactory
    //     let localX1KeyPair: ECKeyPair
    //     let localX2KeyPair: ECKeyPair
    //     var remoteX3PublicKey: ECPoint?
    //     var remoteX4PublicKey: ECPoint?
    //     var remoteXmPublicKey: ECPoint?
    //     var $__lazy_storage_$_ecJPakePhases: [ECJPakePhase]?
    // }


    // enum ECJPakeError: String {
    //     case invalidArgumentException
    //     case illegalStateException
    //     case arithmeticError
    // }


    // class G7TxController.CertificateResponse {
    //     let phase: Swift.UInt8
    //     let certificateSize: Swift.UInt32
    //     let certificateResponseSize: Swift.Int
    // }


    // class G7TxController.ProofOfPossessionResponse {
    //     let challenge: Foundation.Data
    //     let popResponseSize: Swift.Int
    // }


    // https://github.com/j-kaltes/Juggluco/blob/f9aad1a3080e92c42e253b96ed511cb7ba5ac5b2/Common/src/dex/java/tk/glucodata/DexGattCallback.java#L774-L779
    //
    // https://github.com/NightscoutFoundation/xDrip/blob/master/libkeks/src/main/java/jamorham/keks/Plugin.java
    // https://navid200.github.io/xDrip/docs/Dexcom/G7.html
    //
    // keks_p1 = 308201EA3082018FA00302010202142F3C52B6EB08701046D45D78CE81784C9DFE5240300A06082A8648CE3D04030230133111300F06035504030C084445583030504731301E170D3230313033303135353930345A170D3335313032373135353930345A30133111300F06035504030C0844455830335047313059301306072A8648CE3D020106082A8648CE3D03010703420004FB1ACA21D8AEEC9A4EB51F85304953D977A1AD569799250FF863987F42A3CD9FA4FF571EB568BC6C396277C3DCB51DEDAEE85513C80A5C4435538A19F5A96348A381C03081BD300F0603551D130101FF040530030101FF301F0603551D230418301680149E0F1E36F3F276A701FE8E883A6E26A635BD6AFC305A0603551D1F04533051304FA034A0328630687474703A2F2F63726C2E64702E736161732E7072696D656B65792E636F6D2F63726C2F44455830305047312E63726CA217A41530133111300F06035504030C084445583030504731301D0603551D0E0416041488F61E81BC4B17F05C6B1BE2991D60087CCEDD79300E0603551D0F0101FF040403020186300A06082A8648CE3D0403020349003046022100AA69CD897EC663AF5F9E158187DF6851FF0756F00C401624564F81A19F5A0785022100DAEBB9FDB163B731EB0661F1C0A1932871A50E399AD1C6F519EABD4C9E7BA013
    //
    // keks_p2 = 308201CD30820174A003020102021419052FCC17530BFA56E49DCAFCDACF853CE5BA73300A06082A8648CE3D04030230133111300F06035504030C084445583033504731301E170D3233303431343130323831345A170D3235303431333130323831335A303A3138303606035504030C2F30312C303030302C303330304C514543437A4142417741412C63696F69653356625132686C5A4D6A64556D357267413059301306072A8648CE3D020106082A8648CE3D030107034200045118C35E9E41E7E0654FEE801C52A9C5DFC510EF09597D5CCA8461E4AF9C666714834F2BC903F16FABFC45755B0183F1A09745CDFFCB4E2F799E50BED9A6B58CA37F307D300C0603551D130101FF04023000301F0603551D2304183016801488F61E81BC4B17F05C6B1BE2991D60087CCEDD79301D0603551D250416301406082B0601050507030206082B06010505070301301D0603551D0E04160414D309E75C0725412D7A7922E3AACFB27F7EBD6BE0300E0603551D0F0101FF0404030205A0300A06082A8648CE3D0403020347003044022048D4868CF393D9044101B6F07FD68D7F0642805F85DA74E2FE9DE8DD3507F02702201CD1BF7C6C7EDD59435E324925FCF0EBB3CAE2110D79407C77AA3B93B7BC04CB
    //
    // keks_p3 = 308187020100301306072A8648CE3D020106082A8648CE3D030107046D306B0201010420007CFBD596F6E74477B8C0E9F6F7A174275E101EF6BF7D18CAF01181D127B579A144034200045118C35E9E41E7E0654FEE801C52A9C5DFC510EF09597D5CCA8461E4AF9C666714834F2BC903F16FABFC45755B0183F1A09745CDFFCB4E2F799E50BED9A6B58C

}
