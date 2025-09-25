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
        ScrollView {

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
                        // .font(.caption.monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .onReceive(app.timer) { _ in
                            withAnimation {
                                readingCountdown = Int64(settings.readingInterval * 60) - Int64(Date().timeIntervalSince(app.lastConnectionDate))
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
            }

            if history.factoryTrend.count + history.rawTrend.count > 0 {
                HStack {

                    VStack {

                        if history.factoryTrend.count > 0 {
                            VStack(spacing: 4) {
                                Text("Trend").bold()
                                List {
                                    ForEach(history.factoryTrend) { glucose in
                                        (Text("\(glucose.id) \(glucose.date.shortDateTime)**\(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ")**")).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .foregroundStyle(.orange)
                        }

                    }

                    VStack {

                        if history.rawTrend.count > 0 {
                            VStack(spacing: 4) {
                                Text("Raw trend").bold()
                                List {
                                    ForEach(history.rawTrend) { glucose in
                                        (Text("\(glucose.id) \(glucose.date.shortDateTime)**\(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ")**")).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .foregroundStyle(.yellow)
                        }

                    }
                }
                .frame(idealHeight: 300)
            }


            HStack {

                if history.storedValues.count > 0 {
                    VStack(spacing: 4) {
                        Text("HealthKit").bold()
                        List {
                            ForEach(history.storedValues) { glucose in
                                (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)**  \(glucose.value, specifier: "%3d")**"))
                                    .fixedSize(horizontal: false, vertical: true)
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
                                (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)**  \(glucose.value, specifier: "%3d")**"))
                                    .fixedSize(horizontal: false, vertical: true)
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
            .frame(idealHeight: 300)

            HStack {

                VStack {

                    if history.values.count > 0 {
                        VStack(spacing: 4) {
                            Text("OOP history").bold()
                            List {
                                ForEach(history.values) { glucose in
                                    (Text("\(glucose.id) \(glucose.date.shortDateTime)**\(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ")**")).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .foregroundStyle(.blue)
                    }

                    if history.factoryValues.count > 0 {
                        VStack(spacing: 4) {
                            Text("History").bold()
                            List {
                                ForEach(history.factoryValues) { glucose in
                                    (Text("\(glucose.id) \(glucose.date.shortDateTime)**\(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ")**")).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }.frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .foregroundStyle(.orange)
                    }

                }

                if history.rawValues.count > 0 {
                    VStack(spacing: 4) {
                        Text("Raw history").bold()
                        List {
                            ForEach(history.rawValues) { glucose in
                                (Text("\(glucose.id) \(glucose.date.shortDateTime)**\(glucose.value > -1 ? "  \(glucose.value, specifier: "%3d")" : "   … ")**")).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .foregroundStyle(.yellow)
                }
            }
            .frame(idealHeight: 300)

        }
        .padding(.top, -4)
        .edgesIgnoringSafeArea([.bottom])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // .font(.system(.footnote, design: .monospaced)).foregroundStyle(Color(.lightGray))
        .font(.footnote)
        .navigationTitle { Text("Data").foregroundStyle(.tint) }
        .toolbarForegroundStyle(.blue, for: .automatic)
        .tint(.blue)
    }
}


#Preview {
    DataView()
        .environment(AppState.test(tab: .data))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
