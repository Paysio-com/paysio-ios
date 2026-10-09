import SwiftUI

/// Billing address (RN `ui/BillingAddress.tsx`, web BillingAddressFields +
/// AddressFields variant="stacked").
///
/// Saved addresses: a select trigger (radius 12, `secondary`, padding 12 / 10; name
/// 14 medium, address 12 muted, one line each; chevron 16) opening a bottom sheet whose
/// list ends with plus + "Enter a new address" in primary.
///
/// New address: First (user icon) | Last, radius 8 top; Country select full width
/// (flag + name on one line, one chevron, opens a searchable bottom sheet); Address,
/// radius 8 bottom until the next row appears; then City | State (US: searchable sheet
/// of USPS codes) | ZIP revealed over 300 ms, radius 8 bottom. City / State / ZIP stay
/// mounted while collapsed so AutoFill still reaches them.
///
/// Street suggestions (Google Places through Paysio, no key in the app) show under the
/// Address field while it has focus and the shopper typed since the last pick. They need
/// an API base: `apiBase` here, or the one the drop-in sheet passes. `disableSuggestions`
/// turns them off.
public struct PaysioBillingAddress: View {
    @Binding public var customer: PaysioCustomer
    @Binding public var address: PaysioAddress
    public let savedAddresses: [PaysioSavedAddress]
    public let errors: [PaysioField: String]
    public var showHeading: Bool
    public var heading: String
    public var hideName: Bool
    public var alwaysExpanded: Bool
    public var allowedCountries: [String]?
    public var apiBase: URL?
    public var disableSuggestions: Bool
    public var onFieldFocus: ((String) -> Void)?
    /// Called when a field loses focus (field names match `PaysioField` raw values).
    public var onFieldBlur: ((String) -> Void)?

    @Environment(\.paysioTheme) private var theme
    @Environment(\.paysioSheetComponents) private var sheetComponents
    @Environment(\.paysioKeyboardReveal) private var reveal
    @State private var selectedSavedId: String?
    @State private var enteringNew = false
    @State private var sheet: SheetKind?
    @State private var focus: BillingField?
    @State private var streetActive = false
    @State private var typedSincePick = false
    @State private var blurToken = 0
    @StateObject private var suggestions = AddressSuggestionsModel()

    private static let streetAnchor = "paysio.billing.street"

    public init(customer: Binding<PaysioCustomer>, address: Binding<PaysioAddress>,
                savedAddresses: [PaysioSavedAddress] = [], errors: [PaysioField: String] = [:],
                showHeading: Bool = true, heading: String = "Billing address", hideName: Bool = false,
                alwaysExpanded: Bool = false, allowedCountries: [String]? = nil,
                apiBase: URL? = nil, disableSuggestions: Bool = false,
                onFieldFocus: ((String) -> Void)? = nil, onFieldBlur: ((String) -> Void)? = nil) {
        self.onFieldBlur = onFieldBlur
        self._customer = customer
        self._address = address
        self.savedAddresses = savedAddresses
        self.errors = errors
        self.showHeading = showHeading
        self.heading = heading
        self.hideName = hideName
        self.alwaysExpanded = alwaysExpanded
        self.allowedCountries = allowedCountries
        self.apiBase = apiBase
        self.disableSuggestions = disableSuggestions
        self.onFieldFocus = onFieldFocus
    }

    enum SheetKind: String, Identifiable {
        case saved, country, state
        var id: String { rawValue }
    }

    enum BillingField: String {
        case firstName, lastName, address1, city, state, postalCode
    }

    private var usingSaved: Bool { !savedAddresses.isEmpty && !enteringNew }
    private var selectedSaved: PaysioSavedAddress? {
        savedAddresses.first { $0.id == selectedSavedId } ?? savedAddresses.first
    }
    private var suggestBase: URL? { disableSuggestions ? nil : apiBase }
    private var country: String { address.country.trimmingCharacters(in: .whitespaces).uppercased() }
    private var isUS: Bool { country == "US" }
    private var normalizedUSState: String? { isUS ? PaysioCountries.toUSStateCode(address.state) : nil }
    private var expanded: Bool {
        alwaysExpanded || !address.address1.isEmpty || !address.city.isEmpty || !address.state.isEmpty
            || !address.postalCode.isEmpty
    }
    private var countries: [PaysioCountries.Country] {
        guard let allowed = allowedCountries, !allowed.isEmpty else { return PaysioCountries.list }
        let set = Set(allowed.map { $0.uppercased() })
        return PaysioCountries.list.filter { set.contains($0.code) }
    }
    private var suggestionsEnabled: Bool { suggestBase != nil && streetActive && typedSincePick }
    private var listOpen: Bool { suggestionsEnabled && !suggestions.suggestions.isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showHeading { SectionHeading(text: heading) }
            if usingSaved {
                savedTrigger
            } else {
                stack
                if !savedAddresses.isEmpty {
                    Button("Use existing address") {
                        withAnimation(.easeOut(duration: 0.2)) { enteringNew = false }
                        applySaved()
                    }
                    .font(theme.font(12))
                    .foregroundColor(theme.colors.primary)
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            if usingSaved { applySaved() }
            normalizeUSState()
            refreshSuggestions()
        }
        .onChange(of: address.state) { _ in normalizeUSState() }
        .onChange(of: address.country) { _ in normalizeUSState(); refreshSuggestions() }
        .onChange(of: address.address1) { _ in refreshSuggestions() }
        .onChange(of: suggestionsEnabled) { _ in refreshSuggestions() }
        .onChange(of: listOpen) { open in if open { reveal?.reveal(.anchor(Self.streetAnchor)) } }
        .onChange(of: suggestions.suggestions.count) { _ in if listOpen { reveal?.reveal(.anchor(Self.streetAnchor)) } }
        .sheet(item: $sheet) { kind in
            sheetContent(kind).paysioSheetHost(theme: theme, components: sheetComponents)
        }
    }

    // MARK: Saved trigger

    private var savedTrigger: some View {
        Button { sheet = .saved } label: {
            HStack(spacing: 8) {
                savedLines(selectedSaved)
                PaysioIcon(.chevronDown, size: 16, color: theme.colors.mutedForeground)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(theme.colors.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .circular))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1).padding(.horizontal, 12)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1).padding(.horizontal, 12)
            }
            .shadow(color: Color(hex: 0x1A1A1A, opacity: 0.06), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Billing address: \(selectedSaved?.name ?? "No name"), \(selectedSaved.map { Self.format($0.address) } ?? "")")
    }

    private func savedLines(_ saved: PaysioSavedAddress?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(saved.map { $0.name.isEmpty ? "No name" : $0.name } ?? "Choose an address")
                .font(theme.font(14, weight: .medium))
                .foregroundColor(theme.colors.foreground)
                .lineLimit(1)
            Text(saved.map { Self.format($0.address) } ?? "")
                .font(theme.font(12))
                .foregroundColor(theme.colors.mutedForeground)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applySaved() {
        guard let saved = selectedSaved else { return }
        address = saved.address
    }

    /// RN `formatSavedAddress`.
    static func format(_ a: PaysioAddress) -> String {
        let line = [a.address1, a.address2 ?? ""].filter { !$0.trimmed.isEmpty }.joined(separator: ", ")
        let cityState = [a.city, a.state].filter { !$0.trimmed.isEmpty }.joined(separator: " ")
        let second = [cityState, a.postalCode].filter { !$0.isEmpty }.joined(separator: " ")
        return [line, second, a.country].filter { !$0.trimmed.isEmpty }.joined(separator: ", ")
    }

    // MARK: Stacked new-address form

    private func focusBinding(_ field: BillingField) -> Binding<Bool> {
        Binding(get: { focus == field }, set: { on in
            if on { focus = field } else if focus == field { focus = nil }
        })
    }

    private func onFocus(_ field: BillingField, _ on: Bool) {
        if on { onFieldFocus?(field.rawValue) } else { onFieldBlur?(field.rawValue) }
    }

    private var street: Binding<String> {
        Binding(get: { address.address1 }, set: { value in
            if value != address.address1 { typedSincePick = true }
            address.address1 = value
        })
    }

    private var stack: some View {
        VStack(spacing: 0) {
            if !hideName {
                HStack(spacing: -1) {
                    StackedTextField("First Name", text: $customer.firstName, corners: .topLeft,
                                     contentType: .givenName, capitalization: .words,
                                     invalid: errors[.firstName] != nil, leadingIcon: .userSolid,
                                     isFocused: focusBinding(.firstName),
                                     onFocusChange: { onFocus(.firstName, $0) },
                                     onSubmit: { focus = .lastName })
                    StackedTextField("Last Name", text: $customer.lastName, corners: .topRight,
                                     contentType: .familyName, capitalization: .words,
                                     invalid: errors[.lastName] != nil,
                                     isFocused: focusBinding(.lastName),
                                     onFocusChange: { onFocus(.lastName, $0) },
                                     onSubmit: { focus = nil; sheet = .country })
                }
                .zIndex(focus == .firstName || focus == .lastName ? 40 : 10)
            }

            countryRow
                .padding(.top, hideName ? 0 : -1)
                .zIndex(30)

            // The street block carries the street field's stacking order and the
            // suggestions list, and is the reveal target while the list is open.
            VStack(spacing: 0) {
                StackedTextField("Address", text: street, corners: expanded ? .none : .bottom,
                                 contentType: .streetAddressLine1, capitalization: .words,
                                 invalid: errors[.address1] != nil,
                                 leadingIcon: suggestBase != nil ? .mapPinSolid : nil,
                                 isFocused: focusBinding(.address1),
                                 onFocusChange: { on in
                                     onFocus(.address1, on)
                                     blurToken += 1
                                     if on {
                                         streetActive = true
                                     } else {
                                         let token = blurToken
                                         // Hide after a beat so a tap on a row lands first.
                                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                             if token == blurToken { streetActive = false }
                                         }
                                     }
                                 },
                                 onSubmit: { focus = .city })
                if suggestionsEnabled {
                    AddressSuggestionList(suggestions: suggestions.suggestions, query: address.address1) { s in
                        pick(s)
                    }
                }
            }
            .paysioRevealAnchor(Self.streetAnchor)
            .padding(.top, -1)
            .zIndex(focus == .address1 ? 40 : 10)

            cityRow
                .frame(height: expanded ? nil : 0, alignment: .top)
                .clipped()
                .opacity(expanded ? 1 : 0)
                .allowsHitTesting(expanded)
                .accessibilityHidden(!expanded)
                .padding(.top, expanded ? -1 : 0)
                .zIndex(focus == .city || focus == .state || focus == .postalCode ? 40 : 10)
        }
        .animation(.easeOut(duration: 0.3), value: expanded)
        .modifier(ErrorsBelow(errors: errors))
    }

    private var countryRow: some View {
        StackedTrigger(
            value: country.isEmpty ? "" : PaysioCountries.countryName(country),
            placeholder: "Country",
            corners: hideName ? .top : .none,
            invalid: errors[.country] != nil,
            leading: AnyView(countryLeading),
            accessibilityLabel: "Country"
        ) {
            focus = nil
            sheet = .country
        }
    }

    @ViewBuilder
    private var countryLeading: some View {
        if country.isEmpty {
            Circle().fill(theme.colors.mutedForeground.opacity(0.35)).frame(width: 16, height: 16)
        } else {
            Text(PaysioCountries.flagEmoji(country)).font(.system(size: 14))
        }
    }

    private var cityRow: some View {
        HStack(spacing: -1) {
            StackedTextField("City", text: $address.city, corners: .bottomLeft,
                             contentType: .addressCity, capitalization: .words,
                             invalid: errors[.city] != nil,
                             isFocused: focusBinding(.city),
                             onFocusChange: { onFocus(.city, $0) },
                             onSubmit: {
                                 if isUS { focus = nil; sheet = .state } else { focus = .state }
                             })
            if isUS {
                StackedTrigger(value: normalizedUSState ?? "", placeholder: "State", corners: .none,
                               invalid: errors[.state] != nil, accessibilityLabel: "State") {
                    focus = nil
                    sheet = .state
                }
            } else {
                StackedTextField("State", text: $address.state, corners: .none,
                                 contentType: .addressState, capitalization: .words,
                                 invalid: errors[.state] != nil,
                                 isFocused: focusBinding(.state),
                                 onFocusChange: { onFocus(.state, $0) },
                                 onSubmit: { focus = .postalCode })
            }
            StackedTextField(isUS ? "ZIP" : "Postal code", text: $address.postalCode, corners: .bottomRight,
                             keyboard: isUS ? .numberPad : .default,
                             contentType: .postalCode, capitalization: .characters,
                             invalid: errors[.postalCode] != nil, submitLabel: .done,
                             isFocused: focusBinding(.postalCode),
                             onFocusChange: { onFocus(.postalCode, $0) },
                             onSubmit: { focus = nil })
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ kind: SheetKind) -> some View {
        switch kind {
        case .saved:
            PaysioBottomSheet(title: "Billing address", onClose: { sheet = nil }) { _ in
                ForEach(savedAddresses) { saved in
                    PaysioSheetRow(selected: saved.id == selectedSaved?.id, content: AnyView(savedLines(saved))) {
                        sheet = nil
                        selectedSavedId = saved.id
                        address = saved.address
                    }
                }
                PaysioSheetRow(label: "Enter a new address", leading: AnyView(PaysioIcon(.plus, size: 16, color: theme.colors.primary)),
                               accent: true) {
                    sheet = nil
                    withAnimation(.easeOut(duration: 0.2)) { enteringNew = true }
                }
            }
        case .country:
            PaysioBottomSheet(title: "Country", searchable: true, searchPlaceholder: "Search country", onClose: { sheet = nil }) { query in
                let q = query.trimmed.lowercased()
                let list = q.isEmpty ? countries : countries.filter { $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q) }
                if list.isEmpty {
                    PaysioSheetEmpty(text: "No countries found.")
                } else {
                    ForEach(list) { c in
                        PaysioSheetRow(selected: c.code == country, label: c.name, detail: c.code,
                                       leading: AnyView(Text(c.flag).font(.system(size: 16)))) {
                            sheet = nil
                            if c.code != country { address.state = "" }
                            address.country = c.code
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .address1 }
                        }
                    }
                }
            }
        case .state:
            PaysioBottomSheet(title: "State", searchable: true, searchPlaceholder: "Search state", onClose: { sheet = nil }) { query in
                let q = query.trimmed.lowercased()
                let list = q.isEmpty ? PaysioCountries.usStates
                    : PaysioCountries.usStates.filter { $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q) }
                if list.isEmpty {
                    PaysioSheetEmpty(text: "No states found.")
                } else {
                    ForEach(list) { s in
                        PaysioSheetRow(selected: s.code == normalizedUSState, label: s.name, detail: s.code) {
                            sheet = nil
                            address.state = s.code
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .postalCode }
                        }
                    }
                }
            }
        }
    }

    // MARK: Behaviour

    /// US: fold a full name or lower-case code onto the USPS code; a value that is no US
    /// state at all (left over from switching the country) is cleared rather than
    /// submitted invisibly behind an empty picker.
    private func normalizeUSState() {
        guard isUS, !address.state.isEmpty else { return }
        let next = PaysioCountries.toUSStateCode(address.state) ?? ""
        if next != address.state { address.state = next }
    }

    private func refreshSuggestions() {
        suggestions.update(apiBase: suggestBase, query: address.address1, country: country, enabled: suggestionsEnabled)
    }

    private func pick(_ s: PaysioAddressSuggestion) {
        typedSincePick = false
        let base = suggestBase
        Task { @MainActor in
            let d = await suggestions.resolve(s, apiBase: base)
            let picked = d.countryCode.uppercased()
            let allowed = !picked.isEmpty && countries.contains { $0.code == picked }
            let nextCountry = allowed ? picked : country
            let usAfter = nextCountry == "US"
            var next = address
            next.address1 = !d.address1.isEmpty ? d.address1 : (!s.address1.isEmpty ? s.address1 : address.address1)
            if !d.city.isEmpty { next.city = d.city }
            let st = usAfter ? (d.stateCode.isEmpty ? d.state : d.stateCode) : (d.state.isEmpty ? d.stateCode : d.state)
            if !st.isEmpty { next.state = st }
            if !d.postalCode.isEmpty { next.postalCode = d.postalCode }
            if allowed { next.country = picked }
            address = next
            if d.postalCode.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focus = .postalCode }
            } else {
                focus = nil
            }
        }
    }
}

/// First address-related message under the stack.
private struct ErrorsBelow: ViewModifier {
    let errors: [PaysioField: String]
    private static let order: [PaysioField] = [.firstName, .lastName, .country, .address1, .city, .state, .postalCode]

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            FieldErrorText(message: Self.order.compactMap { errors[$0] }.first)
        }
    }
}
