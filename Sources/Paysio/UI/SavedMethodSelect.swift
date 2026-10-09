import SwiftUI

/// Saved method select (RN `SavedMethodSelect.tsx`, web SavedMethodSelect).
///
/// Trigger: radius 10, border `input`, background `card`, padding 12 / 10, shadow
/// 0 1px 2px rgba(26,26,26,0.05). Row: brand mark 32, gap 10, "••••" 14 muted, last4
/// 14 medium, optional badge chip, meta 12 muted tabular pushed right, chevron 16 at
/// muted 70 % rotating 180 when open. Open state: border primary 50 %, 2 pt ring
/// primary 15 %. The list is a bottom sheet with the same rows and an optional pinned
/// "Add a payment method" row.
public struct SavedMethodSelect: View {
    public let methods: [PaysioSavedMethod]
    @Binding public var selected: PaysioSavedMethod?
    public var onAdd: (() -> Void)?
    public var title: String

    @Environment(\.paysioTheme) private var theme
    @Environment(\.paysioSheetComponents) private var sheetComponents
    @State private var open = false

    private static let dots = "\u{2022}\u{2022}\u{2022}\u{2022}"

    public init(methods: [PaysioSavedMethod], selected: Binding<PaysioSavedMethod?>, onAdd: (() -> Void)? = nil,
                title: String = "Saved method") {
        self.methods = methods
        self._selected = selected
        self.onAdd = onAdd
        self.title = title
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .circular)
        Button { open = true } label: {
            HStack(spacing: 10) {
                if let method = selected {
                    row(method)
                } else {
                    Text("Select a method\u{2026}")
                        .font(theme.font(14))
                        .foregroundColor(theme.colors.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                PaysioIcon(.chevronDown, size: 16, color: theme.colors.mutedForeground.opacity(0.7))
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .animation(.easeOut(duration: 0.2), value: open)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(open ? theme.colors.foreground.opacity(0.03) : theme.colors.card)
            .clipShape(shape)
            .overlay(shape.strokeBorder(open ? theme.colors.primary.opacity(0.5) : theme.colors.input, lineWidth: 1))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .circular)
                    .strokeBorder(theme.colors.primary.opacity(0.15), lineWidth: 2)
                    .padding(-2)
                    .opacity(open ? 1 : 0)
            )
            .shadow(color: Color(hex: 0x1A1A1A, opacity: 0.05), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(selected.map { "Saved method \(Self.dots) \($0.last4)" } ?? "Select a method")
        .onAppear { if selected == nil { selected = methods.first { !$0.disabled } } }
        .sheet(isPresented: $open) {
            PaysioBottomSheet(title: title, onClose: { open = false }) { _ in
                ForEach(methods) { method in
                    PaysioSheetRow(selected: method.id == selected?.id, disabled: method.disabled,
                                   content: AnyView(row(method))) {
                        open = false
                        selected = method
                    }
                }
                if let onAdd {
                    if !methods.isEmpty {
                        Rectangle().fill(theme.colors.border).frame(height: 1)
                            .padding(.vertical, 4).padding(.horizontal, 8)
                    }
                    PaysioSheetRow(content: AnyView(
                        HStack(spacing: 8) {
                            PaysioIcon(.plus, size: 16, color: theme.colors.mutedForeground)
                            Text("Add a payment method")
                                .font(theme.font(14, weight: .medium))
                                .foregroundColor(theme.colors.mutedForeground)
                        }
                        .frame(maxWidth: .infinity)
                    )) {
                        open = false
                        onAdd()
                    }
                }
            }
            .paysioSheetHost(theme: theme, components: sheetComponents)
        }
    }

    private func row(_ method: PaysioSavedMethod) -> some View {
        HStack(spacing: 10) {
            CardBrandMark(brand: method.isBank ? "bank" : method.brand, size: 32, isBank: method.isBank,
                          bin: method.bin, bankName: method.bankName)
            Text(Self.dots)
                .font(theme.font(14))
                .foregroundColor(theme.colors.mutedForeground)
            Text(method.last4)
                .font(theme.font(14, weight: .medium))
                .foregroundColor(theme.colors.foreground)
            if let badge = method.badge, !badge.isEmpty {
                Text(badge)
                    .font(theme.font(11, weight: .medium))
                    .foregroundColor(theme.colors.foreground)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(theme.colors.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .circular))
            }
            Spacer(minLength: 0)
            if let meta = method.meta, !meta.isEmpty {
                Text(meta.prefix(1).uppercased() + meta.dropFirst())
                    .font(theme.font(12).monospacedDigit())
                    .foregroundColor(theme.colors.mutedForeground)
            }
        }
    }
}
