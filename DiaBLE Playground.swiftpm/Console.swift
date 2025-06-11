import Foundation
import SwiftUI


struct ConsoleTab: View {
    var body: some View {
        NavigationStack {
            // Workaround to avoid top textfields scrolling offscreen in iOS 14
            GeometryReader { _ in
                Console()
            }
        }
    }
}


struct Console: View {
    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(Settings.self) var settings: Settings

    @Environment(\.colorScheme) var colorScheme

    @State private var showingNFCAlert = false
    @State private var showingRePairConfirmationDialog = false
    @State private var showingActivateConfirmationDialog = false
    @State private var showingUnlockConfirmationDialog = false

    #if DEBUG
    @State private var showingResetConfirmationDialog = false
    @State private var showingProlongConfirmationDialog = false
    #endif

    @State private var showingFilterField = false
    @State private var filterText = ""

    var body: some View {

        HStack(spacing: 0) {

            VStack(spacing: 0) {

                ShellView()

                ConsoleLogView(showingFilterField: $showingFilterField, filterText: $filterText)
                #if targetEnvironment(macCatalyst)
                .padding(.horizontal, 15)
                #endif

            }

            ConsoleSidebar(showingNFCAlert: $showingNFCAlert)
            #if targetEnvironment(macCatalyst)
            .padding(.trailing, 15)
            #endif

        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Console")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    settings.caffeinated.toggle()
                    UIApplication.shared.isIdleTimerDisabled = settings.caffeinated
                } label: {
                    Image(systemName: settings.caffeinated ? "cup.and.saucer.fill" : "cup.and.saucer" )
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    withAnimation { showingFilterField.toggle() }
                } label: {
                    VStack(spacing: 0) {
                        Image(systemName: filterText.isEmpty ? "line.horizontal.3.decrease.circle" : "line.horizontal.3.decrease.circle.fill")
                        Text("Filter").font(.footnote)
                    }
                }

                Menu {

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
                        Label("RePair Streaming", systemImage: "sensor.tag.radiowaves.forward.fill")
                            .symbolEffect(.variableColor.reversing, isActive: app.deviceState == "Connected")
                    }

                    Button {
                        if app.main.nfc.isAvailable {
                            settings.logging = true
                            app.main.nfc.taskRequest = .readFRAM
                        } else {
                            showingNFCAlert = true
                        }
                    } label: {
                        Label("Read FRAM", systemImage: "memorychip")
                    }

                    Menu {

                        Button {
                            if app.main.nfc.isAvailable {
                                settings.logging = true
                                showingUnlockConfirmationDialog = true
                            } else {
                                showingNFCAlert = true
                            }
                        } label: {
                            Label("Unlock", systemImage: "lock.open")
                        }

                        Button {
                            if app.main.nfc.isAvailable {
                                settings.logging = true
                                app.main.nfc.taskRequest = .dump
                            } else {
                                showingNFCAlert = true
                            }
                        } label: {
                            Label("Dump Memory", systemImage: "cpu")
                        }

                        #if DEBUG
                        Button {
                            if app.main.nfc.isAvailable {
                                settings.logging = true
                                showingResetConfirmationDialog = true
                            } else {
                                showingNFCAlert = true
                            }
                        } label: {
                            Label("Reset", systemImage: "00.circle")
                        }

                        Button {
                            if app.main.nfc.isAvailable {
                                settings.logging = true
                                showingProlongConfirmationDialog = true
                            } else {
                                showingNFCAlert = true
                            }
                        } label: {
                            Label("Prolong", systemImage: "infinity.circle")
                        }
                        #endif // DEBUG

                    } label: {
                        Label("Hacks", systemImage: "wand.and.stars")
                    }

                    Button {
                        if app.main.nfc.isAvailable {
                            settings.logging = true
                            showingActivateConfirmationDialog = true
                        } else {
                            showingNFCAlert = true
                        }
                    } label: {
                        Label("Activate", systemImage: "bolt.circle")
                    }

                } label: {
                    VStack(spacing: 0) {
                        Image(systemName: "wrench.and.screwdriver")
                        Text("Tools").font(.footnote)
                    }
                }
            }
        }
        .alert("NFC not supported", isPresented: $showingNFCAlert) {
        } message: {
            Text("This device doesn't allow scanning the Libre.")
        }
        .confirmationDialog("Pairing a Libre 2 with this device will break LibreLink and other apps' pairings and you will have to uninstall and reinstall them to get their alarms back again.", isPresented: $showingRePairConfirmationDialog, titleVisibility: .visible) {
            Button("RePair", role: .destructive) {
                app.main.nfc.taskRequest = .enableStreaming
            }
        }
        .confirmationDialog("Activating a fresh/ened sensor will put it in the usual warming-up state for 60 minutes.", isPresented: $showingActivateConfirmationDialog, titleVisibility: .visible) {
            Button("Activate", role: .destructive) {
                app.main.nfc.taskRequest = .activate
            }
        }
        .confirmationDialog("Unlocking the Libre 2 is not reversible and will make it unreadable by LibreLink and other apps.", isPresented: $showingUnlockConfirmationDialog, titleVisibility: .visible) {
            Button("Unlock", role: .destructive) {
                app.main.nfc.taskRequest = .unlock
            }
        }
        #if DEBUG
        .confirmationDialog("Resetting the sensor will clear its measurements memory and put it in an inactivated state.", isPresented: $showingResetConfirmationDialog, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                app.main.nfc.taskRequest = .reset
            }
        }
        .confirmationDialog("Prolonging the sensor will overwrite its maximum life to 0xFFFF minutes (≈ 45.5 days)", isPresented: $showingProlongConfirmationDialog, titleVisibility: .visible) {
            Button("Prolong", role: .destructive) {
                app.main.nfc.taskRequest = .prolong
            }
        }
        #endif // DEBUG

    }
}


struct ConsoleLogView: View {
    @Environment(Log.self) var log: Log
    @Environment(Settings.self) var settings: Settings
    @Environment(\.colorScheme) var colorScheme

    @Binding var showingFilterField: Bool
    @Binding var filterText: String

    var body: some View {

        if showingFilterField {
            HStack {

                HStack {
                    Image(systemName: "magnifyingglass")
                        .padding(.leading)
                        .foregroundStyle(Color(.lightGray))
                    TextField("Filter", text: $filterText)
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(.tint)
                    if filterText.count > 0 {
                        Button {
                            filterText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .padding(.trailing)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)

                HStack {
                    ForEach(Array(log.labels), id: \.self) { label in
                        Button {
                            filterText = label
                        } label: {
                            Text(label)
                                .font(.footnote)
                                .foregroundStyle(.blue)
                        }
                    }
                }

            }
            .padding(.vertical, 6)
        }

        ScrollViewReader { proxy in
            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if filterText.isEmpty {
                        ForEach(log.entries) { entry in
                            Text(entry.message)
                                .textSelection(.enabled)
                        }
                    } else {
                        let pattern = filterText.lowercased()
                        ForEach(log.entries.filter { $0.message.lowercased().contains(pattern) }) { entry in
                            Text(entry.message)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(4)
            }
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(colorScheme == .dark ? Color(.lightGray) : Color(.darkGray))
            .onChange(of: log.entries.count) {
                if !settings.reversedLog {
                    withAnimation {
                        proxy.scrollTo(log.entries.last!.id, anchor: .bottom)
                    }
                } else {
                    withAnimation {
                        proxy.scrollTo(log.entries[0].id, anchor: .top)
                    }
                }
            }
            .onChange(of: log.entries[0].id) {
                if !settings.reversedLog {
                    withAnimation {
                        proxy.scrollTo(log.entries.last!.id, anchor: .bottom)
                    }
                } else {
                    withAnimation {
                        proxy.scrollTo(log.entries[0].id, anchor: .top)
                    }
                }
            }
        }
    }
}


struct ConsoleSidebar: View, LoggingView {
    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(Settings.self) var settings: Settings

    @Binding var showingNFCAlert: Bool

    @State private var onlineCountdown: Int64 = 0
    @State private var readingCountdown: Int64 = 0


    var body: some View {
        VStack(alignment: .center, spacing: 8) {

            Spacer()

            VStack(spacing: 0) {

                Button {
                    if app.main.nfc.isAvailable {
                        app.main.nfc.startSession()
                    } else {
                        showingNFCAlert = true
                    }
                } label: {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill").resizable().frame(width: 26, height: 18)
                        .padding(.init(top: 10, leading: 6, bottom: 14, trailing: 0))
                        .symbolEffect(.variableColor.reversing, isActive: app.deviceState == "Connected")
                }

                Button {
                    app.main.rescan()
                } label: {
                    VStack {
                        Image("Bluetooth").renderingMode(.template).resizable().frame(width: 32, height: 32)
                        Text("Scan")
                    }
                }
            }
            .foregroundStyle(.tint)


            if (app.status.hasPrefix("Scanning") || app.status.hasSuffix("retrying...")) && app.main.centralManager.state != .poweredOff {
                Button {
                    app.main.centralManager.stopScan()
                    app.main.status("Stopped scanning")
                    log("Bluetooth: stopped scanning")
                } label: {
                    Image(systemName: "octagon").resizable().frame(width: 32, height: 32)
                        .overlay((Image(systemName: "hand.raised.fill").resizable().frame(width: 18, height: 18).offset(x: 1)))
                }
                .foregroundStyle(.red)

            } else if app.deviceState == "Connected" || app.deviceState == "Reconnecting..." || app.status.hasSuffix("retrying...") {
                Button {
                    if app.device != nil {
                        app.main.bluetoothDelegate.knownDevices[app.device.peripheral!.identifier.uuidString]!.isIgnored = true
                        app.main.centralManager.cancelPeripheralConnection(app.device.peripheral!)
                    }
                } label: {
                    Image(systemName: "escape").resizable().padding(5).frame(width: 32, height: 32)
                        .foregroundStyle(.blue)
                }

            } else {
                Image(systemName: "octagon").resizable().frame(width: 32, height: 32)
                    .hidden()
            }

            VStack(spacing: 6) {

                if !app.deviceState.isEmpty && app.deviceState != "Disconnected" {
                    Text(readingCountdown > 0 || app.deviceState == "Reconnecting..." ?
                         "\(readingCountdown) s" : "")
                    .fixedSize()
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
                    .contentTransition(.numericText(countsDown: true))
                    .onReceive(app.timer) { _ in
                        withAnimation {
                            readingCountdown = Int64(settings.readingInterval * 60) - Int64(Date().timeIntervalSince(app.lastConnectionDate))
                        }
                    }
                } else {
                    Text("")
                        .fixedSize()
                        .font(.caption.monospacedDigit())
                        .hidden()
                }

                Text(onlineCountdown != 0 ? "\(String(onlineCountdown).count > 5 ? "..." : "\(onlineCountdown) s")" : " ")
                    .fixedSize()
                    .foregroundStyle(.cyan)
                    .font(.caption.monospacedDigit())
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

            Spacer()

            Button {
                settings.userLevel = UserLevel(rawValue: (settings.userLevel.rawValue + 1) % UserLevel.allCases.count)!
            } label: {
                VStack {
                    Image(systemName: ["doc.plaintext", "ladybug", "testtube.2"][settings.userLevel.rawValue]).resizable().frame(width: 24, height: 24).offset(y: 2)
                    Text(["Basic", "Devel", "Test  "][settings.userLevel.rawValue]).font(.caption).offset(y: -4)
                }
            }
            .background(settings.userLevel != .basic ? Color.accentColor : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(settings.userLevel != .basic ? Color(.systemBackground) : .accentColor)
            .padding(.bottom, 6)

            VStack(spacing: 0) {

                Button {
                    UIPasteboard.general.string = log.entries.map(\.message).joined(separator: "\n \n")
                } label: {
                    VStack {
                        Image(systemName: "doc.on.doc").resizable().frame(width: 24, height: 24)
                        Text("Copy").offset(y: -6)
                    }
                }

                Button {
                    log.entries = [LogEntry(message: "Log cleared \(Date().local)")]
                    log.labels = []
                    print("Log cleared \(Date().local)")
                } label: {
                    VStack {
                        Image(systemName: "clear").resizable().frame(width: 24, height: 24)
                        Text("Clear").offset(y: -6)
                    }
                }

            }

            Button {
                settings.reversedLog.toggle()
                log.entries.reverse()
            } label: {
                VStack {
                    Image(systemName: "backward.fill").resizable().frame(width: 12, height: 12).offset(y: 5)
                    Text(" REV ").offset(y: -2)
                }
            }
            .background(settings.reversedLog ? Color.accentColor : .clear)
            .border(Color.accentColor, width: 3)
            .cornerRadius(5)
            .foregroundStyle(settings.reversedLog ? Color(.systemBackground) : .accentColor)


            Button {
                settings.logging.toggle()
                log("\(settings.logging ? "Log started" : "Log stopped") \(Date().local)")
            } label: {
                VStack {
                    Image(systemName: settings.logging ? "stop.circle" : "play.circle").resizable().frame(width: 32, height: 32)
                }
            }
            .foregroundStyle(settings.logging ? .red : .green)

            Spacer()

        }
        .font(.footnote)
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .console))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
