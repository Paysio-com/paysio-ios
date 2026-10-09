import SwiftUI
import UIKit

/// Colour tokens of the SDK, the same values as the React Native SDK's `ui/tokens.ts`
/// (resolved from the web app's `src/index.css`, last synced 2026-10-08). `ring` follows
/// the HOSTED checkout (light rgba(0,0,0,0.35), dark rgba(255,255,255,0.4)), not primary.
public struct PaysioThemeColors: Sendable, Equatable {
    public var primary: Color
    public var foreground: Color
    public var mutedForeground: Color
    public var card: Color
    public var background: Color
    public var secondary: Color
    public var border: Color
    public var input: Color
    public var rowHover: Color
    public var ring: Color
    public var destructive: Color

    public init(primary: Color, foreground: Color, mutedForeground: Color, card: Color, background: Color,
                secondary: Color, border: Color, input: Color, rowHover: Color, ring: Color, destructive: Color) {
        self.primary = primary
        self.foreground = foreground
        self.mutedForeground = mutedForeground
        self.card = card
        self.background = background
        self.secondary = secondary
        self.border = border
        self.input = input
        self.rowHover = rowHover
        self.ring = ring
        self.destructive = destructive
    }

    /// Light tokens.
    public static let light = PaysioThemeColors(
        primary: Color(hex: 0x0B57D0),
        foreground: Color(hex: 0x1B1B1B),
        mutedForeground: Color(hex: 0x5D5D5F),
        card: Color(hex: 0xFCFCFD),
        background: Color(hex: 0xF3F3F4),
        secondary: Color(hex: 0xEAEAED),
        border: Color(hex: 0xECECEC),
        input: Color(hex: 0xDBDBDC),
        rowHover: Color.black.opacity(0.04),
        ring: Color.black.opacity(0.35), // hosted checkout focus ring
        destructive: Color(hex: 0xC70A24)
    )

    /// Dark tokens.
    public static let dark = PaysioThemeColors(
        primary: Color(hex: 0x0B57D0),
        foreground: Color(hex: 0xF0F0F0),
        mutedForeground: Color(hex: 0xA6A6A6),
        card: Color(hex: 0x101010),
        background: Color(hex: 0x0A0A0A),
        secondary: Color(hex: 0x181818),
        border: Color.white.opacity(0.09),
        input: Color(hex: 0x404040), // card mixed 80 % with white
        rowHover: Color.white.opacity(0.05),
        ring: Color.white.opacity(0.4), // hosted checkout focus ring
        destructive: Color(hex: 0xDC2626)
    )
}

/// Partial overrides a merchant applies on top of the light or dark set.
public struct PaysioThemeColorOverrides: Sendable, Equatable {
    public var primary: Color?
    public var foreground: Color?
    public var mutedForeground: Color?
    public var card: Color?
    public var background: Color?
    public var secondary: Color?
    public var border: Color?
    public var input: Color?
    public var rowHover: Color?
    public var ring: Color?
    public var destructive: Color?

    public init(primary: Color? = nil, foreground: Color? = nil, mutedForeground: Color? = nil, card: Color? = nil,
                background: Color? = nil, secondary: Color? = nil, border: Color? = nil, input: Color? = nil,
                rowHover: Color? = nil, ring: Color? = nil, destructive: Color? = nil) {
        self.primary = primary
        self.foreground = foreground
        self.mutedForeground = mutedForeground
        self.card = card
        self.background = background
        self.secondary = secondary
        self.border = border
        self.input = input
        self.rowHover = rowHover
        self.ring = ring
        self.destructive = destructive
    }

    func apply(to base: PaysioThemeColors) -> PaysioThemeColors {
        var c = base
        // The focus ring stays the checkout's translucent grey; it does not follow primary.
        if let v = primary { c.primary = v }
        if let v = foreground { c.foreground = v }
        if let v = mutedForeground { c.mutedForeground = v }
        if let v = card { c.card = v }
        if let v = background { c.background = v }
        if let v = secondary { c.secondary = v }
        if let v = border { c.border = v }
        if let v = input { c.input = v }
        if let v = rowHover { c.rowHover = v }
        if let v = ring { c.ring = v }
        if let v = destructive { c.destructive = v }
        return c
    }
}

/// Theme input. `.auto` follows the system colour scheme.
public struct PaysioTheme: Sendable, Equatable {
    public enum Scheme: String, Sendable { case light, dark, auto }

    public var scheme: Scheme
    public var colors: PaysioThemeColorOverrides
    public var darkColors: PaysioThemeColorOverrides
    /// Font family for every text in the SDK. nil = San Francisco.
    public var fontFamily: String?
    /// Outer radius of the picker (web: 18). Everything else scales from it.
    public var radius: CGFloat

    public init(scheme: Scheme = .auto, colors: PaysioThemeColorOverrides = .init(),
                darkColors: PaysioThemeColorOverrides = .init(), fontFamily: String? = nil, radius: CGFloat = 18) {
        self.scheme = scheme
        self.colors = colors
        self.darkColors = darkColors
        self.fontFamily = fontFamily
        self.radius = radius
    }

    public static let auto = PaysioTheme()
    public static let light = PaysioTheme(scheme: .light)
    public static let dark = PaysioTheme(scheme: .dark)

    /// Resolves against the host's colour scheme.
    public func resolve(colorScheme: ColorScheme) -> PaysioResolvedTheme {
        let dark: Bool
        switch scheme {
        case .light: dark = false
        case .dark: dark = true
        case .auto: dark = colorScheme == .dark
        }
        let base = dark ? PaysioThemeColors.dark : PaysioThemeColors.light
        let merged = dark ? colors.apply(to: base).merging(darkColors) : colors.apply(to: base)
        return PaysioResolvedTheme(dark: dark, colors: merged, fontFamily: fontFamily, radius: radius)
    }
}

private extension PaysioThemeColors {
    func merging(_ overrides: PaysioThemeColorOverrides) -> PaysioThemeColors { overrides.apply(to: self) }
}

/// What views read: concrete colours plus font and radius helpers.
public struct PaysioResolvedTheme: Sendable, Equatable {
    public let dark: Bool
    public let colors: PaysioThemeColors
    public let fontFamily: String?
    public let radius: CGFloat

    public init(dark: Bool, colors: PaysioThemeColors, fontFamily: String?, radius: CGFloat) {
        self.dark = dark
        self.colors = colors
        self.fontFamily = fontFamily
        self.radius = radius
    }

    public static let defaultLight = PaysioResolvedTheme(dark: false, colors: .light, fontFamily: nil, radius: 18)

    public func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let fontFamily { return Font.custom(fontFamily, size: size).weight(weight) }
        return Font.system(size: size, weight: weight)
    }

    public func uiFont(_ size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        if let fontFamily, let f = UIFont(name: fontFamily, size: size) { return f }
        return UIFont.systemFont(ofSize: size, weight: weight)
    }

    /// `UIColor` for the VGS text fields (UIKit).
    public func uiColor(_ color: Color) -> UIColor { UIColor(color) }

    /// Inner radius for rows: 14 on the outer rows, 7 inside (web values at radius 18).
    public var rowRadiusOuter: CGFloat { max(4, radius - 4) }
    public var rowRadiusInner: CGFloat { max(2, (radius - 4) / 2) }
}

// MARK: - Environment plumbing

private struct PaysioThemeKey: EnvironmentKey {
    static let defaultValue: PaysioResolvedTheme = .defaultLight
}

public extension EnvironmentValues {
    /// The resolved theme every Paysio view reads.
    var paysioTheme: PaysioResolvedTheme {
        get { self[PaysioThemeKey.self] }
        set { self[PaysioThemeKey.self] = newValue }
    }
}

/// Resolves a `PaysioTheme` against the system scheme and injects it.
struct PaysioThemed<Content: View>: View {
    let theme: PaysioTheme
    let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content().environment(\.paysioTheme, theme.resolve(colorScheme: colorScheme))
    }
}

public extension View {
    /// Applies a Paysio theme to this subtree. The drop-in sheet does this for you.
    func paysioTheme(_ theme: PaysioTheme) -> some View {
        PaysioThemed(theme: theme) { self }
    }
}

// MARK: - Color helpers

public extension Color {
    /// `Color(hex: 0x0B57D0)`.
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
