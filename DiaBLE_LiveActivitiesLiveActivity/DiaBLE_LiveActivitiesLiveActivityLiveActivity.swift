//
//  DiaBLE_LiveActivitiesLiveActivityLiveActivity.swift
//  DiaBLE_LiveActivitiesLiveActivity
//
//  Created by Marian Dugaesescu on 17/11/2023.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct DiaBLE_LiveActivitiesLiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct DiaBLE_LiveActivitiesLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DiaBLE_LiveActivitiesLiveActivityAttributes.self) { context in
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

extension DiaBLE_LiveActivitiesLiveActivityAttributes {
    fileprivate static var preview: DiaBLE_LiveActivitiesLiveActivityAttributes {
        DiaBLE_LiveActivitiesLiveActivityAttributes(name: "World")
    }
}

extension DiaBLE_LiveActivitiesLiveActivityAttributes.ContentState {
    fileprivate static var smiley: DiaBLE_LiveActivitiesLiveActivityAttributes.ContentState {
        DiaBLE_LiveActivitiesLiveActivityAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: DiaBLE_LiveActivitiesLiveActivityAttributes.ContentState {
         DiaBLE_LiveActivitiesLiveActivityAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: DiaBLE_LiveActivitiesLiveActivityAttributes.preview) {
   DiaBLE_LiveActivitiesLiveActivityLiveActivity()
} contentStates: {
    DiaBLE_LiveActivitiesLiveActivityAttributes.ContentState.smiley
    DiaBLE_LiveActivitiesLiveActivityAttributes.ContentState.starEyes
}
