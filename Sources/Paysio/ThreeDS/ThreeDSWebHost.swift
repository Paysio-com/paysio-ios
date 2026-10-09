import Foundation
import UIKit
import WebKit

/// `WKWebView` implementation of `ThreeDSWebHost`.
///
/// - Fingerprint: a hidden 1 x 1 web view attached to the key window for 3 seconds,
///   then `evaluateJavaScript` reads the browser information from that same page.
/// - Challenge: a `.pageSheet` view controller with a white background, the title
///   "Verify your card" and a Cancel button, loading the issuer's HTML with
///   `loadHTMLString(_:baseURL:)`. Navigation is limited to https (and about:blank)
///   through `WKNavigationDelegate`.
///
/// JavaScript is enabled on these two web views only.
@MainActor
public final class WKThreeDSWebHost: NSObject, ThreeDSWebHost {
    private weak var presenter: UIViewController?
    private var fingerprintView: WKWebView?
    private var challengeController: ThreeDSChallengeViewController?

    /// - Parameter presenter: the view controller to present the challenge from.
    ///   Defaults to the top-most presented controller of the key window.
    public init(presenter: UIViewController? = nil) {
        self.presenter = presenter
        super.init()
    }

    // MARK: ThreeDSWebHost

    public func fingerprint(html: String, duration: TimeInterval) async -> BrowserInfo {
        let webView = WKThreeDSWebHost.makeWebView()
        webView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        webView.isHidden = true
        webView.isUserInteractionEnabled = false
        webView.navigationDelegate = self
        fingerprintView = webView
        defer {
            webView.removeFromSuperview()
            fingerprintView = nil
        }
        guard let window = WKThreeDSWebHost.keyWindow() else { return .fallback() }
        window.addSubview(webView)
        webView.loadHTMLString(html, baseURL: nil)

        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        let js = """
        JSON.stringify({
          java_enabled: false,
          javascript_enabled: true,
          color_depth: (window.screen && window.screen.colorDepth) || 24,
          screen_width: (window.screen && window.screen.width) || 0,
          screen_height: (window.screen && window.screen.height) || 0,
          tz_offset: new Date().getTimezoneOffset(),
          language: navigator.language || 'en-US',
          user_agent: navigator.userAgent || ''
        })
        """
        let result: Any? = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript(js) { value, _ in continuation.resume(returning: value) }
        }
        guard let string = result as? String, let data = string.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .fallback()
        }
        var info = BrowserInfo.fallback()
        info.colorDepth = json.int("color_depth") ?? info.colorDepth
        if let w = json.int("screen_width"), w > 0 { info.screenWidth = w }
        if let h = json.int("screen_height"), h > 0 { info.screenHeight = h }
        info.timezoneOffset = json.int("tz_offset") ?? info.timezoneOffset
        info.language = json.string("language") ?? info.language
        if let ua = json.string("user_agent"), !ua.isEmpty { info.userAgent = ua }
        return info
    }

    public func presentChallenge(_ challenge: ThreeDSChallenge, onCancel: @escaping @Sendable () -> Void) async {
        await dismissChallenge()
        let controller = ThreeDSChallengeViewController(challenge: challenge, onCancel: onCancel)
        challengeController = controller
        guard let host = presenter ?? WKThreeDSWebHost.topViewController() else { return }
        await withCheckedContinuation { continuation in
            host.present(controller, animated: true) { continuation.resume() }
        }
    }

    public func dismissChallenge() async {
        guard let controller = challengeController else { return }
        challengeController = nil
        guard controller.presentingViewController != nil else { return }
        await withCheckedContinuation { continuation in
            controller.dismiss(animated: true) { continuation.resume() }
        }
    }

    // MARK: Helpers

    static func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .white
        webView.isOpaque = true
        return webView
    }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    static func topViewController() -> UIViewController? {
        var top = keyWindow()?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// Allows https and about:blank only.
    static func isAllowed(_ url: URL?) -> Bool {
        guard let url else { return true }
        if url.absoluteString == "about:blank" { return true }
        return url.scheme?.lowercased() == "https"
    }
}

extension WKThreeDSWebHost: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(WKThreeDSWebHost.isAllowed(navigationAction.request.url) ? .allow : .cancel)
    }
}

/// The visible challenge sheet. White background on purpose: issuer pages assume a
/// light page and some paint transparent regions.
final class ThreeDSChallengeViewController: UIViewController, WKNavigationDelegate, UIAdaptivePresentationControllerDelegate {
    private let challenge: ThreeDSChallenge
    private let onCancel: @Sendable () -> Void
    private var webView: WKWebView!
    private var cancelled = false

    init(challenge: ThreeDSChallenge, onCancel: @escaping @Sendable () -> Void) {
        self.challenge = challenge
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .pageSheet
        isModalInPresentation = true
        presentationController?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        overrideUserInterfaceStyle = .light

        let title = UILabel()
        title.text = "Verify your card"
        title.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .black
        title.textAlignment = .center

        let cancel = UIButton(type: .system)
        cancel.setTitle("Cancel", for: .normal)
        cancel.titleLabel?.font = UIFont.systemFont(ofSize: 17)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let header = UIView()
        header.backgroundColor = .white
        [title, cancel].forEach { header.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }

        webView = WKThreeDSWebHost.makeWebView()
        webView.navigationDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        [header, webView].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        let separator = UIView()
        separator.backgroundColor = UIColor(white: 0.9, alpha: 1)
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),

            title.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            cancel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -16),
            cancel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            webView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        load()
    }

    private func load() {
        if let form = challenge.form, !form.isEmpty {
            webView.loadHTMLString(form, baseURL: nil)
        } else if let urlString = challenge.url, let url = URL(string: urlString) {
            if let creq = challenge.creq, !creq.isEmpty {
                // EMV 3DS challenge request: POST `creq` (and `threeDSSessionData`) to the ACS,
                // the same form paysio.js builds.
                webView.loadHTMLString(ThreeDSChallengeViewController.formHTML(action: urlString, creq: creq,
                                                                               sessionData: challenge.sessionData),
                                       baseURL: nil)
            } else {
                webView.load(URLRequest(url: url))
            }
        }
    }

    static func formHTML(action: String, creq: String, sessionData: String?) -> String {
        var inputs = "<input type=\"hidden\" name=\"creq\" value=\"\(escape(creq))\">"
        if let sessionData, !sessionData.isEmpty {
            inputs += "<input type=\"hidden\" name=\"threeDSSessionData\" value=\"\(escape(sessionData))\">"
        }
        return """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
        <body style="margin:0;background:#fff">
        <form id="f" method="POST" action="\(escape(action))">\(inputs)</form>
        <script>document.getElementById('f').submit();</script>
        </body></html>
        """
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    @objc private func cancelTapped() {
        guard !cancelled else { return }
        cancelled = true
        onCancel()
        dismiss(animated: true)
    }

    // Swipe-to-dismiss is blocked by `isModalInPresentation`; if a host overrides it,
    // treat the dismissal as a cancel.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard !cancelled else { return }
        cancelled = true
        onCancel()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(WKThreeDSWebHost.isAllowed(navigationAction.request.url) ? .allow : .cancel)
    }
}
