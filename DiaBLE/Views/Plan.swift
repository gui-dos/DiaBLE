import Foundation
import SwiftUI


struct Plan: View {
    @Environment(AppState.self) var app: AppState
    @Environment(History.self) var history: History
    @Environment(Log.self) var log: Log
    @Environment(Settings.self) var settings: Settings

    @State private var onlineCountdown: Int64 = 0
    @State private var readingCountdown: Int64 = 0


    var body: some View {
        NavigationStack {
            VStack {

                Text("\((app.lastReadingDate != Date.distantPast ? app.lastReadingDate : Date()).dateTime)")


                if app.status.hasPrefix("Scanning") {
                    Text("Scanning...")
                        .foregroundStyle(.orange)
                } else {
                    HStack {
                        if !app.deviceState.isEmpty && app.deviceState != "Connected" {
                            Text(app.deviceState)
                                .foregroundStyle(.red)
                        }
                        Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                             "\(readingCountdown) s" : " ")
                        .foregroundStyle(.orange)
                        .contentTransition(.numericText(countsDown: true))
                        .onReceive(app.timer) { _ in
                            withAnimation {
                                readingCountdown = Int64(settings.readingInterval * 60) - Int64(Date().timeIntervalSince(app.lastConnectionDate))
                            }
                        }
                    }
                }

                Text(onlineCountdown != 0 ? "\(String(onlineCountdown).count > 5 ? "..." : "\(onlineCountdown) s")" : " ")
                    .foregroundStyle(.cyan)
                    .contentTransition(.numericText(countsDown: true))
                    .onReceive(app.timer) { _ in
                        withAnimation {
                            onlineCountdown = Int64(settings.onlineInterval * 60) - Int64(Date().timeIntervalSince(settings.lastOnlineDate))
                        }
                    }
                    .onReceive(app.minuteTimer) { _ in
                        Task {
                            await app.main.libreLinkUp?.reload()
                        }
                    }
            }
            .monospacedDigit()
            #if targetEnvironment(macCatalyst)
            .padding(.horizontal, 15)
            #endif
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Plan")
        }
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
