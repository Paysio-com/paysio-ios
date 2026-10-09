import Combine
import SwiftUI

/// How the drop-in sheet obtains authorization to charge a saved method (phase 2).
/// Return the portal token (from the quick-checkout email-code endpoints or
/// `POST /api/storefront-account/:id/checkout-authorization`) and a CVC when the
/// method `requiresCvc`.
public typealias PaysioSavedMethodAuthorizer = @MainActor (PaysioSavedMethod) async throws -> (portalToken: String, cvc: String?)

/// The drop-in checkout (RN `PaymentSheet.tsx`): loads the session, shows contact, the
/// payment method picker (card / bank panels with the billing address, the bank panel
/// with the ACH consent row), custom fields, runs `pay()` and reports the result. Pay
/// stays disabled until everything the charge needs is valid (RN `canPay`).
@MainActor
public struct PaysioPaymentSheet: View {
    @StateObject private var model: PaymentSheetModel
    private let theme: PaysioTheme
    private let sheetComponents: PaysioSheetComponents?

    /// - Parameters:
    ///   - sessionSlug: checkout session (`api-...`) or payment link slug.
    ///   - apiBase: `https://api.paysio.com` unless you use staging. Also used for
    ///     street address suggestions.
    ///   - customer, billingAddress: prefill; the customer can still edit.
    ///   - savedMethods: show the "Saved method" option (phase 2).
    ///   - savedMethodAuthorizer: required when `savedMethods` is non-empty.
    ///   - appId: bundle id reported in `clientMetadata`; defaults to the main bundle.
    ///   - disableAddressSuggestions: turn street suggestions off.
    ///   - sheetComponents: your own pick-list sheet / row look (see `PaysioSheetComponents`).
    public init(
        sessionSlug: String,
        apiBase: URL = PaysioClient.defaultAPIBase,
        theme: PaysioTheme = .auto,
        customer: PaysioCustomer = .empty,
        billingAddress: PaysioAddress = .empty,
        savedAddresses: [PaysioSavedAddress] = [],
        savedMethods: [PaysioSavedMethod] = [],
        savedMethodAuthorizer: PaysioSavedMethodAuthorizer? = nil,
        appId: String? = Bundle.main.bundleIdentifier,
        disableAddressSuggestions: Bool = false,
        sheetComponents: PaysioSheetComponents? = nil,
        onEvent: PaysioEventHandler? = nil,
        onSuccess: @escaping (PaysioPayResult) -> Void,
        onError: @escaping (PaysioError) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.sheetComponents = sheetComponents
        _model = StateObject(wrappedValue: PaymentSheetModel(
            slug: sessionSlug, apiBase: apiBase, customer: customer, billingAddress: billingAddress,
            savedAddresses: savedAddresses, savedMethods: savedMethods, savedMethodAuthorizer: savedMethodAuthorizer,
            appId: appId, disableAddressSuggestions: disableAddressSuggestions,
            onEvent: onEvent, onSuccess: onSuccess, onError: onError, onCancel: onCancel))
    }

    public var body: some View {
        PaymentSheetBody(model: model)
            .modifier(OptionalSheetComponents(components: sheetComponents))
            .paysioTheme(theme)
            .task { await model.load() }
    }
}

private struct OptionalSheetComponents: ViewModifier {
    let components: PaysioSheetComponents?

    func body(content: Content) -> some View {
        if let components { content.paysioSheetComponents(components) } else { content }
    }
}

// MARK: - Model

@MainActor
final class PaymentSheetModel: ObservableObject {
    enum Phase: Equatable { case loading, ready, failed(String) }

    @Published var phase: Phase = .loading
    @Published var session: PaysioSession?
    @Published var method: PaysioMethodKind = .card
    @Published var customer: PaysioCustomer
    @Published var billingAddress: PaysioAddress
    @Published var selectedSaved: PaysioSavedMethod?
    @Published var savedCvc: String = ""
    @Published var customValues: [String: String] = [:]
    @Published var fieldErrors: [PaysioField: String] = [:]
    @Published var touched: Set<PaysioField> = []
    @Published var errorMessage: String?
    @Published var step: PaysioPayStep = .idle
    @Published var achAuthorized = false
    @Published private(set) var cardController: PaysioCardFieldsController?
    @Published private(set) var bankController: PaysioBankFieldsController?

    let slug: String
    let client: PaysioClient
    let savedAddresses: [PaysioSavedAddress]
    let savedMethods: [PaysioSavedMethod]
    let savedMethodAuthorizer: PaysioSavedMethodAuthorizer?
    let appId: String?
    let disableAddressSuggestions: Bool
    let onEvent: PaysioEventHandler?
    let onSuccess: (PaysioPayResult) -> Void
    let onError: (PaysioError) -> Void
    let onCancel: (() -> Void)?
    private let threeDSHost = WKThreeDSWebHost()
    private var cancellables: Set<AnyCancellable> = []

    init(slug: String, apiBase: URL, customer: PaysioCustomer, billingAddress: PaysioAddress,
         savedAddresses: [PaysioSavedAddress], savedMethods: [PaysioSavedMethod],
         savedMethodAuthorizer: PaysioSavedMethodAuthorizer?, appId: String?, disableAddressSuggestions: Bool,
         onEvent: PaysioEventHandler?,
         onSuccess: @escaping (PaysioPayResult) -> Void, onError: @escaping (PaysioError) -> Void, onCancel: (() -> Void)?) {
        self.slug = slug
        self.client = PaysioClient(apiBase: apiBase)
        self.customer = customer
        self.billingAddress = billingAddress
        self.savedAddresses = savedAddresses
        self.savedMethods = savedMethods
        self.savedMethodAuthorizer = savedMethodAuthorizer
        self.appId = appId
        self.disableAddressSuggestions = disableAddressSuggestions
        self.onEvent = onEvent
        self.onSuccess = onSuccess
        self.onError = onError
        self.onCancel = onCancel
    }

    var options: [PaysioMethodKind] {
        guard let session else { return [] }
        var list: [PaysioMethodKind] = []
        if !savedMethods.isEmpty { list.append(.saved) }
        if session.cardEnabled { list.append(.card) }
        if session.bankEnabled { list.append(.bank) }
        return list
    }

    var isPaying: Bool { step != .idle && step != .done }

    /// RN `PaysioProvider` `canPay`: session loaded and idle, vault present for fresh
    /// methods, contact valid (phone when required), required custom fields filled, and
    /// card valid + address valid, or bank valid + ACH consent + address valid, or a
    /// saved method with an authorizer.
    var canPay: Bool {
        guard let session, phase == .ready, step == .idle else { return false }
        if method != .saved && session.vault == nil { return false }
        if !PaysioValidation.validateContact(customer, requirePhone: session.requirePhone).isEmpty { return false }
        for field in session.customFields where field.required && (customValues[field.id] ?? "").trimmed.isEmpty {
            return false
        }
        let addressValid = PaysioValidation.validateBillingAddress(billingAddress).isEmpty
        switch method {
        case .card: return (cardController?.state.valid ?? false) && addressValid
        case .bank: return (bankController?.state.valid ?? false) && achAuthorized && addressValid
        case .saved: return (selectedSaved ?? savedMethods.first) != nil && savedMethodAuthorizer != nil
        }
    }

    /// Errors to paint: the last pay attempt / server errors, plus local validation for
    /// fields the customer has already left (the web shows red only after blur).
    var displayedErrors: [PaysioField: String] {
        guard let session else { return fieldErrors }
        var local = PaysioValidation.validateContact(customer, requirePhone: session.requirePhone)
        local.merge(PaysioValidation.validateBillingAddress(billingAddress)) { $1 }
        var out = local.filter { touched.contains($0.key) }
        out.merge(fieldErrors) { $1 }
        return out
    }

    func fieldFocused(_ name: String) {
        onEvent?(.fieldFocus(field: name))
    }

    func fieldBlurred(_ name: String) {
        if let field = PaysioField(rawValue: name) { touched.insert(field) }
    }

    func load() async {
        guard session == nil else { return }
        phase = .loading
        do {
            let loaded = try await PaysioSessionLoader.load(slug: slug, client: client)
            session = loaded
            if let vault = loaded.vault {
                let card = PaysioCardFieldsController(vaultConfig: vault, sandbox: loaded.sandbox, onEvent: onEvent)
                let bank = PaysioBankFieldsController(vaultConfig: vault, onEvent: onEvent)
                // Field state lives in the controllers; republish so `canPay` follows it.
                card.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
                bank.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
                cardController = card
                bankController = bank
            } else if savedMethods.isEmpty {
                throw PaysioError(code: .notConfigured, message: "This checkout is not set up for in-app payments.")
            }
            method = options.first ?? .card
            phase = .ready
            onEvent?(.ready(sandbox: loaded.sandbox))
        } catch let error as PaysioError {
            phase = .failed(error.message)
            onEvent?(.error(code: error.code))
            onError(error)
        } catch {
            let wrapped = PaysioError(code: .unknown, message: error.localizedDescription)
            phase = .failed(wrapped.message)
            onError(wrapped)
        }
    }

    func selectMethod(_ kind: PaysioMethodKind) {
        method = kind
        errorMessage = nil
        onEvent?(.methodChange(method: kind))
    }

    func pay() async {
        guard let session, !isPaying, canPay else { return }
        errorMessage = nil
        fieldErrors = [:]

        let pay = PaysioPay(client: client, session: session, threeDSHost: threeDSHost, appId: appId, onEvent: onEvent)
        do {
            step = .aliasing
            let source: PaysioPaymentSource
            switch method {
            case .card:
                guard let controller = cardController else { throw PaysioError(code: .notConfigured, message: "Card entry is not available.") }
                source = .card(try await controller.tokenize())
            case .bank:
                guard let controller = bankController else { throw PaysioError(code: .notConfigured, message: "Bank entry is not available.") }
                source = .bank(try await controller.tokenize())
            case .saved:
                guard let saved = selectedSaved ?? savedMethods.first, let authorizer = savedMethodAuthorizer else {
                    throw PaysioError(code: .notConfigured, message: "No saved method authorizer was provided.")
                }
                let auth = try await authorizer(saved)
                source = .saved(billingId: saved.id, portalToken: auth.portalToken,
                                cvc: auth.cvc ?? (savedCvc.isEmpty ? nil : savedCvc))
            }

            var options = PaysioPayOptions()
            options.customFieldValues = customValues.reduce(into: [:]) { $0[$1.key] = .string($1.value) }
            // Only a ticked consent row authorizes the debit (RN `bank.authorized`).
            options.achAuthorized = method == .bank && achAuthorized
            let result = try await pay.pay(source: source, customer: customer, billingAddress: billingAddress,
                                           options: options) { [weak self] s in self?.step = s }
            step = .done
            if result.status == .pendingSettlement {
                onSuccess(result)
            } else {
                errorMessage = result.status == .declined ? "Your payment was declined." : "Something went wrong. Please try again."
                step = .idle
                onError(PaysioError(code: result.status == .declined ? .declined : .unknown,
                                    message: errorMessage ?? "", idempotencyKey: result.idempotencyKey))
            }
        } catch let error as PaysioError {
            step = .idle
            fieldErrors = error.fieldErrors
            errorMessage = error.message
            if error.code == .sessionExpired || error.code == .sessionInvalid {
                phase = .failed(error.message)
            }
            onError(error)
        } catch {
            step = .idle
            errorMessage = error.localizedDescription
            onError(PaysioError(code: .unknown, message: error.localizedDescription))
        }
    }
}

// MARK: - Body

struct PaymentSheetBody: View {
    @ObservedObject var model: PaymentSheetModel
    @Environment(\.paysioTheme) private var theme
    @Environment(\.paysioSheetComponents) private var sheetComponents
    @State private var openSelect: String?

    var body: some View {
        PaysioScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                switch model.phase {
                case .loading:
                    ProgressView().tint(theme.colors.mutedForeground).frame(maxWidth: .infinity).padding(.vertical, 32)
                case .failed(let message):
                    VStack(spacing: 12) {
                        banner(message)
                        if let onCancel = model.onCancel {
                            Button("Close", action: onCancel)
                                .font(theme.font(14, weight: .medium))
                                .foregroundColor(theme.colors.primary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                case .ready:
                    form
                }
            }
            .padding(20)
        }
        .background(theme.colors.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.session?.brand?.name ?? model.session?.workspaceName ?? "Checkout")
                    .font(theme.font(14, weight: .medium))
                    .foregroundColor(theme.colors.foreground)
                    .lineLimit(1)
                if let total = model.session?.totalFormatted, !total.isEmpty {
                    Text(total)
                        .font(theme.font(24, weight: .semibold))
                        .foregroundColor(theme.colors.foreground)
                }
            }
            Spacer()
            if model.session?.sandbox == true {
                Text("Test mode")
                    .font(theme.font(11, weight: .medium))
                    .foregroundColor(theme.colors.mutedForeground)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(theme.colors.secondary)
                    .clipShape(Capsule())
            }
        }
    }

    private func banner(_ message: String) -> some View {
        Text(message)
            .font(theme.font(14))
            .lineSpacing(6)
            .foregroundColor(theme.colors.destructive)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.colors.destructive.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .circular))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .circular).strokeBorder(theme.colors.destructive.opacity(0.3), lineWidth: 1))
            .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var form: some View {
        if let session = model.session {
            if session.vault == nil {
                banner("This checkout is not set up for in-app payments yet.")
            }

            ContactFields(customer: $model.customer, requirePhone: session.requirePhone, errors: model.displayedErrors,
                          onFieldFocus: { model.fieldFocused($0) }, onFieldBlur: { model.fieldBlurred($0) })

            VStack(alignment: .leading, spacing: 8) {
                SectionHeading(text: "Payment method").padding(.bottom, -8)
                PaymentMethodPicker(
                    options: model.options,
                    selected: Binding(get: { model.method }, set: { model.selectMethod($0) }),
                    savedMethod: model.selectedSaved ?? model.savedMethods.first
                ) { kind in
                    panel(kind, session: session)
                }
            }

            if !session.customFields.isEmpty { customFields(session.customFields) }

            if let message = model.errorMessage {
                banner(message)
            }

            payButton(session)
        }
    }

    private var billing: some View {
        PaysioBillingAddress(customer: $model.customer, address: $model.billingAddress,
                             savedAddresses: model.savedAddresses, errors: model.displayedErrors,
                             apiBase: model.client.apiBase, disableSuggestions: model.disableAddressSuggestions,
                             onFieldFocus: { model.fieldFocused($0) }, onFieldBlur: { model.fieldBlurred($0) })
    }

    /// RN: card panel = card fields + billing; bank panel = bank fields + billing + ACH
    /// consent row; children 20 apart.
    @ViewBuilder
    private func panel(_ kind: PaysioMethodKind, session: PaysioSession) -> some View {
        switch kind {
        case .card:
            VStack(alignment: .leading, spacing: 20) {
                if let controller = model.cardController {
                    PaysioCardFields(controller: controller)
                }
                billing
            }
        case .bank:
            VStack(alignment: .leading, spacing: 20) {
                if let controller = model.bankController {
                    PaysioBankFields(controller: controller)
                }
                billing
                PaysioConsentRow(checked: $model.achAuthorized, text: session.achAuthorizationText,
                                 accessibilityLabel: "Authorize the bank debit")
            }
        case .saved:
            VStack(alignment: .leading, spacing: 12) {
                SavedMethodSelect(methods: model.savedMethods, selected: $model.selectedSaved)
                if model.selectedSaved?.requiresCvc == true {
                    StackedTextField("CVC", text: $model.savedCvc, corners: .all, keyboard: .numberPad)
                        .frame(maxWidth: 120)
                }
            }
        }
    }

    /// RN `PaysioCustomFields`: a 12 pt muted label over each box ("(optional)" when
    /// not required), selects open a bottom sheet, checkboxes are an 18 pt box row.
    private func customFields(_ fields: [PaysioCustomField]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(text: "Additional information").padding(.bottom, -4)
            ForEach(fields.filter { $0.type != "checkbox" }) { field in
                let binding = Binding(get: { model.customValues[field.id] ?? "" },
                                      set: { model.customValues[field.id] = $0 })
                VStack(alignment: .leading, spacing: 6) {
                    Text(field.label + (field.required ? "" : " (optional)"))
                        .font(theme.font(12))
                        .foregroundColor(theme.colors.mutedForeground)
                    if field.type == "select" {
                        StackedTrigger(value: binding.wrappedValue, placeholder: field.placeholder ?? "Select",
                                       corners: .all, accessibilityLabel: field.label) {
                            openSelect = field.id
                        }
                    } else {
                        StackedTextField(field.placeholder ?? field.label, text: binding, corners: .all,
                                         keyboard: field.type == "number" ? .decimalPad : .default,
                                         capitalization: .sentences)
                    }
                }
            }
            ForEach(fields.filter { $0.type == "checkbox" }) { field in
                let checked = ["true", "yes"].contains(model.customValues[field.id] ?? "")
                Button {
                    model.customValues[field.id] = checked ? "" : "true"
                } label: {
                    HStack(spacing: 10) {
                        PaysioCheckBox(checked: checked)
                        Text(field.label + (field.required ? "" : " (optional)"))
                            .font(theme.font(14))
                            .foregroundColor(theme.colors.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(field.label)
                .accessibilityValue(checked ? "Checked" : "Unchecked")
            }
        }
        .sheet(item: Binding(get: { openSelect.map(SelectID.init) }, set: { openSelect = $0?.id })) { select in
            if let field = fields.first(where: { $0.id == select.id }) {
                PaysioBottomSheet(title: field.label, onClose: { openSelect = nil }) { _ in
                    ForEach(field.options, id: \.self) { option in
                        PaysioSheetRow(selected: option == model.customValues[field.id], label: option) {
                            openSelect = nil
                            model.customValues[field.id] = option
                        }
                    }
                }
                .paysioSheetHost(theme: theme, components: sheetComponents)
            }
        }
    }

    private struct SelectID: Identifiable {
        let id: String
    }

    /// RN `PayButton`: 48 high, radius 12, primary, white 16 medium; opacity 0.5 and
    /// disabled until `canPay`; spinner while paying.
    private func payButton(_ session: PaysioSession) -> some View {
        let enabled = model.canPay && !model.isPaying
        return Button {
            Task { await model.pay() }
        } label: {
            HStack(spacing: 8) {
                if model.isPaying { ProgressView().tint(.white) }
                Text(buttonTitle(session))
                    .font(theme.font(16, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(theme.colors.primary)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .circular))
            .opacity(enabled || model.isPaying ? 1 : 0.5)
        }
        .disabled(!enabled)
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(buttonTitle(session))
    }

    private func buttonTitle(_ session: PaysioSession) -> String {
        switch model.step {
        case .threeDs: return "Verifying your card"
        case .aliasing, .charging, .validating: return "Processing"
        default: return session.totalFormatted.isEmpty ? "Pay" : "Pay \(session.totalFormatted)"
        }
    }
}
