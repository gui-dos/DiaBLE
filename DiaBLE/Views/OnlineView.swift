import SwiftUI
import Charts


extension MeasurementColor {
    var color: Color {
        switch self {
        case .green:  .green
        case .yellow: .yellow
        case .orange: .orange
        case .red:    .red
        }
    }
}


struct OnlineView: View, LoggingView {
    @Environment(AppState.self) var app: AppState
    @Environment(History.self) var history: History
    @Environment(Settings.self) var settings: Settings

    @Environment(\.colorScheme) var colorScheme

    @State private var showingNFCAlert = false
    @State private var onlineCountdown: Int64 = 0
    @State private var readingCountdown: Int64 = 0


    var body: some View {
        NavigationStack {

            // Workaround to avoid top textfields scrolling offscreen in iOS 14
            GeometryReader { _ in
                VStack(spacing: 0) {

                    HStack(alignment: .top, spacing: 2) {

                        Button {
                            settings.selectedService =
                            settings.selectedService == .nightscout ? .libreLinkUp :
                            // settings.selectedService == .libreLinkUp ? .dexcomShare :
                                .nightscout
                        } label: {
                            Image(settings.selectedService.rawValue).resizable().frame(width: 32, height: 32).shadow(color: .cyan, radius: 4.0 )
                        }
                        .padding(.top, 8).padding(.trailing, 4)

                        VStack(spacing: 0) {

                            @Bindable var settings = settings

                            if settings.selectedService == .nightscout {
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text("https://")
                                        .foregroundStyle(Color(.lightGray))
                                    TextField("Nightscout URL", text: $settings.nightscoutSite)
                                        .keyboardType(.URL)
                                        .textContentType(.URL)
                                        .autocorrectionDisabled(true)
                                }
                                SecureField("token", text: $settings.nightscoutToken)
                                    .textContentType(.password)


                            } else if settings.selectedService == .libreLinkUp {
                                TextField("email", text: $settings.libreLinkUpEmail)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .onSubmit {
                                        settings.libreLinkUpUserId = ""
                                        app.serviceResponse = "[Logging in...]"
                                        Task {
                                            await app.main.libreLinkUp?.reload(enforcing: true)
                                        }
                                    }
                                SecureField("password", text: $settings.libreLinkUpPassword)
                                    .textContentType(.password)
                                    .onSubmit {
                                        settings.libreLinkUpUserId = ""
                                        app.serviceResponse = "[Logging in...]"
                                        Task {
                                            await app.main.libreLinkUp?.reload(enforcing: true)
                                        }
                                    }
                            }
                        }

                        Spacer()

                        Button {
                            withAnimation { settings.libreLinkUpFollowing.toggle() }
                            app.serviceResponse = "[Logging in...]"
                            settings.libreLinkUpUserId = ""
                            Task {
                                await app.main.libreLinkUp?.reload(enforcing: true)
                            }
                        } label: {
                            Image(systemName: settings.libreLinkUpFollowing ? "f.circle.fill" : "f.circle").font(.title)
                        }

                        VStack(spacing: 0) {

                            Button {
                                withAnimation { settings.libreLinkUpScrapingLogbook.toggle() }
                                if settings.libreLinkUpScrapingLogbook {
                                    app.serviceResponse = "[...]"
                                    Task {
                                        await app.main.libreLinkUp?.reload(enforcing: true)
                                    }
                                }
                            } label: {
                                Image(systemName: settings.libreLinkUpScrapingLogbook ? "book.closed.circle.fill" : "book.closed.circle").font(.title)
                            }

                            Text(onlineCountdown != 0 ? "\(String(onlineCountdown).count > 5 ? "..." : "\(onlineCountdown) s")" : " ")
                                .fixedSize()
                                .foregroundStyle(.cyan)
                                .font(.caption.monospacedDigit())
                                .onReceive(app.timer) { _ in
                                    onlineCountdown = Int64(settings.onlineInterval * 60) - Int64(Date().timeIntervalSince(settings.lastOnlineDate))
                                }
                        }

                        VStack(spacing: 0) {

                            // TODO: reload web page

                            Button {
                                app.main.rescan()
                            } label: {
                                Image(systemName: "arrow.clockwise.circle").font(.title)
                            }

                            Text(!app.deviceState.isEmpty && app.deviceState != "Disconnected" && (readingCountdown > 0 || app.deviceState == "Reconnecting...") ?
                                 "\(readingCountdown) s" : "...")
                            .fixedSize()
                            .foregroundStyle(.orange)
                            .font(.caption.monospacedDigit())
                            .onReceive(app.timer) { _ in
                                readingCountdown = Int64(settings.readingInterval * 60) - Int64(Date().timeIntervalSince(app.lastConnectionDate))
                            }
                        }

                        Button {
                            if app.main.nfc.isAvailable {
                                app.main.nfc.startSession()
                                Task {
                                    app.main.healthKit?.read()
                                    if let (values, _) = try? await app.main.nightscout?.read() {
                                        history.nightscoutValues = values
                                    }
                                }
                            } else {
                                showingNFCAlert = true
                            }
                        } label: {
                            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                .font(.title)
                                .symbolEffect(.variableColor.reversing, isActive: app.deviceState == "Connected")
                        }
                        .alert("NFC not supported", isPresented: $showingNFCAlert) {
                        } message: {
                            Text("This device doesn't allow scanning the Libre.")
                        }
                        .padding(.top, 2)

                    }
                    .foregroundStyle(.tint)
                    .padding(.bottom, 4)
                    #if targetEnvironment(macCatalyst)
                    .padding(.horizontal, 15)
                    #endif

                    if settings.selectedService == .nightscout {

                        @Bindable var app = app

                        WebView(site: settings.nightscoutSite, query: "token=\(settings.nightscoutToken)", delegate: app.main.nightscout )
                            .frame(height: UIScreen.main.bounds.size.height * 0.60)
                            .alert("JavaScript", isPresented: $app.showingJSConfirmAlert) {
                                Button("OK") { log("JavaScript alert: selected OK") }
                                Button("Cancel", role: .cancel) { log("JavaScript alert: selected Cancel") }
                            } message: {
                                Text(app.jsConfirmAlertMessage)
                            }

                        List {
                            ForEach(history.nightscoutValues) { glucose in
                                (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d")").bold())
                                    .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets())
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .listStyle(.plain)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.cyan)
                        #if targetEnvironment(macCatalyst)
                        .padding(.leading, 15)
                        #endif
                        .task {
                            if let (values, _) = try? await app.main.nightscout?.read() {
                                history.nightscoutValues = values
                                log("Nightscout: values read count \(history.nightscoutValues.count)")
                            }
                        }
                    }


                    if settings.selectedService == .libreLinkUp {
                        VStack {

                            if app.main.libreLinkUp?.history.count ?? 0 > 0 {
                                Chart(app.main.libreLinkUp!.history) {
                                    PointMark(
                                        x: .value("Time", $0.glucose.date),
                                        y: .value("Glucose", $0.glucose.value)
                                    )
                                    .foregroundStyle($0.color.color)
                                    .symbolSize(12)
                                }
                                .chartXAxis {
                                    AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                                        AxisGridLine()
                                        AxisTick()
                                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(), anchor: .top)
                                    }
                                }
                                .padding()
                            }

                            HStack {

                                List {
                                    ForEach(app.main.libreLinkUp?.history ?? [LibreLinkUpGlucose]()) { libreLinkUpGlucose in
                                        let glucose = libreLinkUpGlucose.glucose
                                        (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d") ").bold() + Text(libreLinkUpGlucose.trendArrow?.symbol ?? "").font(.subheadline))
                                            .foregroundStyle(libreLinkUpGlucose.color.color)
                                            .fixedSize(horizontal: false, vertical: true).listRowInsets(EdgeInsets())
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                                .onReceive(app.minuteTimer) { _ in
                                    Task {
                                        await app.main.libreLinkUp?.reload()
                                    }
                                }

                                if settings.libreLinkUpScrapingLogbook {
                                    // TODO: alarms
                                    List {
                                        ForEach(app.main.libreLinkUp?.logbookHistory ?? [LibreLinkUpGlucose]()) { libreLinkUpGlucose in
                                            let glucose = libreLinkUpGlucose.glucose
                                            (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d") ").bold() + Text(libreLinkUpGlucose.trendArrow!.symbol).font(.subheadline))
                                                .foregroundStyle(libreLinkUpGlucose.color.color)
                                                .fixedSize(horizontal: false, vertical: true)
                                                .listRowInsets(EdgeInsets())
                                        }
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                    }
                                }
                            }
                            .listStyle(.plain)
                            .font(.system(.caption, design: .monospaced))

                            if let percentiles = app.main.libreLinkUp?.percentiles {

                                @Bindable var settings = settings

                                let midnight = Calendar.current.startOfDay(for: Date.now)

                                HStack {

                                    Chart {
                                        ForEach(percentiles, id: \.time) {
                                            AreaMark(
                                                x: .value("Time", midnight + TimeInterval($0.time)),
                                                yStart: .value("P5", $0.percentile5),
                                                yEnd: .value("P95", $0.percentile95),
                                                series: .value("", 0)
                                            )
                                            .foregroundStyle(.blue)
                                        }
                                        ForEach(percentiles, id: \.time) {
                                            AreaMark(
                                                x: .value("Time", midnight + TimeInterval($0.time)),
                                                yStart: .value("P25", $0.percentile25),
                                                yEnd: .value("P75", $0.percentile75),
                                                series: .value("", 1)
                                            )
                                            .foregroundStyle(.cyan)
                                        }
                                        ForEach(percentiles, id: \.time) {
                                            LineMark(
                                                x: .value("Time", midnight + TimeInterval($0.time)),
                                                y: .value("P50", $0.percentile50),
                                                series: .value("", 2)
                                            )
                                            .foregroundStyle(.white)
                                        }
                                    }
                                    .chartXAxis {
                                        AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                                            AxisGridLine()
                                            AxisTick()
                                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(), anchor: .top)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    if percentiles.count > 0 {
                                        VStack {
                                            TextField("days", value: $settings.libreLinkUpPeriod,
                                                      formatter: NumberFormatter()
                                            )
                                            .keyboardType(.numbersAndPunctuation)
                                            .multilineTextAlignment(.center)
                                            .foregroundStyle(.blue)
                                            .onSubmit {
                                                app.main.libreLinkUp?.percentiles = []
                                                Task {
                                                    await app.main.libreLinkUp?.reload(enforcing: true)
                                                }
                                            }
                                            Text("days")
                                            Stepper("", value: $settings.libreLinkUpPeriod, in: 5...100) { _ in
                                                app.main.libreLinkUp?.percentiles = []
                                                Task {
                                                    await app.main.libreLinkUp?.reload(enforcing: true)
                                                }
                                            }
                                            .scaleEffect(0.6)
                                        }
                                        .frame(maxWidth: 56)
                                    }

                                }
                            }

                            ScrollView(showsIndicators: true) {
                                Text(app.serviceResponse)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(colorScheme == .dark ? Color(.lightGray) : Color(.darkGray))
                                    .textSelection(.enabled)
                            }

                        }
                        #if targetEnvironment(macCatalyst)
                        .padding(.leading, 15)
                        #endif

                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Online")
        }
    }
}


#Preview {
    ContentView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .online))
        .environment(Log())
        .environment(History.test)
        .environment(Settings())
}
