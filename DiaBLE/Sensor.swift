import Foundation

#if !os(watchOS)
import CoreNFC
#endif


enum SensorType: String, CustomStringConvertible {
    case libre1        = "Libre 1"
    case libreUS14day  = "Libre US 14d"
    case libreProH     = "Libre Pro/H"
    case libre2        = "Libre 2"
    case libre2Gen2    = "Libre 2 Gen2"
    case libre3        = "Libre 3"
    case lingo         = "Lingo"
    case dexcomG6      = "Dexcom G6"
    case dexcomONE     = "Dexcom ONE"
    case dexcomG7      = "Dexcom G7"
    case dexcomONEPlus = "Dexcom ONE+"
    case stelo         = "Stelo"
    case unknown       = "unknown"

    var description: String { rawValue }
    var isALibre: Bool { self == .libre3 || self == .libre2Gen2 || self == .libre2 || self == .libre1 || self == .libreUS14day || self == .libreProH || self == .lingo }
}


enum SensorFamily: Int, CustomStringConvertible {
    case unknown    = -1
    case libre1     = 0
    case librePro   = 1
    case libre2     = 3
    case libre3     = 4
    case libreSense = 7

    var description: String {
        switch self {
        case .unknown:    "unknown"
        case .libre1:     "Libre 1"
        case .librePro:   "Libre Pro"
        case .libre2:     "Libre 2"
        case .libre3:     "Libre 3"
        case .libreSense: "Libre Sense"
        }
    }
}


enum SensorRegion: Int, CustomStringConvertible {
    case unknown            = 0
    case european           = 1
    case usa                = 2
    case australianCanadian = 4
    case easternROW         = 8

    var description: String {
        switch self {
        case .unknown:            "unknown"
        case .european:           "European"
        case .usa:                "USA"
        case .australianCanadian: "Australian / Canadian"
        case .easternROW:         "Eastern / Rest of World"
        }
    }
}


enum SensorState: UInt8, CustomStringConvertible {
    case unknown      = 0x00

    case notActivated = 0x01
    case warmingUp    = 0x02    // 60 minutes
    case active       = 0x03    // ≈ 14.5 days
    case expired      = 0x04    // 12 hours more; Libre 2: Bluetooth shutdown
    case shutdown     = 0x05    // 15th day onwards
    case failure      = 0x06

    var description: String {
        switch self {
        case .notActivated: "Not activated"
        case .warmingUp:    "Warming up"
        case .active:       "Active"
        case .expired:      "Expired"
        case .shutdown:     "Shut down"
        case .failure:      "Failure"
        default:            "unknown"
        }
    }
}


@Observable class Sensor: Logging {

    var type: SensorType = .unknown
    var family: SensorFamily = .unknown
    var region: SensorRegion = .unknown
    var serial: String = ""
    var readerSerial: Data = Data()
    var firmware: String = ""

    var transmitter: Transmitter?
    var main: MainDelegate!

    var state: SensorState = .unknown
    var lastReadingDate = Date.distantPast
    var activationTime: UInt32 = 0
    var age: Int = 0
    var maxLife: Int = 0
    var initializations: Int = 0

    var generation: Int = 0
    var securityGeneration: Int = 0

    var patchInfo: PatchInfo = Data() {
        willSet(info) {
            if info.count > 0 {
                type = SensorType(patchInfo: info)
            } else {
                type = .unknown
            }
            if type != .libre3 {
                if info.count > 3 {
                    region = SensorRegion(rawValue: Int(info[3])) ?? .unknown
                }
                if info.count >= 6 {
                    family = SensorFamily(rawValue: Int(info[2] >> 4)) ?? .libre1
                    if serial != "" {
                        serial = "\(family.rawValue)\(serial.dropFirst())"
                    }
                    let generation = info[2] & 0x0F
                    if family == .libre2 {
                        securityGeneration = generation < 9 ? 1 : 2
                    }
                    if family == .libreSense {
                        securityGeneration = generation < 4 ? 1 : 2
                    }
                }
            } else {
                family = .libre3
                region = SensorRegion(rawValue: Int(UInt16(info[2...3]))) ?? .unknown
                securityGeneration = 3 // TODO
            }
        }
    }

    var uid: SensorUid = Data() {
        willSet(uid) {
            if type != .libre3 {
                serial = serialNumber(uid: uid, family: self.family)
            }
        }
    }

    var trend: [Glucose] = []
    var history: [Glucose] = []

    var calibrationInfo = CalibrationInfo()

    var factoryTrend: [Glucose] { trend.map { factoryGlucose(rawGlucose: $0, calibrationInfo: calibrationInfo) }}
    var factoryHistory: [Glucose] { history.map { factoryGlucose(rawGlucose: $0, calibrationInfo: calibrationInfo) }}


    init(transmitter: Transmitter? = nil, main: MainDelegate? = nil) {
        self.transmitter = transmitter
        if transmitter != nil {
            self.main = transmitter!.main
        } else {
            self.main = main
        }
    }


#if !os(watchOS)
    func execute(nfc: NFC, taskRequest: TaskRequest) async throws {
    }
#endif

}
