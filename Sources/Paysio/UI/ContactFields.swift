import SwiftUI

/// Email and (when the workspace requires it, or `showPhone`) phone, stacked like the
/// hosted page's contact block (RN `ContactFields.tsx` with `hideName`: the sheet
/// collects the name inside the billing address). No leading icons, as in RN.
public struct ContactFields: View {
    @Binding public var customer: PaysioCustomer
    public let requirePhone: Bool
    public let showPhone: Bool
    public let errors: [PaysioField: String]
    public var showHeading: Bool
    public var onFieldFocus: ((String) -> Void)?
    public var onFieldBlur: ((String) -> Void)?

    @Environment(\.paysioTheme) private var theme

    public init(customer: Binding<PaysioCustomer>, requirePhone: Bool, showPhone: Bool = false,
                errors: [PaysioField: String] = [:], showHeading: Bool = true,
                onFieldFocus: ((String) -> Void)? = nil, onFieldBlur: ((String) -> Void)? = nil) {
        self.onFieldBlur = onFieldBlur
        self._customer = customer
        self.requirePhone = requirePhone
        self.showPhone = showPhone
        self.errors = errors
        self.showHeading = showHeading
        self.onFieldFocus = onFieldFocus
    }

    private var phoneVisible: Bool { requirePhone || showPhone }

    private var phone: Binding<String> {
        Binding(get: { customer.phone ?? "" }, set: { customer.phone = $0.isEmpty ? nil : $0 })
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeading { SectionHeading(text: "Contact") }
            VStack(spacing: -1) {
                StackedTextField("Email", text: $customer.email, corners: phoneVisible ? .top : .all,
                                 keyboard: .emailAddress, contentType: .emailAddress,
                                 invalid: errors[.email] != nil, submitLabel: phoneVisible ? .next : .done,
                                 onFocusChange: { $0 ? onFieldFocus?("email") : onFieldBlur?("email") })
                if phoneVisible {
                    StackedTextField(requirePhone ? "Phone" : "Phone (optional)", text: phone, corners: .bottom,
                                     keyboard: .phonePad, contentType: .telephoneNumber,
                                     invalid: errors[.phone] != nil, submitLabel: .done,
                                     onFocusChange: { $0 ? onFieldFocus?("phone") : onFieldBlur?("phone") })
                }
            }
            FieldErrorText(message: errors[.email] ?? errors[.phone])
        }
    }
}
