//
//  DiaBLE_LiveActivitiesLiveActivity.swift
//  DiaBLE_LiveActivities
//
//  Created by Marian Dugaesescu on 17/11/2023.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct DiaBLE_LiveActivitiesAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct DiaBLE_LiveActivitiesLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DiaBLE_LiveActivitiesAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension DiaBLE_LiveActivitiesAttributes {
    fileprivate static var preview: DiaBLE_LiveActivitiesAttributes {
        DiaBLE_LiveActivitiesAttributes(name: "World")
    }
}

extension DiaBLE_LiveActivitiesAttributes.ContentState {
    fileprivate static var smiley: DiaBLE_LiveActivitiesAttributes.ContentState {
        DiaBLE_LiveActivitiesAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: DiaBLE_LiveActivitiesAttributes.ContentState {
         DiaBLE_LiveActivitiesAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: DiaBLE_LiveActivitiesAttributes.preview) {
   DiaBLE_LiveActivitiesLiveActivity()
} contentStates: {
    DiaBLE_LiveActivitiesAttributes.ContentState.smiley
    DiaBLE_LiveActivitiesAttributes.ContentState.starEyes
}
