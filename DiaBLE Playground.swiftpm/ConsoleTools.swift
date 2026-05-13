import Foundation
import SwiftUI
import TabularData


struct ShellView: View, LoggingView {

    @Environment(AppState.self) var app: AppState
    @Environment(Log.self) var log: Log
    @Environment(Settings.self) var settings: Settings

    @State private var showingStack = false

    @State private var showingFileImporter = false
    @State private var libreviewCSV = ""


    var body: some View {

        VStack(spacing: 0) {

            if showingStack {
                VStack (spacing: 0) {

                    HStack {

                        TextField("LibreView CSV", text: $libreviewCSV)
                            .textFieldStyle(.roundedBorder)
                            .truncationMode(.head)

                        Button {
                            showingFileImporter = true
                        } label: {
                            Image(systemName: "doc.circle")
                                .font(.system(size: 32))
                        }
                        .fileImporter(
                            isPresented: $showingFileImporter,
                            allowedContentTypes: [.commaSeparatedText]
                        ) { result in
                            switch result {
                            case .success(let file):
                                guard file.startAccessingSecurityScopedResource() else { return }
                                defer { file.stopAccessingSecurityScopedResource() }
                                libreviewCSV = file.path
                                let fileManager = FileManager.default
                                if var csvData = fileManager.contents(atPath: libreviewCSV) {
                                    log("cat \(libreviewCSV)\n\(csvData.prefix(800).string)\n[...]\n\(csvData.suffix(800).string)")
                                    csvData = csvData[(csvData.firstIndex(of: 10)! + 1)...]  //trim first line
                                    do {
                                        var options = CSVReadingOptions()
                                        options.addDateParseStrategy(Date.ParseStrategy(format: "\(day: .twoDigits)-\(month: .twoDigits)-\(year: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)", timeZone: .current))
                                        let dataFrame = try DataFrame(csvData: csvData, options: options)
                                        // ["Device", "Serial Number", "Device Timestamp", "Record Type", "Historic Glucose mg/dL", "Scan Glucose mg/dL", "Non-numeric Rapid-Acting Insulin", "Rapid-Acting Insulin (units)", "Non-numeric Food", "Carbohydrates (grams)", "Carbohydrates (servings)", "Non-numeric Long-Acting Insulin", "Long-Acting Insulin (units)", "Notes", "Strip Glucose mg/dL", "Ketone mmol/L", "Meal Insulin (units)", "Correction Insulin (units)", "User Change Insulin (units)"]
                                        log("TabularData: column names: \(dataFrame.columns.map(\.name))")
                                        log("TabularData:\n\(dataFrame)")
                                        let lastRow = dataFrame.rows.last!
                                        let lastDeviceSerial = lastRow["Serial Number"] as! String
                                        log("TabularData: last device serial: \(lastDeviceSerial)")
                                        var history = try DataFrame(csvData: csvData,
                                                                    columns: ["Serial Number", "Device Timestamp", "Record Type", "Historic Glucose mg/dL"],
                                                                    types: ["Serial Number": .string, "Device Timestamp": .date, "Record Type": .integer, "Historic Glucose mg/dL": .integer],
                                                                    options: options)
                                            .sorted(on: "Device Timestamp", order: .descending)
                                        history.renameColumn("Device Timestamp", to: "Date")
                                        history.renameColumn("Record Type", to: "Type")
                                        history.renameColumn("Historic Glucose mg/dL", to: "Glucose")
                                        var formattingOptions = FormattingOptions(maximumLineWidth: 80, includesColumnTypes: false)
                                        formattingOptions.includesRowIndices = false
                                        log("TabularData: history:\n\(history.description(options: formattingOptions))")
                                        let filteredHistory = history
                                            .filter(on: "Serial Number", String.self) { $0! == lastDeviceSerial }
                                            .filter(on: "Glucose", Int.self) { $0 != nil }
                                            .selecting(columnNames: ["Date", "Glucose"])
                                        formattingOptions.maximumLineWidth = 32
                                        log("TabularData: filtered history:\n\(filteredHistory.description(options: formattingOptions))")
                                    } catch {
                                        log("TabularData: error: \(error.localizedDescription)")
                                    }
                                }
                            case .failure(let error):
                                log("\(error.localizedDescription)")
                            }
                        }

                    }
                    .padding(4)

                }

                CrcCalculator()
                    .padding(4)

            }
        }
        .background(.thinMaterial, ignoresSafeAreaEdges: [])
        .toolbar {
            Button {
                withAnimation { showingStack.toggle() }
            } label: {
                VStack(spacing: 0) {
                    Image(systemName: showingStack ? "fossil.shell.fill" : "fossil.shell")
                    Text("Shell").font(.footnote)
                }
            }
        }
    }
}


#Preview {
    ShellView()
        .preferredColorScheme(.dark)
        .environment(AppState.test(tab: .console))
        .environment(Log())
        .environment(Settings())
}


struct CrcCalculator: View {

    @State private var hexString = ""
    @State private var crc = "0000"
    @State private var computedCrc = "0000"
    @State private var trailingCrc = true

    @FocusState private var focused: Bool

    func updateCRC() {
        hexString = hexString.filter { $0.isHexDigit || $0 == " " }
        var validatedString = hexString == "" ? "00" : hexString
        validatedString = validatedString.replacingOccurrences(of: " ", with: "")
        if validatedString.count % 2 == 1 {
            validatedString = "0" + validatedString
        }
        if validatedString.count < 8 {
            validatedString = String((String(repeating: "0", count: 8 - validatedString.count) + validatedString).suffix(8))
        }
        let validatedBytes = validatedString.bytes
        if trailingCrc {
            crc = Data(String(validatedString.suffix(4)).bytes.reversed()).hex
            computedCrc = validatedBytes.dropLast(2).crc16.hex
        } else {
            crc = Data(String(validatedString.prefix(4)).bytes.reversed()).hex
            computedCrc = validatedBytes.dropFirst(2).crc16.hex
        }
    }


    var body: some View {

        VStack {
            TextField("Hexadecimal string", text: $hexString, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.footnote, design: .monospaced))
                .truncationMode(.head)
                .focused($focused)
                .toolbar {
                    ToolbarItem(placement: .keyboard) {
                        Button("Done") {
                            focused = false
                        }
                    }
                }

            HStack {

                VStack(alignment: .leading) {
                    Text("CRC: \(crc == "0000" ? "---" : crc)")
                    Text("Computed: \(crc == "0000" ? "---" : computedCrc)")
                }
                .foregroundStyle(crc != "0000" && crc == computedCrc ? .green : .primary)

                Spacer()

                Toggle("Trailing CRC", isOn: $trailingCrc)
                    .controlSize(.mini)
                    .fixedSize()
                    .onChange(of: trailingCrc) { updateCRC() }
            }

        }
        .font(.subheadline)
        .onChange(of: hexString) { updateCRC() }
    }
}
