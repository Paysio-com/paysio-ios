import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// What is being charged.
public enum PaysioPaymentSource: Sendable {
    /// A fresh card tokenized by `PaysioVault.tokenizeCard`.
    case card(PaysioCardAlias)
    /// A fresh US bank account tokenized by `PaysioVault.tokenizeBank`. The SDK
    /// sends `achAuthorized: true` only when `PaysioPayOptions.achAuthorized` is set,
    /// i.e. after the payer ticked the consent row showing `session.achAuthorizationText`.
    case bank(PaysioBankAlias)
    /// A saved method (phase 2). `portalToken` comes from the quick-checkout
    /// email-code endpoints; `cvc` only when the method `requiresCvc`.
    case saved(billingId: String, portalToken: String, cvc: String?)

    var kind: PaysioMethodKind {
        switch self {
        case .card: return .card
        case .bank: return .bank
        case .saved: return .saved
        }
    }
}

/// `pay()` orchestration (CONTRACT.md sections 3 and 4):
/// validate -> (3DS for cards) -> charge with one `Idempotency-Key`,
/// retrying once on a transport error only.
@MainActor
public final class PaysioPay {
    public let client: PaysioClient
    public let session: PaysioSession
    public let threeDSHost: ThreeDSWebHost?
    public let appId: String?
    public let onEvent: PaysioEventHandler?

    /// - Parameters:
    ///   - threeDSHost: required for cards when `session.threeDsEnabled`; pass
    ///     `WKThreeDSWebHost()` or your own.
    ///   - appId: bundle identifier reported in `clientMetadata.appId`.
    public init(client: PaysioClient, session: PaysioSession, threeDSHost: ThreeDSWebHost? = nil,
                appId: String? = Bundle.main.bundleIdentifier, onEvent: PaysioEventHandler? = nil) {
        self.client = client
        self.session = session
        self.threeDSHost = threeDSHost
        self.appId = appId
        self.onEvent = onEvent
    }

    /// Charges the session. Throws `PaysioError`; returns the server's result,
    /// including `declined` and `error` statuses (those are results, not throws).
    public func pay(
        source: PaysioPaymentSource,
        customer: PaysioCustomer,
        billingAddress: PaysioAddress,
        options: PaysioPayOptions = PaysioPayOptions(),
        onStep: ((PaysioPayStep) -> Void)? = nil
    ) async throws -> PaysioPayResult {
        onEvent?(.payStart(method: source.kind))
        onStep?(.validating)

        // 1. Local validation mirrors the server rules.
        var fieldErrors = PaysioValidation.validateContact(customer, requirePhone: session.requirePhone)
        let addressErrors = PaysioValidation.validateBillingAddress(billingAddress)
        fieldErrors.merge(addressErrors) { $1 }
        if !fieldErrors.isEmpty {
            let code: PaysioErrorCode = addressErrors.isEmpty ? .contactRequired
                : (fieldErrors.count == addressErrors.count ? .billingAddressRequired : .invalidFields)
            let error = PaysioError(code: code, message: "Some details are missing or invalid.", fieldErrors: fieldErrors)
            onEvent?(.error(code: code))
            throw error
        }
        if case .bank = source, !options.achAuthorized {
            throw fail(PaysioError(code: .invalidFields, message: "Please accept the bank account authorization to continue."))
        }
        if case .saved = source {} else if session.vault == nil {
            throw fail(PaysioError(code: .notConfigured, message: "This checkout is not set up for in-app payments."))
        }

        // 2. 3-D Secure for fresh cards.
        var threeDsToken: String? = nil
        if case .card(let card) = source, session.threeDsEnabled {
            guard let host = threeDSHost else {
                throw fail(PaysioError(code: .notConfigured, message: "3-D Secure is enabled but no ThreeDSWebHost was provided."))
            }
            guard let amountMinor = session.totalMinor ?? options.amountMinor else {
                throw fail(PaysioError(code: .sessionInvalid, message: "The session has no total, so 3-D Secure cannot run. Pass PaysioPayOptions.amountMinor."))
            }
            onStep?(.threeDs)
            let threeDS = PaysioThreeDS(client: client, session: session, host: host, onEvent: onEvent)
            do {
                threeDsToken = try await threeDS.authenticate(
                    card: card, amountMajor: Double(amountMinor) / 100.0,
                    email: customer.email, billingCountry: billingAddress.country)
            } catch let error as PaysioError {
                throw fail(error)
            }
        }

        // 3. Charge, one idempotency key per attempt.
        onStep?(.charging)
        let idempotencyKey = UUID().uuidString.lowercased()
        let body = buildBody(source: source, customer: customer, billingAddress: billingAddress,
                             options: options, threeDsToken: threeDsToken)
        let response = try await postWithOneRetry(body: body, idempotencyKey: idempotencyKey)

        guard response.isSuccess else {
            throw fail(PaysioClient.mapFailure(response, idempotencyKey: idempotencyKey))
        }
        let result = PaysioPay.parseResult(response.json, idempotencyKey: idempotencyKey)
        onStep?(.done)
        onEvent?(.payResult(status: result.status))
        return result
    }

    // MARK: - Internals

    private func fail(_ error: PaysioError) -> PaysioError {
        onEvent?(.error(code: error.code))
        return error
    }

    /// POST /pay. On a transport failure (URLError) retry once with the SAME key.
    /// Never retry on a response (CONTRACT.md section 3).
    private func postWithOneRetry(body: [String: Any], idempotencyKey: String) async throws -> PaysioClient.Response {
        let path = "api/checkout/\(session.slug)/pay"
        let headers = ["Idempotency-Key": idempotencyKey]
        do {
            return try await client.post(path, body: body, headers: headers)
        } catch let first as PaysioError where first.code == .network {
            do {
                return try await client.post(path, body: body, headers: headers)
            } catch let second as PaysioError {
                throw fail(second.with(idempotencyKey: idempotencyKey))
            }
        } catch let other as PaysioError {
            throw fail(other.with(idempotencyKey: idempotencyKey))
        }
    }

    func buildBody(source: PaysioPaymentSource, customer: PaysioCustomer, billingAddress: PaysioAddress,
                   options: PaysioPayOptions, threeDsToken: String?) -> [String: Any] {
        var body: [String: Any] = [
            "email": customer.email.trimmed,
            "firstName": customer.firstName.trimmed,
            "lastName": customer.lastName.trimmed,
            "billingAddress1": billingAddress.address1.trimmed,
            "billingCity": billingAddress.city.trimmed,
            "billingState": billingAddress.state.trimmed,
            "billingPostalCode": billingAddress.postalCode.trimmed,
            "billingCountry": billingAddress.country.uppercased(),
            "clientMetadata": clientMetadata(extra: options.metadata),
        ]
        if let phone = customer.phone?.trimmed, !phone.isEmpty { body["phone"] = phone }
        if let address2 = billingAddress.address2?.trimmed, !address2.isEmpty { body["billingAddress2"] = address2 }

        switch source {
        case .card(let card):
            body["vaultPanAlias"] = card.panAlias
            body["vaultCvcAlias"] = card.cvcAlias
            body["vaultExpMonth"] = card.expMonth
            body["vaultExpYear"] = card.expYear
            if let bin = card.bin { body["vaultBin"] = bin }
            if let brand = card.brand { body["vaultBrand"] = brand }
            if let last4 = card.last4 { body["vaultLast4"] = last4 }
            if let threeDsToken { body["threeDsToken"] = threeDsToken }
        case .bank(let bank):
            body["paymentMethodType"] = "ach"
            body["vaultBankAccountAlias"] = bank.accountAlias
            if let last4 = bank.last4 { body["vaultBankLast4"] = last4 }
            body["routingNumber"] = bank.routingNumber
            body["accountType"] = bank.accountType.rawValue
            body["accountHolderType"] = bank.holderType.rawValue
            // Only reached when options.achAuthorized is set (checked in pay()).
            if options.achAuthorized { body["achAuthorized"] = true }
        case .saved(let billingId, let portalToken, let cvc):
            body["quickCheckout"] = true
            body["billingId"] = billingId
            body["portalToken"] = portalToken
            if let cvc, !cvc.isEmpty { body["cvc"] = cvc }
        }

        let items = options.items ?? session.items
        body["items"] = items.map { item -> [String: Any] in
            var line: [String: Any] = ["productId": item.productId, "quantity": item.quantity]
            if let variantId = item.variantId { line["variantId"] = variantId }
            return line
        }
        if let code = options.discountCode?.trimmed, !code.isEmpty { body["discountCode"] = code }
        if !options.customFieldValues.isEmpty {
            body["customFieldValues"] = options.customFieldValues.mapValues { $0.jsonValue }
        }
        if let shipping = options.shippingAddress {
            var s: [String: Any] = [
                "address1": shipping.address1, "city": shipping.city, "state": shipping.state,
                "postalCode": shipping.postalCode, "country": shipping.country.uppercased(),
            ]
            if let a2 = shipping.address2 { s["address2"] = a2 }
            body["shippingAddress"] = s
        }
        return body
    }

    private func clientMetadata(extra: [String: PaysioJSONScalar]) -> [String: Any] {
        var meta: [String: Any] = [
            "platform": PaysioSDK.platform,
            "sdk": PaysioSDK.clientMetadataSDK,
            "language": Locale.preferredLanguages.first ?? "en-US",
            "timezone": TimeZone.current.identifier,
        ]
        if let appId { meta["appId"] = appId }
        #if canImport(UIKit)
        meta["osVersion"] = UIDevice.current.systemVersion
        meta["deviceModel"] = PaysioPay.deviceModelIdentifier()
        let bounds = UIScreen.main.bounds
        meta["screenWidth"] = Int(bounds.width)
        meta["screenHeight"] = Int(bounds.height)
        #endif
        if !extra.isEmpty { meta["extra"] = extra.mapValues { $0.jsonValue } }
        return meta
    }

    static func parseResult(_ json: [String: Any], idempotencyKey: String) -> PaysioPayResult {
        let status = PaysioPayResult.Status(rawValue: json.string("status") ?? "") ?? .error
        let card = json.object("card") ?? [:]
        return PaysioPayResult(
            status: status,
            transactionId: json.string("transactionId") ?? "",
            orderNumber: json.string("orderNumber"),
            orderLabel: json.string("orderLabel"),
            confirmationToken: json.string("confirmationToken"),
            successUrl: json.string("successUrl"),
            amount: json.double("amount"),
            currency: json.string("currency"),
            cardBrand: card.string("brand"),
            cardLast4: card.string("last4"),
            bankAuthUrl: json.string("bankAuthUrl"),
            idempotencyKey: idempotencyKey
        )
    }

    #if canImport(UIKit)
    /// "iPhone15,2" style identifier via `uname`, the usual way to get the model.
    static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(String(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }
    #endif
}
