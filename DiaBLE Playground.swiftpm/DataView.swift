import Foundation
import SwiftUI


struct DataView: View, LoggingView {
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

                HStack {

                    if app.status.hasPrefix("Scanning") && !(readingCountdown > 0) {
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
                            .onReceive(app.timer) { _ in
                                readingCountdown = Int64(settings.readingInterval * 60) - Int64(Date().timeIntervalSince(app.lastConnectionDate))
                            }
                        }
                    }

                    Text(onlineCountdown != 0 ? "\(String(onlineCountdown).count > 5 ? "..." : "\(onlineCountdown) s")" : " ")
                        .foregroundStyle(.cyan)
                        .onReceive(app.timer) { _ in
                            onlineCountdown = Int64(settings.onlineInterval * 60) - Int64(Date().timeIntervalSince(settings.lastOnlineDate))
                        }
                        .onReceive(app.minuteTimer) { _ in
                            Task {
                                await app.main.libreLinkUp?.reload()
                            }
                        }
                }

                VStack {

                    HStack {

                        VStack {

                            if history.values.count > 0 {
                                VStack(spacing: 4) {
                                    Text("OOP history").bold()
                                    ScrollView {
                                        ForEach(history.values) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .foregroundStyle(.blue)
                            }

                            if history.factoryValues.count > 0 {
                                VStack(spacing: 4) {
                                    Text("History").bold()
                                    ScrollView {
                                        ForEach(history.factoryValues) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .foregroundStyle(.orange)
                            }

                        }

                        if history.rawValues.count > 0 {
                            VStack(spacing: 4) {
                                Text("Raw history").bold()
                                ScrollView {
                                    ForEach(history.rawValues) { glucose in
                                        (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .foregroundStyle(.yellow)
                        }
                    }

                    HStack {

                        VStack {

                            if history.factoryTrend.count > 0 {
                                VStack(spacing: 4) {
                                    Text("Trend").bold()
                                    ScrollView {
                                        ForEach(history.factoryTrend) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .foregroundStyle(.orange)
                            }

                            if history.calibratedValues.count > 0 {
                                VStack(spacing: 4) {
                                    Text("Calibrated history").bold()
                                    ScrollView {
                                        ForEach(history.calibratedValues) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .foregroundStyle(.purple)
                            }

                        }

                        VStack {

                            if history.rawTrend.count > 0 {
                                VStack(spacing: 4) {
                                    Text("Raw trend").bold()
                                    ScrollView {
                                        ForEach(history.rawTrend) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .foregroundStyle(.yellow)
                            }

                            if history.calibratedTrend.count > 0 {
                                VStack(spacing: 4) {
                                    Text("Calibrated trend").bold()
                                    ScrollView {
                                        ForEach(history.calibratedTrend) { glucose in
                                            (Text("\(glucose.id) \(glucose.date.shortDateTime)") + Text(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ").bold())
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .foregroundStyle(.purple)
                            }

                        }
                    }

                    HStack(spacing: 0) {

                        if history.storedValues.count > 0 {
                            VStack(spacing: 4) {
                                Text("HealthKit").bold()
                                List {
                                    ForEach(history.storedValues) { glucose in
                                        (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d")").bold())
                                            .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets()).listRowInsets(EdgeInsets())
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .foregroundStyle(.red)
                            .onAppear { if let healthKit = app.main?.healthKit { healthKit.read() } }
                        }

                        if history.nightscoutValues.count > 0 {
                            VStack(spacing: 4) {
                                Text("Nightscout").bold()
                                List {
                                    ForEach(history.nightscoutValues) { glucose in
                                        (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d")").bold())
                                            .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets())
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            }
                            .foregroundStyle(.cyan)
                            .task {
                                if let (values, _) = try? await app.main.nightscout?.read() {
                                    history.nightscoutValues = values
                                    log("Nightscout: values read count \(history.nightscoutValues.count)")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
#if targetEnvironment(macCatalyst)
                .padding(.leading, 15)
#endif
            }
            .font(.system(.caption, design: .monospaced))
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Data")

        }
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .data))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
