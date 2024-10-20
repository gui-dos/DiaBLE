import Foundation
import SwiftUI


struct Monitor: View, LoggingView {
    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    @Environment(\.dismiss) var dismiss

    @State private var readingCountdown: Int = 0
    @State private var minutesSinceLastReading: Int = 0

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {

        ScrollView {

            VStack(spacing: 0) {

                VStack(spacing: 0) {

                    HStack {

                        VStack(spacing: 0) {
                            if app.lastReadingDate != Date.distantPast {
                                Text(app.lastReadingDate.shortTime)
                                    .monospacedDigit()
                                Text("\(minutesSinceLastReading) min ago")
                                    .font(.system(size: 10))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .onReceive(minuteTimer) { _ in
                                        minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate) / 60)
                                    }
                            } else {
                                Text("---")
                            }
                        }
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .trailing )
                        .foregroundStyle(Color(.lightGray))
                        .onChange(of: app.lastReadingDate) {
                            minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate) / 60)
                        }

                        Text(app.currentGlucose > 0 ? "\(app.currentGlucose.units)" : "---")
                            .font(.system(size: 26, weight: .black))
                            .monospacedDigit()
                            // avoid truncation in 40 mm models
                            .scaledToFill()
                            .minimumScaleFactor(0.85)
                            .foregroundStyle(.black)
                            .padding(.vertical, 0)
                            .padding(.horizontal, 4)
                            .background(app.currentGlucose > 0 && (app.currentGlucose > Int(settings.alarmHigh) || app.currentGlucose < Int(settings.alarmLow)) ?
                                        .red : .blue)
                            .cornerRadius(6)

                        // TODO: display both delta and trend arrow
                        Group {
                            if app.trendDeltaMinutes > 0 {
                                VStack(spacing: -6) {
                                    Text("\(app.trendDelta > 0 ? "+ " : app.trendDelta < 0 ? "- " : "")\(app.trendDelta == 0 ? "→" : abs(app.trendDelta).units)")
                                        .fontWeight(.black)
                                        .fixedSize()
                                    Text("\(app.trendDeltaMinutes)m")
                                        .font(.footnote)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 10)
                            } else {
                                Text(app.trendArrow.symbol)
                                    .font(.system(size: 28))
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 10)
                            }
                        }
                        .foregroundStyle(app.currentGlucose > 0 && ((app.currentGlucose > Int(settings.alarmHigh) && (app.trendDelta > 0 || app.trendArrow == .rising || app.trendArrow == .risingQuickly)) || (app.currentGlucose < Int(settings.alarmLow) && (app.trendDelta < 0 || app.trendArrow == .falling || app.trendArrow == .fallingQuickly))) ?
                            .red : .blue)

                    }

                    if app.glycemicAlarm.description.count + app.trendArrow.description.count != 0 {
                        Text("\(app.glycemicAlarm.description.replacingOccurrences(of: "_", with: " "))\(app.glycemicAlarm.description != "" ? " - " : "")\(app.trendArrow.description.replacingOccurrences(of: "_", with: " "))")
                            .font(.footnote).foregroundStyle(app.currentGlucose > 0 && ((app.currentGlucose > Int(settings.alarmHigh) && (app.trendDelta > 0 || app.trendArrow == .rising || app.trendArrow == .risingQuickly)) || (app.currentGlucose < Int(settings.alarmLow) && (app.trendDelta < 0 || app.trendArrow == .falling || app.trendArrow == .fallingQuickly))) ?
                                .red : .blue).lineLimit(1)
                            .padding(.vertical, -3)
                    }

                    HStack {
                        if !app.deviceState.isEmpty {
                            Text(app.deviceState)
                                .foregroundStyle(app.deviceState == "Connected" ? .green : .red)
                                .font(.footnote)
                                .fixedSize()
                        }
                        if !app.deviceState.isEmpty && app.deviceState != "Disconnected" {
                            Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                                 "\(readingCountdown) s" : "")
                            .fixedSize()
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.orange)
                            .onReceive(timer) { _ in
                                // workaround: watchOS fails converting the interval to an Int32
                                if app.lastConnectionDate == Date.distantPast {
                                    readingCountdown = 0
                                } else {
                                    readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastConnectionDate))
                                }
                            }
                        }
                    }
                }

                Graph()
                    .frame(width: 31 * 4 + 60, height: 80)
                    .padding(.vertical, 2)

                HStack(spacing: 2) {

                    if app.sensor != nil && (app.sensor.state != .unknown || app.sensor.serial != "") {
                        VStack(spacing: -4) {
                            Text(app.sensor.state.description)
                                .foregroundStyle(app.sensor.state == .active ? .green : .red)

                            if app.sensor.age > 0 {
                                Text(app.sensor.age.shortFormattedInterval)
                            }
                        }
                    }

                    if app.device != nil && (app.device.battery > -1 || app.device.rssi != 0) {
                        VStack(spacing: -4) {
                            if app.device.battery > -1 {
                                let battery = app.device.battery
                                HStack(spacing: 4) {
                                    let ext = battery > 95 ? 100 :
                                    battery > 65 ? 75 :
                                    battery > 35 ? 50 :
                                    battery > 10 ? 25 : 0
                                    Image(systemName: "battery.\(ext)percent")
                                    Text("\(app.device.battery)%")
                                }
                                .foregroundStyle(app.device.battery > 10 ? .green : .red)
                            }
                            if app.device.rssi != 0 {
                                Text("RSSI: ").foregroundStyle(Color(.lightGray)) +
                                Text("\(app.device.rssi) dB")
                            }
                        }
                    }

                }
                .font(.footnote)
                .foregroundStyle(.yellow)

                HStack {

                    Spacer()
                    Spacer()

                    Button {
                        app.main.rescan()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 16, height: 16)
                            .foregroundStyle(.blue)
                    }
                    .frame(height: 16)

                    if (app.status.hasPrefix("Scanning") || app.status.hasSuffix("retrying...")) && app.main.centralManager.state != .poweredOff {
                        Spacer()
                        Button {
                            app.main.centralManager.stopScan()
                            app.main.status("Stopped scanning")
                            log("Bluetooth: stopped scanning")
                        } label: {
                            Image(systemName: "stop.circle").resizable().frame(width: 16, height: 16)
                                .foregroundStyle(.red)
                        }
                        .frame(height: 16)
                    }

                    Spacer()

                    NavigationLink(destination: Details()) {
                        Image(systemName: "info.circle").resizable().frame(width: 16, height: 16)
                            .foregroundStyle(.blue)
                    }
                    .frame(height: 16)

                    Spacer()
                    Spacer()
                }

                Text(app.status.hasPrefix("Scanning") ? app.status : app.status.replacingOccurrences(of: "\n", with: " "))
                    .font(.footnote)
                    .lineLimit(app.status.hasPrefix("Scanning") ? 3 : 1)
                    .truncationMode(app.status.hasPrefix("Scanning") ?.tail : .head)
                    .frame(maxWidth: .infinity)

            }

        }
        .edgesIgnoringSafeArea([.bottom])
        .padding(.top, -26)
        .buttonStyle(.plain)
        .multilineTextAlignment(.center)
        // .navigationTitle { Text("Monitor").foregroundStyle(.tint) }
        .tint(.blue)
        .onAppear {
            timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
            if app.lastReadingDate != Date.distantPast {
                minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate)/60)
            }
        }
        .onDisappear {
            timer.upstream.connect().cancel()
            minuteTimer.upstream.connect().cancel()
        }
        // TODO:
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(destination: HamburgerMenu()) {
                    Image(systemName: "line.horizontal.3")
                        .foregroundStyle(.blue)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    settings.caffeinated.toggle()
                    // UIApplication.shared.isIdleTimerDisabled = settings.caffeinated
                } label: {
                    Image(systemName: settings.caffeinated ? "cup.and.saucer.fill" : "cup.and.saucer")
                        .foregroundStyle(.blue)
                }
                    .hidden() // trick to center time
            }

        }
    }
}


#Preview {
    Monitor()
        .environment(AppState.test(tab: .monitor))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
