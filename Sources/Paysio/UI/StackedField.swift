import SwiftUI

/// Which corners of a stacked box are rounded (radius 8).
public struct PaysioCorners: OptionSet, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let topLeft = PaysioCorners(rawValue: 1)
    public static let topRight = PaysioCorners(rawValue: 2)
    public static let bottomLeft = PaysioCorners(rawValue: 4)
    public static let bottomRight = PaysioCorners(rawValue: 8)

    public static let top: PaysioCorners = [.topLeft, .topRight]
    public static let bottom: PaysioCorners = [.bottomLeft, .bottomRight]
    public static let all: PaysioCorners = [.top, .bottom]
    public static let none: PaysioCorners = []

    func radii(_ r: CGFloat, plus extra: CGFloat = 0) -> RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: contains(.topLeft) ? r + extra : extra,
            bottomLeading: contains(.bottomLeft) ? r + extra : extra,
            bottomTrailing: contains(.bottomRight) ? r + extra : extra,
            topTrailing: contains(.topRight) ? r + extra : extra
        )
    }
}

/// Stacked field metrics (RN `StackedField.tsx`).
enum StackedMetrics {
    static let height: CGFloat = 36
    static let radius: CGFloat = 8
    static let fontSize: CGFloat = 16
}

/// The connected-field box from the hosted checkout (RN `StackedBox`): height 36, 1 px
/// `input` border, transparent background, shadow 0 1px 0 rgba(26,26,26,0.04),
/// content clipped. Adjacent boxes overlap by 1 px (`spacing: -1` in the parent) so two
/// borders collapse into one hairline. The focused box paints a 2 px `ring` OUTSIDE its
/// border with the box's radii plus 2 and rises above its siblings; an invalid box
/// (after blur) paints a 1 px `destructive` border and sits between the two. Only the
/// outer corners of a group are rounded: inner seams are square.
public struct StackedFieldBox<Content: View>: View {
    public let corners: PaysioCorners
    public let focused: Bool
    public let invalid: Bool
    public let height: CGFloat
    private let content: () -> Content

    @Environment(\.paysioTheme) private var theme

    public init(corners: PaysioCorners, focused: Bool = false, invalid: Bool = false, height: CGFloat = 36,
                @ViewBuilder content: @escaping () -> Content) {
        self.corners = corners
        self.focused = focused
        self.invalid = invalid
        self.height = height
        self.content = content
    }

    public var body: some View {
        let shape = UnevenRoundedRectangle(cornerRadii: corners.radii(StackedMetrics.radius), style: .circular)
        let ring = UnevenRoundedRectangle(cornerRadii: corners.radii(StackedMetrics.radius, plus: 2), style: .circular)
        let borderColor: Color = invalid && !focused ? theme.colors.destructive : theme.colors.input
        content()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(shape)
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(borderColor, lineWidth: 1)
                    .shadow(color: Color(hex: 0x1A1A1A, opacity: 0.04), radius: 0, x: 0, y: 1)
                    .allowsHitTesting(false)
            )
            .overlay(
                ring.strokeBorder(theme.colors.ring, lineWidth: 2)
                    .padding(-2)
                    .opacity(focused ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .zIndex(focused ? 40 : (invalid ? 20 : 10))
    }
}

/// A native text input inside a `StackedFieldBox` (RN `StackedInput`): 16 pt text in
/// `foreground`, placeholder `mutedForeground` at 90 %, padding left 12 (32 with a
/// leading icon at left 10), right 12 (34 with a trailing element at right 10).
public struct StackedTextField: View {
    public let placeholder: String
    @Binding public var text: String
    public let corners: PaysioCorners
    public var keyboard: UIKeyboardType = .default
    public var contentType: UITextContentType? = nil
    public var capitalization: TextInputAutocapitalization = .never
    public var invalid: Bool = false
    public var leadingIcon: PaysioIconName? = nil
    public var trailing: AnyView? = nil
    public var trailingInset: CGFloat = 10
    public var paddingRight: CGFloat? = nil
    public var submitLabel: SubmitLabel = .next
    public var accessibilityText: String? = nil
    public var onFocusChange: ((Bool) -> Void)? = nil
    public var onSubmit: (() -> Void)? = nil
    private var externalFocus: Binding<Bool>?

    @Environment(\.paysioTheme) private var theme
    @Environment(\.paysioKeyboardReveal) private var reveal
    @FocusState private var focused: Bool

    /// - Parameters:
    ///   - isFocused: optional two-way focus binding, so a parent can move focus
    ///     (e.g. to ZIP after an address suggestion) and track which field is active.
    public init(_ placeholder: String, text: Binding<String>, corners: PaysioCorners,
                keyboard: UIKeyboardType = .default, contentType: UITextContentType? = nil,
                capitalization: TextInputAutocapitalization = .never, invalid: Bool = false,
                leadingIcon: PaysioIconName? = nil, trailing: AnyView? = nil, trailingInset: CGFloat = 10,
                paddingRight: CGFloat? = nil, submitLabel: SubmitLabel = .next, accessibilityLabel: String? = nil,
                isFocused: Binding<Bool>? = nil, onFocusChange: ((Bool) -> Void)? = nil, onSubmit: (() -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.corners = corners
        self.keyboard = keyboard
        self.contentType = contentType
        self.capitalization = capitalization
        self.invalid = invalid
        self.leadingIcon = leadingIcon
        self.trailing = trailing
        self.trailingInset = trailingInset
        self.paddingRight = paddingRight
        self.submitLabel = submitLabel
        self.accessibilityText = accessibilityLabel
        self.externalFocus = isFocused
        self.onFocusChange = onFocusChange
        self.onSubmit = onSubmit
    }

    public var body: some View {
        StackedFieldBox(corners: corners, focused: focused, invalid: invalid) {
            ZStack(alignment: .leading) {
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(theme.colors.mutedForeground.opacity(0.9)))
                    .font(theme.font(StackedMetrics.fontSize))
                    .foregroundColor(theme.colors.foreground)
                    .keyboardType(keyboard)
                    .textContentType(contentType)
                    .textInputAutocapitalization(capitalization)
                    .autocorrectionDisabled()
                    .submitLabel(submitLabel)
                    .onSubmit { onSubmit?() }
                    .focused($focused)
                    .modifier(OptionalAccessibilityLabel(label: accessibilityText))
                    .padding(.leading, leadingIcon == nil ? 12 : 32)
                    .padding(.trailing, paddingRight ?? (trailing == nil ? 12 : 34))
                    .frame(maxHeight: .infinity)
                if let leadingIcon {
                    PaysioIcon(leadingIcon, size: 16,
                               color: focused ? theme.colors.foreground.opacity(0.8) : theme.colors.mutedForeground.opacity(0.7))
                        .padding(.leading, 10)
                        .allowsHitTesting(false)
                }
                if let trailing {
                    HStack {
                        Spacer(minLength: 0)
                        trailing.padding(.trailing, trailingInset)
                    }
                }
            }
        }
        .onChange(of: focused) { isOn in
            if externalFocus?.wrappedValue != isOn { externalFocus?.wrappedValue = isOn }
            onFocusChange?(isOn)
            if isOn { reveal?.reveal(.firstResponder) }
        }
        .onChange(of: externalFocus?.wrappedValue ?? false) { wanted in
            if wanted != focused { focused = wanted }
        }
        .onAppear {
            if let externalFocus, externalFocus.wrappedValue, !focused { focused = true }
        }
    }
}

/// A select trigger in the box (RN `StackedTrigger`, country / state / custom select):
/// same height, text and padding as the input; the value in `foreground` on ONE line,
/// the placeholder in muted at 90 %; a single chevron-down (16, muted) on the right.
public struct StackedTrigger: View {
    public let value: String
    public let placeholder: String
    public let corners: PaysioCorners
    public let invalid: Bool
    public let leading: AnyView?
    public let accessibilityText: String?
    public let action: () -> Void

    @Environment(\.paysioTheme) private var theme

    public init(value: String, placeholder: String, corners: PaysioCorners, invalid: Bool = false,
                leading: AnyView? = nil, accessibilityLabel: String? = nil, action: @escaping () -> Void) {
        self.value = value
        self.placeholder = placeholder
        self.corners = corners
        self.invalid = invalid
        self.leading = leading
        self.accessibilityText = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        StackedFieldBox(corners: corners, invalid: invalid) {
            Button(action: action) {
                ZStack(alignment: .leading) {
                    Text(value.isEmpty ? placeholder : value)
                        .font(theme.font(StackedMetrics.fontSize))
                        .foregroundColor(value.isEmpty ? theme.colors.mutedForeground.opacity(0.9) : theme.colors.foreground)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, leading == nil ? 12 : 32)
                        .padding(.trailing, 34)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    if let leading {
                        leading.padding(.leading, 10)
                    }
                    HStack {
                        Spacer(minLength: 0)
                        PaysioIcon(.chevronDown, size: 16, color: theme.colors.mutedForeground)
                            .padding(.trailing, 10)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(TriggerPressStyle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText ?? placeholder)
        .accessibilityValue(value)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

/// Leaves the system label (placeholder / value, which UI tests tap) unless one is given.
private struct OptionalAccessibilityLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label { content.accessibilityLabel(label) } else { content }
    }
}

/// Pressed rows tint with `rowHover`.
struct TriggerPressStyle: ButtonStyle {
    @Environment(\.paysioTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? theme.colors.rowHover : Color.clear)
    }
}

/// Section heading: 14 pt medium, muted, 8 pt to the fields.
struct SectionHeading: View {
    let text: String
    @Environment(\.paysioTheme) private var theme

    var body: some View {
        Text(text)
            .font(theme.font(14, weight: .medium))
            .foregroundColor(theme.colors.mutedForeground)
            .padding(.bottom, 8)
    }
}

/// Inline cycle toggle (RN `InlineChip`, web InlineFieldToggle): tapping advances to the
/// next option. 11 pt medium, mutedForeground, radius 6, padding 6 / 4, transparent
/// (`background` while pressed).
struct CycleChip: View {
    let label: String
    let nextLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
        }
        .buttonStyle(ChipStyle())
        .accessibilityLabel("\(label). Switch to \(nextLabel)")
    }

    private struct ChipStyle: ButtonStyle {
        @Environment(\.paysioTheme) private var theme

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(theme.font(11, weight: .medium))
                .foregroundColor(theme.colors.mutedForeground)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(configuration.isPressed ? theme.colors.background : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .circular))
                .contentShape(Rectangle().inset(by: -6))
        }
    }
}

/// Row press feedback: scale 0.985 over 150 ms.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Inline validation message under a stack.
struct FieldErrorText: View {
    let message: String?
    @Environment(\.paysioTheme) private var theme

    var body: some View {
        if let message {
            Text(message)
                .font(theme.font(12))
                .foregroundColor(theme.colors.destructive)
                .padding(.top, 6)
                .accessibilityLabel("Error: \(message)")
        }
    }
}

/// A standalone consent checkbox row (RN `ConsentRow`): 18 pt box, radius 5, 1 pt
/// border (`input`, `primary` when checked), primary fill and a white 14 pt check
/// (stroke 2) when checked, 10 pt gap, 12 / 16 pt muted text, top aligned.
public struct PaysioConsentRow: View {
    @Binding public var checked: Bool
    public let text: String
    public let accessibilityText: String

    @Environment(\.paysioTheme) private var theme

    public init(checked: Binding<Bool>, text: String, accessibilityLabel: String? = nil) {
        self._checked = checked
        self.text = text
        self.accessibilityText = accessibilityLabel ?? text
    }

    public var body: some View {
        Button { checked.toggle() } label: {
            HStack(alignment: .top, spacing: 10) {
                PaysioCheckBox(checked: checked)
                    .padding(.top, 1)
                Text(text)
                    .font(theme.font(12))
                    .lineSpacing(2)
                    .foregroundColor(theme.colors.mutedForeground)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityValue(checked ? "Checked" : "Unchecked")
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : [.isButton])
    }
}

/// The 18 pt checkbox square shared by the consent row and checkbox custom fields.
struct PaysioCheckBox: View {
    let checked: Bool
    @Environment(\.paysioTheme) private var theme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .circular)
        ZStack {
            shape.fill(checked ? theme.colors.primary : Color.clear)
            shape.strokeBorder(checked ? theme.colors.primary : theme.colors.input, lineWidth: 1)
            if checked {
                PaysioIcon(.check, size: 14, color: .white, strokeWidth: 2)
            }
        }
        .frame(width: 18, height: 18)
    }
}
