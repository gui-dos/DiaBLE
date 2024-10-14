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

    @State private var onlineCountdown: Int = 0
    @State private var readingCountdown: Int = 0

    @State private var libreLinkUpResponse: String = "[...]"

    @State private var showingCredentials: Bool = false

    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()


    var body: some View {
        VStack {

            HStack {

                Button {
                    settings.selectedService = settings.selectedService == .nightscout ? .libreLinkUp : .nightscout
                } label: {
                    Image(settings.selectedService.rawValue).resizable().frame(width: 32, height: 32).shadow(color: .cyan, radius: 4.0 )
                }

                VStack(spacing: 0) {

                    Text("\(settings.selectedService.rawValue)")
                        .foregroundStyle(.tint)

                    HStack {

                        Button {
                            withAnimation { showingCredentials.toggle() }
                        } label: {
                            Image(systemName: showingCredentials ? "person.crop.circle.fill" : "person.crop.circle").resizable().frame(width: 20, height: 20)
                                .foregroundStyle(.blue)
                        }

                        Button {
                            withAnimation { settings.libreLinkUpScrapingLogbook.toggle() }
                            if settings.libreLinkUpScrapingLogbook {
                                libreLinkUpResponse = "[...]"
                                Task {
                                    libreLinkUpResponse = await app.main.libreLinkUp?.reload(enforcing: true) ?? "[...]"
                                }
                            }
                        } label: {
                            Image(systemName: settings.libreLinkUpScrapingLogbook ? "book.closed.circle.fill" : "book.closed.circle").resizable().frame(width: 20, height: 20)
                                .foregroundStyle(.blue)
                        }

                        Text(onlineCountdown > -1 ? "\(onlineCountdown) s" : "...")
                            .fixedSize()
                            .foregroundStyle(.cyan)
                            .font(.footnote.monospacedDigit())
                            .onReceive(timer) { _ in
                                // workaround: watchOS fails converting the interval to an Int32
                                if settings.lastOnlineDate == Date.distantPast {
                                    onlineCountdown = 0
                                } else {
                                    onlineCountdown = settings.onlineInterval * 60 - Int(Date().timeIntervalSince(settings.lastOnlineDate))
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 0) {
                    Button {
                        app.main.rescan()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 16, height: 16)
                            .foregroundStyle(.blue)
                    }
                    Text(app.deviceState != "Disconnected" && (readingCountdown > 0 || app.deviceState == "Reconnecting...") ?
                         "\(readingCountdown) s" : "...")
                    .fixedSize()
                    .foregroundStyle(.orange)
                    .font(.footnote.monospacedDigit())
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

            if showingCredentials {

                @Bindable var settings = settings
                
                HStack {

                    if settings.selectedService == .nightscout {
                        TextField("Nightscout URL", text: $settings.nightscoutSite)
                            .textContentType(.URL)
                        SecureField("token", text: $settings.nightscoutToken)
                            .textContentType(.password)

                    } else if settings.selectedService == .libreLinkUp {
                        TextField("email", text: $settings.libreLinkUpEmail)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .onSubmit {
                                settings.libreLinkUpUserId = ""
                                libreLinkUpResponse = "[Logging in...]"
                                Task {
                                    libreLinkUpResponse = await app.main.libreLinkUp?.reload(enforcing: true) ?? "[...]"
                                }
                            }
                        SecureField("password", text: $settings.libreLinkUpPassword)
                            .textContentType(.password)
                            .onSubmit {
                                settings.libreLinkUpUserId = ""
                                libreLinkUpResponse = "[Logging in...]"
                                Task {
                                    libreLinkUpResponse = await app.main.libreLinkUp?.reload(enforcing: true) ?? "[...]"
                                }
                            }
                    }
                }
                .font(.footnote)

                Toggle(isOn: $settings.libreLinkUpFollowing) {
                    Text("Follower")
                }
                .onChange(of: settings.libreLinkUpFollowing) {
                    settings.libreLinkUpUserId = ""
                    libreLinkUpResponse = "[Logging in...]"
                    Task {
                        libreLinkUpResponse = await app.main.libreLinkUp?.reload(enforcing: true) ?? "[...]"
                    }
                }
            }

            if settings.selectedService == .nightscout {

                ScrollView(showsIndicators: true) {

                    VStack(spacing: 0) {

                        if history.nightscoutValues.count > 0 {
                            let twelveHours = Double(12 * 60 * 60)  // TODO: the same as LLU
                            let now = Date()
                            let nightscoutHistory = history.nightscoutValues.filter { now.timeIntervalSince($0.date) <= twelveHours }
                            Chart(nightscoutHistory) {
                                PointMark(x: .value("Time", $0.date),
                                          y: .value("Glucose", $0.value)
                                )
                                .foregroundStyle(.cyan)
                                .symbolSize(6)
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(), anchor: .top)
                                }
                            }
                            .padding()
                            .frame(maxHeight: 64)
                        }

                        List {
                            ForEach(history.nightscoutValues) { glucose in
                                (Text("\(String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)])) \(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d")").bold())
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(minHeight: 64)
                    }
                }
                // .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.cyan)
                .task {
                    if let (values, _) = try? await app.main.nightscout?.read() {
                        history.nightscoutValues = values
                        log("Nightscout: values read count \(history.nightscoutValues.count)")
                    }
                }
            }


            if settings.selectedService == .libreLinkUp {

                ScrollView(showsIndicators: true) {

                    VStack(spacing: 0) {

                        if app.main.libreLinkUp?.history.count ?? 0 > 0 {
                            Chart(app.main.libreLinkUp!.history) {
                                PointMark(x: .value("Time", $0.glucose.date),
                                          y: .value("Glucose", $0.glucose.value)
                                )
                                .foregroundStyle($0.color.color)
                                .symbolSize(6)
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                                    AxisGridLine()
                                    AxisTick()
                                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(), anchor: .top)
                                }
                            }
                            .padding()
                            .frame(maxHeight: 64)
                        }

                        HStack {
                            List {
                                ForEach(app.main.libreLinkUp?.history ?? [LibreLinkUpGlucose]()) { libreLinkUpGlucose in
                                    let glucose = libreLinkUpGlucose.glucose
                                    (Text("\(!settings.libreLinkUpScrapingLogbook ? String(glucose.source[..<(glucose.source.lastIndex(of: " ") ?? glucose.source.endIndex)]) + " " : "")\(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d") ").bold() + Text(libreLinkUpGlucose.trendArrow?.symbol ?? "").font(.title3))
                                        .foregroundStyle(libreLinkUpGlucose.color.color)
                                        .padding(.vertical, 1)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                            .onReceive(minuteTimer) { _ in
                                Task {
                                    libreLinkUpResponse = await app.main.libreLinkUp?.reload() ?? "[...]"
                                }
                            }

                            if settings.libreLinkUpScrapingLogbook {
                                // TODO: alarms
                                List {
                                    ForEach(app.main.libreLinkUp?.logbookHistory ?? [LibreLinkUpGlucose]()) { libreLinkUpGlucose in
                                        let glucose = libreLinkUpGlucose.glucose
                                        (Text("\(glucose.date.shortDateTime)") + Text("  \(glucose.value, specifier: "%3d") ").bold() + Text(libreLinkUpGlucose.trendArrow!.symbol).font(.title3))
                                            .foregroundStyle(libreLinkUpGlucose.color.color)
                                            .padding(.vertical, 1)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                }
                            }
                        }
                        // .font(.system(.footnote, design: .monospaced))
                        .frame(minHeight: 64)

                        Text(libreLinkUpResponse)
                        //  .font(.system(.footnote, design: .monospaced))
                        //  .foregroundStyle(Color(.lightGray))
                            .font(.footnote)
                            .foregroundStyle(Color(.lightGray))
                    }

                }
                .task {
                    libreLinkUpResponse = await app.main.libreLinkUp?.reload() ?? "[...]"
                }
            }
        }
        .padding(.top, -4)
        .edgesIgnoringSafeArea([.bottom])
        .buttonStyle(.plain)
        .navigationTitle { Text("Online").foregroundStyle(.tint) }
        .toolbarForegroundStyle(.blue, for: .automatic)
        .tint(.blue)
    }
}


#Preview {
    OnlineView()
        .environment(AppState.test(tab: .online))
        .environment(History.test)
        .environment(Settings())
}
