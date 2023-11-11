//
//  WidgetCenter.swift
//  DiaBLE
//
//  Created by Anubhav Rawat on 11/11/23.
//

import ActivityKit
import Foundation
import SwiftUI

class WidgetCenter: ObservableObject{
    
    static var shared = WidgetCenter()
    
    private init(){
        
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
    
    //    var glycemicAlarmDescription: String
    //    var trendArrowDescription: String
    //    var arrowColor: String
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
    
     func observeActivity(){
        
        if let act = activity{
            let activityState = act.activityState
            if activityState == .dismissed{
                activity = nil
            }
        }
        
//        Task{
//            for await activityState in activity.activityStateUpdates{
//                if activityState == .dismissed{
//                    timer.invalidate()
//                }
//            }
//        }
    }
    
}
