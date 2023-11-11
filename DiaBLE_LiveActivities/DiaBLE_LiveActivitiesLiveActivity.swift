//
//  DiaBLE_LiveActivitiesLiveActivity.swift
//  DiaBLE_LiveActivities
//
//  Created by Anubhav Rawat on 10/11/23.
//

import ActivityKit
import WidgetKit
import SwiftUI



struct DiaBLE_LiveActivitiesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DiaBLE_LiveActivitiesAttributes.self) { context in
            // Lock screen/banner UI goes here
            HStack(spacing: 10){
                VStack {
                    if let lastReadingDate = context.state.lastReadingDate, let minuteSinceLastReading = context.state.minuteSinceLastReading{
                        Text(lastReadingDate).monospacedDigit()
                        Text(minuteSinceLastReading).font(.footnote).monospacedDigit()
                    }else{
                        Text("___")
                    }
                    
    //                Text("Hello \(context.state.emoji)")
                }
                
                HStack{
                    Text(context.state.currentGlucose)
                        .font(.system(size: 32, weight: .black))
                        .foregroundStyle(.black)
                        .padding(5)
                        .background(context.state.color == "red" ? Color.red : Color.blue)
                        .cornerRadius(8)
                    
                    Text("\(context.state.glycemicAlarmDescription.replacingOccurrences(of: "_", with: " "))\(context.state.glycemicAlarmDescription != "" ? " - " : "")\(context.state.trendArrowDescription.replacingOccurrences(of: "_", with: " "))")
                        .foregroundStyle(context.state.arrowColor == "red" ? .red : .white)
                }
                
                
                VStack{
                    Text(context.state.appState)
                        .font(.footnote)
                        .padding(.horizontal, 5)
                    Text(context.state.sensorStateDescription)
                        .foregroundStyle(context.state.sensorStateColor == "green" ? .green : .red)
                }
                
            }
            
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } 
    dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    VStack {
                        if let lastReadingDate = context.state.lastReadingDate, let minuteSinceLastReading = context.state.minuteSinceLastReading{
                            Text(lastReadingDate).monospacedDigit()
                            Text(minuteSinceLastReading).font(.footnote).monospacedDigit()
                        }else{
                            Text("___")
                        }
                        
        //                Text("Hello \(context.state.emoji)")
                    }
                    
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack{
                        Text(context.state.appState)
                            .font(.footnote)
                            .padding(.horizontal, 5)
                        Text(context.state.sensorStateDescription)
                            .foregroundStyle(context.state.sensorStateColor == "green" ? .green : .red)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    // more content
                    HStack{
                        Text(context.state.currentGlucose)
                            .font(.system(size: 32, weight: .black))
                            .foregroundStyle(.black)
                            .padding(5)
                            .background(context.state.color == "red" ? Color.red : Color.blue)
                            .cornerRadius(8)
                        
                        Text("\(context.state.glycemicAlarmDescription.replacingOccurrences(of: "_", with: " "))\(context.state.glycemicAlarmDescription != "" ? " - " : "")\(context.state.trendArrowDescription.replacingOccurrences(of: "_", with: " "))")
                            .foregroundStyle(context.state.arrowColor == "red" ? .red : .white)
                    }
                }
            } compactLeading: {
                VStack{
                    VStack {
                        if let lastReadingDate = context.state.lastReadingDate, let minuteSinceLastReading = context.state.minuteSinceLastReading{
                            Text(lastReadingDate).monospacedDigit()
                                .font(.system(size: 10))
                            Text(minuteSinceLastReading)
                                .font(.system(size: 8))
                                .monospacedDigit()
                        }else{
                            Text("___")
                        }
                        
        //                Text("Hello \(context.state.emoji)")
                    }
                    
                }
            } compactTrailing: {
//                Text("T \(context.state.emoji)")
                ProgressView(value: 1){
                    Text(context.state.currentGlucose)
                        .font(.system(size: 10))
                }
                .progressViewStyle(.circular)
                .tint(context.state.color == "red" ? Color.red : Color.blue)
                
            } minimal: {
//                Text(context.state.emoji)
                ProgressView(value: 1){
                    Text(context.state.currentGlucose)
                }
                .progressViewStyle(.circular)
                .tint(context.state.color == "red" ? Color.red : Color.blue)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}
 
struct DiaBLE_LiveActivitiesAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var lastReadingDate: String?
        var minuteSinceLastReading: String?
        var currentGlucose: String
        var alarmHigh: Int
        var alarmLow: Int
        var color: String
        
        var appState: String
        var sensorStateDescription: String
        var sensorStateColor: String
        
        var glycemicAlarmDescription: String
        var trendArrowDescription: String
        var arrowColor: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

extension DiaBLE_LiveActivitiesAttributes {
    fileprivate static var preview: DiaBLE_LiveActivitiesAttributes {
        DiaBLE_LiveActivitiesAttributes(name: "World")
    }
}

//extension DiaBLE_LiveActivitiesAttributes.ContentState {
//    fileprivate static var smiley: DiaBLE_LiveActivitiesAttributes.ContentState {
//        DiaBLE_LiveActivitiesAttributes.ContentState(emoji: "😀")
//     }
//     
//     fileprivate static var starEyes: DiaBLE_LiveActivitiesAttributes.ContentState {
//         DiaBLE_LiveActivitiesAttributes.ContentState()
//     }
//}

//#Preview("Notification", as: .content, using: DiaBLE_LiveActivitiesAttributes.preview) {
//   DiaBLE_LiveActivitiesLiveActivity()
//} contentStates: {
//    DiaBLE_LiveActivitiesAttributes.ContentState.smiley
//    DiaBLE_LiveActivitiesAttributes.ContentState.starEyes
//}
