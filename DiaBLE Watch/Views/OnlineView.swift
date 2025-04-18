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

    @State private var onlineCountdown: Int64 = 0
    @State private var readingCountdown: Int64 = 0

    @State private var showingCredentials: Bool = false
    @State private var showingPercentiles: Bool = false


    var body: some View {
        VStack {

            HStack {

                Button {
                    settings.selectedService =
                    settings.selectedService == .nightscout ? .libreLinkUp :
                    // settings.selectedService == .libreLinkUp ? .dexcomShare :
                        .nightscout
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
                            withAnimation { showingPercentiles.toggle() }
                        } label: {
                            Image(systemName: showingPercentiles ? "chart.line.uptrend.xyaxis.circle.fill" : "chart.line.uptrend.xyaxis.circle").resizable().frame(width: 20, height: 20)
                                .foregroundStyle(.blue)
                        }

                        Button {
                            withAnimation { settings.libreLinkUpScrapingLogbook.toggle() }
                            if settings.libreLinkUpScrapingLogbook {
                                app.serviceResponse = "[...]"
                                Task {
                                    await app.main.libreLinkUp?.reload(enforcing: true)
                                }
                            }
                        } label: {
                            Image(systemName: settings.libreLinkUpScrapingLogbook ? "book.closed.circle.fill" : "book.closed.circle").resizable().frame(width: 20, height: 20)
                                .foregroundStyle(.blue)
                        }

                        Text(onlineCountdown != 0 ? "\(String(onlineCountdown).count > 5 ? "..." : "\(onlineCountdown) s")" : " ")
                            .fixedSize()
                            .foregroundStyle(.cyan)
                            .font(.footnote.monospacedDigit())
                            .contentTransition(.numericText(countsDown: true))
                            .onReceive(app.timer) { _ in
                                withAnimation {
                                    onlineCountdown = Int64(settings.onlineInterval * 60) - Int64(Date().timeIntervalSince(settings.lastOnlineDate))
                                }
                            }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 0) {
                    Button {
                        app.main.rescan()
                    } label: {
                        Image(systemName: "arrow.clockwise.circle").resizable().frame(width: 20, height: 20)
                            .foregroundStyle(.blue)
                    }
                    Text(app.deviceState != "Disconnected" && (readingCountdown > 0 || app.deviceState == "Reconnecting...") ?
                         "\(readingCountdown) s" : "...")
                    .fixedSize()
                    .foregroundStyle(.orange)
                    .font(.footnote.monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .onReceive(app.timer) { _ in
                        withAnimation {
                            readingCountdown = Int64(settings.readingInterval * 60) - Int64(Date().timeIntervalSince(app.lastConnectionDate))
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
                .font(.footnote)

                Toggle(isOn: $settings.libreLinkUpFollowing) {
                    Text("Follower")
                }
                .onChange(of: settings.libreLinkUpFollowing) {
                    settings.libreLinkUpUserId = ""
                    app.serviceResponse = "[Logging in...]"
                    Task {
                        await app.main.libreLinkUp?.reload(enforcing: true)
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
                                PointMark(
                                    x: .value("Time", $0.date),
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

                        if showingPercentiles {
                            if let percentiles = app.main.libreLinkUp?.percentiles,
                               percentiles.count > 0 {

                                @Bindable var settings = settings

                                let midnight = Calendar.current.startOfDay(for: Date.now)

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
                                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                                        AxisGridLine()
                                        AxisTick()
                                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute(), anchor: .top)
                                    }
                                }
                                .padding()
                                .frame(maxHeight: 80)

                                if percentiles.count > 0 {

                                    Stepper(value: $settings.libreLinkUpPeriod,
                                            in: 5 ... 100) {
                                        Text("\(settings.libreLinkUpPeriod) days")
                                            .font(.footnote)
                                    } onEditingChanged: { _ in
                                        app.main.libreLinkUp?.percentiles = []
                                        Task {
                                            await app.main.libreLinkUp?.reload(enforcing: true)
                                        }
                                    }
                                }
                            }

                        } else if app.main.libreLinkUp?.history.count ?? 0 > 0 {
                            Chart(app.main.libreLinkUp!.history) {
                                PointMark(
                                    x: .value("Time", $0.glucose.date),
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

                        Text(app.serviceResponse)
                        //  .font(.system(.footnote, design: .monospaced))
                        //  .foregroundStyle(Color(.lightGray))
                            .font(.footnote)
                            .foregroundStyle(Color(.lightGray))
                    }

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
