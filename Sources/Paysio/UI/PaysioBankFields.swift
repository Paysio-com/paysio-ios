import SwiftUI
import UIKit
import VGSCollectSDK

public struct PaysioBankFieldsState: Sendable, Equatable {
    public var routing = PaysioFieldState()
    public var account = PaysioFieldState()
    public var accountType: PaysioBankAccountType = .checking
    public var holderType: PaysioBankHolderType = .personal
    public var valid: Bool { routing.valid && account.valid }

    public init() {}
}

/// Owns a separate `VGSCollect` for the bank account field (so a card submit and a
/// bank submit never mix), validates the routing number natively, and produces a
/// `PaysioBankAlias`.
@MainActor
public final class PaysioBankFieldsController: ObservableObject {
    @Published public private(set) var state = PaysioBankFieldsState()
    @Published public var routingNumber: String = "" {
        didSet { validateRouting() }
    }

    public let vault: PaysioVault
    public var onEvent: PaysioEventHandler?

    public init(vaultConfig: PaysioVaultConfig, onEvent: PaysioEventHandler? = nil) {
        self.vault = PaysioVault(config: vaultConfig)
        self.onEvent = onEvent
    }

    /// `bank_account_number`: a plain VGS text field (type `.none`) with a digits-only
    /// pattern of 4 to 17 characters. The route aliases it as GENERIC_T_FOUR.
    public lazy var accountConfiguration: VGSConfiguration = {
        let c = VGSConfiguration(collector: vault.collector, fieldName: PaysioVault.FieldName.bankAccountNumber)
        c.type = .none
        c.isRequiredValidOnly = true
        c.keyboardType = .numberPad
        c.maxInputLength = 17
        c.validationRules = VGSValidationRuleSet(rules: [
            VGSValidationRulePattern(pattern: "^[0-9]{4,17}$", error: VGSValidationErrorType.pattern.rawValue),
        ])
        return c
    }()

    public func setAccountType(_ type: PaysioBankAccountType) { state.accountType = type }
    public func setHolderType(_ type: PaysioBankHolderType) { state.holderType = type }

    func cycleAccountType() { state.accountType = state.accountType == .checking ? .savings : .checking }
    func cycleHolderType() { state.holderType = state.holderType == .personal ? .business : .personal }

    private func validateRouting() {
        let digits = String(routingNumber.filter(\.isNumber).prefix(9))
        if digits != routingNumber { routingNumber = digits; return }
        state.routing.empty = digits.isEmpty
        state.routing.valid = PaysioValidation.isRoutingNumber(digits)
        state.routing.dirty = state.routing.dirty || !digits.isEmpty
        state.routing.error = state.routing.valid ? nil : (digits.isEmpty ? "Enter the routing number." : "Check the routing number.")
    }

    func update(account s: VGSTextFieldState) {
        state.account.valid = s.isValid
        state.account.empty = s.isEmpty
        state.account.dirty = s.isDirty || !s.isEmpty
        state.account.error = s.isValid ? nil : (s.isEmpty ? "Enter the account number." : "Check the account number.")
    }

    func setFocus(_ field: PaysioField, _ focused: Bool) {
        switch field {
        case .routing: state.routing.focused = focused; if !focused { state.routing.dirty = true }
        case .account: state.account.focused = focused; if !focused { state.account.dirty = true }
        default: break
        }
        if focused { onEvent?(.fieldFocus(field: field.rawValue)) }
    }

    public func touchAll() {
        state.routing.dirty = true
        state.account.dirty = true
    }

    public func tokenize() async throws -> PaysioBankAlias {
        guard state.valid else {
            touchAll()
            var errors: [PaysioField: String] = [:]
            if !state.routing.valid { errors[.routing] = state.routing.error ?? "Check the routing number." }
            if !state.account.valid { errors[.account] = state.account.error ?? "Check the account number." }
            throw PaysioError(code: .invalidFields, message: "Check your bank details.", fieldErrors: errors)
        }
        return try await vault.tokenizeBank(routingNumber: routingNumber, accountType: state.accountType,
                                            holderType: state.holderType, last4Hint: nil)
    }

    public func reset() {
        vault.collector.unsubscribeAllTextFields()
        state = PaysioBankFieldsState()
    }
}

/// Bank details (RN `BankFields.tsx`, web VaultBankFields): routing number (native,
/// 9 digits, ABA checksum) with the inline Personal / Business chip, account number
/// (VGS) with the Checking / Savings chip. One stacked group, radius 8 on the top of
/// the routing box and the bottom of the account box, one shared 1 pt seam. Optional
/// ACH text below (the drop-in sheet shows a consent row instead, see
/// `PaysioConsentRow`).
@MainActor
public struct PaysioBankFields: View {
    @ObservedObject public var controller: PaysioBankFieldsController
    public let achAuthorizationText: String?
    public var showHeading: Bool
    /// Hide the account-type / holder-type chips (AptPay ignores both).
    public var hideToggles: Bool

    // Qualified: VGSCollectSDK also declares an `Environment` type.
    @SwiftUI.Environment(\.paysioTheme) private var theme
    @SwiftUI.Environment(\.paysioKeyboardReveal) private var reveal

    public init(controller: PaysioBankFieldsController, achAuthorizationText: String? = nil, showHeading: Bool = true,
                hideToggles: Bool = false) {
        self.controller = controller
        self.achAuthorizationText = achAuthorizationText
        self.showHeading = showHeading
        self.hideToggles = hideToggles
    }

    public var body: some View {
        let s = controller.state
        VStack(alignment: .leading, spacing: 0) {
            if showHeading { SectionHeading(text: "Bank details") }
            VStack(spacing: -1) {
                StackedTextField(
                    "Routing number",
                    text: $controller.routingNumber,
                    corners: .top,
                    keyboard: .numberPad,
                    invalid: s.routing.showsInvalid,
                    trailing: hideToggles ? nil : AnyView(CycleChip(
                        label: s.holderType.label,
                        nextLabel: s.holderType == .personal ? PaysioBankHolderType.business.label : PaysioBankHolderType.personal.label
                    ) { controller.cycleHolderType() }),
                    trailingInset: 6,
                    paddingRight: hideToggles ? 12 : 92,
                    onFocusChange: { controller.setFocus(.routing, $0) }
                )
                StackedFieldBox(corners: .bottom, focused: s.account.focused, invalid: s.account.showsInvalid) {
                    ZStack(alignment: .trailing) {
                        accountField
                        if !hideToggles {
                            CycleChip(
                                label: s.accountType.label,
                                nextLabel: s.accountType == .checking ? PaysioBankAccountType.savings.label : PaysioBankAccountType.checking.label
                            ) { controller.cycleAccountType() }
                                .padding(.trailing, 6)
                        }
                    }
                }
            }
            FieldErrorText(message: s.routing.showsInvalid ? s.routing.error : (s.account.showsInvalid ? s.account.error : nil))
            if let achAuthorizationText, !achAuthorizationText.isEmpty {
                Text(achAuthorizationText)
                    .font(theme.font(12))
                    .lineSpacing(2)
                    .foregroundColor(theme.colors.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .onDisappear { controller.reset() }
    }

    private var accountField: some View {
        let placeholderAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.uiColor(theme.colors.mutedForeground).withAlphaComponent(0.9),
            .font: theme.uiFont(16),
        ]
        return VGSTextFieldRepresentable(configuration: controller.accountConfiguration)
            .attributedPlaceholder(NSAttributedString(string: "Account number", attributes: placeholderAttributes))
            .font(theme.uiFont(16))
            .foregroundColor(theme.uiColor(theme.colors.foreground))
            // No VGS border / radius (default 1 pt lightGray, radius 4): only our box draws.
            .backgroundColor(.clear)
            .border(color: .clear, lineWidth: 0)
            .cornerRadius(0)
            .textFieldPadding(UIEdgeInsets(top: 0, left: 12, bottom: 0, right: hideToggles ? 12 : 92))
            .textFieldAccessibilityLabel("Account number")
            .onEditingEvent { event in
                switch event {
                case .didBegin:
                    controller.setFocus(.account, true)
                    reveal?.reveal(.firstResponder)
                case .didEnd: controller.setFocus(.account, false)
                case .didChange: break
                }
            }
            .onStateChange { newState in controller.update(account: newState) }
            .frame(height: StackedMetrics.height - 2)
    }
}
