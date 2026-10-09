import SwiftUI

/// The mobile stand-in for the web's Select / Popover lists (RN `ui/BottomSheet.tsx`):
/// a bottom sheet on a dimmed backdrop with an optional search field and rows the
/// caller renders. Rows follow the web list rows: 14 pt text, 6 pt radius, `secondary`
/// fill on the selected row, a check on the selected row.
///
/// Presented with SwiftUI's own sheet (so the system handles the backdrop, the drag to
/// dismiss and the keyboard), sized to its content up to 72 % of the screen, card
/// background, 18 pt top corners and the SDK's own 36 x 4 grabber.

/// What a custom sheet receives (RN `BottomSheetProps`).
public struct PaysioSheetConfiguration {
    public let title: String?
    public let searchable: Bool
    public let searchPlaceholder: String
    public let close: () -> Void
    /// The rows for a search query ("" when not searchable).
    public let rows: (String) -> AnyView
}

/// What a custom row receives (RN `SheetRowProps`).
public struct PaysioSheetRowConfiguration {
    public let selected: Bool
    public let label: String?
    public let detail: String?
    public let leading: AnyView?
    public let trailing: AnyView?
    public let disabled: Bool
    /// Primary-coloured text (the "Enter a new address" action row).
    public let accent: Bool
    /// Custom row content (two-line address, saved card). Replaces label + detail.
    public let content: AnyView?
    public let action: () -> Void
}

/// An app that already has its own bottom sheet and list rows can render the SDK's
/// pick-lists (country, state, saved address, saved method, custom select fields) with
/// them, so they match the rest of the app (RN `PaysioSheetComponents`). Each part is
/// optional; anything not provided falls back to the SDK's built-in look.
///
/// ```swift
/// PaysioPaymentSheet(...)
///     .paysioSheetComponents(PaysioSheetComponents(
///         row: { row in AnyView(MyListRow(title: row.label ?? "", selected: row.selected, action: row.action)) }
///     ))
/// ```
public struct PaysioSheetComponents {
    /// Replaces the whole sheet body (title, search, list). Presentation stays a sheet.
    public var sheet: ((PaysioSheetConfiguration) -> AnyView)?
    public var row: ((PaysioSheetRowConfiguration) -> AnyView)?
    public var empty: ((String) -> AnyView)?
    /// Replaces the SDK's content-sized detent (e.g. `[.medium, .large]`).
    public var detents: Set<PresentationDetent>?

    public init(sheet: ((PaysioSheetConfiguration) -> AnyView)? = nil,
                row: ((PaysioSheetRowConfiguration) -> AnyView)? = nil,
                empty: ((String) -> AnyView)? = nil,
                detents: Set<PresentationDetent>? = nil) {
        self.sheet = sheet
        self.row = row
        self.empty = empty
        self.detents = detents
    }
}

private struct PaysioSheetComponentsKey: EnvironmentKey {
    static let defaultValue = PaysioSheetComponents()
}

public extension EnvironmentValues {
    var paysioSheetComponents: PaysioSheetComponents {
        get { self[PaysioSheetComponentsKey.self] }
        set { self[PaysioSheetComponentsKey.self] = newValue }
    }
}

public extension View {
    /// Supplies your own sheet / row / empty-state look for every Paysio pick-list below.
    func paysioSheetComponents(_ components: PaysioSheetComponents) -> some View {
        environment(\.paysioSheetComponents, components)
    }
}

// MARK: - Sheet

/// The body of a pick-list sheet. Present it from `.sheet(item:)` / `.sheet(isPresented:)`
/// and apply `.paysioSheetHost(theme:components:)` so it gets the SDK look and size.
struct PaysioBottomSheet<Rows: View>: View {
    let title: String?
    var searchable = false
    var searchPlaceholder = "Search"
    let onClose: () -> Void
    @ViewBuilder let rows: (String) -> Rows

    @Environment(\.paysioTheme) private var theme
    @Environment(\.paysioSheetComponents) private var components
    @State private var query = ""
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        if let custom = components.sheet {
            custom(PaysioSheetConfiguration(title: title, searchable: searchable, searchPlaceholder: searchPlaceholder,
                                            close: onClose, rows: { AnyView(rows($0)) }))
                .modifier(SheetDetents(height: nil, custom: components.detents))
        } else {
            defaultBody
        }
    }

    private var defaultBody: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(theme.colors.mutedForeground.opacity(0.35))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            if let title {
                Text(title)
                    .font(theme.font(14, weight: .medium))
                    .foregroundColor(theme.colors.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityAddTraits(.isHeader)
            }
            if searchable {
                TextField("", text: $query,
                          prompt: Text(searchPlaceholder).foregroundColor(theme.colors.mutedForeground.opacity(0.9)))
                    .font(theme.font(16))
                    .foregroundColor(theme.colors.foreground)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel(searchPlaceholder)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(theme.colors.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .circular))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
            ScrollView {
                VStack(spacing: 0) {
                    rows(query)
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
                })
            }
            .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(SheetDetents(height: headerHeight + contentHeight, custom: components.detents))
    }

    private var headerHeight: CGFloat {
        20 + (title == nil ? 0 : 33) + (searchable ? 40 : 0)
    }
}

private struct SheetContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Content-sized up to 72 % of the screen (RN `maxHeightRatio`), or the host's detents.
private struct SheetDetents: ViewModifier {
    let height: CGFloat?
    let custom: Set<PresentationDetent>?

    func body(content: Content) -> some View {
        if let custom {
            content.presentationDetents(custom)
        } else if let height, height > 0 {
            let maxHeight = UIScreen.main.bounds.height * 0.72
            content.presentationDetents([.height(min(height, maxHeight))])
        } else {
            content.presentationDetents([.fraction(0.72)])
        }
    }
}

/// Re-injects the theme and sheet components (a sheet is a new presentation) and
/// applies the SDK's sheet chrome.
struct PaysioSheetHost: ViewModifier {
    let theme: PaysioResolvedTheme
    let components: PaysioSheetComponents

    func body(content: Content) -> some View {
        let base = content
            .environment(\.paysioTheme, theme)
            .environment(\.paysioSheetComponents, components)
            .presentationDragIndicator(components.sheet == nil ? .hidden : .automatic)
            .preferredColorScheme(theme.dark ? .dark : .light)
        if #available(iOS 16.4, *) {
            base
                .presentationCornerRadius(18)
                .presentationBackground(components.sheet == nil ? theme.colors.card : Color(UIColor.systemBackground))
        } else {
            base.background(theme.colors.card.ignoresSafeArea())
        }
    }
}

extension View {
    func paysioSheetHost(theme: PaysioResolvedTheme, components: PaysioSheetComponents) -> some View {
        modifier(PaysioSheetHost(theme: theme, components: components))
    }
}

// MARK: - Rows

/// A list row: optional leading element, label, optional detail on the right, selected
/// fill and check (RN `SheetRow`). A host `row` component replaces it.
struct PaysioSheetRow: View {
    var selected = false
    var label: String? = nil
    var detail: String? = nil
    var leading: AnyView? = nil
    var trailing: AnyView? = nil
    var disabled = false
    var accent = false
    var content: AnyView? = nil
    let action: () -> Void

    @Environment(\.paysioTheme) private var theme
    @Environment(\.paysioSheetComponents) private var components

    var body: some View {
        if let custom = components.row {
            custom(PaysioSheetRowConfiguration(selected: selected, label: label, detail: detail, leading: leading,
                                               trailing: trailing, disabled: disabled, accent: accent,
                                               content: content, action: action))
        } else {
            Button(action: action) {
                HStack(spacing: 10) {
                    if let leading { leading }
                    if let content {
                        content.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(label ?? "")
                            .font(theme.font(14, weight: accent ? .medium : .regular))
                            .foregroundColor(accent ? theme.colors.primary : theme.colors.foreground)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let detail {
                        Text(detail)
                            .font(theme.font(12))
                            .foregroundColor(theme.colors.mutedForeground)
                    }
                    if let trailing { trailing }
                    if selected && trailing == nil {
                        PaysioIcon(.check, size: 16, color: theme.colors.foreground)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(SheetRowStyle(selected: selected))
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
            .padding(.bottom, 2)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }
}

private struct SheetRowStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.paysioTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(selected ? theme.colors.secondary : (configuration.isPressed ? theme.colors.rowHover : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .circular))
    }
}

/// "No countries found." (RN `SheetEmpty`).
struct PaysioSheetEmpty: View {
    let text: String
    @Environment(\.paysioTheme) private var theme
    @Environment(\.paysioSheetComponents) private var components

    var body: some View {
        if let custom = components.empty {
            custom(text)
        } else {
            Text(text)
                .font(theme.font(14))
                .foregroundColor(theme.colors.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }
}
