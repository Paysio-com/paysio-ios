import Foundation

/// Thin JSON client for the Paysio checkout client API (CONTRACT.md).
///
/// - 20 second timeout on every call (CONTRACT.md section 6).
/// - Sends `X-Paysio-SDK: ios/<version>` on every request.
/// - Maps transport failures to `PaysioError(.network)` and HTTP statuses to the
///   contract's error codes (`mapFailure`).
public final class PaysioClient {
    /// A decoded JSON object. The checkout API is loosely typed, so we keep the
    /// dictionary and read what the contract names.
    public typealias JSONObject = [String: Any]

    public struct Response {
        public let status: Int
        public let json: JSONObject
        public var isSuccess: Bool { (200..<300).contains(status) }
    }

    public static let defaultAPIBase = URL(string: "https://api.paysio.com")!

    public let apiBase: URL
    private let urlSession: URLSession

    /// - Parameter apiBase: `https://api.paysio.com` unless you are pointing at staging.
    public init(apiBase: URL = PaysioClient.defaultAPIBase) {
        self.apiBase = apiBase
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "X-Paysio-SDK": PaysioSDK.headerValue,
        ]
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Requests

    /// `GET <apiBase>/<path>`.
    public func get(_ path: String) async throws -> Response {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "GET"
        return try await perform(request)
    }

    /// `POST <apiBase>/<path>` with a JSON body and optional extra headers.
    public func post(_ path: String, body: JSONObject, headers: [String: String] = [:]) async throws -> Response {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        return try await perform(request)
    }

    /// Like `post` but throws a mapped `PaysioError` for any non-2xx status.
    public func postExpectingSuccess(_ path: String, body: JSONObject, headers: [String: String] = [:]) async throws -> JSONObject {
        let response = try await post(path, body: body, headers: headers)
        guard response.isSuccess else { throw PaysioClient.mapFailure(response) }
        return response.json
    }

    private func url(for path: String) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return apiBase.appendingPathComponent(trimmed)
    }

    /// Performs the request. Transport errors become `PaysioError(.network)`;
    /// any HTTP status is returned to the caller for mapping.
    private func perform(_ request: URLRequest) async throws -> Response {
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await urlSession.data(for: request)
        } catch let error as URLError {
            throw PaysioError(code: .network, message: PaysioClient.describe(error))
        } catch {
            throw PaysioError(code: .network, message: error.localizedDescription)
        }
        let status = (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
        let json = PaysioClient.decode(data)
        return Response(status: status, json: json)
    }

    // MARK: - Mapping

    /// Decodes a JSON object body. Non-object bodies (HTML error pages from a CDN,
    /// empty bodies) become an empty dictionary so the status still drives mapping.
    static func decode(_ data: Data) -> JSONObject {
        guard !data.isEmpty,
              let any = try? JSONSerialization.jsonObject(with: data, options: []),
              let object = any as? JSONObject else { return [:] }
        return object
    }

    /// Status to error code mapping per CONTRACT.md sections 3 and 5.
    static func mapFailure(_ response: Response, idempotencyKey: String? = nil) -> PaysioError {
        let json = response.json
        let message = (json["error"] as? String)
            ?? (json["message"] as? String)
            ?? "Request failed (\(response.status))"
        let serverCode = json["code"] as? String
        let declineCode = json["declineCode"] as? String

        switch response.status {
        case 400:
            // A clean decline is a 400 with code "card_declined" (CONTRACT.md section 3);
            // the declined transaction row exists and the idempotency claim is released.
            if serverCode == "card_declined" || json.string("status") == "declined" {
                return PaysioError(code: .declined, message: message, declineCode: declineCode,
                                   idempotencyKey: idempotencyKey, httpStatus: 400)
            }
            return PaysioError(code: PaysioClient.classify400(message), message: message,
                               idempotencyKey: idempotencyKey, httpStatus: 400)
        case 402:
            // Only "3ds_required" / "3ds_failed": refused before the gateway was contacted.
            return PaysioError(code: .threeDsFailed, message: message,
                               idempotencyKey: idempotencyKey, httpStatus: 402)
        case 404:
            // "Payment link not found or inactive": expired, inactive, deleted or already paid.
            return PaysioError(code: .sessionExpired, message: message,
                               idempotencyKey: idempotencyKey, httpStatus: 404)
        case 409, 422:
            // 409 duplicate_request (same key in flight), 422 idempotency_key_reused
            // (same key, different body). Do not retry blindly; surface with the key.
            let detail = json.string("message") ?? message
            return PaysioError(code: .unknown, message: detail,
                               idempotencyKey: idempotencyKey, httpStatus: response.status)
        case 429:
            return PaysioError(code: .rateLimited, message: message,
                               idempotencyKey: idempotencyKey, httpStatus: 429)
        default:
            return PaysioError(code: .unknown, message: message,
                               idempotencyKey: idempotencyKey, httpStatus: response.status)
        }
    }

    /// Exact validation strings from CONTRACT.md section 3.
    static let billingAddressMessage = "Please enter your full billing address (street, city and postal code)."
    static let contactMessage = "Missing required contact fields"
    static let achAuthorizationMessage = "You must authorize the bank debit to continue"

    /// 400s that are not declines are validation errors. Match the contract's exact
    /// strings first, then fall back to keywords so older backends still map sensibly.
    private static func classify400(_ message: String) -> PaysioErrorCode {
        if message == billingAddressMessage { return .billingAddressRequired }
        if message == contactMessage { return .contactRequired }
        if message == achAuthorizationMessage { return .invalidFields }
        let lower = message.lowercased()
        if lower.contains("billing address") || lower.contains("postal") { return .billingAddressRequired }
        if lower.contains("contact") { return .contactRequired }
        return .invalidFields
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .timedOut: return "The request timed out."
        case .notConnectedToInternet, .networkConnectionLost: return "No internet connection."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "Could not reach Paysio."
        default: return error.localizedDescription
        }
    }
}

// MARK: - JSON helpers shared by the core

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        if let s = self[key] as? String { return s }
        if let n = self[key] as? NSNumber { return n.stringValue }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let b = self[key] as? Bool { return b }
        if let n = self[key] as? NSNumber { return n.boolValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let n = self[key] as? NSNumber { return n.intValue }
        if let s = self[key] as? String { return Int(s) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let n = self[key] as? NSNumber { return n.doubleValue }
        if let s = self[key] as? String { return Double(s) }
        return nil
    }

    func object(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }

    func array(_ key: String) -> [[String: Any]]? { self[key] as? [[String: Any]] }
}
