import Foundation
import SwiftUI
import CoreBluetooth


struct Details: View, LoggingView {
    @Environment(AppState.self) var app: AppState
    @Environment(Settings.self) var settings: Settings

    @State private var showingNFCAlert = false
    @State private var showingRePairConfirmationDialog = false
    @State private var showingCalibrationInfoForm = false

    @State private var readingCountdown: Int64 = 0
    @State private var secondsSinceLastConnection: Int = 0
    @State private var minutesSinceLastReading: Int = 0


    // TODO:
    @ViewBuilder func Row(_ label: String, _ value: String, foregroundStyle: Color? = .yellow) -> some View {
        if !(value.isEmpty || value == "unknown") {
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .foregroundStyle(foregroundStyle!)
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
                            Text("No device connected")
                                .foregroundStyle(.red)
                            Spacer()
                        }
                    }
                }


                if app.device != nil {

                    Section(header: Text("Device").font(.headline)) {

                        Group {
                            Row("Name", app.device.peripheral?.name ?? app.device.name)

                            Row("State", (app.device.peripheral?.state ?? app.device.state).description.capitalized,
                                foregroundStyle: (app.device.peripheral?.state ?? app.device.state) == .connected ? .green : .red)

                            if app.device.lastConnectionDate != .distantPast {
                                HStack {
                                    Text("Since")
                                    Spacer()
                                    Text("\(secondsSinceLastConnection.minsAndSecsFormattedInterval)")
                                        .monospacedDigit()
                                        .foregroundStyle(app.device.state == .connected ? .yellow : .red)
                                        .onReceive(app.timer) { _ in
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
                                foregroundStyle: app.device.battery > 10 ? .green : .red)
                        }

                        if app.device.characteristics.count > 0 {
                            NavigationLink(destination: CharacteristicsDetails()) {
                                Text("Characteristics (\(app.device.characteristics.count))")
                                    .foregroundStyle(.tint)
                            }
                        }

                    }
                    .font(.callout)
                }


                if app.sensor != nil {

                    Section(header: Text("Sensor").font(.headline)) {

                        if (app.sensor as? Libre3) != nil && (app.sensor as? Libre)?.patchInfo.count ?? 0 > 0 {
                            Row("State", Libre3.State(rawValue: (app.sensor as! Libre3).patchInfo[14])!.description,
                                foregroundStyle: app.sensor.state == .active ? .green : .red)
                        } else {
                            Row("State", app.sensor.state.description,
                                foregroundStyle: app.sensor.state == .active ? .green : .red)
                        }

                        if app.sensor.state == .failure && (app.sensor as? Libre)?.fram.count ?? 0 > 8 {
                            let fram = (app.sensor as! Libre).fram
                            let errorCode = fram[6]
                            let failureAge = Int(fram[7]) + Int(fram[8]) << 8
                            let failureInterval = failureAge == 0 ? "an unknown time" : "\(failureAge.formattedInterval)"
                            Row("Failure", "\(decodeFailure(error: errorCode).capitalized) (0x\(errorCode.hex)) at \(failureInterval)",
                                foregroundStyle: .red)
                        }

                        Row("Type", "\(app.sensor.type.description)\(((app.sensor as? Libre)?.patchInfo.hex ?? "").hasPrefix("a2") ? " (new 'A2' kind)" : (app.sensor as? Libre)?.isAPlus ?? false ? " Plus" : "")")

                        Row("Serial", app.sensor.serial)

                        Row("Reader Serial", app.sensor.readerSerial.count >= 16 ? app.sensor.readerSerial[...13].string : "")

                        Row("Region", app.sensor.region.description)

                        if app.sensor.maxLife > 0 {
                            Row("Maximum Life", app.sensor.maxLife.formattedInterval)
                        }

                        if app.sensor.age > 0 {
                            Group {
                                Row("Started on", (app.sensor.activationTime > 0 ? Date(timeIntervalSince1970: Double(app.sensor.activationTime)) : (app.sensor.lastReadingDate - Double(app.sensor.age) * 60)).shortDateTime)
                                Row("Age", (app.sensor.age + minutesSinceLastReading).formattedInterval)
                                if app.sensor.maxLife - app.sensor.age - minutesSinceLastReading > 0 {
                                    Row("Ends in", (app.sensor.maxLife - app.sensor.age - minutesSinceLastReading).formattedInterval,
                                        foregroundStyle: (app.sensor.maxLife - app.sensor.age - minutesSinceLastReading) > 360 ? .green : .red)
                                }
                            }
                            .onReceive(app.minuteTimer) { _ in
                                minutesSinceLastReading = app.sensor.lastReadingDate == .distantPast ? minutesSinceLastReading + 1 : Int(Date().timeIntervalSince(app.sensor.lastReadingDate)/60)
                            }
                        }

                        Row("UID", app.sensor.uid.hex)

                        Group {
                            if (app.sensor as? Libre3)?.receiverId ?? 0 != 0 {
                                Row("Receiver ID", "\((app.sensor as! Libre3).receiverId)")
                            }
                            if ((app.sensor as? Libre3)?.blePIN ?? Data()).count != 0 {
                                Row("BLE PIN", "\((app.sensor as! Libre3).blePIN.hex)")
                            }
                            if !((app.sensor as? Libre)?.patchInfo.isEmpty ?? true) {
                                Row("Patch Info", (app.sensor as! Libre).patchInfo.hex)
                                Row("Firmware", app.sensor.firmware)
                                Row("Security Generation", "\(app.sensor.securityGeneration)")
                            }
                        }

                    }
                    .font(.callout)
                }

                if app.device != nil && app.device.type == .transmitter(.abbott) || settings.preferredTransmitter == .abbott {

                    Section(header: Text("BLE Setup").font(.headline)) {

                        @Bindable var settings = settings

                        if app.sensor == nil || app.sensor?.type == .libre3 || app.sensor?.type == .lingo || app.sensor?.type == .libreSelect || app.sensor?.type == .instinct || app.sensor?.type == .libreX {

                            HStack {
                                Text("Receiver ID")
                                TextField("Receiver ID", value: $settings.activeSensorReceiverId, formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundStyle(.blue)
                            }

                            HStack {
                                Text("BLE PIN")
                                TextField("BLE PIN", value: $settings.activeSensorBlePIN, format: HexDataFormatStyle(maxBytes: 4))
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.blue)
                                    .onChange(of: settings.activeSensorBlePIN) {
                                        (app.sensor as? Libre3)?.blePIN = settings.activeSensorBlePIN
                                    }
                            }

                            HStack {
                                Text("Shared Key")
                                TextField("Shared Key", value: $settings.activeSensorSharedKey, format: HexDataFormatStyle(maxBytes: 16))
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.blue)
                                    .onChange(of: settings.activeSensorSharedKey) {
                                        (app.sensor as? Libre3)?.sharedKey = settings.activeSensorSharedKey
                                    }
                            }

                            if settings.userLevel > .basic {
                                HStack {
                                    Text("kEnc")
                                    TextField("kEnc", value: $settings.activeSensorKEnc, format: HexDataFormatStyle(maxBytes: 16))
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(.blue)
                                        .onChange(of: settings.activeSensorKEnc) {
                                            (app.sensor as? Libre3)?.kEnc = settings.activeSensorKEnc
                                        }
                                }
                                HStack {
                                    Text("ivEnc")
                                    TextField("ivEnc", value: $settings.activeSensorIvEnc, format: HexDataFormatStyle(maxBytes: 8))
                                        .multilineTextAlignment(.trailing)
                                        .foregroundStyle(.blue)
                                        .onChange(of: settings.activeSensorIvEnc) {
                                            (app.sensor as? Libre3)?.ivEnc = settings.activeSensorIvEnc
                                        }
                                }
                            }

                            Text("While the sensor is connected in **Test** mode, switch to **Basic** mode and press **RePair** (also from the **Console Tools** menu) before it disconnects (you need to scan it only once)**\((readingCountdown < 0 ? 0 : readingCountdown) - 30 > 0 ? ": \(readingCountdown - 30) s" : "").**")


                        } else {

                            HStack {
                                Text("Patch Info")
                                TextField("Patch Info", value: $settings.activeSensorInitialPatchInfo, format: HexDataFormatStyle(maxBytes: 4))
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.blue)
                            }

                            HStack {
                                Text("Calibration Info")
                                Spacer()
                                Text("[\(settings.activeSensorCalibrationInfo.i1), \(settings.activeSensorCalibrationInfo.i2), \(settings.activeSensorCalibrationInfo.i3), \(settings.activeSensorCalibrationInfo.i4), \(settings.activeSensorCalibrationInfo.i5), \(settings.activeSensorCalibrationInfo.i6)]")
                                    .foregroundStyle(.blue)
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
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundStyle(.blue)
                                        }
                                        HStack {
                                            Text("i2")
                                            TextField("i2", value: $settings.activeSensorCalibrationInfo.i2,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundStyle(.blue)
                                        }
                                        HStack {
                                            Text("i3")
                                            TextField("i3", value: $settings.activeSensorCalibrationInfo.i3,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundStyle(.blue)
                                        }
                                        HStack {
                                            Text("i4")
                                            TextField("i4", value: $settings.activeSensorCalibrationInfo.i4,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundStyle(.blue)
                                        }
                                        HStack {
                                            Text("i5")
                                            TextField("i5", value: $settings.activeSensorCalibrationInfo.i5,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundStyle(.blue)
                                        }
                                        HStack {
                                            Text("i6")
                                            TextField("i6", value: $settings.activeSensorCalibrationInfo.i6,
                                                      formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundStyle(.blue)
                                        }
                                        HStack {
                                            Spacer()
                                            Button {
                                                showingCalibrationInfoForm = false
                                            } label: {
                                                Text("Set").bold().foregroundStyle(.tint).padding(.horizontal, 4).padding(2).overlay(RoundedRectangle(cornerRadius: 5).stroke(.tint, lineWidth: 2))
                                            }
                                            Spacer()
                                        }
                                    }
                                }
                            }

                            HStack {
                                Text("Unlock Code")
                                TextField("Unlock Code", value: $settings.activeSensorStreamingUnlockCode, formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundStyle(.blue)
                            }
                            HStack {
                                Text("Unlock Count")
                                TextField("Unlock Count", value: $settings.activeSensorStreamingUnlockCount, formatter: NumberFormatter()).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).foregroundStyle(.blue)
                            }

                        }

                        HStack {
                            Spacer()

                            Button {
                                ((app.device as? Abbott)?.sensor as? Libre3)?.pair()
                                if app.main.nfc.isAvailable {
                                    settings.logging = true
                                    settings.selectedTab = .console
                                    if app.sensor as? Libre3 == nil {
                                        showingRePairConfirmationDialog = true
                                    } else {
                                        app.main.nfc.taskRequest = .enableStreaming
                                    }
                                } else {
                                    showingNFCAlert = true
                                }
                            } label: {
                                VStack(spacing: 0) {
                                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .symbolEffect(.variableColor.reversing, isActive: app.deviceState == "Connected")
                                    Text("RePair")
                                        .font(.footnote).bold()
                                        .padding(.bottom, 4)
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.tint, lineWidth: 2.5))
                            .foregroundStyle(.tint)
                            .alert("NFC not supported", isPresented: $showingNFCAlert) {
                            } message: {
                                Text("This device doesn't allow scanning the Libre.")
                            }
                            .confirmationDialog("Pairing a Libre 2 with this device will break LibreLink and other apps' pairings and you will have to uninstall and reinstall them to get their alarms back again.", isPresented: $showingRePairConfirmationDialog, titleVisibility: .visible) {
                                Button("RePair", role: .destructive) {
                                    app.main.nfc.taskRequest = .enableStreaming
                                }
                            }

                            Spacer()

                            Text("using:")
                            Button {
                                settings.usingLibreCRKit.toggle()
                                settings.usingMessinaSharedKeyServer.toggle()
                                log("Settings: \(settings.usingLibreCRKit ? "LibreCRKit" : "Messina server") selected")
                            } label: {
                                VStack(spacing: 0) {
                                    Image(systemName: settings.usingLibreCRKit ? "ring" : "cloud.rainbow.crop")
                                        .resizable().frame(width: 24, height: 24)
                                        .padding(.vertical, 2)
                                    Text("\(settings.usingLibreCRKit ? "LibreCR" : "Messina")")
                                        .font(.footnote).bold()
                                        .padding(.bottom, 4)
                                }
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.tint, lineWidth: 2.5))
                            .foregroundStyle(.tint)

                            Spacer()

                        }
                        .padding(.vertical, 4)

                    }
                    .font(.callout)
                }


                // TODO
                if (app.device != nil && app.device.type == .transmitter(.dexcom)) || settings.preferredTransmitter == .dexcom {

                    Section(header: Text("BLE Setup").font(.headline)) {

                        @Bindable var settings = settings

                        HStack {
                            Text("Transmitter Serial")
                            TextField("Transmitter Serial", text: $settings.activeTransmitterSerial)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.blue)
                        }

                        HStack {
                            Text("Sensor Code")
                            TextField("Sensor Code", text: $settings.activeSensorCode)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(.blue)
                        }

                        HStack {
                            Text("Backfill Minutes")
                            HStack(spacing: 0) {
                                Spacer()
                                if settings.backfillMinutes > 0 {
                                    Button {
                                        settings.backfillMinutes = 0
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                }
                                TextField("Backfill Minutes", value: $settings.backfillMinutes, formatter: NumberFormatter())
                                    .keyboardType(.numbersAndPunctuation)
                                    .multilineTextAlignment(.trailing)
                                    .fixedSize()
                            }
                            .foregroundStyle(.tint)
                        }

                        HStack {
                            Spacer()
                            Button {
                                // TODO
                                settings.logging = true
                                settings.selectedTab = .console
                                app.main.rescan()
                            } label: {
                                VStack(spacing: 0) {
                                    Image("Bluetooth").renderingMode(.template).resizable().frame(width: 32, height: 32) .padding(.horizontal, 12)
                                    Text("RePair").font(.footnote).bold().padding(.bottom, 4)
                                }
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.tint, lineWidth: 2.5))
                            }
                            .foregroundStyle(.tint)
                            Spacer()
                        }
                        .padding(.vertical, 4)

                    }
                    .font(.callout)
                }


                // Embed a specific device setup panel
                // if app.device?.type == Custom.type {
                //     CustomDetailsView(device: app.device as! Custom)
                //     .font(.callout)
                // }

                if !app.main.bluetoothDelegate.knownDevices.isEmpty {
                    Section(header: Text("Known Devices").font(.headline)) {
                        List {
                            ForEach(app.main.bluetoothDelegate.knownDevices.sorted(by: { $0.key < $1.key }), id: \.key) { uuid, device in
                                HStack {
                                    Text(device.name.replacing("an unnamed", with: "Unnamed"))
                                        .font(.callout)
                                        .foregroundStyle((app.device != nil) && uuid == app.device!.peripheral!.identifier.uuidString ? .yellow : .blue)
                                        .onTapGesture {
                                            // TODO: navigate to peripheral details
                                            if let peripheral = app.main.centralManager.retrievePeripherals(withIdentifiers: [UUID(uuidString: uuid)!]).first {
                                                if let appDevice = app.device {
                                                    app.main.centralManager.cancelPeripheralConnection(appDevice.peripheral!)
                                                }
                                                log("Bluetooth: retrieved \(peripheral.name ?? "unnamed peripheral")")
                                                app.main.settings.preferredTransmitter = .none
                                                app.main.bluetoothDelegate.centralManager(app.main.centralManager, didDiscover: peripheral, advertisementData: device.advertisement, rssi: 0)
                                            }
                                        }
                                    if !device.isConnectable {
                                        Spacer()
                                        Image(systemName: "nosign")
                                            .foregroundStyle(.red)
                                    } else if device.isIgnored {
                                        Spacer()
                                        Image(systemName: "hand.raised.slash.fill")
                                            .foregroundStyle(.red)
                                            .onTapGesture {
                                                app.main.bluetoothDelegate.knownDevices[uuid]!.isIgnored.toggle()
                                            }
                                    }
                                }
                            }
                        }
                    }
                }

            }
            .foregroundStyle(.secondary)

            Spacer()

            HStack(alignment: .top, spacing: 40) {

                Spacer()

                VStack(spacing: 0) {

                    Button {
                        app.main.rescan()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 32, height: 32)
                            .foregroundStyle(.tint)
                    }

                    Text(!app.deviceState.isEmpty && app.deviceState != "Disconnected" && (readingCountdown > 0 || app.deviceState == "Reconnecting...") ?
                         "\(readingCountdown) s" : "...")
                    .fixedSize()
                    .foregroundStyle(.orange)
                    .font(.caption.monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .onReceive(app.timer) { _ in
                        withAnimation {
                            readingCountdown = Int64(settings.readingInterval * 60) - Int64(Date().timeIntervalSince(app.lastConnectionDate)) - 1
                        }
                    }
                }

                Button {
                    if app.device != nil {
                        app.main.bluetoothDelegate.knownDevices[app.device.peripheral!.identifier.uuidString]!.isIgnored = true
                        app.main.centralManager.cancelPeripheralConnection(app.device.peripheral!)
                    }
                } label: {
                    Image(systemName: "escape").resizable().frame(width: 28, height: 28)
                        .foregroundStyle(.blue)
                }

                Spacer()

            }
            .padding(.bottom, 8)

        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Details")
        .onAppear {
            if app.sensor != nil {
                minutesSinceLastReading = app.sensor.lastReadingDate == .distantPast ? 0 : Int(Date().timeIntervalSince(app.sensor.lastReadingDate)/60)
            } else if app.lastReadingDate != Date.distantPast {
                minutesSinceLastReading = Int(Date().timeIntervalSince(app.lastReadingDate)/60)
            }
        }
    }
}


extension CBCharacteristic: @retroactive Comparable {
    public static func < (lhs: CBCharacteristic, rhs: CBCharacteristic) -> Bool {
        return lhs.uuid.uuidString < rhs.uuid.uuidString
    }
}

struct CharacteristicsDetails: View, LoggingView {
    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(Settings.self) var settings: Settings


    var body: some View {

        VStack {

            // TODO
            Text("[TODO]")
            Spacer()
            List {
                ForEach(app.device.characteristics.sorted(by: <), id: \.key) { uuid, characteristic in
                    VStack(alignment: .leading) {
                        Text(uuid).bold()
                        if characteristic.uuid.description != uuid {
                            Text(characteristic.uuid.description)
                        }
                        Text(characteristic.properties.description)
                        Text(characteristic.description)
                    }
                    .listRowSpacing(8)
                }
            }

        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Characteristics")
    }
}


#Preview {
    Details()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .monitor))
        .environment(Settings())
}

#Preview {
    NavigationStack {
        Details()
            .preferredColorScheme(.dark)
            .environment(AppState.test(tab: .monitor))
            .environment(Settings())
    }
}
