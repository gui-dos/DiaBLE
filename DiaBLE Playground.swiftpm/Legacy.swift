import Foundation
import SwiftUI


// https://github.com/birdfly/DiaBLE/commit/d604bf7
// "Strip off the management of the Watlaa, preferred watches and bridge transmitters"


class Droplet: Transmitter {
    // override class var type: DeviceType { DeviceType.transmitter(.droplet) }
    override class var name: String { "Droplet" }
    override class var dataServiceUUID: String { "C97433F0-BE8F-4DC8-B6F0-5343E6100EB4" }
    override class var dataReadCharacteristicUUID: String { "C97433F1-BE8F-4DC8-B6F0-5343E6100EB4" }
    override class var dataWriteCharacteristicUUID: String { "C97433F2-BE8F-4DC8-B6F0-5343E6100EB4" }

    enum LibreType: String, CustomStringConvertible {
        case L1   = "10"
        case L2   = "20"
        case US14 = "30"
        case Lpro = "40"

        var description: String {
            switch self {
            case .L1:   "Libre 1"
            case .L2:   "Libre 2"
            case .US14: "Libre US 14d"
            case .Lpro: "Libre Pro"
            }
        }
    }

    override func read(_ data: Data, for uuid: String) {
        if sensor == nil {
            sensor = Sensor(transmitter: self)
            app.sensor = sensor
        }
        if data.count == 8 {
            sensor!.uid = Data(data)
            log("\(name): sensor serial number: \(sensor!.serial))")
        } else {
            log("\(name) response: 0x\(data[0...0].hex)")
            log("\(name) response data length: \(Int(data[1]))")
        }
        // TODO:  9999 = error
    }
}


class Limitter: Droplet {
    // override class var type: DeviceType { DeviceType.transmitter(.limitter) }
    override class var name: String { "Limitter" }

    override func readCommand(interval: Int = 5) -> Data {
        return Data([UInt8(32 + interval)]) // 0x2X
    }

    override func read(_ data: Data, for uuid: String) {

        // https://github.com/SpikeApp/Spike/blob/master/src/services/bluetooth/CGMBluetoothService.as

        if sensor == nil {
            sensor = Sensor(transmitter: self)
            app.sensor = sensor
        }

        let fields = data.string.split(separator: " ")
        guard fields.count == 4 else { return }

        battery = Int(fields[2])!
        log("\(name): battery: \(battery)")

        let firstField = fields[0]
        guard !firstField.hasPrefix("000") else {
            log("\(name): no sensor data")
            main.status("\(name): no data from sensor")
            if firstField.hasSuffix("999") {
                let err = fields[1]
                log("\(name): error \(err)\n(0001 = low battery, 0002 = badly positioned)")
            }
            return
        }

        let rawValue = Int(firstField.dropLast(2))!
        log("\(name): glucose raw value: \(rawValue)")
        main.status("\(name) raw glucose: \(rawValue)")
        app.currentGlucose = rawValue / 10

        let sensorType = LibreType(rawValue: String(firstField.suffix(2)))!.description
        log("\(name): sensor type = \(sensorType)")

        sensor!.age = Int(fields[3])! * 10
        if Double(sensor!.age)/60/24 < 14.5 {
            sensor!.state = .active
        } else {
            sensor!.state = .expired
        }
        log("\(name): sensor age: \(Int(sensor!.age)) minutes (\(String(format: "%.1f", Double(sensor!.age)/60/24)) days)")
        main.status("\(sensorType)  +  \(name)")
    }
}

// Legacy code from bluetoothDelegate didDiscoverCharacteristicsFor

// if app.transmitter.type == .transmitter(.droplet) && serviceUUID == Droplet.dataServiceUUID {

// https://github.com/MarekM60/eDroplet/blob/master/eDroplet/eDroplet/ViewModels/CgmPageViewModel.cs
// Droplet - New Protocol.pdf: https://www.facebook.com/download/preview/961042740919138

// app.transmitter.write([0x31, 0x32, 0x33]); log("Droplet: writing old ping command")
// app.transmitter.write([0x34, 0x35, 0x36]); log("Droplet: writing old read command")
// app.transmitter.write([0x50, 0x00, 0x00]); log("Droplet: writing ping command P00")
// app.transmitter.write([0x54, 0x00, 0x01]); log("Droplet: writing timer command T01")
// T05 = 5 minutes, T00 = quiet mode
// app.transmitter.write([0x53, 0x00, 0x00]); log("Droplet: writing sensor identification command S00")
// app.transmitter.write([0x43, 0x00, 0x01]); log("Droplet: writing FRAM reading command C01")
// app.transmitter.write([0x43, 0x00, 0x02]); log("Droplet: writing FRAM reading command C02")
// app.transmitter.write([0x42, 0x00, 0x01]); log("Droplet: writing RAM reading command B01")
// app.transmitter.write([0x42, 0x00, 0x02]); log("Droplet: writing RAM reading command B02")
// "A0xyz...z” sensor activation where: x=1 for Libre 1, 2 for Libre 2 and US 14-day, 3 for Libre Pro/H; y = length of activation bytes, z...z = activation bytes
// }

// if app.transmitter.type == .transmitter(.limitter) && serviceUUID == Limitter.dataServiceUUID {
//    let readCommand = app.transmitter.readCommand(interval: settings.readingInterval)
//    app.transmitter.write(readCommand)
//    log("Droplet (LimiTTer): writing start reading command 0x\(Data(readCommand).hex)")
//    app.transmitter.peripheral?.readValue(for: app.transmitter.readCharacteristic!)
//    log("Droplet (LimiTTer): reading data")
// }


@Observable class Watlaa: Watch {
    // override class var type: DeviceType { DeviceType.watch(.watlaa) }
    override class var name: String { "Watlaa" }

    enum UUID: String, CustomStringConvertible, CaseIterable {
        case data           = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
        case dataWrite      = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
        case dataRead       = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
        case legacyData     = "00001010-1212-EFDE-0137-875F45AC0113"
        case legacyDataRead = "00001011-1212-EFDE-0137-875F45AC0113"
        case bridgeStatus   = "00001012-1212-EFDE-0137-875F45AC0113"
        case lastGlucose    = "00001013-1212-EFDE-0137-875F45AC0113"
        case calibration    = "00001014-1212-EFDE-0137-875F45AC0113"
        case glucoseUnit    = "00001015-1212-EFDE-0137-875F45AC0113"
        case alerts         = "00001016-1212-EFDE-0137-875F45AC0113"
        case unknown1       = "00001017-1212-EFDE-0137-875F45AC0113"
        case unknown2       = "00001018-1212-EFDE-0137-875F45AC0113"

        var description: String {
            switch self {
            case .data:           "data"
            case .dataWrite:      "data write"
            case .dataRead:       "data read"
            case .legacyData:     "data (legacy)"
            case .legacyDataRead: "raw glucose data (legacy)"
            case .bridgeStatus:   "bridge connection status"
            case .lastGlucose:    "last glucose raw value"
            case .calibration:    "calibration"
            case .glucoseUnit:    "glucose unit"
            case .alerts:         "alerts settings"
            case .unknown1:       "unknown 1"
            case .unknown2:       "unknown 2 (sensor serial)"
            }
        }
    }

    override class var knownUUIDs: [String] { UUID.allCases.map(\.rawValue) }

    override class var dataServiceUUID: String             { UUID.data.rawValue }
    override class var dataWriteCharacteristicUUID: String { UUID.dataWrite.rawValue }
    override class var dataReadCharacteristicUUID: String  { UUID.dataRead.rawValue }
    class var legacyDataServiceUUID: String                { UUID.legacyData.rawValue }
    class var legacyDataReadCharacteristicUUID: String     { UUID.legacyDataRead.rawValue }

    // Same as MiaoMiao
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

    enum BridgeStatus: UInt8, CustomStringConvertible {
        case notConnetced = 0x00
        case connectedInactiveSensor
        case connectedActiveSensor
        case unknown

        var description: String {
            switch self {
            case .notConnetced:            "Not connected"
            case .connectedInactiveSensor: "Connected: inactive sensor"
            case .connectedActiveSensor:   "Connected: active sensor"
            case .unknown:                 "Unknown"
            }
        }
    }

    var bridgeStatus: BridgeStatus = .unknown

    var slope: Float = 0.0 {
        didSet(slope) {
            if slope != self.slope && slope != 0.0 {
                writeAlertsSettings()
            }
        }
    }

    var intercept: Float = 0.0 {
        didSet(intercept) {
            if intercept != self.intercept && intercept != 0.0 {
                writeAlertsSettings()
            }
        }
    }

    var lastGlucose: Int = 0
    var lastGlucoseAge: Int = 0

    var unit: GlucoseUnit = .mgdl {
        didSet(unit) {
            if unit != self.unit {
                write([UInt8(GlucoseUnit.allCases.firstIndex(of: self.unit)!)], for: .glucoseUnit)
            }
        }
    }

    var alarmHigh: Float = 0.0 {
        didSet(alarmHigh) {
            if alarmHigh != self.alarmHigh && alarmHigh != 0.0 {
                writeAlertsSettings()
            }
        }
    }

    var alarmLow: Float = 0.0 {
        didSet(alarmLow) {
            if alarmLow != self.alarmLow && alarmLow != 0.0 {
                writeAlertsSettings()
            }
        }
    }
    var connectionCheckInterval: Int = 0 {
        didSet(connectionCheckInterval) {
            if connectionCheckInterval != self.connectionCheckInterval && connectionCheckInterval != 0 {
                writeAlertsSettings()
            }
        }
    }
    var snoozeLow: Int = 0 {
        didSet(snoozeLow) {
            if snoozeLow != self.snoozeLow && snoozeLow != 0 {
                writeAlertsSettings()
            }
        }
    }
    var snoozeHigh: Int = 0 {
        didSet(snoozeHigh) {
            if snoozeHigh != self.snoozeHigh && snoozeHigh != 0 {
                writeAlertsSettings()
            }
        }
    }
    var sensorLostVibration: Bool = true {
        didSet(sensorLostVibration) {
            if sensorLostVibration != self.sensorLostVibration {
                writeAlertsSettings()
            }
        }
    }
    var glucoseVibration: Bool = true {
        didSet(glucoseVibration) {
            if glucoseVibration != self.glucoseVibration {
                writeAlertsSettings()
            }
        }
    }

    var lastReadingDate: Date = Date()


    func writeAlertsSettings() {
        write([UInt8](withUnsafeBytes(of: &alarmHigh) { Data($0) }) +
              [UInt8](withUnsafeBytes(of: &alarmLow) { Data($0) }) +
              [UInt8(connectionCheckInterval & 0xFF)] +
              [UInt8((connectionCheckInterval >> 8) & 0xFF)] +
              [UInt8(snoozeLow) & 0xFF] +
              [UInt8((snoozeLow >> 8) & 0xFF)] +
              [UInt8(snoozeHigh & 0xFF)] +
              [UInt8((snoozeHigh >> 8) & 0xFF)] +
              [(UInt8(0) | (sensorLostVibration == true ? 8 : 0) | (glucoseVibration == true ? 2 : 0))],
              for: .alerts)
    }


    // TODO: implements in Device class
    func readValue(for uuid: UUID) {
        peripheral?.readValue(for: characteristics[uuid.rawValue]!)
        main.debugLog("\(name): requested value for \(uuid)")
    }

    func write(_ bytes: [UInt8], for uuid: UUID) {
        peripheral?.writeValue(Data(bytes), for: characteristics[uuid.rawValue]!, type: .withResponse)
        main.debugLog("\(name): written value 0x\(Data(bytes).hex) for \(uuid)")
    }


    // Same as MiaoMiao
    override func readCommand(interval: Int = 5) -> Data {
        var command = [UInt8(0xF0)]
        if [1, 3].contains(interval) {
            command.insert(contentsOf: [0xD1, UInt8(interval)], at: 0)
        }
        return Data(command)
    }


    override func read(_ data: Data, for uuid: String) {

        let description = UUID(rawValue: uuid)?.description ?? uuid
        log("\(name): received value for \(description) characteristic")

        switch UUID(rawValue: uuid) {


            // Same as MiaoMiao
        case .dataRead:
            let bridge = transmitter!
            let bridgeName = "\(transmitter!.name) + \(name)"

            let response = ResponseType(rawValue: data[0])
            if bridge.buffer.count == 0 {
                log("\(bridgeName) response: \(response?.description ?? "unknown") (0x\(data[0...0].hex))")
            }
            if data.count == 1 {
                if response == .noSensor {
                    main.status("\(bridgeName): no sensor")
                }
                // TODO: prompt the user and allow writing the command 0xD301 to change sensor
                if response == .newSensor {
                    main.status("\(bridgeName): detected a new sensor")
                }
            } else if data.count == 2 {
                if response == .frequencyChange {
                    if data[1] == 0x01 {
                        log("\(bridgeName): success changing frequency")
                    } else {
                        log("\(bridgeName): failed to change frequency")
                    }
                }
            } else {
                if bridge.sensor == nil {
                    bridge.sensor = Sensor(transmitter: bridge)
                    app.sensor = bridge.sensor
                }
                if bridge.buffer.count == 0 { bridge.sensor!.lastReadingDate = app.lastReadingDate }
                bridge.buffer.append(data)
                log("\(bridgeName): partial buffer size: \(bridge.buffer.count)")
                if bridge.buffer.count >= 363 {
                    log("\(bridgeName): data size: \(Int(bridge.buffer[1]) << 8 + Int(bridge.buffer[2]))")

                    bridge.battery  = Int(bridge.buffer[13])
                    bridge.firmware = bridge.buffer[14...15].hex
                    bridge.hardware = bridge.buffer[16...17].hex
                    log("\(bridgeName): battery: \(battery), firmware: \(firmware), hardware: \(hardware)")

                    bridge.sensor!.age = Int(bridge.buffer[3]) << 8 + Int(bridge.buffer[4])
                    let uid = Data(bridge.buffer[5...12])
                    if uid[5] != 0 {
                        bridge.sensor!.uid = uid
                    } else {
                        bridge.sensor!.uid = Data()
                    }
                    log("\(bridgeName): sensor age: \(bridge.sensor!.age) minutes (\(String(format: "%.1f", Double(bridge.sensor!.age)/60/24)) days), patch uid: \(uid.hex), serial number: \(bridge.sensor!.serial)")

                    if bridge.buffer.count > 369 {
                        bridge.sensor!.patchInfo = Data(bridge.buffer[363...368])
                        log("\(bridgeName): patch info: \(bridge.sensor!.patchInfo.hex)")
                    } else {
                        bridge.sensor!.patchInfo = Data([0xDF, 0x00, 0x00, 0x01, 0x01, 0x02])
                    }
                    bridge.sensor!.fram = Data(bridge.buffer[18 ..< 362])
                    readSetup()
                    main.status("\(bridge.sensor!.type)  +  \(bridgeName)")
                }
            }


        case .legacyDataRead:

            let bridge = transmitter!
            let bridgeName = "\(transmitter!.name) + \(name)"

            if bridge.sensor == nil {
                if app.sensor != nil {
                    bridge.sensor = app.sensor
                } else {
                    bridge.sensor = Sensor(transmitter: bridge)
                    app.sensor = bridge.sensor
                }
            }
            if bridge.buffer.count == 0 { bridge.sensor!.lastReadingDate = app.lastReadingDate }
            lastReadingDate = app.lastReadingDate
            bridge.buffer.append(data)
            log("\(bridgeName): partial buffer size: \(bridge.buffer.count)")

            if bridge.buffer.count == 344 {
                let fram = bridge.buffer[..<344]
                bridge.sensor!.fram = Data(fram)
                readSetup()
                main.status("\(bridge.sensor!.type)  +  \(bridgeName)")
            }


        case .lastGlucose:
            let value = Int(data[1]) << 8 + Int(data[0])
            let age   = Int(data[3]) << 8 + Int(data[2])
            lastGlucose = value
            lastGlucoseAge = age
            log("\(name): last raw glucose: \(value), age: \(age) minutes")

        case .calibration:
            let slope:     Float = Data(data[0...3]).withUnsafeBytes { $0.load(as: Float.self) }
            let intercept: Float = Data(data[4...7]).withUnsafeBytes { $0.load(as: Float.self) }
            self.slope = slope
            self.intercept = intercept
            log("\(name): slope: \(slope), intercept: \(intercept)")

        case .glucoseUnit:
            if let unit = GlucoseUnit(rawValue: GlucoseUnit.allCases[Int(data[0])].rawValue) {
                log("\(name): glucose unit: \(unit)")
                self.unit = unit
            }

        case .bridgeStatus:
            bridgeStatus = data[0] < BridgeStatus.unknown.rawValue ? BridgeStatus(rawValue: data[0])! : .unknown
            log("\(name): transmitter status: \(bridgeStatus.description)")

        case .alerts:
            alarmHigh = Data(data[0...3]).withUnsafeBytes { $0.load(as: Float.self) }
            alarmLow  = Data(data[4...7]).withUnsafeBytes { $0.load(as: Float.self) }
            connectionCheckInterval = Int(data[ 9]) << 8 + Int(data[ 8])
            snoozeLow               = Int(data[11]) << 8 + Int(data[10])
            snoozeHigh              = Int(data[13]) << 8 + Int(data[12])
            let signals: UInt8 = data[14]
            sensorLostVibration = (signals >> 3) & 1 == 1
            glucoseVibration    = (signals >> 1) & 1 == 1

            log("\(name): alerts: high: \(alarmHigh), low: \(alarmLow), bridge connection check: \(connectionCheckInterval) minutes, snooze low: \(snoozeLow) minutes, snooze high: \(snoozeHigh) minutes, sensor lost vibration: \(sensorLostVibration), glucose vibration: \(glucoseVibration)")

        case .unknown2:
            var sensorSerial = data.string
            if sensorSerial.prefix(2) != "00" {
                transmitter?.sensor?.serial = sensorSerial
            } else {
                sensorSerial = "N/A"
            }
            log("\(name): sensor serial number: \(sensorSerial)")

        default:
            break
        }
    }


    func readSetup() {
        readValue(for: .calibration)
        readValue(for: .glucoseUnit)
        readValue(for: .lastGlucose)
        readValue(for: .bridgeStatus)
        readValue(for: .alerts)
        readValue(for: .unknown2) // sensor serial
    }
}


#if !os(watchOS)

struct WatlaaDetailsView: View {
    @Environment(AppState.self) var app: AppState
    @Environment(Settings.self) var settings: Settings

    var device: Watlaa = Watlaa()

    var body: some View {

        @Bindable var device = device

        Group {
            Section {
                HStack {
                    Text("Bridge status")
                    Spacer()
                    Text(device.bridgeStatus.description)
                        .foregroundColor(device.bridgeStatus == .connectedActiveSensor ? .green : .red)
                }
                if !(device.transmitter?.sensor?.serial.isEmpty ?? true) {
                    HStack {
                        Text("Sensor serial")
                        Spacer()
                        Text(device.transmitter!.sensor!.serial).foregroundColor(.yellow)
                    }
                }
            }

            Section(header: Text("SETUP").font(.headline)) {
                HStack {
                    Text("Unit")
                    Spacer().frame(maxWidth: .infinity)
                    Picker(selection: $device.unit, label: Text("Unit")) {
                        ForEach(GlucoseUnit.allCases) { unit in
                            Text(unit.description).tag(unit)
                        }
                    }.pickerStyle(SegmentedPickerStyle())
                }
            }

            Section(header: Text("Calibration")) {
                Group {
                    HStack {
                        Text("Intercept")
                        Spacer().frame(maxWidth: .infinity)
                        TextField("Intercept", value: $device.intercept, formatter: settings.numberFormatter)
                            .foregroundColor(.purple)
                    }
                    HStack {
                        Text("Slope")
                        Spacer().frame(maxWidth: .infinity)
                        TextField("Slope", value: $device.slope, formatter: settings.numberFormatter)
                            .foregroundColor(.purple)
                    }
                }.keyboardType(.numbersAndPunctuation)
            }

            Section(header: Text("Alarms")) {
                HStack {
                    Image(systemName: "bell.fill")
                    Spacer().frame(maxWidth: .infinity)
                    Text(" > ")
                    TextField("High", value: $device.alarmHigh, formatter: NumberFormatter())
                    Text("   < ")
                    TextField("Low", value: $device.alarmLow, formatter: NumberFormatter())
                    // FIXME: doesn't update when changing unit
                    Text(" \(device.unit.description)")
                }.foregroundColor(.red)
                HStack {
                    Image(systemName: "speaker.zzz.fill")
                    Spacer().frame(maxWidth: .infinity)
                    Text("High: ")
                    TextField("High", value: $device.snoozeHigh, formatter: NumberFormatter())
                    Text("Low: ")
                    TextField("Low", value: $device.snoozeLow, formatter: NumberFormatter())
                    Text(" min")
                }.foregroundColor(.yellow)
            }
            Section(header: Text("Vibrations")) {
                HStack {
                    Text("Sensor lost")
                    Toggle("Sensor lost", isOn: $device.sensorLostVibration).labelsHidden()
                    Spacer()
                    Text("Glucose")
                    Toggle("Glucose", isOn: $device.glucoseVibration).labelsHidden()
                }
            }
            HStack {
                Text("Bridge check interval").layoutPriority(1.0)
                Spacer().frame(maxWidth: .infinity)
                TextField("Interval", value: $device.connectionCheckInterval, formatter: NumberFormatter())
                Text(" min")
            }
            // TODO: spacer to allow editing
        }
    }
}


#Preview {
    WatlaaDetailsView(device: Watlaa())
        .environment(AppState.test(tab: .monitor))
        .environment(Settings())
        .environment(\.colorScheme, .dark)
}


#endif


// Legacy code from bluetoothDelegate didDiscoverCharacteristicsFor:

// if app.device.type == .watch(.watlaa) && serviceUUID == Watlaa.dataServiceUUID {
//     (app.device as! Watlaa).readSetup()
//     log("Watlaa: reading configuration")
// }
