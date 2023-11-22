import WidgetKit
import SwiftUI

@main
struct DiaBLEWidgetBundle: WidgetBundle {
    var body: some Widget {
        DiaBLEWidget()
        DiaBLEWidgetLiveActivity()
    }
}
