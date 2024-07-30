import Foundation
import CoreBluetooth


// https://github.com/LoopKit/CGMBLEKit
// https://github.com/Faifly/xDrip/blob/develop/xDrip/Services/Bluetooth/DexcomG6/
// https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/BluetoothTransmitter/CGM/Dexcom/G5/CGMG5Transmitter.swift
// https://github.com/NightscoutFoundation/xDrip/tree/master/app/src/main/java/com/eveningoutpost/dexdrip/G5Model/
// https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/services/G5CollectionService.java
// https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/services/Ob1G5CollectionService.java
// https://github.com/NightscoutFoundation/xDrip/tree/master/libkeks/src/main/java/jamorham/keks


@Observable class Dexcom: Transmitter {
    override class var type: DeviceType { DeviceType.transmitter(.dexcom) }
    override class var name: String { "Dexcom" }

    enum UUID: String, CustomStringConvertible, CaseIterable {

        case advertisement  = "FEBC"

        case data           = "F8083532-849E-531C-C594-30F1F86A4EA5"
        case communication  = "F8083533-849E-531C-C594-30F1F86A4EA5"
        case control        = "F8083534-849E-531C-C594-30F1F86A4EA5"
        case authentication = "F8083535-849E-531C-C594-30F1F86A4EA5"
        case backfill       = "F8083536-849E-531C-C594-30F1F86A4EA5"
        case unknown1       = "F8083537-849E-531C-C594-30F1F86A4EA5"  // older G6
        case jPake          = "F8083538-849E-531C-C594-30F1F86A4EA5"  // ONE/G7 J-PAKE exchange data

        var description: String {
            switch self {
            case .advertisement:  "advertisement"
            case .data:           "data service"
            case .communication:  "communication"
            case .control:        "control"
            case .authentication: "authentication"
            case .backfill:       "backfill"
            case .unknown1:       "unknown 1"
            case .jPake:          "J-PAKE"
            }
        }
    }


    override class var knownUUIDs: [String] { UUID.allCases.map(\.rawValue) }

    override class var dataServiceUUID: String { UUID.data.rawValue }
    override class var dataWriteCharacteristicUUID: String { UUID.control.rawValue }
    override class var dataReadCharacteristicUUID: String  { UUID.control.rawValue }


    override func parseManufacturerData(_ data: Data) {
        if data.count > 0 {
            // TODO
        }
        log("Bluetooth: advertised \(name)'s data: \(data.hex)")
    }


    // https://github.com/LoopKit/CGMBLEKit/blob/dev/CGMBLEKit/Opcode.swift
    // https://github.com/Faifly/xDrip/blob/develop/xDrip/Services/Bluetooth/DexcomG6/Logic/DexcomG6OpCode.swift

    enum Opcode: UInt8 {

        case unknown = 0x00

        // Auth
        case authRequestTx = 0x01
        case authRequest2Tx = 0x02
        case authRequestRx = 0x03
        case authChallengeTx = 0x04
        case authChallengeRx = 0x05
        case keepAlive = 0x06       // setAdvertisementParametersTx for control
        case bondRequest = 0x07     // pairRequestTx
        case pairRequestRx = 0x08

        // Control
        case disconnectTx = 0x09

        case exchangePakePayload = 0x0a  // Auth ONE/G7: 0A00, 0A01, 0A02 sent during initial pairing
        case changeAppLevelKeyTx = 0x0f
        case appLevelKeyAcceptedTx = 0x10

        case setAdvertisementParametersRx = 0x1c

        case firmwareVersionTx = 0x20
        case firmwareVersionRx = 0x21
        case batteryStatusTx = 0x22
        case batteryStatusRx = 0x23
        case transmitterTimeTx = 0x24
        case transmitterTimeRx = 0x25
        case sessionStartTx = 0x26
        case sessionStartRx = 0x27
        case sessionStopTx = 0x28
        case sessionStopRx = 0x29

        case sensorDataTx = 0x2E
        case sensorDataRx = 0x2F

        case glucoseTx = 0x30
        case glucoseRx = 0x31
        case calibrationDataTx = 0x32   // G6Bounds Tx/Rx
        case calibrationDataRx = 0x33
        case calibrateGlucoseTx = 0x34  // G7 Tx/Rx
        case calibrateGlucoseRx = 0x35

        case encryptionInfo = 0x38  // G7 Tx/Rx

        case glucoseHistoryTx = 0x3e

        case resetTx = 0x42
        case resetRx = 0x43

        case transmitterVersionTx = 0x4a  // G7 Tx/Rx
        case transmitterVersionRx = 0x4b

        case glucoseG6Tx = 0x4e  // TODO: rename to G7 .glucoseTx/Rx / .egv
        case glucoseG6Rx = 0x4f

        case glucoseBackfillTx = 0x50  // DataStream
        case glucoseBackfillRx = 0x51  // G7 Tx/Rx start/end of diagnostic data stream

        case transmitterVersionExtended = 0x52  // G7 Tx/Rx
        case transmitterVersionExtendedRx = 0x53

        case backfillFinished = 0x59  // G7 Tx/Rx

        case bleControl = 0xea       // TODO: G7 Tx/Rx EA00

        case keepAliveRx = 0xFF


        var data: Data { Data([rawValue]) }
    }


    var activationDate: Date = Date.distantPast

    var authenticated: Bool = false
    var bonded: Bool = false


    var opCode: Opcode = .unknown


    func write(_ data: Data, for uuid: UUID = .jPake) {
        let packets = (data.count - 1) / 20 + 1
        for i in 0 ... packets - 1 {
            let offset = i * 20
            let packet = data[offset ... min(offset + 19, data.count - 1)]
            debugLog("Bluetooth: writing packet \(packet.hexBytes) to \(peripheral!.name!)'s \(uuid.description) characteristic")
            write(packet, for: uuid.rawValue, .withResponse)
        }
    }


    override func read(_ data: Data, for uuid: String) {

        if uuid == UUID.authentication.rawValue || uuid == UUID.control.rawValue {
            opCode = Opcode(rawValue: data[0]) ?? .unknown
            let g7opCode = DexcomG7.Opcode(rawValue: data[0]) ?? .unknown
            var msg = "\(name): message opCode: "
            if String(describing: g7opCode) != String(describing: opCode) && g7opCode != .unknown {
                msg += String(describing: g7opCode)
            } else {
                msg += String(describing: opCode)
            }
            msg += " (0x\(data[0].hex))"
            log(msg)
        }

        switch UUID(rawValue: uuid) {

        case .authentication:

            switch opCode {

            case .authRequestRx:  // DexcomG7.Opcode.txIdChallenge

                // TODO: Dexcom ONE/G7 J-PAKE
                // https://github.com/Mbed-TLS/mbedtls/blob/development/tf-psa-crypto/drivers/builtin/include/mbedtls/ecjpake.h
                // https://github.com/NightscoutFoundation/xDrip/commit/7ee3473 ("Add keks library")
                // https://github.com/NightscoutFoundation/xDrip/blob/master/libkeks/src/main/java/jamorham/keks/Calc.java
                // https://github.com/NightscoutFoundation/xDrip/blob/master/libkeks/src/main/java/jamorham/keks/Plugin.java
                // https://github.com/particle-iot/iOSBLEExample/blob/main/iOSBLEExample/ParticleBLECode/ECJPake.swift

                let tokenHash = data.subdata(in: 1 ..< 9)
                let challenge = data.subdata(in: 9 ..< 17)
                log("\(name): tokenHash: \(tokenHash.hex), challenge: \(challenge.hex)")
                if settings.userLevel < .test { // not sniffing
                    let doubleChallenge = challenge + challenge
                    let cryptKey = "00\(serial)00\(serial)".data(using: .utf8)!
                    let encrypted = doubleChallenge.aes128Encrypt(keyData: cryptKey)!
                    let challengeResponse = Opcode.authChallengeTx.data + encrypted[0 ..< 8]
                    log("\(name): replying to challenge for transmitter serial \(serial): doubled challenge: \(doubleChallenge.hex), key: \(cryptKey.hex), encrypted: \(encrypted.hex), response: \(challengeResponse.hex)")
                    write(challengeResponse, for: UUID.authentication.rawValue, .withResponse)
                }


            case .authChallengeRx:  // DexcomG7.Opcode.statusReply
                authenticated = data[1] == 1
                bonded = data[2] == 1    // data[2] != 2  // TODO: if data[2] == 3 needsRefresh()
                log("\(name): authenticated: \(authenticated), bonded: \(bonded)")

                // TODO
                if authenticated {
                    if let communicationCharacteristic = characteristics[Dexcom.UUID.communication.rawValue] {
                        peripheral?.setNotifyValue(true, for: communicationCharacteristic)
                        peripheral?.readValue(for: communicationCharacteristic)
                    }
                    peripheral?.setNotifyValue(true, for: characteristics[Dexcom.UUID.control.rawValue]!)

                    if !(sensor?.type == .dexcomG7 || sensor?.type == .dexcomONEPlus) {
                        log("DEBUG: sending \(name) the 'transmitterTimeTx' command (opcode 0x\(Opcode.transmitterTimeTx.rawValue.hex))")
                        write(Opcode.transmitterTimeTx.data, .withResponse)
                    }

                    log("DEBUG: sending \(name) the 'transmitterVersion' command (opcode 0x\(Opcode.transmitterVersionTx.rawValue.hex))")
                    if sensor?.type == .dexcomG7 || sensor?.type == .dexcomONEPlus {
                        write(Opcode.transmitterVersionTx.data, .withResponse)
                    } else {
                        write(Opcode.transmitterVersionTx.data.appendingCRC, .withResponse)
                    }

                    log("DEBUG: sending \(name) the 'transmitterVersionExtended' command (opcode 0x\(Opcode.transmitterVersionExtended.rawValue.hex))")
                    if sensor?.type == .dexcomG7 || sensor?.type == .dexcomONEPlus {
                        write(Opcode.transmitterVersionExtended.data, .withResponse)
                    } else {
                        write(Opcode.transmitterVersionExtended.data.appendingCRC, .withResponse)
                    }
                    peripheral?.setNotifyValue(true, for: characteristics[Dexcom.UUID.backfill.rawValue]!)

                    log("DEBUG: sending \(name) the 'batteryStatusTx' command (opcode 0x\(Opcode.batteryStatusTx.rawValue.hex))")
                    if sensor?.type == .dexcomG7 || sensor?.type == .dexcomONEPlus {
                        write(Opcode.batteryStatusTx.data, .withResponse)
                    } else {
                        write(Opcode.batteryStatusTx.data.appendingCRC, .withResponse)
                    }
                }


            case .exchangePakePayload:
                // TODO
                let status = data[1]
                let phase = data[2]
                var packets = [Data]()
                for i in 0 ..< (buffer.count + 19) / 20 {
                    packets.append(Data(buffer[i * 20 ..< min((i + 1) * 20, buffer.count)]))
                }
                log("\(name): J-PAKE payload (TODO): status: \(status), phase: \(phase), current buffer length: \(buffer.count), current 20-byte packets received: \(packets.count)")


            default:
                break

            }


        case .control:

            switch opCode {

            case .transmitterTimeRx:
                let status = data[1]  // 0: ok, 0x81: lowBattery
                let age = TimeInterval(UInt32(data[2..<6]))
                activationDate = Date.now - age
                let sessionStartTime = TimeInterval(UInt32(data[6..<10]))
                let sensorActivationTime = activationDate.timeIntervalSince1970 + sessionStartTime
                let sensorActivationDate = Date.init(timeIntervalSince1970: sensorActivationTime)
                let sensorAge = Int(Date().timeIntervalSince(sensorActivationDate)) / 60
                sensor?.activationTime = UInt32(sensorActivationTime)
                sensor?.age = sensorAge
                sensor?.state = .active
                sensor?.lastReadingDate = Date()
                if sensor?.maxLife == 0 { sensor?.maxLife = 14400 }
                log("\(name): transmitter status: 0x\(status.hex), age: \(age.formattedInterval), activation date: \(activationDate.local), session start time: \(sessionStartTime.formattedInterval), sensor activation date: \(sensorActivationDate.local), sensor age: \(sensorAge.formattedInterval), valid CRC: \(data.dropLast(2).crc == UInt16(data.suffix(2)))")


            case .glucoseG6Rx:
                let status = data[1]  // 0: ok, 0x81: lowBattery
                let sequenceNumber = UInt32(data[2..<6])
                let timestamp = UInt32(data[6..<10])
                let date = activationDate + TimeInterval(timestamp)
                let glucoseBytes = UInt16(data[10..<12])
                let glucoseIsDisplayOnly = (glucoseBytes & 0xf000) > 0
                let value = Int(glucoseBytes & 0xfff)
                let state = data[12]  // AlgorithmState
                let trend = Int8(bitPattern: data[13])  // TODO: 127 -> not computable
                // TODO: verify predicted value mask
                let predictionData = UInt16(data[14...15])
                let predictedValue: UInt16? = predictionData != 0xffff ? predictionData & 0xfff : nil
                log("\(name): glucose response (EGV): status: 0x\(status.hex), sequence number: \(sequenceNumber), timestamp: \(timestamp.formattedInterval) (0x\(UInt32(timestamp).hex)), date: \(date.local), glucose value: \(value), is display only: \(glucoseIsDisplayOnly), state: \(AlgorithmState(rawValue: state)?.description ?? "unknown") (0x\(state.hex)), trend: \(trend), predicted value: \(predictedValue != nil ? String(predictedValue!) : "nil"),  valid CRC: \(data.dropLast(2).crc == UInt16(data.suffix(2)))")
                // TODO: merge last three hours; move to bluetoothDelegata main.didParseSensor(app.transmitter.sensor!)
                let item = Glucose(value, trendRate: Double(trend), id: Int(Double(timestamp) / 60 / 5), date: date)
                sensor?.trend.insert(item, at: 0)
                app.currentGlucose = item.value
                app.lastReadingDate = item.date
                sensor?.lastReadingDate = app.lastReadingDate
                main.history.factoryTrend.insert(item, at: 0)
                if main.history.factoryValues.count == 0 || main.history.factoryValues[0].id < item.id {
                    main.history.factoryValues = [item] + main.history.factoryValues
                }
                main.healthKit?.write([item]); main.healthKit?.read()


            case .calibrationDataRx:  // G6Bounds
                // TODO: i.e. 3300325000440114005802000000000000018ba4
                let weight = data[2]
                let calBoundError1 = UInt16(data[3...4])
                let calBoundError0 = UInt16(data[5...6])
                let calBoundMin = UInt16(data[7...8])
                let calBoundMax = UInt16(data[9...10])
                let lastBGValue = UInt16(data[11...12])
                let lastCalibrationTimeSeconds = UInt32(data[13...16])
                let autoCalibration: Bool = data[17] == 1
                let crc = UInt16(data[18...19])
                log("\(name): bounds response (TODO): weight: \(weight), calBoundError1: \(calBoundError1), calBoundError0: \(calBoundError0), calBoundMin: \(calBoundMin), calBoundMax: \(calBoundMax), lastBGValue: \(lastBGValue), lastCalibrationTimeSeconds: \(lastCalibrationTimeSeconds.formattedInterval), autoCalibration: \(autoCalibration), CRC: \(crc.hex), valid CRC: \(data.dropLast(2).crc == crc)")


            case .calibrateGlucoseTx:  // DexcomG7.Opcode.calibrate
                // TODO: i.e. 346E00871F0D00 (110) -> 34000100
                break


            case .glucoseBackfillRx:
                if !(sensor is DexcomG7) {
                    // TODO: i. e. 51 00 01 01 7e863600 5a8c3600 3a000000 4528 2247 (20 bytes)
                    // TODO: DataStreamType and DataStreamFilterType first bytes
                    let status = data[1]
                    let backfillStatus = data[2]
                    let identifier = data[3]
                    let startTime = TimeInterval(UInt32(data[4...7]))
                    let endTime = TimeInterval(UInt32(data[8...11]))
                    let bufferLength = UInt32(data[12...15])
                    let bufferCRC = UInt16(data[16...17])
                    let crc = UInt16(data[18...19])
                    log("\(name): backfill: status: \(status), backfill status: \(backfillStatus), identifier: \(identifier), start time: \(startTime.formattedInterval), end time: \(endTime.formattedInterval), buffer length: \(bufferLength), buffer CRC: \(bufferCRC.hex), valid buffer CRC: \(bufferCRC == buffer.crc), CRC: \(crc.hex), valid CRC: \(data.dropLast(2).crc == crc)")
                    var packets = [Data]()
                    for i in 0 ..< (buffer.count + 19) / 20 {
                        packets.append(Data(buffer[i * 20 ..< min((i + 1) * 20, buffer.count)]))
                    }
                    // Drop the first 2 bytes from each frame and the first 4 bytes from the combined message
                    let glucoseData = Data(packets.reduce(into: Data(), { $0.append($1.dropFirst(2)) }).dropFirst(4))
                    var history = [Glucose]()
                    for i in 0 ..< glucoseData.count / 8 {
                        let data = glucoseData.subdata(in: i * 8 ..< (i + 1) * 8)
                        // extract same fields as in .glucoseG6Rx
                        let timestamp = UInt32(data[0..<4])
                        let date = activationDate + TimeInterval(timestamp)
                        let glucoseBytes = UInt16(data[4..<6])
                        let glucoseIsDisplayOnly = (glucoseBytes & 0xf000) > 0
                        let glucose = Int(glucoseBytes & 0xfff)
                        let state = data[6]  // CalibrationState, AlgorithmState
                        let trend = Int8(bitPattern: data[7])
                        log("\(name): backfilled glucose: timestamp: \(timestamp.formattedInterval), date: \(date.local), glucose: \(glucose), is display only: \(glucoseIsDisplayOnly), state: \(AlgorithmState(rawValue: state)?.description ?? "unknown") (0x\(state.hex)), trend: \(trend)")
                        let item = Glucose(glucose, trendRate: Double(trend), id: Int(Double(timestamp) / 60 / 5), date: date)
                        // TODO: manage trend and state
                        history.append(item)
                    }
                    log("\(name): backfilled history (\(history.count) values): \(history)")
                    // TODO: merge last three hours; move to bluetoothDelegata main.didParseSensor(app.transmitter.sensor!)
                    main.history.factoryValues = history.reversed()
                    buffer = Data()
                    // TODO
                }


            case .batteryStatusRx:
                let status = data[1]
                let voltageA = Int(UInt16(data[2...3]))
                let voltageB = Int(UInt16(data[4...5]))
                let runtimeDays = Int(data[6])
                let temperature = Int(data[7])
                log("\(name): battery info response: status: 0x\(status.hex), static voltage A: \(voltageA), dynamic voltage B: \(voltageB), run time: \(runtimeDays) days, temperature: \(temperature), valid CRC: \(data.dropLast(2).crc == UInt16(data.suffix(2)))")


            case .transmitterVersionRx:  // Dexcom ONE
                // TODO: i.e. 4b 00 1ec06722 ba310000 8c00036e006d01 3cef (19 bytes)
                let status = data[1]
                let versionMajor = data[2]
                let versionMinor = data[3]
                let versionRevision = data[4]
                let versionBuild = data[5]
                let firmwareVersion = "\(versionMajor).\(versionMinor).\(versionRevision).\(versionBuild)"
                sensor?.firmware = firmwareVersion
                let swNumber = UInt32(data[6...9])
                // TODO:
                // let storageModeDays: UInt16
                // let apiVersion: UInt8
                // let maxRuntimeDays: UInt16
                // let maxStorageTimeDays: UInt16
                let crc = UInt16(data[17...18])
                log("\(name): version response: status: \(status), firmware: \(firmwareVersion), software number: \(swNumber), CRC: \(crc.hex), valid CRC: \(crc == data.dropLast(2).crc)")


            case  .transmitterVersionExtendedRx:  // Dexcom ONE
                // TODO: i.e. 53 00 0a 0f0000000000303235302d50726f 771a (19 bytes)
                let status = data[1]
                let sessionLength = data[2]
                // TODO:
                // featureFlag: UInt16
                // warmUpLength: UInt16
                let crc = UInt16(data[17...18])
                log("\(name): extended version response: status: \(status), session length: \(sessionLength) days, CRC: \(crc.hex), valid CRC: \(crc == data.dropLast(2).crc)")


            case .bleControl:
                // TODO: i.e. ea00030100000000000200000045ffffff
                let status = data[1]
                log("\(name): BLE control: status: \(status)")


            default:
                break
            }


            // https://github.com/LoopKit/CGMBLEKit/blob/dev/CGMBLEKit/Messages/GlucoseBackfillMessage.swift
            // https://github.com/Faifly/xDrip/blob/develop/xDrip/Services/Bluetooth/DexcomG6/Logic/Messages/Incoming/DexcomG6BackfillStream.swift

        case .backfill:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
            }
            let index = (sensor?.type != .dexcomG7 && sensor?.type != .dexcomONEPlus) ? Int(data[0]) : data.count == 9 ? buffer.count / 9 : Int(ceil(Double(buffer.count) / 20))
            log("\(name): backfill stream: received packet # \(index), partial buffer size: \(buffer.count)")


        case .jPake:
            if buffer.count == 0 {
                buffer = Data(data)
            } else {
                buffer += data
            }
            let index = Int(ceil(Double(buffer.count) / 20))
            log("\(name): J-PAKE exchange: received packet # \(index), partial buffer size: \(buffer.count)")
            if buffer.count == 160 {
                log("\(name): 160-byte J-PAKE payload: \(buffer.hex)")
                buffer = Data()
            }


        default:
            break
        }

        if let sensor = sensor as? DexcomG6 {
            sensor.read(data, for: uuid)
        }
        if let sensor = sensor as? DexcomONE {
            sensor.read(data, for: uuid)
        }
        if let sensor = sensor as? DexcomG7 {
            sensor.read(data, for: uuid)
        }
    }


    // enum CgmFoundation.TxProduct
    enum ProductType: Int {
        case g6, g7, frontier, d1Plus
    }


    // enum CgmFoundation.DisplayType
    enum DisplayType: Int {
        case unknown, medical, phone, watch, receiver, pump, reader, tool, other, transmitter, router
    }


    // TODO: https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/BluetoothTransmitter/CGM/Dexcom/Generic/DexcomAlgorithmState.swift

    enum AlgorithmState: UInt8, CustomStringConvertible {
        case none = 0x00
        case sessionStopped = 0x01
        case sensorWarmup = 0x02
        case excessNoise = 0x03
        case firstOfTwoBGsNeeded = 0x04
        case secondOfTwoBGsNeeded = 0x05
        case okay = 0x06
        case needsCalibration = 0x07
        case calibrationError1 = 0x08
        case calibrationError2 = 0x09
        case calibrationLinearityFitFailure = 0x0A
        case sensorFailedDuetoCountsAberration = 0x0B
        case sensorFailedDuetoResidualAberration = 0x0C
        case outOfCalibrationDueToOutlier = 0x0D
        case outlierCalibrationRequest = 0x0E
        case sessionExpired = 0x0F
        case sessionFailedDueToUnrecoverableError = 0x10
        case sessionFailedDueToTransmitterError = 0x11
        case temporarySensorIssue = 0x12
        case sensorFailedDueToProgressiveSensorDecline = 0x13
        case sensorFailedDueToHighCountsAberration = 0x14
        case sensorFailedDueToLowCountsAberration = 0x15
        case sensorFailedDueToRestart = 0x16

        // CalStateStartUp(129),
        // CalStateFirstOfTwoCalibrationsNeeded(130),
        // CalStateHighWedgeDisplayWithFirstBg(131),
        // CalStateLowWedgeDisplayWithFirstBg(132),
        // CalStateSecondOfTwoCalibrationsNeeded(133),
        // CalStateInCalTransmitter(134),
        // CalStateInCalDisplay(135),
        // CalStateHighWedgeTransmitter(136),
        // CalStateLowWedgeTransmitter(137),
        // CalStateLinearityFitTransmitter(138),
        // CalStateOutOfCalDueToOutlierTransmitter(139),
        // CalStateHighWedgeDisplay(140),
        // CalStateLowWedgeDisplay(141),
        // CalStateLinearityFitDisplay(142),
        // CalStateSessionNotInProgress(143);

        public var description: String {
            switch self {
            case .none: "none"
            case .sessionStopped: "session stopped"
            case .sensorWarmup: "sensor warmup"
            case .excessNoise: "excess noise"
            case .firstOfTwoBGsNeeded: "first of two BGs needed"
            case .secondOfTwoBGsNeeded: "second of two BGs needed"
            case .okay: "OK"
            case .needsCalibration: "needs calibration"
            case .calibrationError1: "calibration error 1"
            case .calibrationError2: "calibration error 2"
            case .calibrationLinearityFitFailure: "calibration linearity fit failure"
            case .sensorFailedDuetoCountsAberration: "sensor failed due to counts aberration"
            case .sensorFailedDuetoResidualAberration: "sensor failed due to residual aberration"
            case .outOfCalibrationDueToOutlier: "out of calibration due to outlier"
            case .outlierCalibrationRequest: "outlier calibration request"
            case .sessionExpired: "session expired"
            case .sessionFailedDueToUnrecoverableError: "session failed due to unrecoverable error"
            case .sessionFailedDueToTransmitterError: "session failed due to transmitter error"
            case .temporarySensorIssue: "temporary sensor issue"
            case .sensorFailedDueToProgressiveSensorDecline: "sensor failed due to progressive sensor decline"
            case .sensorFailedDueToHighCountsAberration: "sensor failed due to high counts aberration"
            case .sensorFailedDueToLowCountsAberration: "sensor failed due to low counts aberration"
            case .sensorFailedDueToRestart: "sensor failed due to restart"
            }
        }
    }


    enum PakePhase: UInt8 {
        case zero  = 0
        case one
        case two
    }


    enum TrendArrow: Int,/* CustomStringConvertible, */ CaseIterable, Codable {
        case none           = 0
        case doubleUp       = 1
        case singleUp       = 2
        case fortyFiveUp    = 3
        case flat           = 4
        case fortyFiveDown  = 5
        case singleDown     = 6
        case doubleDown     = 7
        case notComputable  = 8
        case rateOutOfRange = 9
    }

    // TODO:
    // enum CgmFoundation.TrendArrow {
    //     case doubleUp
    //     case singleUp
    //     case fortyFiveUp
    //     case flat
    //     case fortyFiveDown
    //     case singleDown
    //     case doubleDown
    //     case none
    // }


    enum DataStreamType: Int,/* CustomStringConvertible, */ CaseIterable, Codable {
        // TODO
        case manifestData   = 0
        case privateData    = 1
        case encryptionInfo = 2
        case backFill       = 3
    }

    // TODO:
    enum DataStreamFilterType: UInt8 { case reserved, manifest, inRangeInclusive }


}


@Observable class DexcomG6: Sensor {

    /// called by Dexcom Transmitter class
    func read(_ data: Data, for uuid: String) {

        switch Dexcom.UUID(rawValue: uuid) {

        case .communication:
            log("\(transmitter!.peripheral!.name!): received \(data.count) \(Dexcom.UUID(rawValue: uuid)!) bytes: \(data.hex)")
            // TODO

        default:
            break

        }

    }

}


@Observable class DexcomONE: Sensor {

    /// called by Dexcom Transmitter class
    func read(_ data: Data, for uuid: String) {

        switch Dexcom.UUID(rawValue: uuid) {

        case .communication:
            log("\(transmitter!.peripheral!.name!): received \(data.count) \(Dexcom.UUID(rawValue: uuid)!) bytes: \(data.hex)")
            // TODO

        default:
            break

        }

    }

}


// crcCCITTXModem: https://github.com/LoopKit/CGMBLEKit/blob/dev/CGMBLEKit/NSData+CRC.swift

extension Data {
    var crc: UInt16 {
        var crc: UInt16 = 0
        for byte in self {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = crc << 1 ^ 0x1021
                } else {
                    crc = crc << 1
                }
            }
        }
        return crc
    }
    var appendingCRC: Data { self + self.crc.data }
}


// https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/BluetoothTransmitter/CGM/Dexcom/Generic/DexcomCalibrationParameters.swift

// class com.dexcom.coresdk.transmitter.command.SensorCode
//
// ONE   RANGE         G6
//
// 5171: [2300, 2900], 9713
// 5177: [2400, 2900], 9577
// 5317: [2400, 3000], 9551
// 5375: [2500, 3100], 9371
// 5391: [2600, 3100], 9311
// 5397: [2600, 3200], 9159
// 5795: [2500, 3000], 9515
// 7135: [2700, 3200], 9117
// 7197: [2800, 3300], 5937
// 7539: [2700, 3300], 7171
// 9137: [2900, 3400], 5931
// 9179: [3000, 3400], 5955
// 9357: [3000, 3500], 5917
// 9517: [3100, 3500], 5951
// 9759: [3100, 3600], 5915


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

}
