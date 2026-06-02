import Combine
import SwiftUI

@MainActor
final class AndroidShimAppModel: ObservableObject, @MainActor Logging {

    var main: MainDelegate!  // DiaBLE interconnection

    private enum DefaultsKey {
        static let serverURL = "serverURL"
        static let libreViewPatientId = "libreViewPatientId"
        static let libreViewReceiverId = "libreViewReceiverId"
    }

    let server: AndroidServerClient
    let nfc: Libre3NFC
    let ble: Libre3BLEClient

    @Published var serverURL: String = UserDefaults.standard.string(forKey: DefaultsKey.serverURL) ?? "" {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: DefaultsKey.serverURL)
        }
    }
    @Published var bearerToken: String = ""
    @Published var libreViewPatientId: String = UserDefaults.standard.string(forKey: DefaultsKey.libreViewPatientId) ?? "" {
        didSet {
            UserDefaults.standard.set(libreViewPatientId, forKey: DefaultsKey.libreViewPatientId)
            UserDefaults.standard.set(libreViewPatientId.fnv32Hash, forKey: DefaultsKey.libreViewReceiverId)
        }
    }
    @Published var libreViewReceiverId: Int = UserDefaults.standard.integer(forKey: DefaultsKey.libreViewReceiverId) {
        didSet {
            UserDefaults.standard.set(libreViewReceiverId, forKey: DefaultsKey.libreViewReceiverId)
        }
    }
    @Published var serverStatus: String = "Not contacted yet"
    @Published var lastNFCResult: Libre3NFC.TakeoverResult?
    @Published var lastNFCError: String?
    @Published var selfTestSummary: String = ""

    private var cancellables: Set<AnyCancellable> = []

    /// DiaBLE interconnection:
    init(main: MainDelegate!) {
        self.nfc = main.shimNFC!
        let server = main.shimServer!
        self.server = server
        self.ble = main.shimBLE!

        // Forward child ObservableObject changes up to SwiftUI.
        nfc.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        ble.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    init() {
        let server = AndroidServerClient()
        self.server = server
        self.nfc = Libre3NFC()
        self.ble = Libre3BLEClient(server: server)

        // Forward child ObservableObject changes up to SwiftUI.
        nfc.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
        ble.objectWillChange.sink { [weak self] in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    func applyServerConfig() {
        Task {
            do {
                try server.configure(
                    baseURLString: serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    bearerToken: bearerToken.isEmpty ? nil : bearerToken
                )
                let result = try await server.health()
                serverStatus = "OK — \(result)"
            } catch {
                serverStatus = "Error: \(error.localizedDescription)"
            }
        }
    }

    func runSelfTests() {
        let results = Libre3TestVectors.runAll()
        let pass = results.filter(\.didPass).count
        selfTestSummary = "\(pass)/\(results.count) passed\n" +
        results.map(\.summary).joined(separator: "\n")
    }

    func performTakeover() {
        Task {
            do {
                let receiverId = libreViewReceiverId != 0 ? UInt32(libreViewReceiverId) : libreViewPatientId.fnv32Hash
                let result = try await nfc.performTakeover(receiverId: receiverId, command: 0xA8)
                lastNFCResult = result
                lastNFCError = nil
                ble.takeover = result
                // DiaBLE interconnection:
                // TODO: instantiate a sensor also from the shim
                if main?.app.sensor == nil {
                    main?.app.sensor = Libre3()
                }
                main?.app.sensor?.activationTime = result.activationTime
            } catch {
                lastNFCError = error.localizedDescription
            }
        }
    }

    func performTakepart() {
        Task {
            do {
                let receiverId = libreViewReceiverId != 0 ? UInt32(libreViewReceiverId) : libreViewPatientId.fnv32Hash
                let result = try await nfc.performTakeover(receiverId: receiverId, command: 0xA0)
                lastNFCResult = result
                lastNFCError = nil
                ble.takeover = result
                // DiaBLE interconnection:
                // TODO: instantiate a sensor also from the shim
                if main?.app.sensor == nil {
                    main?.app.sensor = Libre3()
                }
                main?.app.sensor?.activationTime = result.activationTime
            } catch {
                lastNFCError = error.localizedDescription
            }
        }
    }
}


struct AndroidShimContentView: View, LoggingView {

    @Environment(AppState.self) var app
    @Environment(Settings.self) var settings

    var body: some View {
        ShimInnerView(nfc: app.main.shimNFC!, ble: app.main.shimBLE!, model: app.main.shimAppModel!)
    }
}

private struct ShimInnerView: View {

    @Environment(AppState.self) var app
    @Environment(Settings.self) var settings
    @ObservedObject var nfc: Libre3NFC
    @ObservedObject var ble: Libre3BLEClient
    @ObservedObject var model: AndroidShimAppModel

    @State private var receiverId: Int = 0

    var body: some View {
        TabView {
            setupTab.tabItem { Label("Setup", systemImage: "gearshape") }
            nfcTab.tabItem { Label("NFC", systemImage: "wave.3.right") }
            bleTab.tabItem { Label("BLE", systemImage: "antenna.radiowaves.left.and.right") }
            glucoseTab.tabItem { Label("Glucose", systemImage: "drop.fill") }
            logTab.tabItem { Label("Log", systemImage: "text.alignleft") }
        }
    }

    // MARK: - Setup tab

    private var setupTab: some View {
        NavigationStack {
            Form {
                @Bindable var settings = settings
                Section("Android crypto server") {
                    TextField("Base URL (e.g. http://192.168.1.42:8080)",
                              text: $model.serverURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .foregroundStyle(.blue)
                    TextField("Bearer token (optional)", text: $model.bearerToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Apply and ping /health") { model.applyServerConfig() }
                        .buttonStyle(.borderedProminent)
                    Text(model.serverStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("LibreView account") {
                    TextField("Patient UUID", text: $model.libreViewPatientId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.blue)
                        .onChange(of: model.libreViewPatientId) {
                            let trimmed = model.libreViewPatientId.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard UUID(uuidString: trimmed) != nil else { return }
                            let normalized = trimmed.lowercased()
                            if model.libreViewPatientId != normalized {
                                model.libreViewPatientId = normalized
                            }
                            let hash = normalized.fnv32Hash
                            receiverId = Int(hash)
                            model.libreViewReceiverId = Int(hash)
                            settings.activeSensorReceiverId = Int(hash)
                        }
                    let trimmedUUID = model.libreViewPatientId.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedUUID.isEmpty && UUID(uuidString: trimmedUUID) == nil {
                        Text("Enter a valid 36-character UUID")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    LabeledContent("Receiver ID:") {
                        TextField("Receiver ID", value: $receiverId, formatter: NumberFormatter())
                            .keyboardType(.numbersAndPunctuation)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.blue)
                            .onChange(of: receiverId) {
                                settings.activeSensorReceiverId = receiverId
                            }
                    }
                    Text("Used to compute the FNV-32 receiverId baked into the takeover NFC payload. Must match the account that originally activated the sensor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onAppear {
                    receiverId = settings.activeSensorReceiverId
                }

                Section("Self-tests (offline)") {
                    Button("Run all") { model.runSelfTests() }
                    if !model.selfTestSummary.isEmpty {
                        Text(model.selfTestSummary)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Setup")
        }
    }

    // MARK: - NFC tab

    private var nfcTab: some View {
        NavigationStack {
            Form {
                @Bindable var settings = settings
                LabeledContent("Current BLE PIN:") {
                    TextField("BLE PIN", value: $settings.activeSensorBlePIN, formatter: HexDataFormatter())
                        .autocorrectionDisabled()
                        .foregroundStyle(.blue)
                }
                .onChange(of: settings.activeSensorBlePIN) {
                    // TODO
                }

                Section("Take part") {
                    Button {
                        model.performTakepart()
                    } label: {
                        Label("Tap to take part in sensor", systemImage: "wave.3.right")
                    }

                    if model.nfc.isScanning {
                        ProgressView("Scanning...")
                    }
                    if let err = model.lastNFCError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text("Sends 0xA0 instead of 0xA8 — keeps the current BLE PIN unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Takeover") {
                    Button {
                        model.performTakeover()
                    } label: {
                        Label("Tap to take over sensor", systemImage: "wave.3.right")
                    }
                    // .disabled(
                    //      (UUID(uuidString: model.libreViewPatientId.trimmingCharacters(in: .whitespacesAndNewlines)) == nil && model.libreViewReceiverId == 0) || model.nfc.isScanning
                    //  )

                    if model.nfc.isScanning {
                        ProgressView("Scanning...")
                    }
                    if let err = model.lastNFCError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let r = model.lastNFCResult {
                    Section("Result") {
                        LabeledContent("BLE address", value: r.bdAddressString)
                        LabeledContent("BLE PIN", value: r.blePIN.compactHexString)
                        LabeledContent("Activated",
                                       value: Date(timeIntervalSince1970: TimeInterval(r.activationTime))
                            .formatted())
                        DisclosureGroup("patchInfo (24 B)") {
                            Text(r.patchInfo.compactHexString)
                                .font(.system(.caption, design: .monospaced))
                        }
                    }
                }
            }
            .navigationTitle("NFC")
        }
    }

    // MARK: - BLE tab

    private var filteredBLEPeripherals: [Libre3PeripheralRow] {
        model.ble.peripherals.filter { isTwelveCharacterHexCode($0.name) }
    }

    private func isTwelveCharacterHexCode(_ name: String) -> Bool {
        name.range(of: #"^[0-9A-Fa-f]{12}$"#, options: .regularExpression) != nil
    }

    private var bleTab: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    LabeledContent("Connection", value: model.ble.state.rawValue)
                    LabeledContent("Bluetooth", value: model.ble.bluetoothState)
                    LabeledContent("Handshake", value: model.ble.handshakeStage.rawValue)
                    LabeledContent("Session", value: model.ble.hasSession ? "Loaded" : "—")
                    if let kauth = model.ble.exportedKAuth {
                        LabeledContent("kAuth", value: "\(kauth.count) B persisted")
                    }
                }

                Section("Scan") {
                    Button("Start") { model.ble.startScan() }
                    Button("Stop") { model.ble.stopScan() }
                    if filteredBLEPeripherals.isEmpty {
                        Text("No matching peripherals yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredBLEPeripherals) { row in
                            Button {
                                model.ble.connect(to: row)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(row.name)
                                    Text("RSSI \(row.rssi) — \(row.advertisementSummary)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Handshake") {
                    Button("Start handshake (requires NFC takeover + server)") {
                        model.ble.startHandshake()
                    }
                    .disabled(model.lastNFCResult == nil)
                    Button("Disconnect") { model.ble.disconnect() }
                    Button(role: .destructive) {
                        _ = model.ble.clearCachedKAuth()
                    } label: {
                        Label("Clear cached kAuth", systemImage: "trash")
                    }
                    .disabled(model.lastNFCResult == nil)
                    Text("Use this if the sensor was re-paired with another app (e.g. Abbott's Libre 3). The next handshake will take the fresh ECDH path. NFC takeover already clears it automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Diagnostics") {
                    Button("Send Juggluco backfill (history + clinical + events)") {
                        model.ble.sendJugglucoBackfill()
                    }
                    .disabled(!model.ble.hasSession)
                    Text("Fires the three encrypted patch-control commands Juggluco sends after handshake. Some firmware needs these before glucose starts streaming.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("BLE")
        }
    }

    // MARK: - Glucose tab

    private var glucoseTab: some View {
        NavigationStack {
            Form {
                if let g = model.ble.latestGlucose {
                    Section("Current") {
                        LabeledContent("mg/dL", value: "\(g.uncappedCurrentMgDl)")
                        LabeledContent("Rate of change",
                                       value: String(format: "%.2f mg/dL/min", g.rateOfChangePerMinute))
                        LabeledContent("Projected", value: "\(g.projectedGlucose) mg/dL")
                        LabeledContent("Life count", value: "\(g.lifeCount)")
                        if let when = model.ble.latestGlucoseReceivedAt {
                            LabeledContent("Received", value: when.formatted())
                        }
                    }
                } else {
                    Section {
                        Text("No glucose data yet. Complete the handshake and wait ~1 minute.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let s = model.ble.latestPatchStatus {
                    Section("Patch status") {
                        LabeledContent("State", value: "\(s.patchState)")
                        LabeledContent("Life count", value: "\(s.lifeCount)")
                        LabeledContent("Current life count", value: "\(s.currentLifeCount)")
                        if let when = model.ble.latestPatchStatusReceivedAt {
                            LabeledContent("Received", value: when.formatted())
                        }
                    }
                }

                let samples = model.ble.historicSamples
                if !samples.isEmpty {
                    Section("Historical (5-min)") {
                        LabeledContent("Samples", value: "\(samples.count)")
                        if let first = samples.first, let last = samples.last {
                            if let firstDate = model.ble.date(forLifeCount: first.lifeCount),
                               let lastDate = model.ble.date(forLifeCount: last.lifeCount) {
                                LabeledContent("Range",
                                               value: "\(firstDate.formatted(date: .omitted, time: .shortened)) – \(lastDate.formatted(date: .omitted, time: .shortened))")
                            }
                            LabeledContent("Range (lifeCount)",
                                           value: "\(first.lifeCount) – \(last.lifeCount)")
                        }
                        if let when = model.ble.latestHistoryReceivedAt {
                            LabeledContent("Last received", value: when.formatted())
                        }
                        ForEach(samples.reversed()) { s in
                            let label: String = {
                                if let d = model.ble.date(forLifeCount: s.lifeCount) {
                                    return d.formatted(date: .omitted, time: .shortened)
                                }
                                return "lifeCount \(s.lifeCount)"
                            }()
                            LabeledContent(label, value: "\(s.mgDl) mg/dL")
                        }
                    }
                }
            }
            .navigationTitle("Glucose")
        }
    }

    // MARK: - Log tab

    private var logMessagesText: String {
        model.ble.logs.map(\.message).joined(separator: "\n")
    }

    private var logTab: some View {
        NavigationStack {
            List(model.ble.logs) { entry in
                Text(entry.message)
                    .font(.system(.caption, design: .monospaced))
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: logMessagesText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.ble.logs.isEmpty)

                    Button("Clear") { model.ble.clearLog() }
                }
            }
            .navigationTitle("Log")
        }
    }
}

#Preview {
    AndroidShimContentView()
}

