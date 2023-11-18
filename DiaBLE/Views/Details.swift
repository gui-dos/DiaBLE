import Foundation
import SwiftUI


struct Details: View {
    @Environment(AppState.self) var app: AppState
    @Environment(Settings.self) var settings: Settings

    @State private var showingNFCAlert = false
    @State private var showingCalibrationInfoForm = false

    @State private var readingCountdown: Int = 0
    @State private var secondsSinceLastConnection: Int = 0
    @State private var minutesSinceLastReading: Int = 0

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()


    // TODO:
    @ViewBuilder func Row(_ label: String, _ value: String, foregroundColor: Color? = .yellow) -> some View {
        if !value.isEmpty {
            HStack {
                Text(label)
                Spacer()
                Text(value).foregroundColor(foregroundColor)
            }
        } else {
            EmptyView()
        }
    }


    var body: some View {
        VStack {

            Spacer()

            Form {

                if app.status.starts(with: "Scanning") {
                    HStack {
                        Text("\(app.status)").font(.footnote)
                    }
                } else {
                    if app.device == nil && app.sensor == nil {
                        HStack {
                            Spacer()
                            Text("No device connected").foregroundColor(.red)
                            Spacer()
                        }
                    }
                }


                if app.device != nil {

                    Section(header: Text("Device").font(.headline)) {

                        Group {
                            Row("Name", app.device.peripheral?.name ?? app.device.name)

                            Row("State", (app.device.peripheral?.state ?? app.device.state).description.capitalized,
                                foregroundColor: (app.device.peripheral?.state ?? app.device.state) == .connected ? .green : .red)

                            if app.device.lastConnectionDate != .distantPast {
                                HStack {
                                    Text("Since")
                                    Spacer()
                                    Text("\(secondsSinceLastConnection.minsAndSecsFormattedInterval)")
                                        .monospacedDigit()
                                        .foregroundColor(app.device.state == .connected ? .yellow : .red)
                                        .onReceive(timer) { _ in
                                            if let device = app.device {
                                                secondsSinceLastConnection = Int(Date().timeIntervalSince(device.lastConnectionDate))
                                            } else {
                                                secondsSinceLastConnection = 1
                                            }
                                        }
                                }
                            }

                            if settings.userLevel > .basic && app.device.peripheral != nil {
                                Row("Identifier", app.device.peripheral!.identifier.uuidString)
                            }

                            if app.device.name != app.device.peripheral?.name ?? "Unnamed" {
                                Row("Type", app.device.name)
                            }
                        }

                        Row("Serial", app.device.serial)

                        Group {
                            if !app.device.company.isEmpty && app.device.company != "< Unknown >" {
                                Row("Company", app.device.company)
                            }
                            Row("Manufacturer", app.device.manufacturer)
                            Row("Model", app.device.model)
                            Row("Firmware", app.device.firmware)
                            Row("Hardware", app.device.hardware)
                            Row("Software", app.device.software)
                        }

                        if app.device.macAddress.count > 0 {
                            Row("MAC Address", app.device.macAddress.hexAddress)
                        }

                        if app.device.rssi != 0 {
                            Row("RSSI", "\(app.device.rssi) dB")
                        }

                        if app.device.battery > -1 {
                            Row("Battery", "\(app.device.battery)%",
                                foregroundColor: app.device.battery > 10 ? .green : .red)
                        }

                    }.font(.callout)
                }


                if app.sensor != nil {

                    Section(header: Text("Sensor").font(.headline)) {

                        Row("State", app.sensor.state.description,
                            foregroundColor: app.sensor.state == .active ? .green : .red)

                        if app.sensor.state == .failure && app.sensor.fram.count > 8 {
                            let fram = app.sensor.fram
                            let errorCode = fram[6]
                            let failureAge = Int(fram[7]) + Int(fram[8]) << 8
                            let failureInterval = failureAge == 0 ? "an unknown time" : "\(failureAge.formattedInterval)"
                            Row("Failure", "\(decodeFailure(error: errorCode).capitalized) (0x\(errorCode.hex)) at \(failureInterval)",
                                foregroundColor: .red)
                        }

                        Row("Type", "\(app.sensor.type.description)\(app.sensor.patchInfo.hex.hasPrefix("a2") ? " (new 'A2' kind)" : "")")

                        Row("Serial", app.sensor.serial)

                        Row("Reader Serial", app.sensor.readerSerial.count >= 16 ? app.sensor.readerSerial[...13].string : "")

                        Row("Region", app.sensor.region.description)

                        if app.sensor.maxLife > 0 {
                            Row("Maximum Life", app.sensor.maxLife.formattedInterval)
                        }

                        if app.sensor.age > 0 {
                            Group {
                                Row("Age", (app.sensor.age + minutesSinceLastReading).formattedInterval)
                                if app.sensor.maxLife - app.sensor.age - minutesSinceLastReading > 0 {
                                    Row("Ends in", (app.sensor.maxLife - app.sensor.age - minutesSinceLastReading).formattedInterval,
                                        foregroundColor: (app.sensor.maxLife - app.sensor.age - minutesSinceLastReading) > 360 ? .green : .red)
                                }
                                Row("Started on", (app.sensor.activationTime > 0 ? Date(timeIntervalSince1970: Double(app.sensor.activationTime)) : (app.sensor.lastReadingDate - Double(app.sensor.age) * 60)).shortDateTime)
                            }
                            .onReceive(minuteTimer) { _ in
                                minutesSinceLastReading = Int(Date().timeIntervalSince(app.sensor.lastReadingDate)/60)
                            }
                        }

                        Row("UID", app.sensor.uid.hex)

                        Group {
                            if app.sensor.type == .libre3 && (app.sensor as! Libre3).receiverId != 0 {
                                Row("Receiver ID", "\((app.sensor as! Libre3).receiverId)")
                            }
                            if app.sensor.type == .libre3 && !(app.sensor as! Libre3).blePIN.isEmpty {
                                Row("BLE PIN", "\((app.sensor as! Libre3).blePIN.hex)")
                            }
                            if !app.sensor.patchInfo.isEmpty {
                                Row("Patch Info", app.sensor.patchInfo.hex)
                                Row("Firmware", app.sensor.firmware)
                                Row("Security Generation", "\(app.sensor.securityGeneration)")
                            }
                        }

                    }.font(.callout)
                }

                if app.device != nil && app.device.type == .transmitter(.abbott) || settings.preferredTransmitter == .abbott {

                    Section(header: Text("BLE Setup").font(.headline)) {

                        @Bindable var settings = settings

                        if app.sensor?.type != .libre3 {

                            HStack {
                                Text("Patch Info")
                                TextField("Patch Info", value: $settings.activeSensorInitialPatchInfo, formatter: HexDataFormatter()).multilineTextAlignment(.trailing).foregroundColor(.blue)
                            }

                            HStack {
                                Text("Calibration Info")
                                Spacer()
                                Text("[\(settings.activeSensorCalibrationInfo.i1), \(settings.activeSensorCalibrationInfo.i2), \(settings.activeSensorCalibrationInfo.i3), \(settings.activeSensorCalibrationInfo.i4), \(settings.activeSensorCalibrationInfo.i5), \(settings.activeSensorCalibrationInfo.i6)]")
                                    .foregroundColor(.blue)
                            }
                            .onTapGesture {
                                showingCalibrationInfoForm.toggle()
                            }
                            .sheet(isPresented: $showingCalibrationInfoForm) {
                                Form {
                                    Section(header: Text("Calibration Info").font(.headline)) {
                                        HStack {
                                            Text("i1")
                                            TextField("i1", value: $settings.activeSensorCalibrationInfo.i1,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                        }
                                        HStack {
                                            Text("i2")
                                            TextField("i2", value: $settings.activeSensorCalibrationInfo.i2,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                        }
                                        HStack {
                                            Text("i3")
                                            TextField("i3", value: $settings.activeSensorCalibrationInfo.i3,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                        }
                                        HStack {
                                            Text("i4")
                                            TextField("i4", value: $settings.activeSensorCalibrationInfo.i4,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                        }
                                        HStack {
                                            Text("i5")
                                            TextField("i5", value: $settings.activeSensorCalibrationInfo.i5,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                        }
                                        HStack {
                                            Text("i6")
                                            TextField("i6", value: $settings.activeSensorCalibrationInfo.i6,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                                        }
                                        HStack {
                                            Spacer()
                                            Button {
                                                showingCalibrationInfoForm = false
                                            } label: {
                                                Text("Set").bold().foregroundColor(.accentColor).padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor, lineWidth: 2))
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            }

                            HStack {
                                Text("Unlock Code")
                                TextField("Unlock Code", value: $settings.activeSensorStreamingUnlockCode, formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                            }
                            HStack {
                                Text("Unlock Count")
                                TextField("Unlock Count", value: $settings.activeSensorStreamingUnlockCount, formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundColor(.blue)
                            }

                        }

                        HStack {
                            Spacer()
                            Button {
                                ((app.device as? Abbott)?.sensor as? Libre3)?.pair()
                                if app.main.nfc.isAvailable {
                                    app.main.nfc.taskRequest = .enableStreaming
                                    settings.selectedTab = .console
                                } else {
                                    showingNFCAlert = true
                                }
                            } label: {
                                VStack(spacing: 0) {
                                    Image("NFC").renderingMode(.template).resizable().frame(width: 26, height: 18) .padding(.horizontal, 12).padding( .vertical, 6)
                                    Text("RePair").font(.footnote).bold().padding(.bottom, 4)
                                }.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2.5))
                            }
                            .foregroundColor(.accentColor)
                            .alert("NFC not supported", isPresented: $showingNFCAlert) {
                            } message: {
                                Text("This device doesn't allow scanning the Libre.")
                            }
                            Spacer()
                        }.padding(.vertical, 4)

                    }.font(.callout)
                }


                // TODO
                if (app.device != nil && app.device.type == .transmitter(.dexcom)) || settings.preferredTransmitter == .dexcom {

                    Section(header: Text("BLE Setup").font(.headline)) {

                        @Bindable var settings = settings

                        HStack {
                            Text("Transmitter Serial")
                            TextField("Transmitter Serial", text: $settings.activeTransmitterSerial)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.blue)
                        }

                        HStack {
                            Text("Sensor Code")
                            TextField("Sensor Code", text: $settings.activeSensorCode)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.blue)
                        }

                        HStack {
                            Spacer()
                            Button {
                                // TODO
                                app.main.rescan()
                            } label: {
                                VStack(spacing: 0) {
                                    Image("Bluetooth").renderingMode(.template).resizable().frame(width: 32, height: 32) .padding(.horizontal, 12)
                                    Text("RePair").font(.footnote).bold().padding(.bottom, 4)
                                }.overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2.5))
                            }
                            .foregroundColor(.accentColor)
                            Spacer()
                        }.padding(.vertical, 4)

                    }.font(.callout)
                }


                // Embed a specific device setup panel
                // if app.device?.type == Custom.type {
                //     CustomDetailsView(device: app.device as! Custom)
                //     .font(.callout)
                // }


                Section(header: Text("Known Devices").font(.headline)) {
                    List {
                        ForEach(app.main.bluetoothDelegate.knownDevices.sorted(by: { $0.key < $1.key }), id: \.key) { uuid, device in
                            HStack {
                                Text(device.name).font(.callout).foregroundColor((app.device != nil) && uuid == app.device!.peripheral!.identifier.uuidString ? .yellow : .blue)
                                    .onTapGesture {
                                        // TODO: navigate to peripheral details
                                        if let peripheral = app.main.centralManager.retrievePeripherals(withIdentifiers: [UUID(uuidString: uuid)!]).first {
                                            if let appDevice = app.device {
                                                app.main.centralManager.cancelPeripheralConnection(appDevice.peripheral!)
                                            }
                                            app.main.log("Bluetooth: retrieved \(peripheral.name ?? "unnamed peripheral")")
                                            app.main.settings.preferredTransmitter = .none
                                            app.main.bluetoothDelegate.centralManager(app.main.centralManager, didDiscover: peripheral, advertisementData: [:], rssi: 0)
                                        }
                                    }
                                if !device.isConnectable {
                                    Spacer()
                                    Image(systemName: "nosign").foregroundColor(.red)
                                } else if device.isIgnored {
                                    Spacer()
                                    Image(systemName: "hand.raised.slash.fill").foregroundColor(.red)
                                        .onTapGesture {
                                            app.main.bluetoothDelegate.knownDevices[uuid]!.isIgnored.toggle()
                                        }
                                }
                            }
                        }
                    }
                }

            }
            .foregroundColor(.secondary)

            Spacer()

            HStack(alignment: .top, spacing: 40) {

                Spacer()

                VStack(spacing: 0) {

                    Button {
                        app.main.rescan()
                        self.timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                        self.minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 32, height: 32).foregroundColor(.accentColor)
                    }

                    Text(!app.deviceState.isEmpty && app.deviceState != "Disconnected" && (readingCountdown > 0 || app.deviceState == "Reconnecting...") ?
                         "\(readingCountdown) s" : "...")
                    .fixedSize()
                    .foregroundColor(.orange).font(Font.caption.monospacedDigit())
                    .onReceive(timer) { _ in
                        readingCountdown = settings.readingInterval * 60 - Int(Date().timeIntervalSince(app.lastConnectionDate))
                    }
                }

                Button {
                    if app.device != nil {
                        app.main.bluetoothDelegate.knownDevices[app.device.peripheral!.identifier.uuidString]!.isIgnored = true
                        app.main.centralManager.cancelPeripheralConnection(app.device.peripheral!)
                    }
                } label: {
                    Image(systemName: "escape").resizable().frame(width: 28, height: 28)
                        .foregroundColor(.blue)
                }

                Spacer()

            }.padding(.bottom, 8)

                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Details")
        }
        .onAppear {
            if app.sensor != nil {
                minutesSinceLastReading = Int(Date().timeIntervalSince(app.sensor.lastReadingDate)/60)
            } else if app.lastReadingDate != Date.distantPast {
                minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate)/60)
            }
        }
    }
}


#Preview {
    Details()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .monitor))
        .environment(Settings())
}

#Preview {
    NavigationView {
        Details()
            .preferredColorScheme(.dark)
            .environment(AppState.test(tab: .monitor))
            .environment(Settings())
    }
}

