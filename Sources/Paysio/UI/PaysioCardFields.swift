import SwiftUI
import UIKit
import VGSCollectSDK

/// Live state of the three card fields. Mirrors `PaysioCardFieldsState` in RN.
public struct PaysioCardFieldsState: Sendable, Equatable {
    public var number = PaysioFieldState()
    public var expiry = PaysioFieldState()
    public var cvc = PaysioFieldState()
    public var brand: String?
    public var bin: String?
    public var last4: String?
    public var valid: Bool { number.valid && expiry.valid && cvc.valid }

    public init() {}
}

/// Owns the `VGSCollect` instance and the three field configurations, tracks state,
/// and turns the fields into a `PaysioCardAlias` on demand.
///
/// VGS API relied on (vgs-collect-ios 1.20):
/// - `VGSConfiguration(collector:fieldName:)` with `type`, `isRequiredValidOnly`,
///   `keyboardType`, `textContentType`, `validationRules`, `formatPattern`, `divider`
///   (`Core/VGSConfiguration.swift`).
/// - `VGSExpDateConfiguration` with `inputSource` (`Core/VGSExpDateConfiguration.swift`).
/// - `VGSValidationRuleSet(rules:)`, `VGSValidationRuleLengthMatch(lengths:error:)`.
/// - `VGSCardState.bin / last4 / cardBrand`, `VGSTextFieldState.isValid / isEmpty /
///   isDirty / validationErrors` (`UIElements/Text Field/State/State.swift`).
/// - `VGSCollect.unsubscribeAllTextFields()`.
@MainActor
public final class PaysioCardFieldsController: ObservableObject {
    @Published public private(set) var state = PaysioCardFieldsState()

    public let vault: PaysioVault
    public let sandbox: Bool
    public var onEvent: PaysioEventHandler?

    private var numberState: VGSCardState?

    /// - Parameters:
    ///   - vaultConfig: from `session.vault`.
    ///   - sandbox: relaxes the Luhn check; the VGS 3DS sandbox cards are not Luhn-valid.
    public init(vaultConfig: PaysioVaultConfig, sandbox: Bool, onEvent: PaysioEventHandler? = nil) {
        self.vault = PaysioVault(config: vaultConfig)
        self.sandbox = sandbox
        self.onEvent = onEvent
    }

    // MARK: Configurations (stable instances; VGS re-applies them on update)

    public lazy var numberConfiguration: VGSConfiguration = {
        let c = VGSConfiguration(collector: vault.collector, fieldName: PaysioVault.FieldName.cardNumber)
        c.type = .cardNumber
        c.isRequiredValidOnly = true
        c.keyboardType = .numberPad
        c.textContentType = .creditCardNumber
        if sandbox {
            // Length-only rule in sandbox (same idea as `relaxNumberValidation` on the web).
            c.validationRules = VGSValidationRuleSet(rules: [
                VGSValidationRuleLengthMatch(lengths: [13, 14, 15, 16, 19], error: VGSValidationErrorType.cardNumber.rawValue),
            ])
        }
        return c
    }()

    public lazy var expiryConfiguration: VGSExpDateConfiguration = {
        let c = VGSExpDateConfiguration(collector: vault.collector, fieldName: PaysioVault.FieldName.cardExpiry)
        c.inputSource = .keyboard
        c.isRequiredValidOnly = true
        c.keyboardType = .numberPad
        // Output "MM/YY" (CONTRACT.md section 2).
        c.formatPattern = "##/##"
        c.divider = "/"
        return c
    }()

    public lazy var cvcConfiguration: VGSConfiguration = {
        let c = VGSConfiguration(collector: vault.collector, fieldName: PaysioVault.FieldName.cardCvc)
        c.type = .cvc
        c.isRequiredValidOnly = true
        c.keyboardType = .numberPad
        return c
    }()

    // MARK: State updates from the fields

    func update(number s: VGSCardState) {
        numberState = s
        state.number.valid = s.isValid
        state.number.empty = s.isEmpty
        state.number.dirty = s.isDirty || !s.isEmpty
        state.number.error = s.isValid ? nil : (s.isEmpty ? "Enter your card number." : "Check your card number.")
        let brand = PaysioValidation.normalizeBrand(s.cardBrand.stringValue)
        state.brand = s.isEmpty ? nil : brand
        state.bin = s.bin.isEmpty ? nil : s.bin
        state.last4 = s.last4.isEmpty ? nil : s.last4
    }

    func update(expiry s: VGSTextFieldState) {
        state.expiry.valid = s.isValid
        state.expiry.empty = s.isEmpty
        state.expiry.dirty = s.isDirty || !s.isEmpty
        state.expiry.error = s.isValid ? nil : (s.isEmpty ? "Enter the expiry date." : "Check the expiry date.")
    }

    func update(cvc s: VGSTextFieldState) {
        state.cvc.valid = s.isValid
        state.cvc.empty = s.isEmpty
        state.cvc.dirty = s.isDirty || !s.isEmpty
        state.cvc.error = s.isValid ? nil : (s.isEmpty ? "Enter the security code." : "Check the security code.")
    }

    func setFocus(_ field: PaysioField, _ focused: Bool) {
        switch field {
        case .number: state.number.focused = focused; if !focused { state.number.dirty = true }
        case .expiry: state.expiry.focused = focused; if !focused { state.expiry.dirty = true }
        case .cvc: state.cvc.focused = focused; if !focused { state.cvc.dirty = true }
        default: break
        }
        if focused { onEvent?(.fieldFocus(field: field.rawValue)) }
    }

    /// Marks every field dirty so invalid borders show after a failed Pay tap.
    public func touchAll() {
        state.number.dirty = true
        state.expiry.dirty = true
        state.cvc.dirty = true
    }

    /// Tokenizes with VGS and returns the aliases. Throws `invalid_fields` first if
    /// any field is invalid.
    public func tokenize() async throws -> PaysioCardAlias {
        guard state.valid else {
            touchAll()
            var errors: [PaysioField: String] = [:]
            if !state.number.valid { errors[.number] = state.number.error ?? "Check your card number." }
            if !state.expiry.valid { errors[.expiry] = state.expiry.error ?? "Check the expiry date." }
            if !state.cvc.valid { errors[.cvc] = state.cvc.error ?? "Check the security code." }
            throw PaysioError(code: .invalidFields, message: "Check your card details.", fieldErrors: errors)
        }
        return try await vault.tokenizeCard(numberState: numberState)
    }

    /// Call when the fields leave the screen so a re-mounted panel does not leave
    /// stale (empty) fields registered on the collector.
    public func reset() {
        vault.collector.unsubscribeAllTextFields()
        numberState = nil
        state = PaysioCardFieldsState()
    }
}

/// The stacked card fields (MOBILE_SDK_PLAN.md section 8.2): number on top, expiry and
/// CVC below, 1 px overlaps, focus ring, invalid border after blur, brand mark on the
/// right of the number, lock in the CVC box. Wraps VGS's SwiftUI representables:
/// `VGSCardTextFieldRepresentable`, `VGSExpDateTextFieldRepresentable`,
/// `VGSCVCTextFieldRepresentable` (modifiers per the VGS SwiftUI Components page:
/// `.placeholder`, `.font(UIFont)`, `.foregroundColor(UIColor)`, `.textFieldPadding`,
/// `.cardIconSize`, `.setSecureTextEntry`, `.onEditingEvent`, `.onStateChange`).
@MainActor
public struct PaysioCardFields: View {
    @ObservedObject public var controller: PaysioCardFieldsController
    public var showHeading: Bool

    // Qualified: VGSCollectSDK also declares an `Environment` type.
    @SwiftUI.Environment(\.paysioTheme) private var theme
    @SwiftUI.Environment(\.paysioKeyboardReveal) private var reveal

    public init(controller: PaysioCardFieldsController, showHeading: Bool = true) {
        self.controller = controller
        self.showHeading = showHeading
    }

    public var body: some View {
        let s = controller.state
        VStack(alignment: .leading, spacing: 0) {
            if showHeading { SectionHeading(text: "Card information") }

            VStack(spacing: -1) {
                // One continuous group: radius on the outer corners only (top on the
                // number, bottom-left on expiry, bottom-right on CVC), shared 1 pt seams.
                StackedFieldBox(corners: .top, focused: s.number.focused, invalid: s.number.showsInvalid) {
                    ZStack(alignment: .trailing) {
                        numberField
                        brandMark
                            .offset(y: 1)
                            .padding(.trailing, 10)
                            .allowsHitTesting(false)
                    }
                }
                HStack(spacing: -1) {
                    StackedFieldBox(corners: .bottomLeft, focused: s.expiry.focused, invalid: s.expiry.showsInvalid) {
                        expiryField
                    }
                    StackedFieldBox(corners: .bottomRight, focused: s.cvc.focused, invalid: s.cvc.showsInvalid) {
                        ZStack(alignment: .trailing) {
                            cvcField
                            PaysioIcon(.lockSolid, size: 16, color: theme.colors.mutedForeground.opacity(0.7))
                                .padding(.trailing, 10)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .zIndex(s.expiry.focused || s.cvc.focused ? 40 : 0)
            }

            FieldErrorText(message: firstError(s))
        }
        .onDisappear { controller.reset() }
    }

    private func firstError(_ s: PaysioCardFieldsState) -> String? {
        if s.number.showsInvalid { return s.number.error }
        if s.expiry.showsInvalid { return s.expiry.error }
        if s.cvc.showsInvalid { return s.cvc.error }
        return nil
    }

    /// RN: `<CardBrand brand bin size={30} animate fallback={<AcceptedBrandStack size={24} />} />`.
    private var brandMark: some View {
        CardBrandView(brand: controller.state.brand, bin: controller.state.bin, size: 30,
                      fallbackColor: theme.colors.mutedForeground) {
            AcceptedBrandStack(size: 24)
        }
    }

    private func editing<S>(_ field: PaysioField, _ event: VGSTextFieldEditingEvent<S>) {
        switch event {
        case .didBegin:
            controller.setFocus(field, true)
            reveal?.reveal(.firstResponder)
        case .didEnd: controller.setFocus(field, false)
        case .didChange: break
        }
    }

    private var placeholderAttributes: [NSAttributedString.Key: Any] {
        [.foregroundColor: theme.uiColor(theme.colors.mutedForeground).withAlphaComponent(0.9),
         .font: theme.uiFont(16)]
    }

    private var numberField: some View {
        VGSCardTextFieldRepresentable(configuration: controller.numberConfiguration)
            .attributedPlaceholder(NSAttributedString(string: "0000 0000 0000 0000", attributes: placeholderAttributes))
            .font(theme.uiFont(16))
            .foregroundColor(theme.uiColor(theme.colors.foreground))
            // VGSTextField draws a 1 pt lightGray border with radius 4 by default
            // (VGSTextField.swift mainStyle); only our StackedFieldBox may draw.
            .backgroundColor(.clear)
            .border(color: .clear, lineWidth: 0)
            .cornerRadius(0)
            .textFieldPadding(UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 92))
            // We draw our own brand mark; shrink VGS's icon away.
            .cardIconSize(CGSize(width: 0, height: 0))
            .textFieldAccessibilityLabel("Card number")
            .onEditingEvent { editing(.number, $0) }
            .onStateChange { newState in controller.update(number: newState) }
            .frame(height: StackedMetrics.height - 2)
    }

    private var expiryField: some View {
        VGSExpDateTextFieldRepresentable(configuration: controller.expiryConfiguration)
            .attributedPlaceholder(NSAttributedString(string: "MM / YY", attributes: placeholderAttributes))
            .font(theme.uiFont(16))
            .foregroundColor(theme.uiColor(theme.colors.foreground))
            .backgroundColor(.clear)
            .border(color: .clear, lineWidth: 0)
            .cornerRadius(0)
            .textFieldPadding(UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12))
            .textFieldAccessibilityLabel("Expiry date")
            .onEditingEvent { editing(.expiry, $0) }
            .onStateChange { newState in controller.update(expiry: newState) }
            .frame(height: StackedMetrics.height - 2)
    }

    private var cvcField: some View {
        VGSCVCTextFieldRepresentable(configuration: controller.cvcConfiguration)
            .attributedPlaceholder(NSAttributedString(string: "CVC", attributes: placeholderAttributes))
            .font(theme.uiFont(16))
            .foregroundColor(theme.uiColor(theme.colors.foreground))
            .backgroundColor(.clear)
            .border(color: .clear, lineWidth: 0)
            .cornerRadius(0)
            .textFieldPadding(UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 34))
            // Not masked: the hosted checkout shows the CVC digits, and the value never leaves the VGS field.
            .setSecureTextEntry(false)
            .cvcIconSize(CGSize(width: 0, height: 0))
            .textFieldAccessibilityLabel("Security code")
            .onEditingEvent { editing(.cvc, $0) }
            .onStateChange { newState in controller.update(cvc: newState) }
            .frame(height: StackedMetrics.height - 2)
    }
}
