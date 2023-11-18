//
//  WidgetCenter.swift
//  DiaBLE
//
//  Created by Anubhav Rawat on 11/11/23.
//

import ActivityKit
import Foundation
import SwiftUI
import AVFoundation
//

class WidgetCenter: NSObject, ObservableObject{
    
    static var shared = WidgetCenter()
    let session = AVAudioSession.sharedInstance()
    var testSoundPlayer: AVAudioPlayer!
    
    var soundPath: String { Bundle.main.path(forResource: "sound", ofType: "mp3")! }
    var soundURL: URL { URL(fileURLWithPath: soundPath) }
    
   var showingNFCAlert = false
   var onlineCountdown: Int = 0
   var readingCountdown: Int = 0

   var libreLinkUpResponse: String = "[...]"
   var libreLinkUpHistory: [LibreLinkUpGlucose] = []
   var libreLinkUpLogbookHistory: [LibreLinkUpGlucose] = []

//   var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
//   var minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    var minuteTimer: Timer?
   
//   var widgetController: WidgetCenter = .shared
//   
   var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    var app: AppState? = nil
    var history: History? = nil
    var settings: Settings? = nil
    
    var soundTimer: Timer?
    
    private override init(){
        super.init()
        
//        set category
        do {
            try session.setCategory(.playback, mode: .default, options: .mixWithOthers)
            try session.setActive(true)
        } catch {
            print(error)
        }
        
//        setup the sound player.
        do {
            testSoundPlayer = try AVAudioPlayer(contentsOf: soundURL)
        } catch {
            print(error)
        }
        
        
        soundTimer = Timer(timeInterval: 30, repeats: true, block: { [weak self] (timer) in
            guard let self = self else { return }
            self.testSoundPlayer.play()
        })
        RunLoop.main.add(soundTimer!, forMode: .common)
        
        
        
    }
    
    func runBackgroundLoop(app: AppState, history: History, settings: Settings){
        
        print("running background loops")
//        updating these objects every time app is opened.
        self.app = app
        self.history = history
        self.settings = settings
        
//        if timer is not running, i.e. background loop has never started, start the timer in background
        if minuteTimer == nil{
            
//
            minuteTimer = Timer(timeInterval: 10, repeats: true, block: { [weak self] (weakTimer) in
                guard let self = self else {return}
                Task{
//                    relaods the data and updates the live activity
                    await self.reloadLibreLinkUp()
                }
            })
            
            RunLoop.main.add(minuteTimer!, forMode: .common)
        }
        
    }
    
    func reloadLibreLinkUp() async {
        
        
        if let app = self.app, let history = self.history, let settings = self.settings{
            
            print("reload function from the loop.  ############")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3){
                
                
                
                if let sensor = app.sensor{
                    self.startLiveActivity(
                        lastReadingDate: app.lastReadingDate.shortTime,
                        minuteSinceLastReading: "\(Int(Date().timeIntervalSince(app.lastReadingDate)/60))",
                        currentGlucose: app.currentGlucose > 0 ? "\(app.currentGlucose.units) " : "--- ", alarmHigh: Int(settings.alarmHigh),
                        alarmLow: Int(settings.alarmLow),
                        color: app.currentGlucose > 0 && ((app.currentGlucose > Int(settings.alarmHigh) && (app.trendDelta > 0 || app.trendArrow == .rising || app.trendArrow == .risingQuickly)) || (app.currentGlucose < Int(settings.alarmLow) && (app.trendDelta < 0 || app.trendArrow == .falling || app.trendArrow == .fallingQuickly))) ? "red" : "blue", appState: app.status,
                        sensorStateDescription: sensor.state.description, sensorStateColor: app.sensor.state == .active ? "green" : "red",
                        glycemicAlarmDescription: app.glycemicAlarm.description,
                        trendArrowDescription: app.trendArrow.description,
                        arrowColor: app.currentGlucose > 0 && ((app.currentGlucose > Int(settings.alarmHigh) && (app.trendDelta > 0 || app.trendArrow == .rising || app.trendArrow == .risingQuickly)) || (app.currentGlucose < Int(settings.alarmLow) && (app.trendDelta < 0 || app.trendArrow == .falling || app.trendArrow == .fallingQuickly))) ?
                        "red" : "blue")
                }
                
            }
            
            
            if let libreLinkUp = await app.main?.libreLinkUp {
                var dataString = ""
                var retries = 0
            loop: repeat {
                do {
                    if settings.libreLinkUpPatientId.isEmpty ||
                        settings.libreLinkUpToken.isEmpty ||
                        settings.libreLinkUpTokenExpirationDate < Date() ||
                        retries == 1 {
                        do {
                            try await libreLinkUp.login()
                        } catch {
                            libreLinkUpResponse = error.localizedDescription.capitalized
                        }
                    }
                    if !(settings.libreLinkUpPatientId.isEmpty ||
                         settings.libreLinkUpToken.isEmpty) {
                        let (data, _, graphHistory, logbookData, logbookHistory, _) = try await libreLinkUp.getPatientGraph()
                        dataString = (data as! Data).string
                        libreLinkUpResponse = dataString + (logbookData as! Data).string
                        // TODO: just merge with newer values
                        libreLinkUpHistory = graphHistory.reversed()
                        libreLinkUpLogbookHistory = logbookHistory
                        if graphHistory.count > 0 {
                            DispatchQueue.main.async {
                                settings.lastOnlineDate = Date()
                                let lastMeasurement = self.libreLinkUpHistory[0]
                                app.lastReadingDate = lastMeasurement.glucose.date
                                app.sensor?.lastReadingDate = app.lastReadingDate
                                app.currentGlucose = lastMeasurement.glucose.value
                                // TODO: keep the raw values filling the gaps with -1 values
                                history.rawValues = []
                                history.factoryValues = self.libreLinkUpHistory.dropFirst().map(\.glucose) // TEST
                                var trend = history.factoryTrend
                                if trend.isEmpty || lastMeasurement.id > trend[0].id {
                                    trend.insert(lastMeasurement.glucose, at: 0)
                                }
                                // keep only the latest 22 minutes considering the 17-minute latency of the historic values update
                                trend = trend.filter { lastMeasurement.id - $0.id < 22 }
                                history.factoryTrend = trend
                                // TODO: merge and update sensor history / trend
                                app.main.didParseSensor(app.sensor)
                            }
                        }
                        if dataString != "{\"message\":\"MissingCachedUser\"}\n" {
                            break loop
                        }
                        retries += 1
                    }
                } catch {
                    libreLinkUpResponse = error.localizedDescription.capitalized
                }
            } while retries == 1
            }
            
            if let sensor = app.sensor{
                startLiveActivity(
                    lastReadingDate: app.lastReadingDate.shortTime,
                    minuteSinceLastReading: "\(Int(Date().timeIntervalSince(app.lastReadingDate)/60))",
                    currentGlucose: app.currentGlucose > 0 ? "\(app.currentGlucose.units) " : "--- ", alarmHigh: Int(settings.alarmHigh),
                    alarmLow: Int(settings.alarmLow),
                    color: app.currentGlucose > 0 && ((app.currentGlucose > Int(settings.alarmHigh) && (app.trendDelta > 0 || app.trendArrow == .rising || app.trendArrow == .risingQuickly)) || (app.currentGlucose < Int(settings.alarmLow) && (app.trendDelta < 0 || app.trendArrow == .falling || app.trendArrow == .fallingQuickly))) ? "red" : "blue", appState: app.status,
                    sensorStateDescription: sensor.state.description, sensorStateColor: app.sensor.state == .active ? "green" : "red",
                    glycemicAlarmDescription: app.glycemicAlarm.description,
                    trendArrowDescription: app.trendArrow.description,
                    arrowColor: app.currentGlucose > 0 && ((app.currentGlucose > Int(settings.alarmHigh) && (app.trendDelta > 0 || app.trendArrow == .rising || app.trendArrow == .risingQuickly)) || (app.currentGlucose < Int(settings.alarmLow) && (app.trendDelta < 0 || app.trendArrow == .falling || app.trendArrow == .fallingQuickly))) ?
                    "red" : "blue")
            }
//            self.startLiveact  14 26 270 162
            
            
        }
        
    }
    
    var activity: Activity<DiaBLE_LiveActivitiesAttributes>? = nil

    func startLiveActivity(lastReadingDate: String? = nil,  minuteSinceLastReading: String? = nil, currentGlucose: String, alarmHigh: Int, alarmLow: Int, color: String, appState: String, sensorStateDescription: String, sensorStateColor: String, glycemicAlarmDescription: String, trendArrowDescription: String, arrowColor: String){
        
        if activity != nil{
            updateLiveActivity(lastReadingDate: lastReadingDate, minuteSinceLastReading: minuteSinceLastReading, currentGlucose: currentGlucose, alarmHigh: alarmHigh, alarmLow: alarmLow, color: color, appState: appState, sensorStateDescription: sensorStateDescription, sensorStateColor: sensorStateColor, glycemicAlarmDescription: glycemicAlarmDescription, trendArrowDescription: trendArrowDescription, arrowColor: arrowColor)
            return
        }
        
        print("starting live activity.")
        
        let attributes = DiaBLE_LiveActivitiesAttributes(name: "live activity")
        
        let state = ActivityContent(state: DiaBLE_LiveActivitiesAttributes.ContentState(lastReadingDate: lastReadingDate, minuteSinceLastReading: minuteSinceLastReading, currentGlucose: currentGlucose, alarmHigh: alarmHigh, alarmLow: alarmLow, color: color, appState: appState, sensorStateDescription: sensorStateDescription, sensorStateColor: sensorStateColor, glycemicAlarmDescription: glycemicAlarmDescription, trendArrowDescription: trendArrowDescription, arrowColor: arrowColor), staleDate: nil)
        
        activity = try?Activity.request(attributes: attributes, content: state)
        
    }
    func updateLiveActivity(lastReadingDate: String? = nil,  minuteSinceLastReading: String? = nil, currentGlucose: String, alarmHigh: Int, alarmLow: Int, color: String, appState: String, sensorStateDescription: String, sensorStateColor: String, glycemicAlarmDescription: String, trendArrowDescription: String, arrowColor: String){
        
        if activity == nil{
            return
        }
        
        print("updating live activity")
         let state = ActivityContent(state: DiaBLE_LiveActivitiesAttributes.ContentState(lastReadingDate: lastReadingDate, minuteSinceLastReading: minuteSinceLastReading, currentGlucose: currentGlucose, alarmHigh: alarmHigh, alarmLow: alarmLow, color: color, appState: appState, sensorStateDescription: sensorStateDescription, sensorStateColor: sensorStateColor, glycemicAlarmDescription: glycemicAlarmDescription, trendArrowDescription: trendArrowDescription, arrowColor: arrowColor), staleDate: nil)
        
        Task{
            await activity?.update(state)
        }
    }
    
    func stopActivity(lastReadingDate: String? = nil,  minuteSinceLastReading: String? = nil, currentGlucose: String, alarmHigh: Int, alarmLow: Int, color: String, appState: String, sensorStateDescription: String, sensorStateColor: String, glycemicAlarmDescription: String, trendArrowDescription: String, arrowColor: String){
        
        if activity == nil{
            return
        }
        
        print("updating live activity")
//         let state = ActivityContent(state: DiaBLE_LiveActivitiesAttributes.ContentState(lastReadingDate: lastReadingDate, minuteSinceLastReading: minuteSinceLastReading, currentGlucose: currentGlucose, alarmHigh: alarmHigh, alarmLow: alarmLow, color: color, appState: appState, sensorStateDescription: sensorStateDescription, sensorStateColor: sensorStateColor, glycemicAlarmDescription: glycemicAlarmDescription, trendArrowDescription: trendArrowDescription, arrowColor: arrowColor), staleDate: nil)
        let state = DiaBLE_LiveActivitiesAttributes.ContentState(lastReadingDate: lastReadingDate, minuteSinceLastReading: minuteSinceLastReading, currentGlucose: currentGlucose, alarmHigh: alarmHigh, alarmLow: alarmLow, color: color, appState: appState, sensorStateDescription: sensorStateDescription, sensorStateColor: sensorStateColor, glycemicAlarmDescription: glycemicAlarmDescription, trendArrowDescription: trendArrowDescription, arrowColor: arrowColor)
        
        Task{
            await activity?.end(using: state, dismissalPolicy: .immediate)
        }
    }
    
     func observeActivity(){
        
        if let act = activity{
            let activityState = act.activityState
            if activityState == .dismissed{
                activity = nil
            }
        }
    }
    
}
