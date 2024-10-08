import Foundation
import CoreBluetooth

@Observable class MiaoMiao: Transmitter {
    override class var type: DeviceType { DeviceType.transmitter(.miaomiao) }
    override class var name: String { "MiaoMiao" }

    enum UUID: String, CustomStringConvertible, CaseIterable {
        case data      = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
        case dataWrite = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
        case dataRead  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

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

    enum ResponseType: UInt8, CustomStringConvertible {
        case dataPacket = 0x28
        case newSensor  = 0x32
        case noSensor   = 0x34
        case frequencyChange = 0xD1

        var description: String {
            switch self {
            case .dataPacket:      "data packet"
            case .newSensor:       "new sensor"
            case .noSensor:        "no sensor"
            case .frequencyChange: "frequency change"
            }
        }
    }

    override init(peripheral: CBPeripheral?, main: MainDelegate) {
        super.init(peripheral: peripheral!, main: main)
        if let peripheral = peripheral, peripheral.name!.contains("miaomiao2") {
            name += " 2"
        }
    }

    override func readCommand(interval: Int = 5) -> Data {
        var command = [UInt8(0xF0)]
        if [1, 3].contains(interval) {
            command.insert(contentsOf: [0xD1, UInt8(interval)], at: 0)
        }
        return Data(command)
    }

    override func parseManufacturerData(_ data: Data) {
        if data.count >= 8 {
            macAddress = data.suffix(6)
            log("\(Self.name): MAC address: \(macAddress.hexAddress)")
        }
    }

    override func read(_ data: Data, for uuid: String) {

        // https://github.com/NightscoutFoundation/xDrip/blob/master/app/src/main/java/com/eveningoutpost/dexdrip/Models/Tomato.java
        // https://github.com/UPetersen/LibreMonitor/blob/Swift4/LibreMonitor/Bluetooth/MiaoMiaoManager.swift
        // https://github.com/gshaviv/ninety-two/blob/master/WoofWoof/MiaoMiao.swift

        let response = ResponseType(rawValue: data[0])
        if buffer.count == 0 {
            log("\(name) response: \(response?.description ?? "unknown") (0x\(data[0...0].hex))")
        }
        if data.count == 1 {
            if response == .noSensor {
                main.status("\(name): no sensor")
            }
            // TODO: prompt the user and allow writing the command 0xD301 to change sensor
            if response == .newSensor {
                main.status("\(name): detected a new sensor")
            }
        } else if data.count == 2 {
            if response == .frequencyChange {
                if data[1] == 0x01 {
                    log("\(name): success changing frequency")
                } else {
                    log("\(name): failed to change frequency")
                }
            }
        } else {
            // TODO: instantiate specifically a Libre2() (when detecting A4 in the uid, i. e.)
            if sensor == nil {
                sensor = Libre(transmitter: self)
                app.sensor = sensor
            }
            if buffer.count == 0 {
                app.lastReadingDate = app.lastConnectionDate
                sensor!.lastReadingDate = app.lastConnectionDate
            }
            buffer.append(data)
            log("\(name): partial buffer size: \(buffer.count)")

            var framBlocks = 43

            if buffer.count >= 363 {  // 18 + framBlocks * 8 + 1
                log("\(name): data size: \(Int(buffer[1]) << 8 + Int(buffer[2]))")

                battery = Int(buffer[13])
                firmware = buffer[14...15].hex
                hardware = buffer[16...17].hex
                log("\(name): battery: \(battery), firmware: \(firmware), hardware: \(hardware)")

                sensor!.age = Int(buffer[3]) << 8 + Int(buffer[4])
                sensorUid = Data(buffer[5...12])
                sensor!.uid = sensorUid
                settings.currentSensorUid = sensorUid
                log("\(name): sensor age: \(sensor!.age) minutes (\(String(format: "%.1f", Double(sensor!.age)/60/24)) days), patch uid: \(sensor!.uid.hex)")


                if buffer.count >= 369 {  // 18 + 43 * 8 + 1 + 6
                    // TODO: verify that buffer[362] is the end marker 0x29
                    (sensor! as! Libre).patchInfo = Data(buffer[363...368])
                    settings.currentPatchInfo = (sensor! as! Libre).patchInfo
                    settings.activeSensorSerial = sensor!.serial
                    log("\(name): patch info: \((sensor! as! Libre).patchInfo.hex), sensor type: \(sensor!.type.rawValue), serial number: \(sensor!.serial)")

                    if sensor != nil && sensor!.type == .libreProH {
                        let libreProSensor = LibrePro(transmitter: self)
                        // FIXME: buffer[3...4] doesn't match the real sensor age in body[2...3]
                        libreProSensor.age = sensor!.age
                        libreProSensor.uid = sensor!.uid
                        libreProSensor.patchInfo = (sensor! as! LibrePro).patchInfo
                        libreProSensor.lastReadingDate = sensor!.lastReadingDate
                        sensor = libreProSensor
                        app.sensor = sensor

                        // TODO: manage the 21 partial historic blocks (28 measurements)
                        framBlocks = 43 // 22

                    }
                } else {
                    // https://github.com/dabear/LibreOOPAlgorithm/blob/master/app/src/main/java/com/hg4/oopalgorithm/oopalgorithm/AlgorithmRunner.java
                    (sensor! as! Libre).patchInfo = Data([0xDF, 0x00, 0x00, 0x01, 0x01, 0x02])
                }
                (sensor! as! Libre).fram = Data(buffer[18 ..< 18 + framBlocks * 8])

                main.status("\(sensor!.type)  +  \(name)")
            }
        }
    }
}
