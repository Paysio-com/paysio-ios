import SwiftUI

/// A small SVG path-data parser that turns a `d` attribute into a SwiftUI `Path`.
///
/// Every glyph the SDK draws (card brand marks, Mynaui icons) is the exact path data
/// from the React Native SDK, so nothing here is hand drawn. Supported:
/// - commands M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z, absolute and relative;
/// - implicit repeated commands (extra coordinate pairs after M are line-tos);
/// - compact number syntax: `-.897-2`, `1.343,3`, `.895.895`, exponents;
/// - packed arc flags (`a1 1 0 01.2.3`).
///
/// Malformed data stops the parse at the first bad token and keeps what was drawn so far.
enum SVGPathParser {
    private static let cache = SVGPathCache()

    /// Parsed path in the data's own coordinate space. Cached by string.
    static func path(_ d: String) -> Path {
        if let hit = cache.get(d) { return hit }
        let parsed = parse(d)
        cache.set(d, parsed)
        return parsed
    }

    static func parse(_ d: String) -> Path {
        var scanner = Scanner(Array(d.utf8))
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: UInt8 = 0

        while true {
            scanner.skipSeparators()
            guard let c = scanner.peek() else { break }
            if Scanner.isCommand(c) {
                command = c
                scanner.advance()
            } else if command == 0 || command == UInt8(ascii: "Z") || command == UInt8(ascii: "z") {
                // Numbers with no command to repeat: stop.
                break
            }

            let relative = command >= UInt8(ascii: "a")
            let origin = relative ? current : .zero
            var nextCubic: CGPoint?
            var nextQuad: CGPoint?

            switch command {
            case UInt8(ascii: "M"), UInt8(ascii: "m"):
                guard let p = scanner.point() else { return path }
                let target = CGPoint(x: origin.x + p.x, y: origin.y + p.y)
                path.move(to: target)
                current = target
                subpathStart = target
                // Further pairs are implicit line-tos.
                command = relative ? UInt8(ascii: "l") : UInt8(ascii: "L")
            case UInt8(ascii: "L"), UInt8(ascii: "l"):
                guard let p = scanner.point() else { return path }
                let target = CGPoint(x: origin.x + p.x, y: origin.y + p.y)
                path.addLine(to: target)
                current = target
            case UInt8(ascii: "H"), UInt8(ascii: "h"):
                guard let x = scanner.number() else { return path }
                let target = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: target)
                current = target
            case UInt8(ascii: "V"), UInt8(ascii: "v"):
                guard let y = scanner.number() else { return path }
                let target = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: target)
                current = target
            case UInt8(ascii: "C"), UInt8(ascii: "c"):
                guard let c1 = scanner.point(), let c2 = scanner.point(), let p = scanner.point() else { return path }
                let control1 = CGPoint(x: origin.x + c1.x, y: origin.y + c1.y)
                let control2 = CGPoint(x: origin.x + c2.x, y: origin.y + c2.y)
                let target = CGPoint(x: origin.x + p.x, y: origin.y + p.y)
                path.addCurve(to: target, control1: control1, control2: control2)
                nextCubic = control2
                current = target
            case UInt8(ascii: "S"), UInt8(ascii: "s"):
                guard let c2 = scanner.point(), let p = scanner.point() else { return path }
                let control1 = lastCubicControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let control2 = CGPoint(x: origin.x + c2.x, y: origin.y + c2.y)
                let target = CGPoint(x: origin.x + p.x, y: origin.y + p.y)
                path.addCurve(to: target, control1: control1, control2: control2)
                nextCubic = control2
                current = target
            case UInt8(ascii: "Q"), UInt8(ascii: "q"):
                guard let c1 = scanner.point(), let p = scanner.point() else { return path }
                let control = CGPoint(x: origin.x + c1.x, y: origin.y + c1.y)
                let target = CGPoint(x: origin.x + p.x, y: origin.y + p.y)
                path.addQuadCurve(to: target, control: control)
                nextQuad = control
                current = target
            case UInt8(ascii: "T"), UInt8(ascii: "t"):
                guard let p = scanner.point() else { return path }
                let control = lastQuadControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let target = CGPoint(x: origin.x + p.x, y: origin.y + p.y)
                path.addQuadCurve(to: target, control: control)
                nextQuad = control
                current = target
            case UInt8(ascii: "A"), UInt8(ascii: "a"):
                guard let rx = scanner.number(), let ry = scanner.number(), let rotation = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(), let p = scanner.point() else { return path }
                let target = CGPoint(x: origin.x + p.x, y: origin.y + p.y)
                addArc(to: &path, from: current, to: target, rx: rx, ry: ry, rotationDegrees: rotation,
                       largeArc: large, sweep: sweep)
                current = target
            case UInt8(ascii: "Z"), UInt8(ascii: "z"):
                path.closeSubpath()
                current = subpathStart
            default:
                return path
            }
            lastCubicControl = nextCubic
            lastQuadControl = nextQuad
        }
        return path
    }

    /// Endpoint arc to cubic Beziers (SVG 1.1 implementation notes, F.6.5 / F.6.6).
    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                               rotationDegrees: CGFloat, largeArc: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            path.addLine(to: p1)
            return
        }
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx2 = (p0.x - p1.x) / 2
        let dy2 = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : sqrt(max(0, num / den))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = coef * -ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2) - 1e-9)))
        let step = delta / CGFloat(segments)
        let t = 4.0 / 3.0 * tan(step / 4)

        func point(_ a: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(a) * cosPhi - ry * sin(a) * sinPhi,
                    y: cy + rx * cos(a) * sinPhi + ry * sin(a) * cosPhi)
        }
        func derivative(_ a: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(a) * cosPhi - ry * cos(a) * sinPhi,
                    y: -rx * sin(a) * sinPhi + ry * cos(a) * cosPhi)
        }
        var a1 = theta1
        for i in 0..<segments {
            let a2 = a1 + step
            let start = point(a1)
            let end = i == segments - 1 ? p1 : point(a2)
            let d1 = derivative(a1)
            let d2 = derivative(a2)
            path.addCurve(to: end,
                          control1: CGPoint(x: start.x + t * d1.x, y: start.y + t * d1.y),
                          control2: CGPoint(x: end.x - t * d2.x, y: end.y - t * d2.y))
            a1 = a2
        }
    }

    // MARK: - Tokenizer

    private struct Scanner {
        let bytes: [UInt8]
        var i = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        func peek() -> UInt8? { i < bytes.count ? bytes[i] : nil }
        mutating func advance() { i += 1 }

        static func isCommand(_ c: UInt8) -> Bool {
            switch c {
            case UInt8(ascii: "M"), UInt8(ascii: "m"), UInt8(ascii: "L"), UInt8(ascii: "l"),
                 UInt8(ascii: "H"), UInt8(ascii: "h"), UInt8(ascii: "V"), UInt8(ascii: "v"),
                 UInt8(ascii: "C"), UInt8(ascii: "c"), UInt8(ascii: "S"), UInt8(ascii: "s"),
                 UInt8(ascii: "Q"), UInt8(ascii: "q"), UInt8(ascii: "T"), UInt8(ascii: "t"),
                 UInt8(ascii: "A"), UInt8(ascii: "a"), UInt8(ascii: "Z"), UInt8(ascii: "z"):
                return true
            default:
                return false
            }
        }

        private static func isDigit(_ c: UInt8) -> Bool { c >= UInt8(ascii: "0") && c <= UInt8(ascii: "9") }

        mutating func skipSeparators() {
            while i < bytes.count {
                switch bytes[i] {
                case UInt8(ascii: " "), UInt8(ascii: ","), UInt8(ascii: "\n"), UInt8(ascii: "\t"), UInt8(ascii: "\r"):
                    i += 1
                default:
                    return
                }
            }
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let start = i
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") { i += 1 }
            var sawDigit = false
            var sawDot = false
            while i < bytes.count {
                let c = bytes[i]
                if Scanner.isDigit(c) {
                    sawDigit = true
                    i += 1
                } else if c == UInt8(ascii: "."), !sawDot {
                    sawDot = true
                    i += 1
                } else {
                    break
                }
            }
            guard sawDigit else {
                i = start
                return nil
            }
            if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                var j = i + 1
                if j < bytes.count, bytes[j] == UInt8(ascii: "-") || bytes[j] == UInt8(ascii: "+") { j += 1 }
                if j < bytes.count, Scanner.isDigit(bytes[j]) {
                    i = j
                    while i < bytes.count, Scanner.isDigit(bytes[i]) { i += 1 }
                }
            }
            guard let text = String(bytes: bytes[start..<i], encoding: .ascii), let value = Double(text) else {
                i = start
                return nil
            }
            return CGFloat(value)
        }

        mutating func point() -> CGPoint? {
            let save = i
            guard let x = number(), let y = number() else {
                i = save
                return nil
            }
            return CGPoint(x: x, y: y)
        }

        /// Arc flags are a single `0` or `1` and may be packed against the next token.
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < bytes.count else { return nil }
            switch bytes[i] {
            case UInt8(ascii: "0"): i += 1; return false
            case UInt8(ascii: "1"): i += 1; return true
            default: return nil
            }
        }
    }
}

/// Thread-safe string -> Path cache; the glyph set is small and fixed.
private final class SVGPathCache: @unchecked Sendable {
    private var storage: [String: Path] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> Path? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ key: String, _ value: Path) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }
}

/// One element of a drawing on an SVG canvas: a path or a rounded rect.
enum SVGElement {
    case path(String)
    case rect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, rx: CGFloat)

    var path: Path {
        switch self {
        case .path(let d):
            return SVGPathParser.path(d)
        case let .rect(x, y, width, height, rx):
            let rect = CGRect(x: x, y: y, width: width, height: height)
            if rx > 0 {
                return Path(roundedRect: rect, cornerSize: CGSize(width: rx, height: rx), style: .circular)
            }
            return Path(rect)
        }
    }
}

/// Draws an element from `viewBox` coordinates into the view's frame with SVG's
/// default `preserveAspectRatio="xMidYMid meet"`.
struct SVGShape: Shape {
    let element: SVGElement
    let viewBox: CGRect

    func path(in rect: CGRect) -> Path {
        element.path.applying(SVGShape.transform(viewBox: viewBox, into: rect))
    }

    static func scale(viewBox: CGRect, into rect: CGRect) -> CGFloat {
        guard viewBox.width > 0, viewBox.height > 0 else { return 1 }
        return min(rect.width / viewBox.width, rect.height / viewBox.height)
    }

    static func transform(viewBox: CGRect, into rect: CGRect) -> CGAffineTransform {
        let s = scale(viewBox: viewBox, into: rect)
        let tx = rect.minX + (rect.width - viewBox.width * s) / 2 - viewBox.minX * s
        let ty = rect.minY + (rect.height - viewBox.height * s) / 2 - viewBox.minY * s
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty)
    }
}
