import Foundation
import SwiftUI


struct SettingsView: View, LoggingView {
    @Environment(AppState.self) var app: AppState
    @Environment(Settings.self) var settings: Settings

    @Environment(\.colorScheme) var colorScheme

    @State private var showingCalendarPicker = false

    @State var showingAllDefaults = false


    var body: some View {

        @Bindable var settings = settings

        NavigationView {
            VStack {

                Spacer()

                VStack(spacing: 20) {
                    VStack {
                        HStack(spacing: 0) {

                            Button {
                                settings.stoppedBluetooth.toggle()
                                if settings.stoppedBluetooth {
                                    app.main.centralManager.stopScan()
                                    if let device = app.device {
                                        app.main.centralManager.cancelPeripheralConnection(device.peripheral!)
                                        app.main.status("Stopped connection")
                                    } else {
                                        app.main.status("Stopped scanning")
                                        log("Bluetooth: stopped scanning")
                                    }
                                } else {
                                    app.main.rescan()
                                }
                            } label: {
                                Image("Bluetooth").renderingMode(.template).resizable().frame(width: 32, height: 32)
                                    .foregroundStyle(.blue)
                                    .overlay(settings.stoppedBluetooth ? Image(systemName: "line.diagonal").resizable().frame(width: 24, height: 24).rotationEffect(.degrees(90)) : nil).foregroundStyle(.red)
                            }

                            Picker(selection: $settings.preferredTransmitter, label: Text("Preferred")) {
                                ForEach(TransmitterType.allCases) { t in
                                    Text(t.name).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(settings.stoppedBluetooth)
                        }
                        HStack(spacing: 0) {
                            Button {
                            } label: {
                                Image(systemName: "line.horizontal.3.decrease.circle").resizable().frame(width: 20, height: 20).padding(.leading, 6)
                            }
                            TextField("device name pattern", text: $settings.preferredDevicePattern)
                                .padding(.horizontal, 12)
                                .frame(alignment: .center)
                        }
                    }
                    .foregroundStyle(.tint)
                    #if targetEnvironment(macCatalyst)
                    .padding(.horizontal, 15)
                    #endif

                    NavigationLink(destination: Details()) {
                        Text("Details").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                    }
                }

                Spacer()

                VStack {

                    HStack {
                        Spacer()
                        Stepper(value: $settings.readingInterval,
                                in: settings.preferredTransmitter == .miaomiao || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.miaomiao)) ?
                                1 ... 5 : settings.preferredTransmitter == .blu || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.blu)) ?
                                5 ... 5 : settings.preferredTransmitter == .abbott || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.abbott)) ?
                                1 ... 1 : 1 ... 15,
                                step: settings.preferredTransmitter == .miaomiao || (settings.preferredTransmitter == .none && app.transmitter != nil && app.transmitter.type == .transmitter(.miaomiao)) ?
                                2 : 1,
                                label: {
                            HStack {
                                Image(systemName: "timer").resizable().frame(width: 24, height: 24)
                                Text("\(settings.readingInterval) min")
                            }
                        })
                        .foregroundStyle(.orange)
                        .frame(maxWidth: 200)
                        Spacer()
                    }

                    HStack {
                        Spacer()
                        Stepper {
                            HStack {
                                Image(systemName: settings.onlineInterval > 0 ? "network" : "wifi.slash").resizable().frame(width: 24, height: 24)
                                Text(settings.onlineInterval > 0 ? "\(settings.onlineInterval) min" : "offline")
                            }
                        } onIncrement: {
                            settings.onlineInterval += settings.onlineInterval >= 5 ? 5 : 1
                        } onDecrement: {
                            settings.onlineInterval -= settings.onlineInterval == 0 ? 0 : settings.onlineInterval <= 5 ? 1 : 5
                        }
                        .foregroundStyle(.cyan)
                        .frame(maxWidth: 200)
                        Spacer()
                    }

                }

                Spacer()

                Button {
                    settings.selectedTab = (settings.preferredTransmitter != .none) ? .monitor : .console
                    app.main.rescan()
                } label: {
                    Text("Rescan").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                }

                Spacer()

                VStack {

                    HStack {
                        Spacer()
                        Picker(selection: $settings.displayingMillimoles, label: Text("Unit")) {
                            ForEach(GlucoseUnit.allCases) { unit in
                                Text(unit.description).tag(unit == .mmoll)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                        Spacer()
                    }
                    .padding(.bottom)

                    VStack(spacing: 0) {
                        Image(systemName: "hand.thumbsup.fill")
                            .foregroundStyle(.green)
                            .padding(4)
                        Text("\(settings.targetLow.units) - \(settings.targetHigh.units)")
                            .foregroundStyle(.green)
                        HStack {
                            //Slider(value: $settings.targetLow,  in: 40 ... 99, step: 1)
                            SwiftUISlider(
                                value: $settings.targetLow,
                                minValue: 40,
                                maxValue: 99,
                                stepValue: 1,
                                minTrackColor: .init(uiColor: colorScheme == .dark ? .systemFill : .secondarySystemFill), // FIXME
                                maxTrackColor: .green
                            )
                            Slider(value: $settings.targetHigh, in: 120 ... 300, step: 1)
                        }
                    }
                    .tint(.green)

                    VStack(spacing: 0) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.red)
                            .padding(4)
                        Text("< \(settings.alarmLow.units)   > \(settings.alarmHigh.units)")
                            .foregroundStyle(.red)
                        HStack {
                            Slider(value: $settings.alarmLow,  in: 40 ... 99, step: 1)
                            // Slider(value: $settings.alarmHigh, in: 120 ... 300, step: 1)
                            SwiftUISlider(
                                value: $settings.alarmHigh,
                                minValue: 120,
                                maxValue: 300,
                                stepValue: 1,
                                minTrackColor: .init(uiColor: colorScheme == .dark ? .systemFill : .secondarySystemFill), // FIXME
                                maxTrackColor: .red
                            )
                        }
                    }
                    .tint(.red)
                }
                .padding(.horizontal, 40)

                HStack(spacing: 24) {
                    Button {
                        settings.mutedAudio.toggle()
                    } label: {
                        Image(systemName: settings.mutedAudio ? "speaker.slash.fill" : "speaker.2.fill").resizable().frame(width: 24, height: 24)
                            .foregroundStyle(.tint)
                    }

                    HStack(spacing: 0) {
                        Button {
                            withAnimation { settings.disabledNotifications.toggle() }
                            if settings.disabledNotifications {
                                UNUserNotificationCenter.current().setBadgeCount(0)
                            } else {
                                UNUserNotificationCenter.current().setBadgeCount(
                                    settings.displayingMillimoles ? Int(Float(app.currentGlucose.units)! * 10) : Int(app.currentGlucose.units)!
                                )
                            }
                        } label: {
                            Image(systemName: settings.disabledNotifications ? "zzz" : "app.badge.fill").resizable().frame(width: 24, height: 24)
                                .foregroundStyle(.tint)
                        }
                        if settings.disabledNotifications {
                            Picker(selection: $settings.alarmSnoozeInterval, label: Text("")) {
                                ForEach([0, 5, 15, 30, 60, 120], id: \.self) { t in
                                    Text("\([0: "Unsnooze", 5: "5 minutes", 15: "15 minutes", 30: "30 minutes", 60: "1 hour", 120: "2 hours"][t]!)")
                                }
                            }
                            .labelsHidden()
                            .onChange(of: settings.alarmSnoozeInterval) { oldInterval, newInterval in
                                if settings.alarmSnoozeInterval == 0 {
                                    settings.disabledNotifications = false
                                    settings.alarmSnoozeInterval = oldInterval
                                }
                            }
                        }
                    }

                    Button {
                        showingCalendarPicker = true
                    } label: {
                        Image(systemName: settings.calendarTitle != "" ? "calendar.circle.fill" : "calendar.circle").resizable().frame(width: 32, height: 32)
                            .foregroundStyle(.tint)
                    }
                    .popover(isPresented: $showingCalendarPicker, arrowEdge: .bottom) {
                        VStack {
                            Section {
                                Button {
                                    settings.calendarTitle = ""
                                    showingCalendarPicker = false
                                    app.main.eventKit?.sync()
                                } label: {
                                    Text("None").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                                }
                                .disabled(settings.calendarTitle == "")
                            }
                            Section {
                                Picker(selection: $settings.calendarTitle, label: Text("Calendar")) {
                                    ForEach([""] + (app.main.eventKit?.calendarTitles ?? [""]), id: \.self) { title in
                                        Text(title != "" ? title : "None")
                                    }
                                }
                                .pickerStyle(.wheel)
                            }
                            Section {
                                HStack {
                                    Image(systemName: "bell.fill")
                                        .foregroundStyle(.red)
                                        .padding(8)
                                    Toggle("High / Low", isOn: $settings.calendarAlarmIsOn)
                                        .disabled(settings.calendarTitle == "")
                                }
                            }
                            Section {
                                Button {
                                    showingCalendarPicker = false
                                    app.main.eventKit?.sync()
                                } label: {
                                    Text(settings.calendarTitle == "" ? "Don't remind" : "Remind").bold().padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                                        .animation(.default, value: settings.calendarTitle)
                                }

                            }
                            .padding(.top, 40)
                        }
                        .padding(60)
                    }
                }
                .padding(.top, 16)

                Spacer()

            }
            .font(.body.monospacedDigit())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation { showingAllDefaults.toggle() }
                    } label: {
                        Image(systemName: showingAllDefaults ? "curlybraces.square.fill" : "curlybraces.square")
                            .resizable().frame(width: 32, height: 32)
                    }
                }
            }
            .overlay(
                showingAllDefaults ?
                ScrollView(showsIndicators: true) {
                    // TODO: DefaultsEditor
                    Text("\(Settings.defaults.keys.map { [$0, UserDefaults.standard.dictionaryRepresentation()[$0]!] }.sorted { ($0[0] as! String) < ($1[0] as! String) }.map { "\($0[0]): \($0[1])" }.joined(separator: "\n"))")
                        .font(.system(.footnote, design: .monospaced))
                        .background(.black)
                        .textSelection(.enabled)
                } : nil
            )
        }
        .navigationViewStyle(.stack)
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .settings))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
