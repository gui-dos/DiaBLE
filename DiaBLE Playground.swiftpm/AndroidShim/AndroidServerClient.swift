import Foundation

/// HTTP transport to the Android crypto server (the shim APK that wraps
/// `liblibre3extension.so`). All Libre 3 SKB primitives the iOS app cannot
/// run natively (because of WhiteCryption Chow-style white-box AES) are
/// delegated to that server via this client.
///
/// Wire protocol (matches the shim APK's `HttpServer.kt`):
///
/// ```
/// POST /session                             → { "sessionId": "<uuid>" }
/// POST /session/{id}/process1               → { "rc": <int> }
///        body: { "op": <int>,
///                "a":  "<base64>" | null,
///                "b":  "<base64>" | null }
/// POST /session/{id}/process2               → { "rc": <int>,
///                                               "out": "<base64>" }
///        body: same as process1
/// DELETE /session/{id}                      → 204
/// GET /health                               → { "ok": true, ... }
/// ```
///
/// **Opcode map (matches Juggluco's `Libre3SKBCryptoLib` JNI surface):**
///
/// | Op | Method        | Inputs                                | Output     |
/// |----|---------------|---------------------------------------|------------|
/// | 1  | process1      | (null, null)                          | int rc     |
/// | 2  | process1      | (appPrivKeyBlob, kAuthBlob?)          | int rc     |
/// | 4  | process1      | (patchCert 140 B, null)               | int rc=1   |
/// | 5  | process2      | (null, null)                          | bytes 65 B |
/// | 6  | process1      | (patchEphemeral 65 B, null)           | int rc=1   |
/// | 7  | process2      | (nonce1 7 B, plaintext 36 B)          | bytes 40 B |
/// | 8  | process2      | (nonce 7 B, ct+tag 60 B)              | bytes 56 B |
/// | 9  | process2      | (null, null)                          | bytes 149 B|
///
/// Sessions on the server hold the per-connection SKB engine state.
/// Allocate one session per BLE connection; tear down on disconnect.
// actor AndroidServerClient {
@MainActor
final class AndroidServerClient: @MainActor Logging {  // DiaBLE ihterconnection

    var main: MainDelegate!

    struct Configuration {
        /// e.g. `http://mac-mini.local:8080` or `http://192.168.1.42:8080`.
        var baseURL: URL
        /// Optional shared secret passed in `Authorization: Bearer <token>`
        /// if the server is exposed beyond localhost. Default: no auth.
        var bearerToken: String?
        /// Per-call timeout. Conservative default — the slowest opcode
        /// (op 6, kAuth derivation) takes ~50 ms on a Pixel and well
        /// under 200 ms on AVD.
        var requestTimeout: TimeInterval = 5
    }

    enum ServerError: Error, LocalizedError {
        case notConfigured
        case badURL(String)
        case transport(Error)
        case httpStatus(Int, body: String)
        case unexpectedResponse(String)
        case skbFailure(rc: Int, op: Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Android crypto server URL not set. Open Settings and enter the server URL."
            case .badURL(let s):
                return "Malformed server URL: \(s)"
            case .transport(let e):
                return "Network error: \(e.localizedDescription)"
            case .httpStatus(let code, let body):
                return "Server returned HTTP \(code): \(body.prefix(200))"
            case .unexpectedResponse(let why):
                return "Server response malformed: \(why)"
            case .skbFailure(let rc, let op):
                return "SKB op \(op) returned rc=0x\(String(rc, radix: 16, uppercase: true)) (non-success)."
            }
        }
    }

    private var configuration: Configuration?
    private var sessionId: String?
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Configuration

    func configure(_ configuration: Configuration) {
        self.configuration = configuration
    }

    /// Convenience: configure with a base URL string. Throws on parse failure.
    func configure(baseURLString: String, bearerToken: String? = nil) throws {
        guard let url = URL(string: baseURLString) else {
            throw ServerError.badURL(baseURLString)
        }
        configure(Configuration(baseURL: url, bearerToken: bearerToken))
    }

    var currentSessionId: String? { sessionId }
    var isConfigured: Bool { configuration != nil }

    // MARK: - Health check

    /// Pings the server's `/health` endpoint. Reachability + version smoke
    /// test; does not allocate a session.
    func health() async throws -> [String: Any] {
        let cfg = try requireConfig()
        var request = URLRequest(url: cfg.baseURL.appendingPathComponent("health"))
        request.httpMethod = "GET"
        attachAuth(&request, cfg: cfg)
        request.timeoutInterval = cfg.requestTimeout
        let (data, response) = try await send(request)
        try ensureOK(response, data: data)
        let json = try parseJSON(data)
        return json
    }

    // MARK: - Session lifecycle

    func openSession() async throws {
        let cfg = try requireConfig()
        var request = URLRequest(url: cfg.baseURL.appendingPathComponent("session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachAuth(&request, cfg: cfg)
        request.timeoutInterval = cfg.requestTimeout
        let (data, response) = try await send(request)
        try ensureOK(response, data: data)
        let json = try parseJSON(data)
        guard let id = json["sessionId"] as? String, !id.isEmpty else {
            throw ServerError.unexpectedResponse("missing sessionId in /session response")
        }
        sessionId = id
    }

    func closeSession() async {
        guard let cfg = try? requireConfig(), let id = sessionId else { return }
        sessionId = nil
        var request = URLRequest(url: cfg.baseURL.appendingPathComponent("session/\(id)"))
        request.httpMethod = "DELETE"
        attachAuth(&request, cfg: cfg)
        request.timeoutInterval = cfg.requestTimeout
        // Best-effort; ignore errors on teardown.
        _ = try? await send(request)
    }

    // MARK: - Opcode helpers

    /// `process1(op, a, b) -> int`. Used for opcodes 1, 2, 4, 6.
    /// Throws `.skbFailure` if `rc == 0` (Juggluco convention: 1 means success).
    @discardableResult
    func process1(op: Int, a: Data? = nil, b: Data? = nil) async throws -> Int {
        let json: [String: Any] = [
            "rc": try await postOp(path: "process1", op: op, a: a, b: b)
        ]
        guard let rc = json["rc"] as? Int else {
            throw ServerError.unexpectedResponse("rc missing")
        }
        // Juggluco's convention: nonzero (often == 1) means success.
        // Refuse to claim success for rc==0 so callers don't silently
        // proceed on a no-op result.
        if rc == 0 {
            throw ServerError.skbFailure(rc: rc, op: op)
        }
        return rc
    }

    /// `process2(op, a, b) -> bytes`. Used for opcodes 5, 7, 8, 9.
    /// Returns the raw byte output; throws if the response is empty or
    /// the server signals failure.
    func process2(op: Int, a: Data? = nil, b: Data? = nil) async throws -> Data {
        let cfg = try requireConfig()
        let id = try requireSessionId()
        var request = URLRequest(url: cfg.baseURL.appendingPathComponent("session/\(id)/process2"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachAuth(&request, cfg: cfg)
        request.timeoutInterval = cfg.requestTimeout
        request.httpBody = try makeOpBody(op: op, a: a, b: b)
        let (data, response) = try await send(request)
        try ensureOK(response, data: data)
        let json = try parseJSON(data)
        if let rc = json["rc"] as? Int, rc == 0 {
            throw ServerError.skbFailure(rc: rc, op: op)
        }
        guard let outBase64 = json["out"] as? String,
              let bytes = Data(base64Encoded: outBase64) else {
            throw ServerError.unexpectedResponse("out missing or not base64")
        }
        return bytes
    }

    // MARK: - Internal HTTP

    private func postOp(path: String, op: Int, a: Data?, b: Data?) async throws -> Int {
        let cfg = try requireConfig()
        let id = try requireSessionId()
        var request = URLRequest(url: cfg.baseURL.appendingPathComponent("session/\(id)/\(path)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachAuth(&request, cfg: cfg)
        request.timeoutInterval = cfg.requestTimeout
        request.httpBody = try makeOpBody(op: op, a: a, b: b)
        let (data, response) = try await send(request)
        try ensureOK(response, data: data)
        let json = try parseJSON(data)
        guard let rc = json["rc"] as? Int else {
            throw ServerError.unexpectedResponse("rc missing")
        }
        return rc
    }

    private func makeOpBody(op: Int, a: Data?, b: Data?) throws -> Data {
        var body: [String: Any] = ["op": op]
        body["a"] = a?.base64EncodedString() ?? NSNull()
        body["b"] = b?.base64EncodedString() ?? NSNull()
        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw ServerError.transport(error)
        }
    }

    private func ensureOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ServerError.unexpectedResponse("non-HTTP response")
        }
        guard 200 ..< 300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ServerError.httpStatus(http.statusCode, body: body)
        }
    }

    private func parseJSON(_ data: Data) throws -> [String: Any] {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let dict = any as? [String: Any] else {
            throw ServerError.unexpectedResponse("not a JSON object")
        }
        return dict
    }

    private func requireConfig() throws -> Configuration {
        guard let cfg = configuration else { throw ServerError.notConfigured }
        return cfg
    }

    private func requireSessionId() throws -> String {
        if let id = sessionId { return id }
        throw ServerError.unexpectedResponse("no open session; call openSession() first")
    }

    private func attachAuth(_ request: inout URLRequest, cfg: Configuration) {
        if let token = cfg.bearerToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}
