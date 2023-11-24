#if canImport(ActivityKit)

import ActivityKit
import WidgetKit
import SwiftUI

struct DiaBLEWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct DiaBLEWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DiaBLEWidgetAttributes.self) { context in
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

extension DiaBLEWidgetAttributes {
    fileprivate static var preview: DiaBLEWidgetAttributes {
        DiaBLEWidgetAttributes(name: "World")
    }
}

extension DiaBLEWidgetAttributes.ContentState {
    fileprivate static var smiley: DiaBLEWidgetAttributes.ContentState {
        DiaBLEWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: DiaBLEWidgetAttributes.ContentState {
         DiaBLEWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: DiaBLEWidgetAttributes.preview) {
   DiaBLEWidgetLiveActivity()
} contentStates: {
    DiaBLEWidgetAttributes.ContentState.smiley
    DiaBLEWidgetAttributes.ContentState.starEyes
}

#endif
