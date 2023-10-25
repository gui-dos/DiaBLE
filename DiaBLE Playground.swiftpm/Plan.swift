import Foundation
import SwiftUI


struct Plan: View {
    @Environment(AppState.self) var app: AppState
    @Environment(History.self) var history: History
    @Environment(Log.self) var log: Log
    @Environment(Settings.self) var settings: Settings

    @State private var readingCountdown: Int = 0

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()


    var body: some View {
        NavigationView {
            VStack {
                Text("\((app.lastReadingDate != Date.distantPast ? app.lastReadingDate : Date()).dateTime)")
                if app.status.hasPrefix("Scanning") {
                    Text("Scanning...").foregroundColor(.orange)
                } else if !app.deviceState.isEmpty && app.deviceState != "Connected" {
                    Text(app.deviceState).foregroundColor(.red)
                } else {
                    Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                            "\(readingCountdown) s" : "")
                        .fixedSize()
                        .font(Font.caption.monospacedDigit()).foregroundColor(.orange)
                        .onReceive(timer) { _ in
                            readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastConnectionDate))
                        }
                }
            }
#if targetEnvironment(macCatalyst)
            .padding(.horizontal, 15)
#endif
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Plan")
        }.navigationViewStyle(.stack)
    }
}


struct Plan_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            ContentView()
                .preferredColorScheme(.dark)
                .environment(AppState.test(tab: .plan))
                .environment(Log())
                .environment(History.test)
                .environment(Settings())
        }
    }
}
