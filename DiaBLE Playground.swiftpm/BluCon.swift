import Foundation


// https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/UtilityModels/Blukon.java
// https://github.com/JohanDegraeve/xdripswift/tree/master/xdrip/BluetoothTransmitter/CGM/Libre/Blucon


@Observable class BluCon: Transmitter {
    override class var type: DeviceType { DeviceType.transmitter(.blu) }
    override class var name: String { "BluCon" }

    /// 6-digit pairing pass code, i.e. 415420
    var passCode: Data = Data()

    enum UUID: String, CustomStringConvertible, CaseIterable {
        case data      = "436A62C0-082E-4CE8-A08B-01D81F195B24"
        case dataWrite = "436AA6E9-082E-4CE8-A08B-01D81F195B24"
        case dataRead  = "436A0C82-082E-4CE8-A08B-01D81F195B24"

        var description: String {
            switch self {
            case .data:      "data"
            case .dataWrite: "data write"
            case .dataRead:  "data read"
            }
        }
    }

    override class var knownUUIDs: [String] { UUID.allCases.map(\.rawValue) }

    override class var dataServiceUUID: String             { UUID.data.rawValue }
    override class var dataWriteCharacteristicUUID: String { UUID.dataWrite.rawValue }
    override class var dataReadCharacteristicUUID: String  { UUID.dataRead.rawValue }


    enum ResponseType: String, CustomStringConvertible {
        case ack            = "8b0a00"
        case patchUidInfo   = "8b0e"
        case noSensor       = "8b1a02000f"
        case readingError   = "8b1a020011"
        case timeout        = "8b1a020014"
        case sensorInfo     = "8bd9"
        case battery        = "8bda"
        case firmware       = "8bdb"
        case singleBlock    = "8bde"
        case multipleBlocks = "8bdf"
        case wakeup         = "cb010000"
        case batteryLow1    = "cb020000"
        case batteryLow2    = "cbdb0000"

        var description: String {
            switch self {
            case .ack:            "ack"
            case .patchUidInfo:   "patch uid/info"
            case .noSensor:       "no sensor"
            case .readingError:   "reading error"
            case .timeout:        "timeout"
            case .sensorInfo:     "sensor info"
            case .battery:        "battery"
            case .firmware:       "firmware"
            case .singleBlock:    "single block"
            case .multipleBlocks: "multiple blocks"
            case .wakeup:         "wake up"
            case .batteryLow1:    "battery low 1"
            case .batteryLow2:    "battery low 2"
            }
        }
    }


    // read single block:    01 0d 0e 01 <block number>
    // read multiple blocks: 01 0d 0f 02 <start block> <end block>

    enum RequestType: String, CustomStringConvertible {
        case none         = ""
        case ack          = "81 0a 00"
        case sleep        = "01 0c 0e 00"
        case wakeupReply  = "01 0c 0f 00"
        case sensorInfo   = "01 0d 09 00"
        case fram         = "01 0d 0f 02 00 2b"
        case battery      = "01 0d 0a 00"
        case firmware     = "01 0d 0b 00"
        case patchUid     = "01 0e 00 03 26 01 00"
        case patchInfo    = "01 0e 00 03 02 a1 07"

        var description: String {
            switch self {
            case .none:        "none"
            case .ack:         "ack"
            case .sleep:       "sleep"
            case .wakeupReply: "wake up response"
            case .sensorInfo:  "sensor info"
            case .fram:        "fram"
            case .battery:     "battery"
            case .firmware:    "firmware"
            case .patchUid:    "patch uid"
            case .patchInfo:   "patch info"
            }
        }
    }

    var currentRequest: RequestType = .none

    func write(request: RequestType) {
        write(request.rawValue.bytes, .withResponse)
        currentRequest = request
        log("\(name): did write request for \(request)")
    }


    override func readCommand(interval: Int = 5) -> Data {
        return Data([0x00]) // TODO
    }


    override func read(_ data: Data, for uuid: String) {

        let dataHex = data.hex

        let response = ResponseType(rawValue: dataHex)
        log("\(name) response: \(response?.description ?? "data") (0x\(dataHex))")

        guard data.count > 0 else { return }

        if response == .timeout {
            main.status("\(name): timeout")
            write(request: .sleep)

        } else if response == .noSensor {
            main.status("\(name): no sensor")
            // write(request: .sleep) // FIXME: causes an immediate .wakeup

        } else if response == .wakeup {
            write(request: .sensorInfo)

        } else {
            // TODO: instantiate specifically a Libre2() (when detecting A4 in the uid, i. e.)
            if sensor == nil {
                sensor = Sensor(transmitter: self)
                app.sensor = sensor
            }
            if dataHex.hasPrefix(ResponseType.sensorInfo.rawValue) {
                sensorUid = Data(data[3...10])
                sensor!.uid = sensorUid
                settings.patchUid = sensorUid
                // FIXME: doesn't work with Libre 2
                if let sensorState = SensorState(rawValue: data[17]) {
                    sensor!.state = sensorState
                }
                log("\(name): patch uid: \(sensor!.uid.hex), serial number: \(sensor!.serial), sensor state: \(sensor!.state)")
                if sensor!.state == .active {
                    write(request: .ack)
                } else {
                    write(request: .sleep)
                }

            } else if response == .ack {
                if currentRequest == .ack {
                    write(request: .firmware)
                } else { // after a .sleep request
                    currentRequest = .none
                }

            } else if dataHex.hasPrefix(ResponseType.firmware.rawValue) {
                let firmware = dataHex.bytes.dropFirst(2).map { String($0) }.joined(separator: ".")
                self.firmware = firmware
                log("\(name): firmware: \(firmware)")
                write(request: .battery)

            } else if dataHex.hasPrefix(ResponseType.battery.rawValue) {
                if data[2] == 0xaa {
                    // battery = 100 // TODO
                } else if data[2] == 0x02 {
                    battery = 5
                }
                write(request: .patchInfo)
                // write(request: .patchUid) // will give same .patchUidInfo response type

            } else if dataHex.hasPrefix(ResponseType.patchUidInfo.rawValue) {
                if currentRequest == .patchInfo {
                    let patchInfo = Data(data[3...])
                    sensor!.patchInfo = patchInfo
                    settings.patchInfo = sensor!.patchInfo
                    log("\(name): patch info: \(sensor!.patchInfo.hex) (sensor type: \(sensor!.type.rawValue))")
                } else if currentRequest == .patchUid {
                    sensorUid = Data(data[4...])
                    sensor!.uid = sensorUid
                    settings.patchUid = sensorUid
                    settings.activeSensorSerial = sensor!.serial
                    log("\(name): patch uid: \(sensor!.uid.hex), serial number: \(sensor!.serial)")
                }
                write(request: .fram)

            } else if dataHex.hasPrefix(ResponseType.multipleBlocks.rawValue) {
                if buffer.count == 0 {
                    app.lastReadingDate = app.lastConnectionDate
                    sensor!.lastReadingDate = app.lastConnectionDate
                }
                buffer.append(data.suffix(from: 4))
                log("\(name): partial buffer size: \(buffer.count)")
                if buffer.count == 344 {
                    write(request: .sleep)
                    sensor!.fram = Data(buffer)
                    main.status("\(sensor!.type)  +  \(name)")
                }
            }
        }
    }
}
