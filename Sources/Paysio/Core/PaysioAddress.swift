import Foundation

/// One street address suggestion (RN `AddressSuggestion`).
public struct PaysioAddressSuggestion: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let address1: String
    public let city: String
    public let state: String
    public let stateCode: String
    public let postalCode: String
    public let countryCode: String

    public init(id: String, label: String, address1: String = "", city: String = "", state: String = "",
                stateCode: String = "", postalCode: String = "", countryCode: String = "") {
        self.id = id
        self.label = label
        self.address1 = address1
        self.city = city
        self.state = state
        self.stateCode = stateCode
        self.postalCode = postalCode
        self.countryCode = countryCode
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? String, let label = json["label"] as? String, !label.isEmpty else { return nil }
        self.init(id: id, label: label,
                  address1: json["address1"] as? String ?? "",
                  city: json["city"] as? String ?? "",
                  state: json["state"] as? String ?? "",
                  stateCode: json["stateCode"] as? String ?? "",
                  postalCode: json["postalCode"] as? String ?? "",
                  countryCode: json["countryCode"] as? String ?? "")
    }
}

/// Street address autocomplete through the same two public endpoints the hosted
/// checkout uses (RN `core/address.ts`):
///
///     GET /api/checkout/address-suggest?q=&country=&sessiontoken=
///         -> { suggestions: AddressSuggestion[] }   (placeId + display text only)
///     GET /api/checkout/address-details?placeId=&sessiontoken=
///         -> { suggestion: AddressSuggestion | null } (parsed components)
///
/// The backend holds the Google Places key, so nothing secret ships in the app. Both
/// endpoints answer an empty result when Places is not configured. Neither call ever
/// throws: any failure is an empty list / nil and the street line stays plain text.
public enum PaysioAddressSuggest {
    public static let minQuery = 3
    public static let debounceNanoseconds: UInt64 = 250_000_000
    static let timeout: TimeInterval = 8

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpAdditionalHeaders = ["Accept": "application/json", "X-Paysio-SDK": PaysioSDK.headerValue]
        return URLSession(configuration: config)
    }()

    private static func url(_ apiBase: URL, _ path: String, _ params: [(String, String?)]) -> URL? {
        let base = apiBase.absoluteString.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard var components = URLComponents(string: base + path) else { return nil }
        components.queryItems = params.compactMap { key, value in
            guard let value, !value.isEmpty else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        // URLComponents leaves "+" unescaped, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url
    }

    private static func getJSON(_ url: URL) async -> [String: Any]? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// Suggestions for `query` (at least 3 characters); `[]` on any failure.
    public static func suggest(apiBase: URL, query: String, country: String?, sessionToken: String?) async -> [PaysioAddressSuggestion] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= minQuery else { return [] }
        let cc = String((country ?? "").lowercased().prefix(2))
        guard let url = url(apiBase, "/api/checkout/address-suggest",
                            [("q", text), ("country", cc), ("sessiontoken", sessionToken)]),
              let json = await getJSON(url),
              let list = json["suggestions"] as? [[String: Any]] else { return [] }
        return list.compactMap(PaysioAddressSuggestion.init(json:))
    }

    /// Parsed components for a picked suggestion; nil when it cannot be resolved.
    public static func details(apiBase: URL, placeId: String, sessionToken: String?) async -> PaysioAddressSuggestion? {
        guard !placeId.isEmpty,
              let url = url(apiBase, "/api/checkout/address-details", [("placeId", placeId), ("sessiontoken", sessionToken)]),
              let json = await getJSON(url),
              let suggestion = json["suggestion"] as? [String: Any] else { return nil }
        return PaysioAddressSuggestion(json: suggestion)
    }
}
