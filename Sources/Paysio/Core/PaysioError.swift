import Foundation

/// Error codes every Paysio Mobile SDK exposes (CONTRACT.md section 5).
///
/// The raw values are the same strings the React Native SDK uses, so merchants
/// can share error handling across platforms.
public enum PaysioErrorCode: String, Codable, Sendable, CaseIterable {
    /// One or more fields are invalid. `PaysioError.fieldErrors` says which.
    case invalidFields = "invalid_fields"
    /// Street, city, postal code or country is missing.
    case billingAddressRequired = "billing_address_required"
    /// Email, first name, last name (or phone when the workspace requires it) is missing.
    case contactRequired = "contact_required"
    /// 3-D Secure authentication was declined or errored.
    case threeDsFailed = "three_ds_failed"
    /// The customer closed the 3-D Secure challenge. Nothing was charged.
    case threeDsCancelled = "three_ds_cancelled"
    /// The 3-D Secure challenge did not resolve within four minutes.
    case threeDsTimeout = "three_ds_timeout"
    /// The processor declined the payment. See `PaysioError.declineCode`.
    case declined = "declined"
    /// The checkout session is no longer active. Create a new one on your server.
    case sessionExpired = "session_expired"
    /// The slug does not exist or is not a checkout session / payment link.
    case sessionInvalid = "session_invalid"
    /// Too many attempts from this device for this session. Try again later.
    case rateLimited = "rate_limited"
    /// The request never reached Paysio (offline, DNS, TLS, timeout).
    case network = "network"
    /// The outcome is unknown (5xx or unexpected payload). `idempotencyKey` is set so
    /// a retry with the same key can never charge twice.
    case unknown = "unknown"
    /// VGS Collect could not secure the card or bank details.
    case vaultUnavailable = "vault_unavailable"
    /// The session has no vault configuration; the workspace is not on the VGS vault.
    case notConfigured = "not_configured"
}

/// Field identifiers used in `PaysioError.fieldErrors` and `PaysioEvent.fieldFocus`.
public enum PaysioField: String, Codable, Sendable, CaseIterable, Hashable {
    case number, expiry, cvc, routing, account
    case email, firstName, lastName, phone
    case address1, city, state, postalCode, country
}

/// The single error type thrown by the SDK. Mirrors `PaysioErrorShape` in the RN SDK.
public struct PaysioError: Error, Sendable, CustomStringConvertible {
    public let code: PaysioErrorCode
    public let message: String
    /// Processor decline code when `code == .declined`.
    public let declineCode: String?
    /// Per-field messages when `code == .invalidFields` (or the contact/billing codes).
    public let fieldErrors: [PaysioField: String]
    /// The `Idempotency-Key` used for the charge attempt, when one was minted.
    public let idempotencyKey: String?
    /// HTTP status of the response that produced this error, if any.
    public let httpStatus: Int?

    public init(
        code: PaysioErrorCode,
        message: String,
        declineCode: String? = nil,
        fieldErrors: [PaysioField: String] = [:],
        idempotencyKey: String? = nil,
        httpStatus: Int? = nil
    ) {
        self.code = code
        self.message = message
        self.declineCode = declineCode
        self.fieldErrors = fieldErrors
        self.idempotencyKey = idempotencyKey
        self.httpStatus = httpStatus
    }

    public var description: String { "PaysioError(\(code.rawValue)): \(message)" }

    /// Returns a copy carrying the idempotency key of the attempt that failed.
    func with(idempotencyKey: String?) -> PaysioError {
        PaysioError(code: code, message: message, declineCode: declineCode,
                    fieldErrors: fieldErrors, idempotencyKey: idempotencyKey ?? self.idempotencyKey,
                    httpStatus: httpStatus)
    }
}

extension PaysioError: LocalizedError {
    public var errorDescription: String? { message }
}
