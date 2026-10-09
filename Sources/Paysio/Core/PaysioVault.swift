import Foundation
import VGSCollectSDK

/// Wraps one `VGSCollect` instance and turns a submit to the vault's inbound route
/// into aliases (CONTRACT.md section 2).
///
/// The raw PAN, CVC and account number live only inside the VGS text fields and the
/// TLS request VGS makes; this class never sees them.
///
/// VGS API relied on (vgs-collect-ios 1.20, `VGSCollect+network.swift`):
/// ```swift
/// public func sendData(path: String, method: VGSCollectHTTPMethod = .post, routeId: String? = nil,
///                      extraData: [String: Any]? = nil,
///                      requestOptions: VGSCollectRequestOptions = VGSCollectRequestOptions()) async -> VGSResponse
/// @frozen public enum VGSResponse {
///     case success(_ code: Int, _ data: Data?, _ response: URLResponse?)
///     case failure(_ code: Int, _ data: Data?, _ response: URLResponse?, _ error: Error?)
/// }
/// ```
@MainActor
public final class PaysioVault {
    /// Field names fixed by the inbound route (CONTRACT.md section 2).
    public enum FieldName {
        public static let cardNumber = "card_number"
        public static let cardExpiry = "card_exp"
        public static let cardCvc = "card_cvc"
        public static let bankAccountNumber = "bank_account_number"
    }

    public let config: PaysioVaultConfig
    /// The collector the SDK's fields register with. Exposed so custom layouts can
    /// build their own `VGSConfiguration` against it.
    public let collector: VGSCollect

    public static let submitTimeout: TimeInterval = 20

    public init(config: PaysioVaultConfig) {
        self.config = config
        // `VGSCollect(id:environment:dataRegion:hostname:)`, `Environment` is
        // `.sandbox` / `.live` (vgs-collect-ios `Core/Enums.swift`).
        let environment: Environment = config.environment == .live ? .live : .sandbox
        self.collector = VGSCollect(id: config.vaultId, environment: environment)
    }

    /// Submits the three card fields to `/post` and reads the aliases from the echo.
    /// `bin`, `brand`, `last4` come from the number field's state, never from the raw value.
    public func tokenizeCard(numberState: VGSCardState?) async throws -> PaysioCardAlias {
        let body = try await submit(path: "/post")
        guard let panAlias = body.string(FieldName.cardNumber), !panAlias.isEmpty,
              let cvcAlias = body.string(FieldName.cardCvc), !cvcAlias.isEmpty,
              let exp = body.string(FieldName.cardExpiry),
              let parsed = PaysioValidation.parseExpiry(exp) else {
            throw PaysioError(code: .vaultUnavailable, message: "The vault did not return the card aliases.")
        }
        let brandName = numberState?.cardBrand.stringValue
        return PaysioCardAlias(
            panAlias: panAlias,
            cvcAlias: cvcAlias,
            expMonth: parsed.month,
            expYear: parsed.year,
            bin: numberState.flatMap { $0.bin.isEmpty ? nil : $0.bin },
            brand: PaysioValidation.normalizeBrand(brandName),
            last4: numberState.flatMap { $0.last4.isEmpty ? nil : $0.last4 }
        )
    }

    /// Submits the bank account field. The routing number is not sensitive and is
    /// collected natively, so it is passed through.
    public func tokenizeBank(routingNumber: String, accountType: PaysioBankAccountType,
                             holderType: PaysioBankHolderType, last4Hint: String?) async throws -> PaysioBankAlias {
        let body = try await submit(path: "/post")
        guard let accountAlias = body.string(FieldName.bankAccountNumber), !accountAlias.isEmpty else {
            throw PaysioError(code: .vaultUnavailable, message: "The vault did not return the bank account alias.")
        }
        // GENERIC_T_FOUR aliases keep the last four digits at the end.
        let last4 = last4Hint ?? String(accountAlias.suffix(4))
        return PaysioBankAlias(accountAlias: accountAlias, last4: last4, routingNumber: routingNumber,
                               accountType: accountType, holderType: holderType)
    }

    // MARK: - Submit

    /// Runs `sendData` with a 20 s ceiling and returns the posted-body echo
    /// (`json.json ?? json.data ?? json`).
    private func submit(path: String) async throws -> [String: Any] {
        let collector = self.collector
        // A task group would wait for the VGS call to finish before returning, so the
        // ceiling is enforced with two unstructured tasks racing on one continuation.
        let response: VGSResponse = try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            Task { @MainActor in
                let value = await collector.sendData(path: path, method: .post)
                once.resume(.success(value))
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(PaysioVault.submitTimeout * 1_000_000_000))
                once.resume(.failure(PaysioError(code: .vaultUnavailable,
                    message: "Securing your details took too long. Check your connection and try again.")))
            }
        }

        switch response {
        case .success(_, let data, _):
            let root = PaysioClient.decode(data ?? Data())
            return (root["json"] as? [String: Any]) ?? (root["data"] as? [String: Any]) ?? root
        case .failure(let code, _, _, let error):
            // `VGSErrorType.inputDataIsNotValid` means a field failed validation; the
            // SDK validates before submitting so this is a programming error.
            if code == VGSErrorType.inputDataIsNotValid.rawValue {
                throw PaysioError(code: .invalidFields, message: "Check the card details and try again.")
            }
            let message = error?.localizedDescription ?? "The vault rejected the request (\(code))."
            throw PaysioError(code: .vaultUnavailable, message: message, httpStatus: code)
        }
    }
}

/// Resumes a continuation at most once, whichever racing task finishes first.
final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    func resume(_ result: Result<T, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(with: result)
    }
}
