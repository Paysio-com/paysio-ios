import Foundation

/// The subset of `GET /api/checkout/:slug` the SDK keeps (CONTRACT.md section 1).
public struct PaysioSession: Sendable {
    public let slug: String
    public let workspaceId: String
    public let workspaceName: String
    public let sandbox: Bool
    public let currency: String
    /// Total in minor units when the server provides it; nil for pay-what-you-want.
    public let totalMinor: Int?
    public let totalFormatted: String
    public let cardEnabled: Bool
    public let bankEnabled: Bool
    public let threeDsEnabled: Bool
    public let requirePhone: Bool
    public let collectShippingAddress: Bool
    public let customFields: [PaysioCustomField]
    public let items: [PaysioSessionItem]
    public let vault: PaysioVaultConfig?
    public let achAuthorizationText: String
    public let brand: PaysioBrand?
    /// Raw server payload for anything the typed subset does not cover.
    /// Stored as a JSON-encoded string so the struct stays `Sendable`.
    public let rawJSON: String

    /// Decodes `rawJSON` back into a dictionary.
    public var raw: [String: Any] {
        guard let data = rawJSON.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data),
              let object = any as? [String: Any] else { return [:] }
        return object
    }

    /// Amount in major units for 3-D Secure (`amount: 12.34`).
    public var totalMajor: Double? { totalMinor.map { Double($0) / 100.0 } }

    /// ACH consent template used only when an older backend omits
    /// `workspace.achAuthorizationText`. Same wording as
    /// `backend/src/lib/checkout-copy.ts` (`ACH_AUTHORIZATION_TEXT`).
    public static let defaultAchAuthorizationTemplate =
        "By continuing, you authorize {merchant} to debit {amount} from the bank account above by " +
        "electronic funds transfer (ACH). You understand that this authorization will remain in effect " +
        "until the payment is processed, and that if the payment is returned unpaid you may be charged " +
        "a return fee. Transactions are processed securely by Paysio."

    /// Fills `{merchant}` and `{amount}` in the consent template (CONTRACT.md section 1).
    /// Same rule as RN `fillAchTemplate`: `{merchant}` / `{amount}`, case-insensitive,
    /// spaces inside the braces allowed; "this merchant" / "the amount shown" when unknown.
    public static func fillAchTemplate(_ template: String, merchant: String, amount: String) -> String {
        func fill(_ text: String, _ name: String, _ value: String) -> String {
            text.replacingOccurrences(of: "\\{\\s*\(name)\\s*\\}", with: NSRegularExpression.escapedTemplate(for: value),
                                      options: [.regularExpression, .caseInsensitive])
        }
        let m = merchant.isEmpty ? "this merchant" : merchant
        let a = amount.isEmpty ? "the amount shown" : amount
        return fill(fill(template, "merchant", m), "amount", a)
    }
}

/// Loads and parses a checkout session.
public enum PaysioSessionLoader {
    /// `GET /api/checkout/:slug` -> `PaysioSession`.
    ///
    /// Throws `session_expired` for the 404 every inactive, expired, deleted or paid
    /// session answers (CONTRACT.md section 1) and the usual `network` /
    /// `rate_limited` / `unknown` codes. `vault == nil` means `not_configured`.
    public static func load(slug: String, client: PaysioClient) async throws -> PaysioSession {
        let response = try await client.get("api/checkout/\(slug)")
        guard response.isSuccess else { throw PaysioClient.mapFailure(response) }
        return try parse(slug: slug, json: response.json)
    }

    /// Pure mapping from the server payload. Exposed for contract fixture tests.
    public static func parse(slug: String, json: [String: Any]) throws -> PaysioSession {
        let link = json.object("paymentLink") ?? [:]
        let workspace = json.object("workspace") ?? [:]
        // No status / expiry fields exist on the payload: an unusable session is a 404
        // (mapped to session_expired by PaysioClient.mapFailure).

        let vaultConfig = json.object("vaultConfig") ?? [:]
        var vault: PaysioVaultConfig? = nil
        if vaultConfig.bool("enabled") == true,
           let vaultId = vaultConfig.string("vaultId"),
           let envRaw = vaultConfig.string("environment") {
            // `environment` is the vault slug (`sandbox` / `live`), possibly with a
            // region suffix; anything containing "live" is live.
            let env: PaysioEnvironment = envRaw.lowercased().contains("live") ? .live : .sandbox
            vault = PaysioVaultConfig(vaultId: vaultId, environment: env)
        }

        let products = json.array("products") ?? []
        let items: [PaysioSessionItem] = products.compactMap { product in
            guard let productId = product.string("productId") ?? product.string("id") else { return nil }
            return PaysioSessionItem(
                productId: productId,
                // `items` for the charge are `{ productId, quantity: defaultQuantity }`.
                quantity: max(1, product.int("defaultQuantity") ?? product.int("quantity") ?? 1),
                variantId: product.string("variantId"),
                name: product.string("productName") ?? product.string("name"),
                unitAmount: product.int("productPrice") ?? product.int("price") ?? product.int("unitAmount")
            )
        }

        let currency = (json.string("currency")
            ?? products.first?.string("productCurrency")
            ?? products.first?.string("currency")
            ?? "USD").uppercased()

        // Totals: prefer an explicit server total; else sum the lines when every
        // line carries a unit amount; else nil (pay what you want).
        var totalMinor: Int? = json.int("totalAmount") ?? json.int("total")
        if totalMinor == nil, !items.isEmpty, items.allSatisfy({ $0.unitAmount != nil }) {
            totalMinor = items.reduce(0) { $0 + ($1.unitAmount ?? 0) * $1.quantity }
        }

        let customFields: [PaysioCustomField] = (link.array("customFields") ?? []).compactMap { field in
            guard let id = field.string("id") else { return nil }
            return PaysioCustomField(
                id: id,
                label: field.string("label") ?? id,
                type: field.string("type") ?? "text",
                required: field.bool("required") ?? false,
                options: (field["options"] as? [String]) ?? [],
                placeholder: field.string("placeholder")
            )
        }

        var brand: PaysioBrand? = nil
        if let b = json.object("brand"), let name = b.string("name") {
            brand = PaysioBrand(name: name, logoUrl: b.string("logoUrl"), accent: b.string("accent"))
        }

        let rawData = (try? JSONSerialization.data(withJSONObject: json, options: [])) ?? Data()
        let workspaceName = workspace.string("name") ?? brand?.name ?? ""
        let totalFormatted = PaysioMoney.format(minor: totalMinor, currency: currency)
        let achTemplate = workspace.string("achAuthorizationText")
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            ?? PaysioSession.defaultAchAuthorizationTemplate

        return PaysioSession(
            slug: slug,
            workspaceId: json.string("workspaceId") ?? "",
            workspaceName: workspaceName,
            sandbox: link.bool("sandbox") ?? false,
            currency: currency,
            totalMinor: totalMinor,
            totalFormatted: totalFormatted,
            cardEnabled: json.bool("cardEnabled") ?? false,
            bankEnabled: workspace.bool("achEnabled") ?? false,
            threeDsEnabled: json.bool("threeDsEnabled") ?? false,
            requirePhone: workspace.bool("requireCheckoutPhone") ?? false,
            collectShippingAddress: link.bool("collectShippingAddress") ?? false,
            customFields: customFields,
            items: items,
            vault: vault,
            achAuthorizationText: PaysioSession.fillAchTemplate(achTemplate, merchant: workspaceName, amount: totalFormatted),
            brand: brand,
            rawJSON: String(data: rawData, encoding: .utf8) ?? "{}"
        )
    }
}

/// Money formatting for display only; the server recomputes every total.
public enum PaysioMoney {
    public static func format(minor: Int?, currency: String, locale: Locale = .current) -> String {
        guard let minor else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: Double(minor) / 100.0)) ?? "\(Double(minor) / 100.0) \(currency)"
    }
}
