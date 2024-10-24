import WidgetKit
import SwiftUI

@main
struct DiaBLEWidgetBundle: WidgetBundle {
    var body: some Widget {
        DiaBLEWidget()
        #if canImport(ActivityKit)  && !targetEnvironment(macCatalyst) // TODO: Catalyst support
        DiaBLEWidgetLiveActivity()
        #endif
    }
}
