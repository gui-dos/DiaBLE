import SwiftUI
import CoreBluetooth
import AVFoundation
import os.log
import UserNotifications


protocol Logging {
    var main: MainDelegate! { get set }
}

extension Logging {
    func log(_ msg: String)      { main?.log(msg) }
    func debugLog(_ msg: String) { main?.debugLog(msg) }

    var app: AppState            { main.app }
    var settings: Settings       { main.settings }
}

protocol LoggingView {
    var app: AppState { get }
}

extension View where Self: LoggingView {
    func log(_ msg: String) { app.main?.log(msg) }
    func debugLog(_ msg: String) { app.main?.debugLog(msg) }
}


public class MainDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate, WKExtendedRuntimeSessionDelegate {

    var app: AppState
    var logger: Logger
    var log: Log
    var history: History
    var settings: Settings

    var extendedSession: WKExtendedRuntimeSession! // TODO

    var centralManager: CBCentralManager
    var bluetoothDelegate: BluetoothDelegate
    var healthKit: HealthKit?
    var libreLinkUp: LibreLinkUp?
    var nightscout: Nightscout?


    override init() {

        UserDefaults.standard.register(defaults: Settings.defaults)

        settings = Settings()
        logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Debug")
        log = Log()
        history = History()
        app = AppState()

        extendedSession = WKExtendedRuntimeSession()

        bluetoothDelegate = BluetoothDelegate()
        centralManager = CBCentralManager(delegate: bluetoothDelegate,
                                          queue: nil,
                                          options: [CBCentralManagerOptionRestoreIdentifierKey: "DiaBLE"])

        healthKit = HealthKit()

        super.init()

        log.entries = [LogEntry(message: "Welcome to DiaBLE!"), LogEntry(message: "\(settings.logging ? "Log started" : "Log stopped") \(Date().local)")]
        debugLog("User defaults: \(Settings.defaults.keys.map { [$0, UserDefaults.standard.dictionaryRepresentation()[$0]!] }.sorted { ($0[0] as! String) < ($1[0] as! String) })")

        app.main = self
        extendedSession.delegate = self
        bluetoothDelegate.main = self

        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .criticalAlert]) { _, _ in }
        settings.lastAlarmDate = .now

        let numberFormatter = NumberFormatter()
        numberFormatter.minimumFractionDigits = 8
        settings.numberFormatter = numberFormatter

        Task {

            if let healthKit {
                healthKit.main = self
                await healthKit.requestAuthorization()
                if healthKit.isAuthorized {
                    healthKit.read { [self] in debugLog("HealthKit: last 12 stored values: \($0[..<(min(12, $0.count))])") }
                } else {
                    log("HealthKit: not authorized")
                }
            } else {
                log("HealthKit: not available")
            }

            settings.lastOnlineDate = .distantPast
            libreLinkUp = LibreLinkUp(main: self)
            if settings.selectedService == .libreLinkUp {
                await libreLinkUp?.reload(enforcing: true)
            }
            nightscout = Nightscout(main: self)
            if let (values, _) = try? await nightscout?.read() {
                history.nightscoutValues = values
            }

            // features currently in beta testing
            if settings.userLevel >= .test {
                // Libre3.testAESCCM()
            }

        }

    }


    public func log(_ msg: String, level: LogLevel = .info, label: String = "") {
        if settings.logging || msg.hasPrefix("Log") {
            let entry = LogEntry(message: msg, level: level, label: label)
            Task { @MainActor in
                if settings.reversedLog {
                    log.entries.insert(entry, at: 0)
                } else {
                    log.entries.append(entry)
                }
                print(msg)
                if settings.userLevel > .basic {
                    logger.log("\(msg, privacy: .public)")
                }
                if !entry.label.isEmpty {
                    log.labels.insert(entry.label)
                }
            }
        }
    }


    public func debugLog(_ msg: String) {
        if settings.userLevel > .basic {
            log(msg, level: .debug)
        }
    }

    public func status(_ text: String) {
        Task { @MainActor in
            app.status = text
        }
    }

    public func errorStatus(_ text: String) {
        if !app.status.contains(text) {
            Task { @MainActor in
                app.status.append("\n\(text)")
            }
        }
    }


    public func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        log("TODO: handling background tasks")
    }


    public func rescan() {
        if let device = app.device {
            centralManager.cancelPeripheralConnection(device.peripheral!)
        }
        if centralManager.state == .poweredOn {
            settings.stoppedBluetooth = false
            if !(settings.preferredDevicePattern.matches("abbott") || settings.preferredDevicePattern.matches("dexcom")) {
                log("Bluetooth: scanning...")
                status("Scanning...")
                centralManager.scanForPeripherals(withServices: nil, options: nil)
            } else {
                if !settings.preferredDevicePattern.matches("dexcom"),
                   let peripheral = centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(string: Libre3.UUID.data.rawValue)]).first {
                    log("Bluetooth: retrieved \(peripheral.name ?? "unnamed peripheral")")
                    bluetoothDelegate.centralManager(centralManager, didDiscover: peripheral, advertisementData: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: Libre3.UUID.data.rawValue)]], rssi: 0)
                } else if !settings.preferredDevicePattern.matches("dexcom"),
                          let peripheral = centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(string: Abbott.dataServiceUUID)]).first {
                    log("Bluetooth: retrieved \(peripheral.name ?? "unnamed peripheral")")
                    bluetoothDelegate.centralManager(centralManager, didDiscover: peripheral, advertisementData: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: Abbott.dataServiceUUID)]], rssi: 0)
                } else if !settings.preferredDevicePattern.matches("abbott"),
                          let peripheral = centralManager.retrieveConnectedPeripherals(withServices: [CBUUID(string: Dexcom.UUID.advertisement.rawValue)]).first {
                    log("Bluetooth: retrieved \(peripheral.name ?? "unnamed peripheral")")
                    bluetoothDelegate.centralManager(centralManager, didDiscover: peripheral, advertisementData: [CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: Dexcom.UUID.advertisement.rawValue)]], rssi: 0)
                } else {
                    log("Bluetooth: scanning for a Libre/Dexcom...")
                    status("Scanning for a Libre/Dexcom...")
                    centralManager.scanForPeripherals(withServices: nil, options: nil)
                }
            }
        } else {
            log("Bluetooth is powered off: cannot scan")
        }
        Task {
            if settings.selectedService == .libreLinkUp {
                await libreLinkUp?.reload(enforcing: true)
            }
            if let (values, _) = try? await nightscout?.read() {
                history.nightscoutValues = values
            }
            healthKit?.read()
        }
    }


    public func playAlarm(vibrating: Bool = true) {
        let currentGlucose = app.currentGlucose
        if !settings.mutedAudio {
            do {
                try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playback, options: [.duckOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                log("Audio Session error: \(error)")
            }
            let soundName = currentGlucose > Int(settings.alarmHigh) ? "alarm_high" : "alarm_low"
            let audioPlayer = try! AVAudioPlayer(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: soundName, ofType: "mp3")!), fileTypeHint: "mp3")
            audioPlayer.play()
            _ = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) {
                _ in audioPlayer.stop()
                do {
                    try AVAudioSession.sharedInstance().setActive(false)
                } catch { }
            }
        }
        if !settings.disabledNotifications || vibrating {
            let hapticDirection: WKHapticType = currentGlucose > Int(settings.alarmHigh) ? .directionUp : .directionDown
            WKInterfaceDevice.current().play(hapticDirection)
            let times = currentGlucose > Int(settings.alarmHigh) ? 3 : 4
            let pause = times == 3 ? 1.0 : 5.0 / 6
            for s in 0 ..< times {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(s) * pause) {
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        }
    }


    func parseSensorData(_ sensor: Sensor) {

        (sensor as? Libre)?.detailFRAM()

        if sensor.history.count > 0 || sensor.trend.count > 0 {

            let calibrationInfo = sensor.calibrationInfo
            if sensor.serial == settings.activeSensorSerial {
                settings.activeSensorCalibrationInfo = calibrationInfo
            }

            history.rawTrend = sensor.trend
            log("Raw trend: \(sensor.trend.map(\.rawValue))")
            debugLog("Raw trend temperatures: \(sensor.trend.map(\.rawTemperature))")
            let factoryTrend = sensor.factoryTrend
            history.factoryTrend = factoryTrend
            log("Factory trend: \(factoryTrend.map(\.value))")
            log("Trend temperatures: \(factoryTrend.map { Double(String(format: "%.1f", $0.temperature))! }))")
            history.rawValues = sensor.history
            log("Raw history: \(sensor.history.map(\.rawValue))")
            debugLog("Raw historic temperatures: \(sensor.history.map(\.rawTemperature))")
            let factoryHistory = sensor.factoryHistory
            history.factoryValues = factoryHistory
            log("Factory history: \(factoryHistory.map(\.value))")
            log("Historic temperatures: \(factoryHistory.map { Double(String(format: "%.1f", $0.temperature))! })")

            // TODO
            debugLog("Trend has errors: \(sensor.trend.map(\.hasError))")
            debugLog("Trend data quality: [\n\(sensor.trend.map(\.dataQuality.description).joined(separator: ",\n"))\n]")
            debugLog("Trend quality flags: [\(sensor.trend.map { "0" + String($0.dataQualityFlags,radix: 2).suffix(2) }.joined(separator: ", "))]")
            debugLog("History has errors: \(sensor.history.map(\.hasError))")
            debugLog("History data quality: [\n\(sensor.history.map(\.dataQuality.description).joined(separator: ",\n"))\n]")
            debugLog("History quality flags: [\(sensor.history.map { "0" + String($0.dataQualityFlags,radix: 2).suffix(2) }.joined(separator: ", "))]")
        }

        if let sensor = sensor as? Libre {

            debugLog("Sensor uid: \(sensor.uid.hex), saved uid: \(settings.currentSensorUid.hex), patch info: \(sensor.patchInfo.hex.count > 0 ? sensor.patchInfo.hex : "<nil>"), saved patch info: \(settings.currentPatchInfo.hex)")

            if sensor.uid.count > 0 && sensor.patchInfo.count > 0 {
                settings.currentSensorUid = sensor.uid
                settings.currentPatchInfo = sensor.patchInfo
            }

            if sensor.uid.count == 0 || settings.currentSensorUid.count > 0 {
                if sensor.uid.count == 0 {
                    sensor.uid = settings.currentSensorUid
                }

                if sensor.uid == settings.currentSensorUid {
                    sensor.patchInfo = settings.currentPatchInfo
                }
            }
        }

        Task {

            didParseSensor(sensor)

        }

    }


    func didParseSensor(_ sensor: Sensor?) {

        guard let sensor else {
            extendedSession.start(at: max(app.lastReadingDate, app.lastConnectionDate) + Double(settings.readingInterval * 60) - 5.0)
            log("Watch: extended session to be started in \(Double(settings.readingInterval * 60) - 5.0) seconds")
            return
        }

        if history.factoryTrend.count > 0 {
            app.currentGlucose = history.factoryTrend[0].value
        }

        let currentGlucose = app.currentGlucose

        // TODO: delete mirrored implementation from Abbott Device
        // TODO: compute accurate delta and update trend arrow
        if history.factoryTrend.count > 5 {
            let lastTrendValues = history.factoryTrend.prefix(6).filter { $0.value > 0 }
            let deltaMinutes = lastTrendValues[0].id - lastTrendValues.last!.id
            let delta = lastTrendValues[0].value - lastTrendValues.last!.value
            app.trendDeltaMinutes = deltaMinutes
            app.trendDelta = delta
        }

        let remainingSnooze = (Double(settings.alarmSnoozeInterval * 60) + settings.lastAlarmDate.timeIntervalSinceNow)

        let snoozed = (remainingSnooze - 3.0) >= 0 && settings.disabledNotifications
        var alarmed = false

        if currentGlucose > 0 && (currentGlucose > Int(settings.alarmHigh) || currentGlucose < Int(settings.alarmLow)) {
            alarmed = true
            log("ALARM: current glucose: \(currentGlucose.units) (settings: high: \(settings.alarmHigh.units), low: \(settings.alarmLow.units), muted audio: \(settings.mutedAudio ? "yes" : "no")), \(snoozed ? "" : "not ")snoozed\(snoozed ? " for \((Int(remainingSnooze + 3.0) / 60)) mins" : "")")

            if !snoozed {
                settings.lastAlarmDate = .now
                playAlarm()
            }
        }

        if !settings.disabledNotifications || snoozed || alarmed {
            // TODO:
            // UNUserNotificationCenter.current().setBadgeCount(
            //     settings.displayingMillimoles ? Int(Float(currentGlucose.units)! * 10) : Int(currentGlucose.units)!
            // )
        } else {
            // TODO:
            // UNUserNotificationCenter.current().setBadgeCount(0)
        }

        if history.values.count > 0 || history.factoryValues.count > 0 || currentGlucose > 0 {
            var entries = [Glucose]()
            if history.values.count > 0 {
                entries += history.values
            } else {
                entries += history.factoryValues
            }
            entries += history.factoryTrend.dropFirst() + [Glucose(currentGlucose, date: sensor.lastReadingDate)]
            entries = entries.filter { $0.value > 0 && $0.id > -1 }

            // TODO: Libre 3: delete older non-historical values (lifeCount not divisible by 5)

            Task {

                let newEntries = (entries.filter { $0.date > healthKit?.lastDate ?? Calendar.current.date(byAdding: .hour, value: -8, to: Date())! })
                if newEntries.count > 0 {
                    await healthKit?.write(newEntries)
                    healthKit?.read()
                }

                if let (values, _) = try? await nightscout?.read() {
                    let newEntries = values.count > 0 ? entries.filter { $0.date > values[0].date } : entries
                    if newEntries.count > 0 {
                        try await nightscout?.post(entries: newEntries)
                        if let (values, _) = try? await nightscout?.read() {
                            history.nightscoutValues = values
                        }
                    }
                }
            }
        }

        // TODO:
        extendedSession.start(at: max(app.lastReadingDate, app.lastConnectionDate) + Double(settings.readingInterval * 60) - 5.0)
        log("Watch: extended session to be started in \(Double(settings.readingInterval * 60) - 5.0) seconds")
    }


    public func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        debugLog("Watch: extended session did start")
    }

    public func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        debugLog("Watch: extended session will expire")
    }

    public func extendedRuntimeSession(_ extendedRuntimeSession: WKExtendedRuntimeSession, didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason, error: Error?) {
        let errorDescription = error != nil ? error!.localizedDescription : "undefined"
        debugLog("Watch: extended session did invalidate: reason: \(reason), error: \(errorDescription)")
    }
}
