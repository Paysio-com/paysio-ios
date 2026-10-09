import SwiftUI

/// The Mynaui icons the SDK draws. Path data is copied verbatim from the React Native
/// SDK (`sdks/react-native/src/ui/Icon.tsx`, itself copied from @mynaui/icons-react);
/// do not hand-author new ones. Solid variants are filled; the directional and action
/// glyphs (chevron, plus, check) are stroked at Mynaui's 1.5 weight with round caps.
public enum PaysioIconName: String, Sendable, CaseIterable {
    case chevronDown = "chevron-down"
    case plus
    case check
    case creditCardSolid = "credit-card-solid"
    case creditCardPlusSolid = "credit-card-plus-solid"
    case bankSolid = "bank-solid"
    case lockSolid = "lock-solid"
    case mapPinSolid = "map-pin-solid"
    case userSolid = "user-solid"

    var paths: [String] {
        switch self {
        case .chevronDown:
            return ["m6 9 6 6 6-6"]
        case .plus:
            return ["M18 12h-6m0 0H6m6 0V6m0 6v6"]
        case .check:
            return ["m6 13.626 1.606 1.722c.886.95 1.329 1.424 1.825 1.574.436.131.9.096 1.315-.1.473-.224.852-.761 1.612-1.836L18 7"]
        case .creditCardSolid:
            return ["M17.83 4.25H6.17c-.534 0-.98 0-1.345.03-.38.03-.736.098-1.074.27a2.75 2.75 0 0 0-1.201 1.2c-.172.338-.24.694-.27 1.074-.03.365-.03.81-.03 1.345v7.66c0 .535 0 .98.03 1.345.03.38.098.736.27 1.073a2.75 2.75 0 0 0 1.201 1.203c.337.171.694.238 1.073.27.364.029.81.029 1.342.029h11.668c.533 0 .978 0 1.341-.03.38-.03.736-.098 1.073-.27a2.75 2.75 0 0 0 1.203-1.202c.171-.337.238-.693.27-1.072.029-.364.029-.809.029-1.342V8.166c0-.533 0-.978-.03-1.342-.03-.38-.098-.736-.27-1.073a2.75 2.75 0 0 0-1.202-1.201c-.337-.172-.694-.24-1.074-.27-.363-.03-.81-.03-1.343-.03M4.433 5.886c.09-.046.228-.088.515-.111.296-.024.68-.025 1.253-.025h11.6c.573 0 .957 0 1.252.025.287.023.424.065.515.111.236.12.427.312.547.546.046.09.088.228.111.515.024.295.025.679.025 1.25v.053H3.75V8.2c0-.572 0-.957.025-1.253.023-.287.065-.424.111-.515.12-.235.311-.426.546-.546M6 14.25h4a.75.75 0 0 1 0 1.5H6a.75.75 0 0 1 0-1.5"]
        case .creditCardPlusSolid:
            return ["M6.17 4.25h6.33a.75.75 0 0 1 0 1.5H6.2c-.572 0-.957 0-1.253.025-.287.023-.424.065-.515.111-.235.12-.426.311-.546.546-.046.09-.088.228-.111.515-.024.296-.025.68-.025 1.253v.05h8.75a.75.75 0 0 1 0 1.5H3.75v6.05c0 .573 0 .957.025 1.253.023.287.065.424.111.514.12.236.312.427.546.547.09.046.228.088.515.111.295.024.679.025 1.25.025h11.606c.571 0 .955 0 1.25-.025.287-.023.424-.065.514-.111.235-.12.427-.312.547-.547.046-.09.088-.227.111-.514.024-.295.025-.678.025-1.25V11a.75.75 0 0 1 1.5 0v4.834c0 .533 0 .978-.03 1.342-.03.38-.098.735-.27 1.072a2.75 2.75 0 0 1-1.202 1.203c-.337.171-.693.238-1.073.27-.363.029-.808.029-1.341.029H6.166c-.533 0-.978 0-1.342-.03-.38-.03-.736-.098-1.073-.27a2.75 2.75 0 0 1-1.201-1.202c-.172-.337-.24-.693-.27-1.073-.03-.364-.03-.81-.03-1.344V8.17c0-.534 0-.98.03-1.345.03-.38.098-.736.27-1.074a2.75 2.75 0 0 1 1.2-1.201c.338-.172.694-.24 1.074-.27.365-.03.81-.03 1.345-.03m11.83 0a.75.75 0 0 1 .75.75v1.75h1.75a.75.75 0 0 1 0 1.5h-1.75V10a.75.75 0 0 1-1.5 0V8.25H15.5a.75.75 0 0 1 0-1.5h1.75V5a.75.75 0 0 1 .75-.75M5.25 15a.75.75 0 0 1 .75-.75h4a.75.75 0 0 1 0 1.5H6a.75.75 0 0 1-.75-.75"]
        case .bankSolid:
            return ["M12.784 2.436a1.74 1.74 0 0 0-1.568 0L3.452 6.344c-1.64.825-1.074 3.327.784 3.327H6.25v7.579H4.5a2.25 2.25 0 0 0 0 4.5h15a2.25 2.25 0 0 0 0-4.5h-1.75V9.67h2.014c1.858 0 2.423-2.501.784-3.326zM7.75 17.25V9.67h3.5v7.58zm5 0V9.67h3.5v7.58z"]
        case .lockSolid:
            return ["M9.572 4.904c.51-.703 1.28-1.154 2.428-1.154s1.919.45 2.428 1.154c.532.736.822 1.813.822 3.096v1.25h-6.5V8c0-1.283.29-2.36.822-3.096M16.75 9.25V8c0-1.478-.33-2.901-1.107-3.975-.8-1.107-2.03-1.775-3.643-1.775s-2.842.668-3.643 1.775C7.58 5.099 7.25 6.522 7.25 8v1.25h-.58c-.535 0-.98 0-1.345.03-.38.031-.736.098-1.073.27a2.75 2.75 0 0 0-1.202 1.202c-.172.337-.24.694-.27 1.074-.03.364-.03.81-.03 1.344v4.66c0 .535 0 .98.03 1.345.03.38.098.737.27 1.074a2.75 2.75 0 0 0 1.202 1.202c.337.172.693.239 1.073.27.365.03.81.03 1.345.03h10.66c.535 0 .98 0 1.345-.03.38-.031.736-.098 1.073-.27a2.75 2.75 0 0 0 1.202-1.202c.172-.337.24-.694.27-1.074.03-.364.03-.81.03-1.344V13.17c0-.534 0-.98-.03-1.344-.03-.38-.098-.737-.27-1.074a2.75 2.75 0 0 0-1.2-1.202c-.338-.172-.694-.239-1.074-.27-.365-.03-.81-.03-1.345-.03z"]
        case .mapPinSolid:
            return [
                "M12 8.75a1.25 1.25 0 1 0 0 2.5 1.25 1.25 0 0 0 0-2.5",
                "M18.227 3.9A8.68 8.68 0 0 0 12 1.25c-2.34 0-4.579.956-6.227 2.65-3.03 3.117-3.012 6.85-1.612 10.199 1.386 3.312 4.143 6.335 6.794 8.304a1.75 1.75 0 0 0 2.09 0c2.65-1.969 5.408-4.992 6.794-8.304 1.4-3.348 1.418-7.082-1.612-10.199M12 12.75a2.75 2.75 0 1 1 0-5.5 2.75 2.75 0 0 1 0 5.5",
            ]
        case .userSolid:
            return ["M12 12.75c3.942 0 7.987 2.563 8.249 7.712a.75.75 0 0 1-.71.787c-2.08.106-11.713.171-15.077 0a.75.75 0 0 1-.711-.787C4.013 15.314 8.058 12.75 12 12.75m0-9a3.75 3.75 0 1 0 0 7.5 3.75 3.75 0 0 0 0-7.5"]
        }
    }

    var filled: Bool {
        switch self {
        case .chevronDown, .plus, .check: return false
        default: return true
        }
    }
}

/// One Mynaui icon on its 24 x 24 canvas, like RN `<Icon name size color strokeWidth />`.
public struct PaysioIcon: View {
    public let name: PaysioIconName
    public let size: CGFloat
    public let color: Color
    public let strokeWidth: CGFloat

    /// Mynaui's own stroke weight (the web icons render at 1.5).
    public static let defaultStroke: CGFloat = 1.5
    private static let viewBox = CGRect(x: 0, y: 0, width: 24, height: 24)

    public init(_ name: PaysioIconName, size: CGFloat = 20, color: Color = .black, strokeWidth: CGFloat = PaysioIcon.defaultStroke) {
        self.name = name
        self.size = size
        self.color = color
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        let scale = size / 24
        ZStack {
            ForEach(Array(name.paths.enumerated()), id: \.offset) { _, d in
                if name.filled {
                    SVGShape(element: .path(d), viewBox: Self.viewBox).fill(color)
                } else {
                    SVGShape(element: .path(d), viewBox: Self.viewBox)
                        .stroke(color, style: StrokeStyle(lineWidth: strokeWidth * scale, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
