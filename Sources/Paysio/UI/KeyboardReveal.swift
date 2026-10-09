import SwiftUI
import UIKit

/// Keeps whatever the customer is typing into clear of the keyboard (RN
/// `ui/KeyboardReveal.tsx`).
///
/// Shrinking the page above the keyboard is not enough on its own: the scroll offset
/// does not move, so a field low on the page ends up on the keyboard's edge and the
/// address suggestion list under the street field ends up behind it. This scrolls the
/// host just far enough that the target's bottom edge sits `gap` (24) above the
/// keyboard, and does it inside the keyboard's own animation: `keyboardWillShow`
/// carries the final frame, duration and curve, so the page slides up together with
/// the keyboard instead of after it.
///
/// `PaysioPaymentSheet` sets this up itself. A host that renders the fields inside its
/// own `ScrollView` adds `.paysioKeyboardReveal()` to the scroll view's content (or
/// uses `PaysioScrollView`). Without either, every call is a no-op.
@MainActor
public final class PaysioKeyboardReveal: NSObject, ObservableObject {
    public nonisolated static let defaultGap: CGFloat = 24
    /// A reveal asked for just before the keyboard finished opening is retried when it lands.
    private static let pendingWindow: TimeInterval = 1.2

    public enum Target: Equatable {
        /// Whichever text input has focus (VGS fields included, they wrap a UITextField).
        case firstResponder
        /// A view registered with `.paysioRevealAnchor(id)` (e.g. street field + suggestions).
        case anchor(String)
    }

    weak var scrollView: UIScrollView?
    private var anchors: [String: WeakView] = [:]
    private var keyboardTop: CGFloat?
    private var pending: (target: Target, gap: CGFloat, at: Date)?

    public override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                           name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    /// Bring `target` clear of the keyboard. Before the keyboard is up the request waits
    /// for `keyboardWillShow`; with the keyboard up it runs after layout settles.
    public func reveal(_ target: Target = .firstResponder, gap: CGFloat = PaysioKeyboardReveal.defaultGap) {
        let request = (target: target, gap: gap, at: Date())
        pending = request
        // Two run-loop turns so a list that just appeared has laid out.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async {
                guard let self, let pending = self.pending, pending.at == request.at, let top = self.keyboardTop else { return }
                self.pending = nil
                self.scroll(to: target, gap: gap, keyboardTop: top, duration: 0.25, curve: .curveEaseInOut)
            }
        }
    }

    func register(anchor id: String, view: UIView) { anchors[id] = WeakView(view: view) }

    // MARK: Keyboard

    @objc private func keyboardWillShow(_ note: Notification) {
        guard let info = note.userInfo,
              let endFrame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? 0.25
        let curveRaw = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue ?? 7
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        guard let window = scrollView?.window else { return }
        let frame = window.convert(endFrame, from: window.screen.coordinateSpace)
        let top = min(frame.minY, window.bounds.height)
        keyboardTop = top
        if let p = pending, Date().timeIntervalSince(p.at) < Self.pendingWindow {
            pending = nil
            scroll(to: p.target, gap: p.gap, keyboardTop: top, duration: duration, curve: options)
            return
        }
        scroll(to: .firstResponder, gap: Self.defaultGap, keyboardTop: top, duration: duration, curve: options)
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        keyboardTop = nil
    }

    // MARK: Scrolling

    private func scroll(to target: Target, gap: CGFloat, keyboardTop: CGFloat, duration: TimeInterval,
                        curve: UIView.AnimationOptions) {
        guard let scrollView, let window = scrollView.window, let view = view(for: target, in: scrollView) else { return }
        let rect = view.convert(view.bounds, to: window)
        let overlap = rect.maxY + gap - keyboardTop
        guard overlap > 1 else { return }
        // Never push the top of the target above the visible top of the scroll view.
        let visibleTop = scrollView.convert(scrollView.bounds, to: window).minY + scrollView.adjustedContentInset.top
        let shift = min(overlap, max(0, rect.minY - visibleTop))
        guard shift > 1 else { return }
        let offset = CGPoint(x: scrollView.contentOffset.x, y: scrollView.contentOffset.y + shift)
        UIView.animate(withDuration: duration, delay: 0, options: [curve, .beginFromCurrentState, .allowUserInteraction]) {
            scrollView.contentOffset = offset
        }
    }

    private func view(for target: Target, in root: UIView) -> UIView? {
        switch target {
        case .firstResponder:
            return Self.firstResponder(in: root)
        case .anchor(let id):
            guard let view = anchors[id]?.view, view.window != nil else { return Self.firstResponder(in: root) }
            return view
        }
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for sub in view.subviews {
            if let found = firstResponder(in: sub) { return found }
        }
        return nil
    }

    fileprivate struct WeakView {
        weak var view: UIView?
    }
}

// MARK: - Environment

private struct PaysioKeyboardRevealKey: EnvironmentKey {
    static let defaultValue: PaysioKeyboardReveal? = nil
}

public extension EnvironmentValues {
    /// The reveal coordinator of the enclosing Paysio scroll container, if any.
    var paysioKeyboardReveal: PaysioKeyboardReveal? {
        get { self[PaysioKeyboardRevealKey.self] }
        set { self[PaysioKeyboardRevealKey.self] = newValue }
    }
}

/// Finds the `UIScrollView` behind a SwiftUI `ScrollView` from inside its content.
private struct ScrollViewProbe: UIViewRepresentable {
    let reveal: PaysioKeyboardReveal

    func makeUIView(context: Context) -> ProbeView {
        let v = ProbeView()
        v.reveal = reveal
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: ProbeView, context: Context) { uiView.reveal = reveal }

    final class ProbeView: UIView {
        weak var reveal: PaysioKeyboardReveal?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attach()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if reveal?.scrollView == nil { attach() }
        }

        private func attach() {
            var v = superview
            while let current = v {
                if let scroll = current as? UIScrollView {
                    reveal?.scrollView = scroll
                    return
                }
                v = current.superview
            }
        }
    }
}

/// Registers a view as a reveal target (`PaysioKeyboardReveal.Target.anchor`).
private struct RevealAnchor: UIViewRepresentable {
    let id: String
    let reveal: PaysioKeyboardReveal?

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.isUserInteractionEnabled = false
        v.backgroundColor = .clear
        reveal?.register(anchor: id, view: v)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) { reveal?.register(anchor: id, view: uiView) }
}

private struct KeyboardRevealHost: ViewModifier {
    @StateObject private var reveal = PaysioKeyboardReveal()

    func body(content: Content) -> some View {
        content
            .background(ScrollViewProbe(reveal: reveal))
            .environment(\.paysioKeyboardReveal, reveal)
    }
}

private struct RevealAnchorModifier: ViewModifier {
    let id: String
    @Environment(\.paysioKeyboardReveal) private var reveal

    func body(content: Content) -> some View {
        content.background(RevealAnchor(id: id, reveal: reveal))
    }
}

public extension View {
    /// Apply to the CONTENT of your own `ScrollView` that hosts Paysio fields, so the
    /// focused field (and the address suggestions) stay clear of the keyboard.
    func paysioKeyboardReveal() -> some View { modifier(KeyboardRevealHost()) }

    /// Marks this view as a reveal target with the given id.
    func paysioRevealAnchor(_ id: String) -> some View { modifier(RevealAnchorModifier(id: id)) }
}

/// A `ScrollView` that provides the keyboard reveal for its own content (RN
/// `PaysioScrollView`). Used by the drop-in sheet; exported for custom layouts.
public struct PaysioScrollView<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        ScrollView { content.paysioKeyboardReveal() }
    }
}
