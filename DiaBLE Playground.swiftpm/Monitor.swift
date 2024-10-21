import Foundation
import SwiftUI


struct Monitor: View, LoggingView {
    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    @State private var showingCalibrationParameters = false
    @State private var editingCalibration = false

    @State private var showingNFCAlert = false

    @State private var readingCountdown: Int64 = 0
    @State private var minutesSinceLastReading: Int = 0
    @State private var onlineCountdown: Int64 = 0


    var body: some View {
        NavigationView {

            ZStack(alignment: .topLeading) {

                VStack {

                    if !(editingCalibration && showingCalibrationParameters)  {
                        Spacer()
                    }

                    VStack {

                        HStack {

                            VStack {
                                if app.lastReadingDate != Date.distantPast {
                                    Text(app.lastReadingDate.shortTime)
                                        .monospacedDigit()
                                    Text("\(minutesSinceLastReading) min ago")
                                        .font(.footnote)
                                        .monospacedDigit()
                                        .onReceive(app.minuteTimer) { _ in
                                            minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate) / 60)
                                        }
                                } else {
                                    Text("---")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.trailing, 12)
                            .foregroundStyle(Color(.lightGray))
                            .onChange(of: app.lastReadingDate) {
                                minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate) / 60)
                            }

                            Text(app.currentGlucose > 0 ? "\(app.currentGlucose.units) " : "--- ")
                                .font(.system(size: 42, weight: .black))
                                .monospacedDigit()
                                .foregroundStyle(.black)
                                .padding(5)
                                .background(app.currentGlucose > 0 && (app.currentGlucose > Int(settings.alarmHigh) || app.currentGlucose < Int(settings.alarmLow)) ?
                                            .red : .blue)
                                .cornerRadius(8)

                            // TODO: display both delta and trend arrow
                            Group {
                                if app.trendDeltaMinutes > 0 {
                                    VStack {
                                        Text("\(app.trendDelta > 0 ? "+ " : app.trendDelta < 0 ? "- " : "")\(app.trendDelta == 0 ? "→" : abs(app.trendDelta).units)")
                                            .fontWeight(.black)
                                        Text("\(app.trendDeltaMinutes) min")
                                            .font(.footnote)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 12)
                                } else {
                                    Text(app.trendArrow.symbol)
                                        .font(.largeTitle)
                                        .bold()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 12)
                                }
                            }
                            .foregroundStyle(app.currentGlucose > 0 && ((app.currentGlucose > Int(settings.alarmHigh) && (app.trendDelta > 0 || app.trendArrow == .rising || app.trendArrow == .risingQuickly)) || (app.currentGlucose < Int(settings.alarmLow) && (app.trendDelta < 0 || app.trendArrow == .falling || app.trendArrow == .fallingQuickly))) ?
                                .red : .blue)

                        }

                        Text("\(app.glycemicAlarm.description.replacingOccurrences(of: "_", with: " "))\(app.glycemicAlarm.description != "" ? " - " : "")\(app.trendArrow.description.replacingOccurrences(of: "_", with: " "))")
                            .foregroundStyle(app.currentGlucose > 0 && ((app.currentGlucose > Int(settings.alarmHigh) && (app.trendDelta > 0 || app.trendArrow == .rising || app.trendArrow == .risingQuickly)) || (app.currentGlucose < Int(settings.alarmLow) && (app.trendDelta < 0 || app.trendArrow == .falling || app.trendArrow == .fallingQuickly))) ?
                                .red : .blue)

                        HStack {
                            Text(app.deviceState)
                                .foregroundStyle(app.deviceState == "Connected" ? .green : .red)
                                .fixedSize()

                            if !app.deviceState.isEmpty && app.deviceState != "Disconnected" {
                                Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                                     "\(readingCountdown) s" : "")
                                .fixedSize()
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.orange)
                                .onReceive(app.timer) { _ in
                                    readingCountdown = Int64(settings.readingInterval * 60) - Int64(Date().timeIntervalSince(app.lastConnectionDate))
                                }
                            }
                            Text(onlineCountdown != 0 ? "\(onlineCountdown) s" : " ")
                                .fixedSize()
                                .font(.callout.monospacedDigit())
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
                    }

                    Graph()
                        .frame(width: 31 * 7 + 60, height: 150)

                    if !(editingCalibration && showingCalibrationParameters) {

                        VStack {

                            HStack(spacing: 12) {

                                if app.sensor != nil && (app.sensor.state != .unknown || app.sensor.serial != "") {
                                    VStack {
                                        Text(app.sensor.state.description)
                                            .foregroundStyle(app.sensor.state == .active ? .green : .red)

                                        if app.sensor.age > 0 {
                                            Text(app.sensor.age.shortFormattedInterval)
                                        }
                                    }
                                }

                                if app.device != nil && (app.device.battery > -1 || app.device.rssi != 0) {
                                    VStack {
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

                            Text(app.status)
                                .font(.footnote)
                                .padding(.vertical, 5)
                                .frame(maxWidth: .infinity)

                            NavigationLink(destination: Details()) {
                                Text("Details")
                                    .font(.footnote)
                                    .bold()
                                    .fixedSize()
                                    .padding(.horizontal, 4)
                                    .padding(2)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                            }
                        }

                        Spacer()
                        Spacer()

                    }

                    VStack {

                        HStack {

                            @Bindable var settings = settings

                            Toggle(isOn: $settings.usingOOP.animation()) {
                                Text("OOP")
                            }
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                            .onChange(of: settings.usingOOP) {
                                Task {
                                    await app.main.applyOOP(sensor: app.sensor)
                                    app.main.didParseSensor(app.sensor)
                                }
                            }

                        }

                        CalibrationView(showingCalibrationParameters: $showingCalibrationParameters, editingCalibration: $editingCalibration)

                    }
                    #if targetEnvironment(macCatalyst)
                    .padding(.horizontal, 15)
                    #endif

                    Spacer()
                    Spacer()

                    HStack {

                        Button {
                            app.main.rescan()

                        } label: {
                            Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 32, height: 32)
                                .padding(.bottom, 8)
                                .foregroundStyle(.tint)
                        }

                        if (app.status.hasPrefix("Scanning") || app.status.hasSuffix("retrying...")) && app.main.centralManager.state != .poweredOff {
                            Button {
                                app.main.centralManager.stopScan()
                                app.main.status("Stopped scanning")
                                log("Bluetooth: stopped scanning")
                            } label: {
                                Image(systemName: "stop.circle").resizable().frame(width: 32, height: 32)
                            }
                            .padding(.bottom, 8)
                            .foregroundStyle(.red)
                        }

                    }

                }
                .multilineTextAlignment(.center)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Monitor")
                .onAppear {
                    if app.lastReadingDate != Date.distantPast {
                        minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate) / 60)
                    }
                }
                .toolbar {

                    ToolbarItem(placement: .navigation) {
                        Button {
                            settings.caffeinated.toggle()
                            UIApplication.shared.isIdleTimerDisabled = settings.caffeinated
                        } label: {
                            Image(systemName: settings.caffeinated ? "cup.and.saucer.fill" : "cup.and.saucer" )
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if app.main.nfc.isAvailable {
                                app.main.nfc.startSession()
                            } else {
                                showingNFCAlert = true
                            }
                        } label: {
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                .symbolEffect(.variableColor.reversing, isActive: app.deviceState == "Connected")
                        }
                    }
                }
                .alert("NFC not supported", isPresented: $showingNFCAlert) {
                } message: {
                    Text("This device doesn't allow scanning the Libre.")
                }

                HamburgerMenu()
            }
        }
        .navigationViewStyle(.stack)
    }
}


struct CalibrationView: View {

    @Environment(AppState.self) var app: AppState
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    @Binding var showingCalibrationParameters: Bool
    @Binding var editingCalibration: Bool

    func endEditingCalibration() {
        withAnimation { editingCalibration = false }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

    }

    var body: some View {
        VStack(spacing: 0) {

            @Bindable var settings = settings

            Toggle(isOn: $settings.calibrating.animation()) {
                Text("Calibration")
            }
            .toggleStyle(SwitchToggleStyle(tint: .purple))
            .onChange(of: settings.calibrating) {

                if !settings.calibrating {
                    withAnimation {
                        editingCalibration = false
                    }
                }
                app.main.didParseSensor(app.sensor)
            }

            if settings.calibrating {

                @Bindable var app = app

                DisclosureGroup(isExpanded: $showingCalibrationParameters) {

                    VStack(spacing: 6) {
                        HStack {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Slope slope:")
                                    TextField("Slope slope", value: $app.calibration.slopeSlope,
                                              formatter: settings.numberFormatter) { editing in
                                        if !editing {
                                            // TODO: update when loosing focus
                                        }
                                    }
                                              .foregroundStyle(.purple)
                                              .keyboardType(.numbersAndPunctuation)
                                              .onTapGesture { withAnimation { editingCalibration = true } }
                                }
                                if editingCalibration {
                                    Slider(value: $app.calibration.slopeSlope, in: 0.00001 ... 0.00002, step: 0.00000005)
                                }
                            }

                            VStack(spacing: 0) {
                                HStack {
                                    Text("Slope offset:")
                                    TextField("Slope offset", value: $app.calibration.offsetSlope,
                                              formatter: settings.numberFormatter) { editing in
                                        if !editing {
                                            // TODO: update when loosing focus
                                        }
                                    }
                                              .foregroundStyle(.purple)
                                              .keyboardType(.numbersAndPunctuation)
                                              .onTapGesture { withAnimation { editingCalibration = true } }
                                }
                                if editingCalibration {
                                    Slider(value: $app.calibration.offsetSlope, in: -0.02 ... 0.02, step: 0.0001)
                                }
                            }
                        }

                        HStack {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("Offset slope:")
                                    TextField("Offset slope", value: $app.calibration.slopeOffset,
                                              formatter: settings.numberFormatter) { editing in
                                        if !editing {
                                            // TODO: update when loosing focus
                                        }
                                    }
                                              .foregroundStyle(.purple)
                                              .keyboardType(.numbersAndPunctuation)
                                              .onTapGesture { withAnimation { editingCalibration = true } }
                                }
                                if editingCalibration {
                                    Slider(value: $app.calibration.slopeOffset, in: -0.01 ... 0.01, step: 0.00005)
                                }
                            }

                            VStack(spacing: 0) {
                                HStack {
                                    Text("Offset offset:")
                                    TextField("Offset offset", value: $app.calibration.offsetOffset,
                                              formatter: settings.numberFormatter) { editing in
                                        if !editing {
                                            // TODO: update when loosing focus
                                        }
                                    }
                                              .foregroundStyle(.purple)
                                              .keyboardType(.numbersAndPunctuation)
                                              .onTapGesture {  withAnimation { editingCalibration = true } }
                                }
                                if editingCalibration {
                                    Slider(value: $app.calibration.offsetOffset, in: -100 ... 100, step: 0.5)
                                }
                            }
                        }
                    }
                    .font(.footnote)
                    .keyboardType(.numbersAndPunctuation)

                    if editingCalibration || history.calibratedValues.count == 0 {
                        Spacer()
                        HStack(spacing: 20) {

                            if editingCalibration {
                                Button {
                                    endEditingCalibration()
                                } label: {
                                    Text("Use")
                                        .bold()
                                        .padding(.horizontal, 4)
                                        .padding(2)
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                                }

                                if app.calibration != settings.calibration && app.calibration != settings.oopCalibration {
                                    Button {
                                        endEditingCalibration()
                                        settings.calibration = app.calibration
                                    } label: {
                                        Text("Save")
                                            .bold(
                                            ).padding(.horizontal, 4)
                                            .padding(2)
                                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                                    }
                                }
                            }

                            if settings.calibration != .empty && (app.calibration != settings.calibration || app.calibration == .empty) {
                                Button {
                                    endEditingCalibration()
                                    app.calibration = settings.calibration
                                } label: {
                                    Text("Load")
                                        .bold()
                                        .padding(.horizontal, 4)
                                        .padding(2)
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                                }
                            }

                            if settings.oopCalibration != .empty && ((app.calibration != settings.oopCalibration && editingCalibration) || app.calibration == .empty) {
                                Button {
                                    endEditingCalibration()
                                    app.calibration = settings.oopCalibration
                                    settings.calibration = Calibration()
                                } label: {
                                    Text("Restore OOP")
                                        .bold()
                                        .padding(.horizontal, 4)
                                        .padding(2)
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                                }
                            }

                        }
                        .font(.footnote)
                    }

                } label: {
                    Button {
                        withAnimation { showingCalibrationParameters.toggle() }
                    } label: {
                        Text("Parameters")
                    }
                    .foregroundStyle(.purple)
                }

            }

        }
        .tint(.purple)
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .monitor))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
