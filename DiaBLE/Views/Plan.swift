import Foundation
import SwiftUI


struct Plan: View {
    @Environment(AppState.self) var app: AppState
    @Environment(History.self) var history: History
    @Environment(Log.self) var log: Log
    @Environment(Settings.self) var settings: Settings

    @State private var onlineCountdown: Int = 0
    @State private var readingCountdown: Int = 0

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()


    var body: some View {
        NavigationView {
            VStack {

                Text("\((app.lastReadingDate != Date.distantPast ? app.lastReadingDate : Date()).dateTime)")


                if app.status.hasPrefix("Scanning") {
                    Text("Scanning...").foregroundColor(.orange)
                } else {
                    HStack {
                        if !app.deviceState.isEmpty && app.deviceState != "Connected" {
                            Text(app.deviceState).foregroundColor(.red)
                        }
                        Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                             "\(readingCountdown) s" : " ")
                        .foregroundColor(.orange)
                        .onReceive(timer) { _ in
                            readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastConnectionDate))
                        }
                    }
                }

                Text(onlineCountdown > 0 ? "\(onlineCountdown) s" : "")
                    .foregroundColor(.cyan)
                    .onReceive(timer) { _ in
                        onlineCountdown = settings.onlineInterval * 60 - Int(Date().timeIntervalSince(settings.lastOnlineDate))
                    }
            }
            .monospacedDigit()
            #if targetEnvironment(macCatalyst)
            .padding(.horizontal, 15)
            #endif
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Plan")
        }.navigationViewStyle(.stack)
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .plan))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
