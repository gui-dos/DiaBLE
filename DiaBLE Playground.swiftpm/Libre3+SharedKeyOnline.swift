import Foundation

//
// Claude:
//

extension Libre3 {

    public static var sharedKeyEndpoint = ""
        // "https://XXX.YYY.ZZZ"

    /// sensorStatic: patchCertificate!.patchStaticPublicKey,
    /// sensorEphemeral: patchEphemeral,
    /// appPrivateStatic: appPrivateKeys[securityVersion].bytes,
    /// appPrivateEphemeral: ephemeralPrivateKey.rawRepresentation
    func getSharedKey(
        sensorStatic:        Data,
        sensorEphemeral:     Data,
        appPrivateStatic:    Data,
        appPrivateEphemeral: Data, // P256.KeyAgreement.PrivateKey
        // timeout:             TimeInterval = 2
    ) async throws -> Data {

        let payload: [String: String] = [
            "sensor_static":         sensorStatic.hex,
            "sensor_ephemeral":      sensorEphemeral.hex,
            "app_private_static":    appPrivateStatic.hex,
            "app_private_ephemeral": appPrivateEphemeral.hex,
        ]

        var request = URLRequest(url: URL(string: Libre3.sharedKeyEndpoint)!)
        request.httpMethod = "POST"
        // request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        debugLog("Libre 3: posting to \(request.url!.absoluteString) JSON payload:\(request.httpBody!.string)")
        let (body, response) = try await URLSession(configuration: .ephemeral)
            .data(for: request)
        debugLog("Libre 3: shared key response body: \(body.string.trimmingCharacters(in: .newlines))")

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw SharedKeyError.httpStatus(http.statusCode,
                                            body: String(data: body, encoding: .utf8))
        }
        let hexString = String(data: body, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let key = hexString.bytes
        if key.count < 16 {
            throw SharedKeyError.malformedResponse(hexString)
        }
        return key
    }

    public enum SharedKeyError: Error, LocalizedError {
        case httpStatus(Int, body: String?)
        case malformedResponse(String)

        public var errorDescription: String? {
            switch self {
            case .httpStatus(let code, let body):
                return "Shared-key server returned HTTP \(code). Body: \(body ?? "<empty>")"
            case .malformedResponse(let s):
                return "Shared-key response is not valid hex or is too short: \(s)"
            }
        }
    }
}
