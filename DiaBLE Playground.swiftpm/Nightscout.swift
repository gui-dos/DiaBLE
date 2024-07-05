import Foundation

#if !os(watchOS)
import WebKit
#endif


enum NightscoutError: LocalizedError {
    case noConnection
    case jsonDecoding

    var errorDescription: String? {
        switch self {
        case .noConnection: "no connection"
        case .jsonDecoding: "JSON decoding"
        }
    }
}


class Nightscout: NSObject, Logging {

    var main: MainDelegate!

#if !os(watchOS)
    var webView: WKWebView?
#endif


    init(main: MainDelegate) {
        self.main = main
    }


    // https://github.com/ps2/rileylink_ios/blob/master/NightscoutUploadKit/NightscoutUploader.swift
    // https://github.com/JohanDegraeve/xdripswift/blob/master/xdrip/Managers/NightScout/NightScoutUploadManager.swift


    // TODO: use URLQueryItems paramaters
    func request(_ endpoint: String = "", _ query: String = "", handler: @escaping (Data?, URLResponse?, Error?, [Any]) -> Void) {
        var url = "https://\(settings.nightscoutSite)"

        if !endpoint.isEmpty { url += ("/" + endpoint) }
        if !query.isEmpty    { url += ("?" + query) }
        if !settings.nightscoutToken.isEmpty { url += "&token=" + settings.nightscoutToken }

        var request = URLRequest(url: URL(string: url)!)
        debugLog("Nightscout: URL request: \(request.url!.absoluteString)")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let data {
                debugLog("Nightscout: response data: \(data.string)")
                if let json = try? JSONSerialization.jsonObject(with: data) {
                    if let array = json as? [Any] {
                        DispatchQueue.main.async {
                            handler(data, response, error, array)
                        }
                    }
                }
            } else if let error {
                log("Nightscout: server error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    handler(data, response, error, [])
                }
            }
        }.resume()
    }


    func request(_ endpoint: String = "", _ query: String = "") async throws -> (Any, URLResponse) {
        var url = "https://\(settings.nightscoutSite)"

        if !endpoint.isEmpty { url += ("/" + endpoint) }
        if !query.isEmpty    { url += ("?" + query) }
        if !settings.nightscoutToken.isEmpty { url += "&token=" + settings.nightscoutToken }

        var request = URLRequest(url: URL(string: url)!)
        debugLog("Nightscout: URL request: \(request.url!.absoluteString)")
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            debugLog("Nightscout: response data: \(data.string)")
            do {
                let json = try JSONSerialization.jsonObject(with: data)
                if let array = json as? [Any] {
                    return (array, response)
                }
            } catch {
                log("Nightscout: error while decoding response: \(error.localizedDescription)")
                throw NightscoutError.jsonDecoding
            }
        } catch {
            log("Nightscout: server error: \(error.localizedDescription)")
            throw NightscoutError.noConnection
        }
        return (["": ""], URLResponse())
    }


    func read() async throws -> ([Glucose], URLResponse) {
        guard settings.onlineInterval > 0 else { return ([Glucose](), URLResponse()) }
        let (data, response) = try await request("api/v1/entries.json", "count=100")
        var values = [Glucose]()
        if let array = data as? [[String: Any]?] {
            for dict in array {
                // watchOS doesn't recognize dict["date"] as Int
                if let value = dict?["sgv"] as? Int, let id = dict?["date"] as? NSNumber, let device = dict?["device"] as? String {
                    values.append(Glucose(value, id: Int(truncating: id), date: Date(timeIntervalSince1970: Double(truncating: id)/1000), source: device))
                }
            }
        }
        return (values, response)
    }


    func post(_ endpoint: String, _ jsonObject: Any) async throws -> (Any, URLResponse) {
        let url = "https://" + settings.nightscoutSite
        let token = settings.nightscoutToken.SHA1
        let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject)
        var request = URLRequest(url: URL(string: "\(url)/\(endpoint)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "api-secret")
        request.httpBody = jsonData
        do {
            debugLog("Nightscout: posting to \(request.url!.absoluteString) \(jsonData!.string)")
            let (data, response) = try await URLSession.shared.data(for: request)
            debugLog("Nightscout: response data: \(data.string)")
            if let response = response as? HTTPURLResponse {
                let status = response.statusCode
                if status == 401 {
                    log("Nightscout: POST not authorized")
                } else {
                    log("Nightscout: POST \((200..<300).contains(status) ? "success" : "error") (status: \(status))")
                }
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data)
                if let array = json as? [Any] {
                    return (array, response)
                }
            } catch {
                log("Nightscout: error while decoding response: \(error.localizedDescription)")
                throw NightscoutError.jsonDecoding
            }
        } catch {
            log("Nightscout: server error: \(error.localizedDescription)")
            throw NightscoutError.noConnection
        }
        return (["": ""], URLResponse())
    }


    func post(entries: [Glucose]) async throws {
        guard settings.onlineInterval > 0 else { return }
        let dictionaryArray = entries.map { [
            "type": "sgv",
            "dateString": ISO8601DateFormatter().string(from: $0.date),
            "date": Int64(($0.date.timeIntervalSince1970 * 1000.0).rounded()),
            "sgv": $0.value,
            "device": $0.source
            // "direction": "NOT COMPUTABLE", // TODO
        ] }
        let (json, response) = try await post("api/v1/entries", dictionaryArray)
        debugLog("Nightscout: received JSON: \(json), HTTP response: \(response)")
    }


    func delete(_ endpoint: String = "api/v1/entries", _ query: String = "", handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {
        var url = "https://\(settings.nightscoutSite)"

        if !endpoint.isEmpty { url += ("/" + endpoint) }
        if !query.isEmpty    { url += ("?" + query) }

        var request = URLRequest(url: URL(string: url)!)
        debugLog("Nightscout: DELETE request: \(request.url!.absoluteString)")
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(settings.nightscoutToken.SHA1, forHTTPHeaderField: "api-secret")
        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let error {
                log("Nightscout: error: \(error.localizedDescription)")
            }
            if let response = response as? HTTPURLResponse {
                let status = response.statusCode
                if status == 401 {
                    log("Nightscout: DELETE not authorized")
                }
                if let data {
                    debugLog("Nightscout: delete \((200..<300).contains(status) ? "success" : "error") (\(status)): \(data.string)")
                }
            }
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }.resume()
    }


    // TODO:
    func test(handler: (((Data?, URLResponse?, Error?) -> Void))? = nil) {
        var request = URLRequest(url: URL(string: "https://\(settings.nightscoutSite)/api/v1/entries.json?token=\(settings.nightscoutToken)")!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(settings.nightscoutToken.SHA1, forHTTPHeaderField: "api-secret")
        URLSession.shared.dataTask(with: request) { [self] data, response, error in
            if let error {
                log("Nightscout: authorization error: \(error.localizedDescription)")
            }
            if let response = response as? HTTPURLResponse {
                let status = response.statusCode
                if status == 401 {
                    log("Nightscout: not authorized")
                }
                if let data {
                    debugLog("Nightscout: authorization \((200..<300).contains(status) ? "success" : "error") (\(status)): \(data.string)")
                }
            }
            DispatchQueue.main.async {
                handler?(data, response, error)
            }
        }.resume()
    }

}


#if !os(watchOS)

extension Nightscout: WKNavigationDelegate, WKUIDelegate {

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        debugLog("Nightscout: decide policy for action \(navigationAction): allow")
        return(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        debugLog("Nightscout: decide policy for response \(navigationResponse): allow")
        return(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        log("Nightscout: webView did fail: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        log("Nightscout: create veb view for action: \(navigationAction)")
        //        if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
        //        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        log("Nightscout: JavaScript alert panel message: \(message)")
        app.jsConfirmAlertMessage = message
        app.showingJSConfirmAlert = true
        // TODO: block web page updates
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        log("Nightscout: TODO: JavaScript confirm panel message: \(message)")
        app.jsConfirmAlertMessage = message
        app.showingJSConfirmAlert = true
        // TODO: block web page updates
        completionHandler(true)
    }
}

#endif
