import Foundation


class LibreLink {

    public static let countryIds = ["AR", "AU", "AT", "BH", "BE", "BR", "CA", "CL", "CO", "CZ", "HR", "DK", "EG", "FI", "FR", "DE", "GR", "HK", "IN", "IE", "IL", "IT", "JO", "JP", "KW", "LU", "LB", "MX", "NL", "NO", "NZ", "OM", "PL", "PT", "QA", "SA", "SG", "ZA", "ES", "SE", "SI", "SK", "CH", "TR", "TW", "AE", "GB", "US"] + ["CN", "RU"]

    // TODO: verify `com.abbott.librelink.xx`, `com.abbott.librelink.xx2` and `com.abbott.libre3.xx` CFBundleIdentifier's
    // https://apps.apple.com/xx/developer/abbott-labs/id1027177119
    //
    // .libre1: "FreeStyle LibreLink – XX" - https://apps.apple.com/xx/app/freestyle-librelink-xx/idxxxxxxxxxx
    // .libre2: "FreeStyle Libre 2 – XX"   - https://apps.apple.com/xx/app/freestyle-libre-2-xx/idxxxxxxxxxx
    // .libre3: "FreeStyle Libre 3 - XX"   - https://apps.apple.com/xx/app/freestyle-libre-3-xx/idxxxxxxxxxx

    public static let appStoreIds: [String: [UInt64: SensorFamily]] = [
        "ae": [1303805538: .libre1],
        "ar": [1449777200: .libre1],
        "at": [6446912740: .libre3, 1307002746: .libre1],
        "au": [1331664436: .libre1],
        "be": [1610189706: .libre3, 1307005072: .libre1],
        "bh": [1404613642: .libre1],
        "br": [1448904780: .libre1],
        "ca": [1472261764: .libre2],
        "ch": [1610191342: .libre3, 1307016232: .libre1],
        "cl": [1444948958: .libre1],
        "cn": [1401595601: .libre1], // TODO: 瞬感宝 -> "%E7%9E%AC%E6%84%9F%E5%AE%9D"
        "co": [1444948961: .libre1],
        "cz": [1620058766: .libre1],
        "de": [1525101160: .libre3],
        "dk": [1459182321: .libre1],
        "eg": [1620058780: .libre1],
        "es": [1610196996: .libre3, 1307013620: .libre1],
        "fi": [1610184646: .libre3, 1307006148: .libre1],
        "fr": [1610185297: .libre3, 1307006511: .libre1],
        "gb": [1610185835: .libre3, 1307017454: .libre1, 1670445335: .lingo],
        "gr": [1510846765: .libre1],
        "hk": [1449774428: .libre1],
        "hr": [1624981463: .libre1],
        "ie": [1307010255: .libre1],
        "il": [1444947368: .libre1],
        "in": [6448857658: .libre1],
        "it": [1610190599: .libre3, 1307012550: .libre1],
        "jo": [1404614365: .libre1],
        "jp": [1449296861: .libre1],
        "kw": [1404615911: .libre1],
        "lb": [1404615931: .libre1],
        "lu": [1459185581: .libre1],
        "mx": [1444948977: .libre1],
        "nl": [1610186860: .libre3, 1307013272: .libre1],
        "no": [1610187870: .libre3, 1455572221: .libre1],
        "nz": [1449682730: .libre1],
        "om": [1404617727: .libre1],
        "pl": [1404591671: .libre1],
        "pt": [1459186046: .libre1],
        "qa": [6466910868: .libre3, 1404618364: .libre1],
        "sa": [1338938836: .libre1],
        "se": [1610188806: .libre3, 1307014059: .libre1],
        "sg": [1398447126: .libre1],
        "si": [1625156441: .libre1],
        "sk": [1625157323: .libre1],
        "ru": [1523326671: .libre2, 1449293800: .libre1],
        "tr": [1439483369: .libre1],
        "tw": [1495861686: .libre1],
        "za": [1444947746: .libre1],
        "us": [1524572429: .libre3, 1472261444: .libre2, 1325992472: .libre1, 1670445335: .lingo]
        // TODO: developer/abbott/id402314324: Lingo by Abbott -> lingo-by-abbott
        // TODO: 6501954823: MyFreeStyle -> myfreestyle
    ]
}


// https://github.com/timoschlueter/nightscout-librelink-up
// https://gist.github.com/khskekec/6c13ba01b10d3018d816706a32ae8ab2


enum LibreLinkUpError: LocalizedError {
    case noConnection
    case notAuthenticated
    case jsonDecoding
    case touMustBeReaccepted

    var errorDescription: String? {
        switch self {
        case .noConnection:        "No connection"
        case .notAuthenticated:    "Not authenticated"
        case .jsonDecoding:        "JSON decoding error"
        case .touMustBeReaccepted: "Terms of Use must be re-accepted by running LibreLink (tip: log out and re-login)"
        }
    }
}


struct AuthTicket: Codable {
    let token: String
    let expires: Int
    let duration: UInt64
}


enum MeasurementColor: Int, Codable {
    case green  = 1
    case yellow = 2
    case orange = 3
    case red    = 4
}


struct GlucoseMeasurement: Codable {
    let factoryTimestamp: String
    let timestamp: String
    let type: Int                // 0: graph, 1: logbook, 2: alarm, 3: hybrid
    let alarmType: Int?          // when type = 3  0: fixedLow, 1: low, 2: high
    let valueInMgPerDl: Int
    let trendArrow: TrendArrow?  // in logbook but not in graph data, 0: HI/LO
    let trendMessage: String?
    let measurementColor: MeasurementColor
    let glucoseUnits: Int        // 0: mmoll, 1: mgdl
    let value: Int
    let isHigh: Bool             // HI
    let isLow: Bool              // LO
    enum CodingKeys: String, CodingKey { case factoryTimestamp = "FactoryTimestamp", timestamp = "Timestamp", type, alarmType, valueInMgPerDl = "ValueInMgPerDl", trendArrow = "TrendArrow", trendMessage = "TrendMessage", measurementColor = "MeasurementColor", glucoseUnits = "GlucoseUnits", value = "Value", isHigh, isLow }
}


struct LibreLinkUpGlucose: Identifiable, Codable {
    let glucose: Glucose
    let color: MeasurementColor
    let trendArrow: TrendArrow?
    var id: Int { glucose.id }
}


struct LibreLinkUpAlarm: Identifiable, Codable, CustomStringConvertible {
    let factoryTimestamp: String
    let timestamp: String
    let type: Int  // 2 (1 for measurements)
    let alarmType: Int  // 0: low, 1: high, 2: fixedLow
    enum CodingKeys: String, CodingKey { case factoryTimestamp = "FactoryTimestamp", timestamp = "Timestamp", type, alarmType }
    var id: Int { Int(date.timeIntervalSince1970) }
    var date: Date = Date()
    var alarmDescription: String { alarmType == 1 ? "HIGH" : "LOW" }
    var description: String { "\(date): \(alarmDescription)" }
}


class LibreLinkUp: Logging {

    var main: MainDelegate!

    let siteURL = "https://api.libreview.io"
    let loginEndpoint = "llu/auth/login"
    let configEndpoint = "llu/config"
    let connectionsEndpoint = "llu/connections"
    let measurementsEndpoint = "lsl/api/measurements"

    let regions = ["ae", "ap", "au", "ca", "de", "eu", "eu2", "fr", "jp", "la", "us"]  // eu2: GB and IE

    var regionalSiteURL: String { "https://api-\(settings.libreLinkUpRegion).libreview.io" }

    var unit: GlucoseUnit = .mgdl

    let headers = [
        "User-Agent": "Mozilla/5.0",
        "Content-Type": "application/json",
        "product": "llu.ios",
        "version": "4.12.0",
        "Accept-Encoding": "gzip, deflate, br",
        "Connection": "keep-alive",
        "Pragma": "no-cache",
        "Cache-Control": "no-cache",
    ]

    var history: [LibreLinkUpGlucose] = []
    var logbookHistory: [LibreLinkUpGlucose] = []


    init(main: MainDelegate) {
        self.main = main
    }


    @discardableResult
    func login() async throws -> (Any, URLResponse) {
        var request = URLRequest(url: URL(string: "\(siteURL)/\(loginEndpoint)")!)
        let credentials = [
            "email": settings.libreLinkUpEmail,
            "password": settings.libreLinkUpPassword
        ]
        request.httpMethod = "POST"
        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
        let jsonData = try? JSONSerialization.data(withJSONObject: credentials)
        request.httpBody = jsonData
        do {
            var redirected: Bool
            loop: repeat {
                redirected = false
                debugLog("LibreLinkUp: posting to \(request.url!.absoluteString) \(jsonData!.string), headers: \(headers)")
                let (data, response) = try await URLSession.shared.data(for: request)
                if let response = response as? HTTPURLResponse {
                    let status = response.statusCode
                    debugLog("LibreLinkUp: response data: \(data.string.trimmingCharacters(in: .newlines)), status: \(status)")
                    if status == 401 {
                        log("LibreLinkUp: POST not authorized")
                    } else {
                        log("LibreLinkUp: POST \((200..<300).contains(status) ? "success" : "error")")
                    }
                }
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let status = json["status"] as? Int {

                        let data = json["data"] as? [String: Any]

                        if status == 2 || status == 429 || status == 911 {
                            // {"status":2,"error":{"message":"notAuthenticated"}}
                            // {"status":429,"data":{"code":60,"data":{"failures":3,"interval":60,"lockout":300},"message":"locked"}}
                            // {"status":911} when logging in at a stranger regional server
                            if let data, let message = data["message"] as? String {
                                if message == "locked" {
                                    if let data = data["data"] as? [String: Any],
                                       let failures = data["failures"] as? Int,
                                       let interval = data["interval"] as? Int,
                                       let lockout = data["lockout"] as? Int {
                                        log("LibreLinkUp: login failures: \(failures), interval: \(interval) s, lockout: \(lockout) s")
                                        // TODO: warn the user to wait 5 minutes before reattempting
                                    }
                                }

                            }
                            throw LibreLinkUpError.notAuthenticated
                        }

                        // TODO: status 4 requires accepting new Terms of Use

                        // https://github.com/poml88/LibreWrist/blob/a4fdf7b/SharedPhoneWatch/LibreLinkUp.swift#L249
                        // let mockupData = """
                        // {"status":4,"data":{"step":{"type":"tou","componentName":"AcceptDocument","props":{"reaccept":true,"titleKey":"Common.termsOfUse","type":"tou"}},"user":{"accountType":"pat","country":"DE","uiLanguage":"de-DE"},"authTicket":{"token":"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjJjMTFhMmNlLTY1MmYtMTFlZi1hOGY5LWU2NTlhODBiNTU2OSIsImZpcnN0TmFtZSI6IkxpYnJlICIsImxhc3ROYW1lIjoiV3Jpc3QiLCJjb3VudHJ5IjoiREUiLCJyZWdpb24iOiJkZSIsInJvbGUiOiJwYXRpZW50IiwiZW1haWwiOiJsaWJyZXdpZGdldEBjbWRsaW5lLm5ldCIsImMiOjEsInMiOiJsbHUuaW9zIiwiZXhwIjoxNzI3MzQyNTE4fQ._-kekmE1JEmpmdUUhpKTyqg15xwGXLSo3vh9wbTLVn8","expires":1727342518,"duration":3600000}}}
                        // """.data(using: .utf8)!

                        if status == 4 {
                            if let data,

                                let step = data["step"] as? [String: Any],
                               let type = step["type"] as? String,  // "tou", "pp"
                               let componentName = step["componentName"] as? String,
                               let props = step["props"] as? [String: Any],
                               let reaccept = props["reaccept"] as? Bool,
                               let titleKey = props["titleKey"] as? String,
                               let componentType = props["type"] as? String,

                                let user = data["user"] as? [String: Any],
                               let country = user["country"] as? String,
                               let authTicketDict = data["authTicket"] as? [String: Any],
                               let authTicketData = try? JSONSerialization.data(withJSONObject: authTicketDict),
                               let authTicket = try? JSONDecoder().decode(AuthTicket.self, from: authTicketData) {
                                debugLog("LibreLinkUp: reaccept step: type: \(type), component name: \(componentName), reaccept: \(reaccept), title key: \(titleKey), component type: \(componentType), user country: \(country), authTicket: \(authTicket), expires on \(Date(timeIntervalSince1970: Double(authTicket.expires)))")

                                throw LibreLinkUpError.touMustBeReaccepted

                                // TODO: api.libreview.io/auth/continue/tou (or `pp` type)
                            }
                        }

                        // {"status":0,"data":{"redirect":true,"region":"fr"}}
                        if let redirect = data?["redirect"] as? Bool,
                           let region = data?["region"] as? String {
                            redirected = redirect
                            Task { @MainActor in
                                settings.libreLinkUpRegion = region
                            }
                            log("LibreLinkUp: redirecting to \(regionalSiteURL)/\(loginEndpoint) ")
                            request.url = URL(string: "\(regionalSiteURL)/\(loginEndpoint)")!
                            continue loop
                        }

                        if let data,
                           let user = data["user"] as? [String: Any],
                           let id = user["id"] as? String,
                           let country = user["country"] as? String,
                           let authTicketDict = data["authTicket"] as? [String: Any],
                           let authTicketData = try? JSONSerialization.data(withJSONObject: authTicketDict),
                           let authTicket = try? JSONDecoder().decode(AuthTicket.self, from: authTicketData) {
                            log("LibreLinkUp: user id: \(id), country: \(country), authTicket: \(authTicket), expires on \(Date(timeIntervalSince1970: Double(authTicket.expires)))")
                            Task { @MainActor in
                                settings.libreLinkUpUserId = id
                                settings.libreLinkUpPatientId = id  // avoid scraping patientId when following ourselves
                                settings.libreLinkUpCountry = country
                                settings.libreLinkUpToken = authTicket.token
                                settings.libreLinkUpTokenExpirationDate = Date(timeIntervalSince1970: Double(authTicket.expires))
                            }

                            if !country.isEmpty {
                                // default "de" and "fr" regional servers
                                let defaultRegion = regions.contains(country.lowercased()) ? country.lowercased() : settings.libreLinkUpRegion
                                var request = URLRequest(url: URL(string: "\(siteURL)/\(configEndpoint)/country?country=\(country)")!)
                                for (header, value) in headers {
                                    request.setValue(value, forHTTPHeaderField: header)
                                }
                                debugLog("LibreLinkUp: URL request: \(request.url!.absoluteString), headers: \(request.allHTTPHeaderFields!)")
                                let (data, response) = try await URLSession.shared.data(for: request)
                                debugLog("LibreLinkUp: response data: \(data.string.trimmingCharacters(in: .newlines)), status: \((response as! HTTPURLResponse).statusCode)")
                                do {
                                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                       let data = json["data"] as? [String: Any],
                                       let server = data["lslApi"] as? String {
                                        let regionIndex = server.firstIndex(of: "-")
                                        let region = regionIndex == nil ? defaultRegion : String(server[server.index(regionIndex!, offsetBy: 1) ... server.index(regionIndex!, offsetBy: 2)])
                                        log("LibreLinkUp: regional server: \(server), saved default region: \(region)")
                                        Task { @MainActor in
                                            settings.libreLinkUpRegion = region
                                        }
                                        if settings.userLevel >= .test {
                                            var countryCodes = [String]()
                                            if let countryList = data["CountryList"] as? [String: Any],
                                               let countries = countryList["countries"] as? [[String: Any]] {
                                                for country in countries {
                                                    countryCodes.append(country["ValueMember"] as! String)
                                                }
                                                // ["AR", "AU", "AT", "BH", "BE", "BR", "CA", "CL", "CO", "CZ", "HR", "DK", "EG", "FI", "FR", "DE", "GR", "HK", "IN", "IE", "IL", "IT", "JO", "JP", "KW", "LU", "LB", "MX", "NL", "NO", "NZ", "OM", "PL", "PT", "QA", "SA", "SG", "ZA", "ES", "SE", "SI", "SK", "CH", "TR", "TW", "AE", "GB", "US"]
                                                debugLog("LibreLinkUp: country codes: \(countryCodes)")
                                            }
                                        }
                                    }
                                } catch {
                                    log("LibreLinkUp: error while decoding response: \(error.localizedDescription)")
                                    throw LibreLinkUpError.jsonDecoding
                                }
                            }

                            if settings.libreLinkUpFollowing {
                                log("LibreLinkUp: getting connections for follower user id: \(id)")
                                var request = URLRequest(url: URL(string: "\(regionalSiteURL)/\(connectionsEndpoint)")!)
                                var authenticatedHeaders = headers
                                authenticatedHeaders["Authorization"] = "Bearer \(settings.libreLinkUpToken)"
                                authenticatedHeaders["Account-Id"] = settings.libreLinkUpUserId.SHA256
                                for (header, value) in authenticatedHeaders {
                                    request.setValue(value, forHTTPHeaderField: header)
                                }
                                debugLog("LibreLinkUp: URL request: \(request.url!.absoluteString), authenticated headers: \(request.allHTTPHeaderFields!)")
                                let (data, response) = try await URLSession.shared.data(for: request)
                                debugLog("LibreLinkUp: response data: \(data.string.trimmingCharacters(in: .newlines)), status: \((response as! HTTPURLResponse).statusCode)")
                                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let data = json["data"] as? [[String: Any]] {
                                    if data.count > 0 {
                                        let connection = data[0]
                                        let patientId = connection["patientId"] as! String
                                        log("LibreLinkUp: first patient Id: \(patientId)")
                                        Task { @MainActor in
                                            settings.libreLinkUpPatientId = patientId
                                        }
                                    }
                                }
                            }

                        }
                    }
                    return (data, response)
                }
            } while redirected

            return (Data(), URLResponse())

        } catch LibreLinkUpError.jsonDecoding {
            log("LibreLinkUp: error while decoding response: \(LibreLinkUpError.jsonDecoding.localizedDescription)")
            throw LibreLinkUpError.jsonDecoding
        } catch LibreLinkUpError.notAuthenticated {
            log("LibreLinkUp: error: \(LibreLinkUpError.notAuthenticated.localizedDescription)")
            throw LibreLinkUpError.notAuthenticated
        } catch LibreLinkUpError.touMustBeReaccepted {
            log("LibreLinkUp: WARNING: \(LibreLinkUpError.touMustBeReaccepted.localizedDescription)")
            throw LibreLinkUpError.touMustBeReaccepted
        } catch {
            log("LibreLinkUp: server error: \(error.localizedDescription)")
            throw LibreLinkUpError.noConnection
        }
    }


    /// - Returns: (data, response, history, logbookData, logbookHistory, logbookAlarms)
    func getPatientGraph() async throws -> (Any, URLResponse, [LibreLinkUpGlucose], Any, [LibreLinkUpGlucose], [LibreLinkUpAlarm]) {
        var request = URLRequest(url: URL(string: "\(regionalSiteURL)/\(connectionsEndpoint)/\(settings.libreLinkUpPatientId)/graph")!)
        var authenticatedHeaders = headers
        authenticatedHeaders["Authorization"] = "Bearer \(settings.libreLinkUpToken)"
        authenticatedHeaders["Account-Id"] = settings.libreLinkUpUserId.SHA256
        for (header, value) in authenticatedHeaders {
            request.setValue(value, forHTTPHeaderField: header)
        }
        debugLog("LibreLinkUp: URL request: \(request.url!.absoluteString), authenticated headers: \(request.allHTTPHeaderFields!)")

        var history: [LibreLinkUpGlucose] = []
        var logbookData: Data = Data()
        var logbookHistory: [LibreLinkUpGlucose] = []
        var logbookAlarms: [LibreLinkUpAlarm] = []

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "M/d/yyyy h:mm:ss a"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as! HTTPURLResponse).statusCode
            debugLog("LibreLinkUp: response data: \(data.string.trimmingCharacters(in: .newlines)), status: \(status)")
            // TODO: {"status":911}: server maintenance
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let data = json["data"] as? [String: Any],
                   let connection = data["connection"] as? [String: Any] {
                    log("LibreLinkUp: connection data: \(connection)")
                    unit = connection["uom"] as? Int ?? 1 == 1 ? .mgdl : .mmoll
                    log("LibreLinkUp: measurement unit: \(unit)")
                    var deviceSerials: [String: String] = [:]
                    var deviceActivationTimes: [String: Int] = [:]
                    var deviceTypes: [String: SensorType] = [:]
                    if let activeSensors = data["activeSensors"] as? [[String: Any]] {
                        log("LibreLinkUp: active sensors: \(activeSensors)")
                        for (i, activeSensor) in activeSensors.enumerated() {
                            if let sensor = activeSensor["sensor"] as? [String: Any],
                               let device = activeSensor["device"] as? [String: Any],
                               let dtid = device["dtid"] as? Int,
                               let v = device["v"] as? String,
                               let alarms = device["alarms"] as? Bool,
                               let deviceId = sensor["deviceId"] as? String,
                               var sn = sensor["sn"] as? String,
                               let a = sensor["a"] as? Int,
                               // FIXME: pruduct type should be 0: .libre1, 3: .libre2, 4: .libre3 but happening a Libre 1 with `pt` = 3...
                               let pt = sensor["pt"] as? Int {
                                var sensorType: SensorType =
                                dtid == 40068 ? .libre3 :
                                dtid == 40067 ? .libre2 :
                                dtid == 40066 ? .libre1 : .unknown
                                // FIXME:
                                // according to bundle.js, if `alarms` is true 40066 is also a .libre2
                                // but happening a Libre 1 with `alarms` = true...
                                if sensorType == .libre1 && alarms == true { sensorType = .libre2 }
                                deviceTypes[deviceId] = sensorType
                                if sn.count == 10 {
                                    switch sensorType {
                                    case .libre1: sn = "0" + sn
                                    case .libre2: sn = "3" + sn
                                    case .libre3: sn = String(sn.dropLast()) // trim final 0
                                    default: break
                                    }
                                }
                                deviceSerials[deviceId] = sn
                                if deviceActivationTimes[deviceId] == nil || deviceActivationTimes[deviceId]! > a {
                                    deviceActivationTimes[deviceId] = a
                                }
                                let activationDate = Date(timeIntervalSince1970: Double(a))
                                log("LibreLinkUp: active sensor # \(i + 1) of \(activeSensors.count): serial: \(sn), activation date: \(activationDate) (timestamp = \(a)), LibreLink version: \(v), device id: \(deviceId), product type: \(pt), sensor type: \(sensorType), alarms: \(alarms)")
                            }
                        }
                    }
                    let sensorTypes: [String: SensorType] = deviceTypes
                    if let patientDevice = connection["patientDevice"] as? [String: Any],
                       let patientSensor = connection["sensor"] as? [String: Any],
                       let deviceId = patientDevice["did"] as? String,
                       let dtid = patientDevice["dtid"] as? Int,
                       let v = patientDevice["v"] as? String,
                       let alarms = patientDevice["alarms"] as? Bool,
                       var sn = patientSensor["sn"] as? String,
                       let a = patientSensor["a"] as? Int,
                       let pt = patientSensor["pt"] as? Int {
                        // FIXME: pruduct type should be 0: .libre1, 3: .libre2, 4: .libre3 but happening a Libre 1 with `pt` = 3...
                        var patientSensorType = sensorTypes[deviceId] ?? (
                            dtid == 40068 ? .libre3 :
                                dtid == 40067 ? .libre2 :
                                dtid == 40066 ? .libre1 : .unknown
                        )
                        // FIXME:
                        // according to bundle.js, if `alarms` is true 40066 is also a .libre2
                        // but happening a Libre 1 with `alarms` = true...
                        if patientSensorType == .libre1 && alarms == true { patientSensorType = .libre2 }
                        let sensorType = patientSensorType // to pass to Task
                        if sn.count == 10 {
                            switch sensorType {
                            case .libre1: sn = "0" + sn
                            case .libre2: sn = "3" + sn
                            case .libre3: sn = String(sn.dropLast()) // trim final 0
                            default: break
                            }
                        }
                        let serial = deviceSerials[deviceId] ?? sn
                        let activationTime = deviceActivationTimes[deviceId] ?? a
                        let activationDate = Date(timeIntervalSince1970: Double(activationTime))
                        let isLateJoined = patientSensor["lj"] as? Bool ?? false
                        let isStreaming = ((patientSensor["s"] as? Bool ?? false) || sensorType == .libre3) && !isLateJoined
                        Task { @MainActor in
                            if app.sensor == nil {
                                app.sensor = sensorType == .libre3 ? Libre3(main: self.main) : sensorType == .libre2 ? Libre2(main: self.main) : Libre(main: self.main) // TODO: Libre2Gen2
                                app.sensor.type = sensorType
                                app.sensor.serial = serial
                            } else {
                                if app.sensor.serial.isEmpty {
                                    app.sensor.serial = serial
                                }
                            }
                            let sensor = main.app.sensor!
                            if sensor.serial.hasSuffix(serial) || sensorTypes.count == 1 {
                                sensor.activationTime = UInt32(activationTime)
                                sensor.age = Int(Date().timeIntervalSince(activationDate)) / 60
                                sensor.state = .active
                                sensor.lastReadingDate = Date()
                                if sensor.type == .libre3 {
                                    sensor.serial = serial
                                    if sensor.maxLife == 0 {
                                        sensor.maxLife = 20160 // TODO: 21600 for 15-day Libre 3+
                                    }
                                    let receiverId = settings.libreLinkUpPatientId.fnv32Hash
                                    (sensor as! Libre3).receiverId = receiverId
                                    log("LibreLinkUp: LibreView receiver ID: \(receiverId)")
                                }
                                main.status("\(sensor.type)  +  LLU")
                            }
                        }
                        log("LibreLinkUp: sensor serial: \(serial), activation date: \(activationDate) (timestamp = \(activationTime)),  LibreLink version: \(v), device id: \(deviceId), product type: \(pt), sensor type: \(sensorType), alarms: \(alarms), late joined: \(isLateJoined), is streaming: \(isStreaming)")
                        // TODO: glucoseAlarm not null
                        let glucoseAlarm = connection["glucoseAlarm"] as? Int?
                        log ("LibreLinkUp: glucose alarm: \(String(describing: glucoseAlarm))")
                        if let lastGlucoseMeasurement = connection["glucoseMeasurement"] as? [String: Any],
                           let measurementData = try? JSONSerialization.data(withJSONObject: lastGlucoseMeasurement),
                           let measurement = try? JSONDecoder().decode(GlucoseMeasurement.self, from: measurementData) {
                            let date = dateFormatter.date(from: measurement.timestamp)!
                            let lifeCount = Int(round(date.timeIntervalSince(activationDate) / 60))
                            let lastGlucose = LibreLinkUpGlucose(glucose: Glucose(measurement.valueInMgPerDl, id: lifeCount, date: date, source: "LibreLinkUp"), color: measurement.measurementColor, trendArrow: measurement.trendArrow)
                            debugLog("LibreLinkUp: last glucose measurement: \(measurement) (JSON: \(lastGlucoseMeasurement))")
                            if lastGlucose.trendArrow != nil {
                                Task { @MainActor in
                                    app.trendArrow = lastGlucose.trendArrow!
                                }
                            }
                            // TODO: scrape historic data only when the 17-minute delay has passed
                            var i = 0
                            if let graphData = data["graphData"] as? [[String: Any]] {
                                for glucoseMeasurement in graphData {
                                    if let measurementData = try? JSONSerialization.data(withJSONObject: glucoseMeasurement),
                                       let measurement = try? JSONDecoder().decode(GlucoseMeasurement.self, from: measurementData) {
                                        i += 1
                                        let date = dateFormatter.date(from: measurement.timestamp)!
                                        var lifeCount = Int(date.timeIntervalSince(activationDate)) / 60
                                        // FIXME: lifeCount not always multiple of 5
                                        if lifeCount % 5 == 1 { lifeCount -= 1 }
                                        history.append(LibreLinkUpGlucose(glucose: Glucose(measurement.valueInMgPerDl, id: lifeCount, date: date, source: "LibreLinkUp"), color: measurement.measurementColor, trendArrow: measurement.trendArrow))
                                        debugLog("LibreLinkUp: graph measurement # \(i) of \(graphData.count): \(measurement) (JSON: \(glucoseMeasurement)), lifeCount = \(lifeCount)")
                                    }
                                }
                            }
                            history.append(lastGlucose)
                            log("LibreLinkUp: graph values: \(history.map { ($0.glucose.id, $0.glucose.value, $0.glucose.date.shortDateTime, $0.color) })")

                            // TODO: https://api-eu.libreview.io/glucoseHistory?from=1700092800&numPeriods=5&period=14
                            if settings.userLevel >= .test {
                                let period = 15
                                let numPeriods = 2
                                if let ticketDict = json["ticket"] as? [String: Any],
                                   let token = ticketDict["token"] as? String {
                                    log("LibreView: new token for glucoseHistory: \(token)")
                                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                    request.setValue(settings.libreLinkUpUserId.SHA256, forHTTPHeaderField: "Account-Id")
                                    request.url = URL(string: "https://api.libreview.io/glucoseHistory?numPeriods=\(numPeriods)&period=\(period)")!
                                    debugLog("LibreView: URL request: \(request.url!.absoluteString), authenticated headers: \(request.allHTTPHeaderFields!)")
                                    let (data, response) = try await URLSession.shared.data(for: request)
                                    debugLog("LibreView: response data: \(data.string.trimmingCharacters(in: .newlines)), status: \((response as! HTTPURLResponse).statusCode)")
                                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                       // let status = json["status"] as? Int,
                                       let data = json["data"] as? [String: Any] {
                                        let lastUpload = data["lastUpload"] as! Int
                                        let lastUploadDate = Date(timeIntervalSince1970: Double(lastUpload))
                                        let lastUploadCGM = data["lastUploadCGM"] as! Int
                                        let lastUploadCGMDate = Date(timeIntervalSince1970: Double(lastUploadCGM))
                                        let lastUploadPro = data["lastUploadPro"] as! Int
                                        let lastUploadProDate = Date(timeIntervalSince1970: Double(lastUploadPro))
                                        let reminderSent = data["reminderSent"] as! Bool
                                        let devices = data["devices"] as! [Int]
                                        let periods = data["periods"] as! [[String: Any]]
                                        debugLog("LibreView: last upload date: \(lastUploadDate.local), last upload CGM date: \(lastUploadCGMDate.local), last upload pro date: \(lastUploadProDate.local), reminder sent: \(reminderSent), devices: \(devices), periods: \(periods.count)")
                                        var i = 0
                                        for period in periods {
                                            let dateEnd = period["dateEnd"] as! Int
                                            let endDate = Date(timeIntervalSince1970: Double(dateEnd))
                                            let dateStart = period["dateStart"] as! Int
                                            let startDate = Date(timeIntervalSince1970: Double(dateStart))
                                            let daysOfData = period["daysOfData"] as! Int
                                            let data = period["data"] as! [String: Any]
                                            let blocks = data["blocks"] as! [[[String: Any]]]
                                            i += 1
                                            debugLog("LibreView: period # \(i) of \(periods.count), start date: \(startDate.local), end date: \(endDate.local), days of data: \(daysOfData)")
                                            var j = 0
                                            for block in blocks {
                                                j += 1
                                                debugLog("LibreView: block # \(j) of period # \(i): \(block.count) percentiles times: \(block.map { $0["time"] as! Int })")
                                            }
                                        }
                                    }
                                }
                            }

                            if settings.libreLinkUpScrapingLogbook,
                               let ticketDict = json["ticket"] as? [String: Any],
                               let token = ticketDict["token"] as? String {
                                log("LibreLinkUp: new token for logbook: \(token)")
                                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                                request.setValue(settings.libreLinkUpUserId.SHA256, forHTTPHeaderField: "Account-Id")
                                request.url = URL(string: "\(regionalSiteURL)/\(connectionsEndpoint)/\(settings.libreLinkUpPatientId)/logbook")!
                                debugLog("LibreLinkUp: URL request: \(request.url!.absoluteString), authenticated headers: \(request.allHTTPHeaderFields!)")
                                let (data, response) = try await URLSession.shared.data(for: request)
                                debugLog("LibreLinkUp: response data: \(data.string.trimmingCharacters(in: .newlines)), status: \((response as! HTTPURLResponse).statusCode)")
                                logbookData = data
                                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let data = json["data"] as? [[String: Any]] {
                                    for entry in data {
                                        let type = entry["type"] as! Int

                                        if type == 1 || type == 3 {  // measurement
                                            if let measurementData = try? JSONSerialization.data(withJSONObject: entry),
                                               let measurement = try? JSONDecoder().decode(GlucoseMeasurement.self, from: measurementData) {
                                                i += 1
                                                let date = dateFormatter.date(from: measurement.timestamp)!
                                                logbookHistory.append(LibreLinkUpGlucose(glucose: Glucose(measurement.valueInMgPerDl, id: i, date: date, source: "LibreLinkUp"), color: measurement.measurementColor, trendArrow: measurement.trendArrow))
                                                let alarmDescription = if let alarmType = measurement.alarmType {
                                                    ["fixed low", "low", "high"][alarmType]
                                                } else {
                                                    ""
                                                }
                                                // TODO
                                                debugLog("LibreLinkUp: logbook measurement # \(i - history.count) of \(data.count): \(measurement)\(alarmDescription != "" ? ", alarm: \(alarmDescription)" : "") (JSON: \(entry))")
                                            }

                                        } else if type == 2 {  // alarm
                                            if let alarmData = try? JSONSerialization.data(withJSONObject: entry),
                                               var alarm = try? JSONDecoder().decode(LibreLinkUpAlarm.self, from: alarmData) {
                                                alarm.date = dateFormatter.date(from: alarm.timestamp)!
                                                logbookAlarms.append(alarm)
                                                debugLog("LibreLinkUp: logbook alarm: \(alarm) (JSON: \(entry))")
                                            }
                                        }
                                    }
                                    // TODO: merge with history and display trend arrow
                                    log("LibreLinkUp: logbook values: \(logbookHistory.map { ($0.glucose.id, $0.glucose.value, $0.glucose.date.shortDateTime, $0.color, $0.trendArrow!.symbol) }), alarms: \(logbookAlarms.map(\.description))")
                                }
                            }
                        }
                    }
                }
                return (data, response, history, logbookData, logbookHistory, logbookAlarms)
            } catch {
                log("LibreLinkUp: error while decoding response: \(error.localizedDescription)")
                throw LibreLinkUpError.jsonDecoding
            }
        } catch {
            log("LibreLinkUp: server error: \(error.localizedDescription)")
            throw LibreLinkUpError.noConnection
        }
    }


    @discardableResult
    func reload(enforcing: Bool = false) async -> String {

        guard settings.onlineInterval > 0 else {
            debugLog("LibreLinkUp: online mode is disabled - didn't reload")
            return "[Online mode is disabled]"
        }

        guard enforcing || Int(Date().timeIntervalSince(settings.lastOnlineDate)) >= settings.onlineInterval * 60 - 5 else {
            debugLog("LibreLinkUp: throttled reload (\(Int(Date().timeIntervalSince(settings.lastOnlineDate))) of \(settings.onlineInterval * 60) seconds passed)")
            return "[Reload was throttled: \(Int(Date().timeIntervalSince(settings.lastOnlineDate))) of \(settings.onlineInterval * 60) secs passed)]"
        }

        var response = ""
        var dataString = ""
        var retries = 0
        loop: repeat {
            do {
                if settings.libreLinkUpUserId.isEmpty ||
                    settings.libreLinkUpToken.isEmpty ||
                    settings.libreLinkUpTokenExpirationDate < Date() ||
                    retries == 1 {
                    do {
                        try await login()
                    } catch {
                        response = error.localizedDescription
                        log("LibreLinkUp: error: \(response)")
                    }
                }
                if !(settings.libreLinkUpUserId.isEmpty ||
                     settings.libreLinkUpToken.isEmpty) {
                    let (data, _, graphHistory, logbookData, logbookHistory, _) = try await getPatientGraph()
                    dataString = (data as! Data).string
                    response = dataString + (logbookData as! Data).string
                    // TODO: just merge with newer values
                    history = graphHistory.reversed()
                    self.logbookHistory = logbookHistory
                    if graphHistory.count > 0 {
                        Task { @MainActor in
                            settings.lastOnlineDate = Date()
                            let lastMeasurement = history[0]
                            app.lastReadingDate = lastMeasurement.glucose.date
                            app.sensor?.lastReadingDate = app.lastReadingDate
                            app.currentGlucose = lastMeasurement.glucose.value
                            // TODO: keep the raw values filling the gaps with -1 values
                            main.history.rawValues = []
                            main.history.factoryValues = history.dropFirst().map(\.glucose) // TEST
                            var trend = main.history.factoryTrend
                            if trend.isEmpty || lastMeasurement.id > trend[0].id {
                                trend.insert(lastMeasurement.glucose, at: 0)
                            }
                            if let sensor = app.sensor as? Libre3, main.history.factoryValues.count > 0 {
                                sensor.currentLifeCount = lastMeasurement.id
                                sensor.lastHistoricLifeCount = main.history.factoryValues[0].id
                                sensor.lastHistoricReadingDate = main.history.factoryValues[0].date
                            }
                            // keep only the latest 22 minutes considering the 17-minute latency of the historic values update
                            trend = trend.filter { lastMeasurement.id - $0.id < 22 }
                            main.history.factoryTrend = trend
                            // TODO: merge and update sensor history / trend
                            app.main.didParseSensor(app.sensor)
                        }
                    }
                    if dataString != "{\"message\":\"MissingCachedUser\"}\n" {
                        break loop
                    }
                    retries += 1
                }
            } catch {
                response = error.localizedDescription
                log("LibreLinkUp: error: \(response)")
            }

        } while retries == 1

        app.serviceResponse = response

        return response
    }

}
