import SwiftUI

/// 1:1 port of the web "Payment method" picker (MOBILE_SDK_PLAN.md section 8.1).
///
/// - Container radius 18 (theme.radius), 1 px border, hairline shadow, clipped.
/// - Rows: margin 4, padding 12, gap 12: radio + icon + label + trailing.
/// - Radio 18 pt, checked = primary fill + 4 pt ring at 15 % + 6 pt white dot (200 ms).
/// - Selected row background: foreground at 7 %. Press scale 0.985 / 150 ms.
/// - Panel: padding 16 / 4 top / 16 bottom, 240 ms with curve (0.32, 0.72, 0, 1);
///   no animation on first paint.
/// - With a single option there is no picker chrome, only the panel.
public struct PaymentMethodPicker<Panel: View>: View {
    public let options: [PaysioMethodKind]
    @Binding public var selected: PaysioMethodKind
    public let savedMethod: PaysioSavedMethod?
    private let panel: (PaysioMethodKind) -> Panel

    @Environment(\.paysioTheme) private var theme
    @State private var didAppear = false

    public init(options: [PaysioMethodKind], selected: Binding<PaysioMethodKind>,
                savedMethod: PaysioSavedMethod? = nil, @ViewBuilder panel: @escaping (PaysioMethodKind) -> Panel) {
        self.options = options
        self._selected = selected
        self.savedMethod = savedMethod
        self.panel = panel
    }

    private var hasSaved: Bool { options.contains(.saved) }

    public var body: some View {
        Group {
            if options.count <= 1, let only = options.first {
                panel(only)
            } else {
                picker
            }
        }
        .onAppear {
            // Defer so the first layout is not animated.
            DispatchQueue.main.async { didAppear = true }
        }
    }

    private var picker: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                if index > 0 {
                    Rectangle().fill(theme.colors.border).frame(height: 1)
                }
                row(option, isFirst: index == 0, isLast: index == options.count - 1)
                if selected == option {
                    panel(option)
                        .padding(EdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(theme.colors.border, lineWidth: 1))
        .shadow(color: Color(hex: 0x1A1A1A, opacity: 0.04), radius: 1, x: 0, y: 1)
        .animation(didAppear ? .timingCurve(0.32, 0.72, 0, 1, duration: 0.24) : nil, value: selected)
    }

    private func row(_ option: PaysioMethodKind, isFirst: Bool, isLast: Bool) -> some View {
        let isSelected = selected == option
        let top: CGFloat = isFirst ? theme.rowRadiusOuter : theme.rowRadiusInner
        let bottom: CGFloat = (isLast && !isSelected) ? theme.rowRadiusOuter : theme.rowRadiusInner
        let shape = UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: bottom, topTrailing: top),
            style: .continuous)

        return Button {
            if selected != option { selected = option }
        } label: {
            HStack(spacing: 12) {
                RadioDot(checked: isSelected)
                PaysioIcon(icon(for: option), size: 20, color: theme.colors.mutedForeground)
                Text(label(for: option))
                    .font(theme.font(14, weight: .medium))
                    .foregroundColor(theme.colors.foreground)
                Spacer(minLength: 8)
                trailing(for: option)
                    .opacity(isSelected ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: isSelected)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(isSelected ? theme.colors.foreground.opacity(0.07) : Color.clear)
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle())
        .padding(4)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel(label(for: option))
    }

    private func label(for option: PaysioMethodKind) -> String {
        switch option {
        case .saved: return "Saved method"
        case .card: return hasSaved ? "New card" : "Card"
        case .bank: return hasSaved ? "New bank account" : "Bank account"
        }
    }

    /// The Mynaui glyphs RN PaymentSheet uses for each row.
    private func icon(for option: PaysioMethodKind) -> PaysioIconName {
        switch option {
        case .saved: return .creditCardSolid
        case .card: return .creditCardPlusSolid
        case .bank: return .bankSolid
        }
    }

    @ViewBuilder
    private func trailing(for option: PaysioMethodKind) -> some View {
        switch option {
        case .card:
            AcceptedBrandStack(size: 28)
        case .saved:
            if let saved = savedMethod {
                HStack(spacing: 6) {
                    CardBrandMark(brand: saved.isBank ? "bank" : saved.brand, size: 28, isBank: saved.isBank,
                                  bin: saved.bin, bankName: saved.bankName)
                    Text("\u{2022}\u{2022}\u{2022}\u{2022}")
                        .font(theme.font(12))
                        .foregroundColor(theme.colors.mutedForeground)
                    Text(saved.last4)
                        .font(theme.font(12, weight: .medium))
                        .foregroundColor(theme.colors.foreground)
                    if let badge = saved.badge, !badge.isEmpty {
                        Text(badge)
                            .font(theme.font(11, weight: .medium))
                            .foregroundColor(theme.colors.foreground)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(theme.colors.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .circular))
                    }
                }
            } else {
                EmptyView()
            }
        case .bank:
            EmptyView()
        }
    }
}

/// 18 pt radio: 1 px border (muted 35 %) unchecked; primary fill + border, 4 pt ring at
/// 15 % and a 6 pt white dot scaling 0 -> 1 in 200 ms when checked.
struct RadioDot: View {
    let checked: Bool
    @Environment(\.paysioTheme) private var theme

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.colors.primary.opacity(0.15))
                .frame(width: 26, height: 26)
                .opacity(checked ? 1 : 0)
            Circle()
                .fill(checked ? theme.colors.primary : Color.clear)
                .overlay(Circle().strokeBorder(checked ? theme.colors.primary : theme.colors.mutedForeground.opacity(0.35), lineWidth: 1))
                .frame(width: 18, height: 18)
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .scaleEffect(checked ? 1 : 0.01)
        }
        .frame(width: 18, height: 18)
        .animation(.easeOut(duration: 0.2), value: checked)
        .accessibilityHidden(true)
    }
}
