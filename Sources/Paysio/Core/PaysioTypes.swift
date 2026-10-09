import Foundation

// Public value types of the Paysio Mobile SDK. These mirror
// `sdks/react-native/src/types.ts` one for one so the three SDKs share a vocabulary.

// MARK: - Session

/// VGS vault environment the session targets.
public enum PaysioEnvironment: String, Codable, Sendable {
    case sandbox
    case live
}

/// VGS Collect target returned by `GET /api/checkout/:slug` as `vaultConfig`.
public struct PaysioVaultConfig: Codable, Sendable, Equatable {
    public let vaultId: String
    public let environment: PaysioEnvironment

    public init(vaultId: String, environment: PaysioEnvironment) {
        self.vaultId = vaultId
        self.environment = environment
    }
}

/// A custom field the merchant added to the payment link.
public struct PaysioCustomField: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let label: String
    /// `text`, `textarea`, `select`, `checkbox`, `number` or any future type.
    public let type: String
    public let required: Bool
    public let options: [String]
    public let placeholder: String?

    public init(id: String, label: String, type: String, required: Bool = false,
                options: [String] = [], placeholder: String? = nil) {
        self.id = id
        self.label = label
        self.type = type
        self.required = required
        self.options = options
        self.placeholder = placeholder
    }
}

/// One line of the session; sent back to the server as `items`.
public struct PaysioSessionItem: Codable, Sendable, Equatable {
    public let productId: String
    public let quantity: Int
    public let variantId: String?
    public let name: String?
    /// Unit amount in minor units when the server provides it.
    public let unitAmount: Int?

    public init(productId: String, quantity: Int, variantId: String? = nil,
                name: String? = nil, unitAmount: Int? = nil) {
        self.productId = productId
        self.quantity = quantity
        self.variantId = variantId
        self.name = name
        self.unitAmount = unitAmount
    }
}

/// White-label brand of the selling workspace (nil means Paysio).
public struct PaysioBrand: Codable, Sendable, Equatable {
    public let name: String
    public let logoUrl: String?
    public let accent: String?

    public init(name: String, logoUrl: String? = nil, accent: String? = nil) {
        self.name = name
        self.logoUrl = logoUrl
        self.accent = accent
    }
}

// MARK: - Customer and addresses

public struct PaysioAddress: Codable, Sendable, Equatable {
    public var address1: String
    public var address2: String?
    public var city: String
    public var state: String
    public var postalCode: String
    public var country: String

    public init(address1: String = "", address2: String? = nil, city: String = "",
                state: String = "", postalCode: String = "", country: String = "US") {
        self.address1 = address1
        self.address2 = address2
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
    }

    public static let empty = PaysioAddress()
}

public struct PaysioCustomer: Codable, Sendable, Equatable {
    public var email: String
    public var firstName: String
    public var lastName: String
    public var phone: String?

    public init(email: String = "", firstName: String = "", lastName: String = "", phone: String? = nil) {
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.phone = phone
    }

    public static let empty = PaysioCustomer()
}

public struct PaysioBillingDetails: Codable, Sendable, Equatable {
    public var customer: PaysioCustomer
    public var address: PaysioAddress

    public init(customer: PaysioCustomer, address: PaysioAddress) {
        self.customer = customer
        self.address = address
    }
}

public struct PaysioSavedAddress: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let address: PaysioAddress

    public init(id: String, name: String, address: PaysioAddress) {
        self.id = id
        self.name = name
        self.address = address
    }
}

// MARK: - Payment methods

public enum PaysioMethodKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case card
    case bank
    case saved

    public var id: String { rawValue }
}

/// A previously saved payment method (phase 2: quick checkout).
public struct PaysioSavedMethod: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let brand: String?
    public let bin: String?
    public let bankName: String?
    public let isBank: Bool
    public let last4: String
    /// Right-aligned detail: an expiry ("12/32") or an account type ("Checking").
    public let meta: String?
    public let badge: String?
    public let disabled: Bool
    /// Whether a CVC must be collected before charging this method.
    public let requiresCvc: Bool

    public init(id: String, brand: String? = nil, bin: String? = nil, bankName: String? = nil,
                isBank: Bool = false, last4: String, meta: String? = nil, badge: String? = nil,
                disabled: Bool = false, requiresCvc: Bool = false) {
        self.id = id
        self.brand = brand
        self.bin = bin
        self.bankName = bankName
        self.isBank = isBank
        self.last4 = last4
        self.meta = meta
        self.badge = badge
        self.disabled = disabled
        self.requiresCvc = requiresCvc
    }
}

public enum PaysioBankAccountType: String, Codable, Sendable, CaseIterable {
    case checking
    case savings

    public var label: String { self == .checking ? "Checking" : "Savings" }
}

public enum PaysioBankHolderType: String, Codable, Sendable, CaseIterable {
    case personal
    case business

    public var label: String { self == .personal ? "Personal" : "Business" }
}

// MARK: - Tokenized results (what leaves the fields: aliases only)

/// What the card fields produce. Never contains the PAN or the CVC.
public struct PaysioCardAlias: Codable, Sendable, Equatable {
    public let panAlias: String
    public let cvcAlias: String
    /// Two digits, "MM".
    public let expMonth: String
    /// Four digits, "YYYY".
    public let expYear: String
    public let bin: String?
    public let brand: String?
    public let last4: String?

    public init(panAlias: String, cvcAlias: String, expMonth: String, expYear: String,
                bin: String?, brand: String?, last4: String?) {
        self.panAlias = panAlias
        self.cvcAlias = cvcAlias
        self.expMonth = expMonth
        self.expYear = expYear
        self.bin = bin
        self.brand = brand
        self.last4 = last4
    }
}

/// What the bank fields produce. The account number is an alias.
public struct PaysioBankAlias: Codable, Sendable, Equatable {
    public let accountAlias: String
    public let last4: String?
    public let routingNumber: String
    public let accountType: PaysioBankAccountType
    public let holderType: PaysioBankHolderType

    public init(accountAlias: String, last4: String?, routingNumber: String,
                accountType: PaysioBankAccountType, holderType: PaysioBankHolderType) {
        self.accountAlias = accountAlias
        self.last4 = last4
        self.routingNumber = routingNumber
        self.accountType = accountType
        self.holderType = holderType
    }
}

// MARK: - Field state

public struct PaysioFieldState: Sendable, Equatable {
    public var valid: Bool
    public var empty: Bool
    public var focused: Bool
    public var dirty: Bool
    /// First validation message, once the field has been touched.
    public var error: String?

    public init(valid: Bool = false, empty: Bool = true, focused: Bool = false,
                dirty: Bool = false, error: String? = nil) {
        self.valid = valid
        self.empty = empty
        self.focused = focused
        self.dirty = dirty
        self.error = error
    }

    /// Red border rule from the web: only after blur, never while focused.
    public var showsInvalid: Bool { dirty && !focused && !valid }
}

// MARK: - Pay flow

public enum PaysioPayStep: String, Sendable {
    case idle, validating, aliasing, threeDs = "three_ds", charging, done
}

/// Options for one `pay()` call.
public struct PaysioPayOptions: Sendable {
    /// Overrides the items from the session.
    public var items: [PaysioSessionItem]?
    public var discountCode: String?
    public var customFieldValues: [String: PaysioJSONScalar]
    public var shippingAddress: PaysioAddress?
    /// Merchant metadata merged into `clientMetadata.extra` (never card data).
    public var metadata: [String: PaysioJSONScalar]
    /// Amount in minor units for 3-D Secure when the session has no fixed total
    /// (pay what you want). Ignored when the session carries a total.
    public var amountMinor: Int?
    /// The payer ticked the ACH consent row (`session.achAuthorizationText`). A bank
    /// charge is refused locally without it, and `achAuthorized: true` is only sent
    /// when it is set (RN `bank.authorized`).
    public var achAuthorized: Bool

    public init(items: [PaysioSessionItem]? = nil, discountCode: String? = nil,
                customFieldValues: [String: PaysioJSONScalar] = [:],
                shippingAddress: PaysioAddress? = nil,
                metadata: [String: PaysioJSONScalar] = [:],
                amountMinor: Int? = nil,
                achAuthorized: Bool = false) {
        self.achAuthorized = achAuthorized
        self.items = items
        self.discountCode = discountCode
        self.customFieldValues = customFieldValues
        self.shippingAddress = shippingAddress
        self.metadata = metadata
        self.amountMinor = amountMinor
    }
}

/// A JSON scalar (string, number or bool) for custom fields and metadata.
public enum PaysioJSONScalar: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)

    var jsonValue: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        }
    }
}

public struct PaysioPayResult: Sendable, Equatable {
    public enum Status: String, Sendable {
        case pendingSettlement = "pending_settlement"
        case declined
        case error
    }

    public let status: Status
    public let transactionId: String
    public let orderNumber: String?
    public let orderLabel: String?
    public let confirmationToken: String?
    public let successUrl: String?
    public let amount: Double?
    public let currency: String?
    public let cardBrand: String?
    public let cardLast4: String?
    /// Instant ACH authorization URL when the bank rail needs it.
    public let bankAuthUrl: String?
    public let idempotencyKey: String

    public init(status: Status, transactionId: String, orderNumber: String? = nil,
                orderLabel: String? = nil, confirmationToken: String? = nil,
                successUrl: String? = nil, amount: Double? = nil, currency: String? = nil,
                cardBrand: String? = nil, cardLast4: String? = nil, bankAuthUrl: String? = nil,
                idempotencyKey: String) {
        self.status = status
        self.transactionId = transactionId
        self.orderNumber = orderNumber
        self.orderLabel = orderLabel
        self.confirmationToken = confirmationToken
        self.successUrl = successUrl
        self.amount = amount
        self.currency = currency
        self.cardBrand = cardBrand
        self.cardLast4 = cardLast4
        self.bankAuthUrl = bankAuthUrl
        self.idempotencyKey = idempotencyKey
    }
}

// MARK: - Events (analytics hook; never contains card data)

public enum PaysioEvent: Sendable, Equatable {
    case ready(sandbox: Bool)
    case fieldFocus(field: String)
    case methodChange(method: PaysioMethodKind)
    case payStart(method: PaysioMethodKind)
    case threeDsStart
    case threeDsChallenge
    case threeDsResult(approved: Bool)
    case payResult(status: PaysioPayResult.Status)
    case error(code: PaysioErrorCode)
}

public typealias PaysioEventHandler = @Sendable (PaysioEvent) -> Void
