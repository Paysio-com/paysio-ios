import SwiftUI

/// The brand mark itself, ported from the React Native SDK's `CardBrandMark`
/// (`sdks/react-native/src/ui/CardBrand.tsx`): the same artwork (`CardBrandArt`),
/// viewBox crop `2 7 28 18`, width `size`, height `size * 0.65`, and the same
/// brand-normalisation rules (lower-case, spaces / dashes / underscores removed,
/// wallets first, BIN fallback for "unknown").
///
/// Banks: a recognised institution's logo is a remote asset. Pass `bankLogoURL` to
/// draw it (the 32 x 32 canvas scaled by 32/28 and centred, as in RN); without one,
/// or when it fails to load, the generic bank badge is drawn.
public struct CardBrandMark: View {
    public let brand: String?
    public let bin: String?
    public let walletType: String?
    public let isBank: Bool
    public let bankName: String?
    public let bankLogoURL: URL?
    public let size: CGFloat
    /// Used by the generic card only, so it can sit on either theme.
    public let fallbackColor: Color

    public init(brand: String?, size: CGFloat = 30, isBank: Bool = false, bin: String? = nil,
                walletType: String? = nil, bankName: String? = nil, bankLogoURL: URL? = nil,
                fallbackColor: Color = Color(hex: 0x6E6E6E)) {
        self.brand = brand
        self.bin = bin
        self.walletType = walletType
        self.isBank = isBank
        self.bankName = bankName
        self.bankLogoURL = bankLogoURL
        self.size = size
        self.fallbackColor = fallbackColor
    }

    private var width: CGFloat { size }
    private var height: CGFloat { size * CardBrandArt.ratio }

    private var showsBank: Bool {
        let key = CardBrandResolver.normalize(brand)
        return isBank || key == "bank" || (key.isEmpty && bankName != nil)
    }

    public var body: some View {
        Group {
            if showsBank, let bankLogoURL {
                BankLogo(url: bankLogoURL, width: width, height: height)
            } else {
                CardBrandArtwork(layers: CardBrandResolver.layers(brand: isBank ? "bank" : brand, bin: bin, walletType: walletType),
                                 fallbackColor: fallbackColor)
                    .frame(width: width, height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if showsBank { return bankName ?? "Bank account" }
        switch CardBrandResolver.key(brand: brand, bin: bin, walletType: walletType) {
        case "apple_pay": return "Apple Pay"
        case "google_pay": return "Google Pay"
        case "visa": return "Visa"
        case "mastercard": return "Mastercard"
        case "amex", "americanexpress": return "American Express"
        case "discover": return "Discover"
        case "dinersclub", "diners": return "Diners Club"
        case "jcb": return "JCB"
        case "unionpay": return "UnionPay"
        case "maestro": return "Maestro"
        default: return "Card"
        }
    }
}

/// Brand resolution shared by the mark and `hasBrandArt` (RN `normalize`,
/// `brandFromBin`, `hasBrandArt`).
public enum CardBrandResolver {
    static func normalize(_ brand: String?) -> String {
        guard let brand else { return "" }
        return String(brand.lowercased().filter { $0 != " " && $0 != "-" && $0 != "_" && !$0.isWhitespace })
    }

    /// Same BIN table the web uses, for rows that stored a number but no brand.
    public static func brandFromBin(_ bin: String) -> String {
        let n = bin.filter { !$0.isWhitespace }
        func matches(_ pattern: String) -> Bool { n.range(of: pattern, options: .regularExpression) != nil }
        if matches("^4") { return "visa" }
        if matches("^5[1-5]") || matches("^2[2-7]") { return "mastercard" }
        if matches("^3[47]") { return "amex" }
        if matches("^6(?:011|5)") { return "discover" }
        if matches("^3(?:0[0-5]|[68])") { return "dinersclub" }
        if matches("^35") { return "jcb" }
        if matches("^62") { return "unionpay" }
        if matches("^(?:5018|5020|5038|6304|6759|676[1-3])") { return "maestro" }
        return ""
    }

    /// The resolved artwork key: a wallet type, "bank", or a normalised brand.
    static func key(brand: String?, bin: String?, walletType: String?) -> String {
        if walletType == "apple_pay" || walletType == "google_pay" { return walletType! }
        var key = normalize(brand)
        if key == "bank" { return key }
        if key.isEmpty || key == "unknown", let bin { key = brandFromBin(bin) }
        return key
    }

    /// Whether a brand (or bin) resolves to artwork; used to decide on the fallback.
    public static func hasBrandArt(brand: String?, bin: String? = nil, walletType: String? = nil) -> Bool {
        let k = key(brand: brand, bin: bin, walletType: walletType)
        return ["apple_pay", "google_pay", "bank", "visa", "mastercard", "amex", "americanexpress", "discover",
                "dinersclub", "diners", "jcb", "unionpay", "maestro"].contains(k)
    }

    static func layers(brand: String?, bin: String?, walletType: String?) -> [CardBrandArt.Layer] {
        switch key(brand: brand, bin: bin, walletType: walletType) {
        case "apple_pay": return CardBrandArt.applePay
        case "google_pay": return CardBrandArt.googlePay
        case "bank": return CardBrandArt.bank
        case "visa": return CardBrandArt.visa
        case "mastercard": return CardBrandArt.mastercard()
        case "amex", "americanexpress": return CardBrandArt.amex
        case "discover": return CardBrandArt.discover
        case "dinersclub", "diners": return CardBrandArt.dinersClub
        case "jcb": return CardBrandArt.jcb
        case "unionpay": return CardBrandArt.unionPay
        case "maestro": return CardBrandArt.mastercard(left: 0xEB001B, right: 0x00A2E5, centre: 0x7375CF, card: 0xFFFFFF)
        default: return CardBrandArt.generic
        }
    }
}

/// Draws a layer list on the `2 7 28 18` canvas.
struct CardBrandArtwork: View {
    let layers: [CardBrandArt.Layer]
    let fallbackColor: Color

    var body: some View {
        ZStack {
            ForEach(Array(layers.enumerated()), id: \.offset) { _, layer in
                SVGShape(element: layer.element, viewBox: CardBrandArt.viewBox)
                    .fill(color(layer.fill))
                    .opacity(layer.opacity)
            }
        }
    }

    private func color(_ fill: CardBrandArt.Fill) -> Color {
        switch fill {
        case .hex(let hex): return Color(hex: hex)
        case .fallback: return fallbackColor
        }
    }
}

/// A bank's own logo. These SVGs are drawn on the same 32 x 32 canvas as the card marks
/// with the badge inset at 2,7 (28 x 18), so the whole canvas is scaled by 32/28 and
/// centred in a card-sized box: the badge lands at exactly the card-mark size. A broken
/// image falls back to the bank badge.
private struct BankLogo: View {
    let url: URL
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let canvas = width * 32 / 28
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit().frame(width: canvas, height: canvas)
            case .failure:
                CardBrandArtwork(layers: CardBrandArt.bank, fallbackColor: .gray)
            default:
                CardBrandArtwork(layers: CardBrandArt.bank, fallbackColor: .gray).opacity(0)
            }
        }
        .frame(width: width, height: height)
    }
}

/// CardBrandIcon's behaviour (RN `CardBrand`): the mark, or `fallback` when no brand
/// resolves, with the web's 150 ms scale / opacity blip on every change.
public struct CardBrandView<Fallback: View>: View {
    public let brand: String?
    public let bin: String?
    public let size: CGFloat
    public let fallbackColor: Color
    private let fallback: Fallback

    @State private var blip: CGFloat = 1

    public init(brand: String?, bin: String? = nil, size: CGFloat = 30, fallbackColor: Color = Color(hex: 0x6E6E6E),
                @ViewBuilder fallback: () -> Fallback) {
        self.brand = brand
        self.bin = bin
        self.size = size
        self.fallbackColor = fallbackColor
        self.fallback = fallback()
    }

    private var key: String { "\(CardBrandResolver.normalize(brand))|\(bin ?? "")" }

    public var body: some View {
        Group {
            if CardBrandResolver.hasBrandArt(brand: brand, bin: bin) {
                CardBrandMark(brand: brand, size: size, bin: bin, fallbackColor: fallbackColor)
            } else {
                fallback
            }
        }
        .opacity(0.7 + 0.3 * blip)
        .scaleEffect(0.95 + 0.05 * blip)
        .onChange(of: key) { _ in
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { blip = 0 }
            withAnimation(.linear(duration: 0.15)) { blip = 1 }
        }
    }
}

/// Overlapping stack of the brands we accept (web / RN AcceptedBrandStack): each mark
/// after the first shifted -8, z-order first on top. The placeholder before a BIN
/// identifies the card.
public struct AcceptedBrandStack: View {
    public static let acceptedBrands = ["visa", "mastercard", "amex", "discover"]

    public let size: CGFloat
    public let brands: [String]

    public init(size: CGFloat = 22, brands: [String] = AcceptedBrandStack.acceptedBrands) {
        self.size = size
        self.brands = brands
    }

    public var body: some View {
        HStack(spacing: -8) {
            ForEach(Array(brands.enumerated()), id: \.offset) { index, brand in
                CardBrandMark(brand: brand, size: size)
                    .zIndex(Double(brands.count - index))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Visa, Mastercard, American Express, Discover")
    }
}
