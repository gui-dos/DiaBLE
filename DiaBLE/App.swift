import SwiftUI


@main
struct DiaBLEApp: App {

#if !os(watchOS)
    @UIApplicationDelegateAdaptor(MainDelegate.self) var main
#else
    @WKApplicationDelegateAdaptor(MainDelegate.self) var main
#endif

    @Environment(\.scenePhase) private var scenePhase

    @SceneBuilder var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(main.app)
                .environment(main.log)
                .environment(main.history)
                .environment(main.settings)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                #if !os(watchOS)
                UIApplication.shared.isIdleTimerDisabled = main.settings.caffeinated
                #endif
            }
            if scenePhase == .background {
                if main.settings.userLevel >= .devel {
                    main.debugLog("DEBUG: app went background at \(Date.now.shortTime)")
                }
            }
        }
    }
}


enum TabTitle: String {
    case monitor
    case online
    case console
    case settings
    case data
    case plan
}


enum OnlineService: String, CaseIterable {
    case nightscout  = "Nightscout"
    case libreLinkUp = "LibreLinkUp"
    case dexcomShare = "DexcomShare"
}


enum GlycemicAlarm: Int, CustomStringConvertible, CaseIterable, Codable {
    case unknown              = -1
    case notDetermined        = 0
    case lowGlucose           = 1
    case projectedLowGlucose  = 2
    case glucoseOK            = 3
    case projectedHighGlucose = 4
    case highGlucose          = 5

    var description: String {
        switch self {
        case .notDetermined:        "NOT_DETERMINED"
        case .lowGlucose:           "LOW_GLUCOSE"
        case .projectedLowGlucose:  "PROJECTED_LOW_GLUCOSE"
        case .glucoseOK:            "GLUCOSE_OK"
        case .projectedHighGlucose: "PROJECTED_HIGH_GLUCOSE"
        case .highGlucose:          "HIGH_GLUCOSE"
        default:                    ""
        }
    }

    init(string: String) {
        self = Self.allCases.first { $0.description == string } ?? .unknown
    }

    var shortDescription: String {
        switch self {
        case .lowGlucose:           "LOW"
        case .projectedLowGlucose:  "GOING LOW"
        case .glucoseOK:            "OK"
        case .projectedHighGlucose: "GOING HIGH"
        case .highGlucose:          "HIGH"
        default:                    ""
        }
    }
}


enum TrendArrow: Int, CustomStringConvertible, CaseIterable, Codable {
    case unknown        = -1
    case notDetermined  = 0
    case fallingQuickly = 1
    case falling        = 2
    case stable         = 3
    case rising         = 4
    case risingQuickly  = 5

    var description: String {
        switch self {
        case .notDetermined:  "NOT_DETERMINED"
        case .fallingQuickly: "FALLING_QUICKLY"
        case .falling:        "FALLING"
        case .stable:         "STABLE"
        case .rising:         "RISING"
        case .risingQuickly:  "RISING_QUICKLY"
        default:              ""
        }
    }

    init(string: String) {
        self = Self.allCases.first { $0.description == string } ?? .unknown
    }

    var symbol: String {
        switch self {
        case .fallingQuickly: "↓"
        case .falling:        "↘︎"
        case .stable:         "→"
        case .rising:         "↗︎"
        case .risingQuickly:  "↑"
        default:              "---"
        }
    }
}


@Observable class AppState {

    var device: Device!
    var transmitter: Transmitter!
    var sensor: Sensor!

    var main: MainDelegate!

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var currentGlucose: Int = 0
    var lastReadingDate: Date = Date.distantPast
    var glycemicAlarm: GlycemicAlarm = .unknown
    var trendArrow: TrendArrow = .unknown
    var trendDelta: Int = 0
    var trendDeltaMinutes: Int = 0

    var deviceState: String = ""
    var lastConnectionDate: Date = Date.distantPast
    var serviceResponse: String = "Welcome to DiaBLE!"

    var status: String = "Welcome to DiaBLE!"

    var showingJSConfirmAlert: Bool = false
    var jsConfirmAlertMessage: String = ""
    var jsAlertReturn: String = ""
}


public enum UserLevel: Int, CaseIterable, Comparable {
    case basic = 0
    case devel = 1
    case test  = 2

    public static func < (lhs: UserLevel, rhs: UserLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}


/// https://github.com/apple/swift-log/blob/main/Sources/Logging/Logging.swift
public enum LogLevel: UInt8, Codable, CaseIterable {
    case trace, debug, info, notice, warning, error, critical
}


struct LogEntry: Identifiable {
    let id = UUID()
    let message: String
    let time: Date
    var label: String
    var level: LogLevel
    init(message: String, level: LogLevel = .info,  label: String = "") {
        var label = label
        self.message = message
        self.level = level
        self.time = Date()
        if label.isEmpty {
            label = String(message[message.startIndex ..< (message.firstIndex(of: ":") ?? message.startIndex)])
            label = !label.contains(" ") ? label : ""
        }
        self.label = label
    }
}


@Observable class Log {
    var entries: [LogEntry]
    var labels: Set<String>
    init(_ text: String = "Log \(Date().local)\n") {
        entries = [LogEntry(message: text)]
        labels = []
    }
}


@Observable class History {
   var values:        [Glucose] = []
   var rawValues:     [Glucose] = []
   var rawTrend:      [Glucose] = []
   var factoryValues: [Glucose] = []
   var factoryTrend:  [Glucose] = []
   var storedValues:     [Glucose] = []
   var nightscoutValues: [Glucose] = []
}


// For UI testing

extension AppState {
    static func test(tab: TabTitle) -> AppState {

        let main = MainDelegate()
        let app = main.app

        let transmitter = Abbott(main: main)
        transmitter.type = .transmitter(.abbott); transmitter.name = "Thingy"; transmitter.battery = 54; transmitter.rssi =  -75; transmitter.firmware = "4.56"; transmitter.manufacturer = "Acme Inc."; transmitter.hardware = "2.3"; transmitter.macAddress = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]); transmitter.state = .connected; transmitter.lastConnectionDate = Date() - 5
        app.transmitter = transmitter
        app.device = app.transmitter
        app.lastConnectionDate = transmitter.lastConnectionDate
        app.lastReadingDate = transmitter.lastConnectionDate

        let sensor = Libre(transmitter: transmitter, main: main)
        sensor.state = .active; sensor.serial = "3MH001DG75W"; sensor.age = 18705; sensor.uid = "2fe7b10000a407e0".bytes; sensor.patchInfo = "9d083001712b".bytes
        app.sensor = sensor
        app.device.serial = sensor.serial

        app.main.settings.selectedTab = tab
        app.currentGlucose = 234
        app.trendDelta = -12
        app.trendDeltaMinutes = 6
        app.glycemicAlarm = .highGlucose
        app.trendArrow = .falling
        app.deviceState = "Connected"
        app.status = "Sensor + Transmitter\nError about connection\nError about sensor"

        return app
    }
}


extension History {
    static var test: History {

        let history = History()

        let values = [231, 252, 253, 254, 245, 196, 177, 128, 149, 150, 101, 122, 133, 144, 155, 166, 177, 178, 149, 140, 141, 142, 143, 144, 155, 166, 177, 178, 169, 150, 141, 132].enumerated().map { Glucose($0.1, id: 5000 - $0.1 * 15, date: Date() - Double($0.1) * 15 * 60) }
        history.values = values

        let rawValues = [241, 252, 263, 254, 205, 196, 187, 138, 159, 160, 121, 132, 133, 154, 165, 176, 157, 148, 149, 140, 131, 132, 143, 154, 155, 176, 177, 168, 159, 150, 142].enumerated().map { Glucose($0.1, id: 5000 - $0.0 * 15, date: Date() - Double($0.1) * 15 * 60) }
        history.rawValues = rawValues

        let factoryArray = [231, 242, 243, 244, 255, 216, 197, 138, 159, 120, 101, 102, 143, 154, 165, 186, 187, 168, 139, 130, 131, 142, 143, 144, 155, 166, 177, 188, 169, 150, 141, 132]

        let factoryValues = factoryArray.enumerated().map { Glucose($0.1, id: 5000 - $0.1 * 15, date: Date() - Double($0.1) * 15 * 60) }
        history.factoryValues = factoryValues

        let rawTrend = [241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 241, 242, 243, 244, 245].enumerated().map { Glucose($0.1, id: 5000 - $0.0, date: Date() - Double($0.1) * 60) }
        history.rawTrend = rawTrend

        let factoryTrend = [231, 232, 233, 234, 235, 236, 237, 238, 239, 230, 231, 232, 233, 234, 235].enumerated().map { Glucose($0.1, id: 5000 - $0.0, date: Date() - Double($0.1) * 60) }
        history.factoryTrend = factoryTrend

        let storedValues = [231, 252, 253, 254, 245, 196, 177, 128, 149, 150, 101, 122, 133, 144, 155, 166, 177, 178, 149, 140, 141, 142, 143, 144, 155, 166, 177, 178, 169, 150, 141, 132].enumerated().map { Glucose($0.1, id: $0.0, date: Date() - Double($0.1) * 15 * 60, source: "SourceApp com.example.sourceapp") }
        history.storedValues = storedValues

        let nightscoutValues = [231, 252, 253, 254, 245, 196, 177, 128, 149, 150, 101, 122, 133, 144, 155, 166, 177, 178, 149, 140, 141, 142, 143, 144, 155, 166, 177, 178, 169, 150, 141, 132].enumerated().map { Glucose($0.1, id: $0.0, date: Date() - Double($0.1) * 15 * 60, source: "Device") }
        history.nightscoutValues = nightscoutValues

        return history
    }
}
