import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Browser information the 3-D Secure server needs (CONTRACT.md section 4, step 3).
///
/// Collected from the hidden fingerprint web view so the issuer sees the real
/// device. The wire format is snake_case because that is what the backend's
/// `BrowserInfo` reads (`backend/src/lib/vgs-vault/three-ds.ts`).
public struct BrowserInfo: Sendable, Equatable {
    public var javaEnabled: Bool
    public var javascriptEnabled: Bool
    public var colorDepth: Int
    public var screenWidth: Int
    public var screenHeight: Int
    /// Minutes, as `Date().getTimezoneOffset()` returns in JavaScript.
    public var timezoneOffset: Int
    public var language: String
    public var userAgent: String

    public init(javaEnabled: Bool = false, javascriptEnabled: Bool = true, colorDepth: Int = 24,
                screenWidth: Int, screenHeight: Int, timezoneOffset: Int, language: String, userAgent: String) {
        self.javaEnabled = javaEnabled
        self.javascriptEnabled = javascriptEnabled
        self.colorDepth = colorDepth
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.timezoneOffset = timezoneOffset
        self.language = language
        self.userAgent = userAgent
    }

    /// Exactly the keys CONTRACT.md section 4 step 3 lists (snake_case). `userAgent`
    /// stays local for diagnostics; the backend does not read it.
    var requestBody: [String: Any] {
        [
            "java_enabled": javaEnabled,
            "javascript_enabled": javascriptEnabled,
            "color_depth": colorDepth,
            "screen_width": screenWidth,
            "screen_height": screenHeight,
            "tz_offset": timezoneOffset,
            "language": language,
        ]
    }
}

/// What the issuer sent back for a challenge (CONTRACT.md section 4, step 4).
public struct ThreeDSChallenge: Sendable, Equatable {
    /// Self-posting HTML to render as is.
    public let form: String?
    /// ACS URL to POST `creq` to (or to navigate to when `creq` is nil).
    public let url: String?
    public let creq: String?
    public let sessionData: String?

    public init(form: String?, url: String?, creq: String?, sessionData: String?) {
        self.form = form
        self.url = url
        self.creq = creq
        self.sessionData = sessionData
    }
}

/// The web views the state machine needs. `WKThreeDSWebHost` is the WebKit
/// implementation; tests inject a stub.
@MainActor
public protocol ThreeDSWebHost: AnyObject {
    /// Loads the device fingerprint HTML in a hidden web view for `duration`
    /// seconds, then returns the browser information read from that same view.
    /// Must not throw: on any failure return sensible defaults.
    func fingerprint(html: String, duration: TimeInterval) async -> BrowserInfo

    /// Presents the visible challenge. Returns once it is on screen. `onCancel`
    /// fires if the customer dismisses it.
    func presentChallenge(_ challenge: ThreeDSChallenge, onCancel: @escaping @Sendable () -> Void) async

    /// Removes the challenge from screen (approved, failed or timed out).
    func dismissChallenge() async
}

/// CONTRACT.md section 4 as a state machine.
///
/// preflight -> create-card -> init (fingerprint 3 s) -> authenticate
/// -> frictionless token | challenge (poll finish every 3 s, max 80) | skipped.
@MainActor
public final class PaysioThreeDS {
    public static let fingerprintDuration: TimeInterval = 3
    public static let pollInterval: TimeInterval = 3
    public static let maxPolls = 80

    private let client: PaysioClient
    private let session: PaysioSession
    private let host: ThreeDSWebHost
    private let onEvent: PaysioEventHandler?

    public init(client: PaysioClient, session: PaysioSession, host: ThreeDSWebHost, onEvent: PaysioEventHandler? = nil) {
        self.client = client
        self.session = session
        self.host = host
        self.onEvent = onEvent
    }

    /// Runs the full flow. Returns the `tds_` token to pass to the charge, or nil when
    /// 3DS is not required / was skipped by the server.
    public func authenticate(card: PaysioCardAlias, amountMajor: Double, email: String, billingCountry: String) async throws -> String? {
        let base: [String: Any] = [
            "workspaceId": session.workspaceId,
            "sandbox": session.sandbox,
        ]
        let identity: [String: Any] = [
            "panAlias": card.panAlias,
            "vaultBin": card.bin ?? NSNull(),
            "brand": card.brand ?? NSNull(),
            "expMonth": card.expMonth,
            "expYear": card.expYear,
            "billingCountry": billingCountry,
            "email": email,
            "last4": card.last4 ?? NSNull(),
        ]

        // 1. preflight
        let pre = try await post("api/vault/3ds/preflight", body: base.merging(identity) { $1 })
        if pre.bool("required") == false { return nil }

        onEvent?(.threeDsStart)

        // 2. create-card
        let created = try await post("api/vault/3ds/create-card", body: base.merging([
            "panAlias": card.panAlias, "expMonth": card.expMonth, "expYear": card.expYear,
        ]) { $1 })
        guard let cardRef = created.string("cardRef") else {
            throw PaysioError(code: .threeDsFailed, message: "Card verification could not start.")
        }
        let withRef = base.merging(["cardRef": cardRef]) { $1 }

        // 3. init + fingerprint (skip the 3 s wait when the HTML is null)
        let initResponse = try await post("api/vault/3ds/init", body: withRef)
        let transactionInfo = initResponse.object("transactionInfo") ?? [:]
        var browser = BrowserInfo.fallback()
        if let html = initResponse.string("deviceFingerprintingHtml"), !html.isEmpty {
            browser = await host.fingerprint(html: html, duration: PaysioThreeDS.fingerprintDuration)
        }

        // 4. authenticate
        let redirectUrl = client.apiBase.appendingPathComponent("api/vault/3ds/challenge-return").absoluteString
        var authBody = withRef.merging(identity) { $1 }
        authBody["amount"] = amountMajor
        authBody["currency"] = session.currency
        authBody["browser"] = browser.requestBody
        authBody["redirectUrl"] = redirectUrl
        authBody["transactionInfo"] = transactionInfo
        authBody["channel"] = "app"
        let auth = try await post("api/vault/3ds/authenticate", body: authBody)

        if auth.bool("skipped") == true { return nil }

        let challengeRequired = auth.bool("challengeRequired") == true || auth.string("status") == "CHALLENGE_REQUIRED"
        if !challengeRequired {
            return try finalize(auth)
        }

        // 5. challenge + poll
        let challengeJSON = auth.object("challenge") ?? [:]
        let challenge = ThreeDSChallenge(
            form: challengeJSON.string("form"),
            url: challengeJSON.string("url"),
            creq: challengeJSON.string("creq"),
            sessionData: challengeJSON.string("session_data") ?? challengeJSON.string("sessionData")
        )
        guard challenge.form != nil || challenge.url != nil else {
            throw PaysioError(code: .threeDsFailed, message: "Card verification requires a challenge, but the issuer returned no challenge content.")
        }

        onEvent?(.threeDsChallenge)
        let cancelled = CancelFlag()
        await host.presentChallenge(challenge) { cancelled.set() }
        defer { Task { await self.host.dismissChallenge() } }

        let finishBody = withRef.merging(["amount": amountMajor, "transactionInfo": transactionInfo]) { $1 }
        for _ in 0..<PaysioThreeDS.maxPolls {
            try await Task.sleep(nanoseconds: UInt64(PaysioThreeDS.pollInterval * 1_000_000_000))
            if cancelled.isSet {
                onEvent?(.threeDsResult(approved: false))
                throw PaysioError(code: .threeDsCancelled, message: "Card verification was cancelled.")
            }
            let finish = try await post("api/vault/3ds/finish", body: finishBody)
            // CONTRACT.md section 4 step 5: stop on a string `threeDsToken` (approved) or on
            // `challengeRequired: false` without a token (failed). Otherwise keep polling.
            if let token = finish.string("threeDsToken"), !token.isEmpty {
                return try finalize(finish)
            }
            if finish.bool("challengeRequired") == false {
                return try finalize(finish) // throws three_ds_failed with the ACS reason
            }
        }
        onEvent?(.threeDsResult(approved: false))
        throw PaysioError(code: .threeDsTimeout, message: "Card verification did not complete in time. Please try again.")
    }

    /// 3DS call with the contract's mapping: a `502 { error, detail }` (VGS failed) and any
    /// other non-2xx that is not a rate limit becomes `three_ds_failed`.
    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let response = try await client.post(path, body: body)
        guard response.isSuccess else {
            let mapped = PaysioClient.mapFailure(response)
            if mapped.code == .rateLimited || mapped.code == .network { throw mapped }
            let message = response.json.string("error") ?? "Card verification failed."
            throw PaysioError(code: .threeDsFailed, message: message, httpStatus: response.status)
        }
        return response.json
    }

    /// Approved statuses per the hosted checkout (`paysio-storefront.js`).
    private static let approvedStatuses: Set<String> = ["APPROVED", "ATTEMPTS_PERFORMED", "Y", "A"]

    private func finalize(_ result: [String: Any]) throws -> String {
        let status = result.string("status") ?? ""
        guard PaysioThreeDS.approvedStatuses.contains(status) || result.bool("approved") == true else {
            onEvent?(.threeDsResult(approved: false))
            // `message` carries the ACS reason on a failed challenge.
            let message = status.isEmpty
                ? "Card verification did not complete. Please try again."
                : (result.string("message").map { "Card verification was declined: \($0)" }
                    ?? "Card verification was declined. Please use a different card.")
            throw PaysioError(code: .threeDsFailed, message: message)
        }
        guard let token = result.string("threeDsToken"), !token.isEmpty else {
            onEvent?(.threeDsResult(approved: false))
            throw PaysioError(code: .threeDsFailed, message: "Card verification did not complete. Please try again.")
        }
        onEvent?(.threeDsResult(approved: true))
        return token
    }
}

/// Thread-safe one-way flag flipped by the challenge's Cancel button.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

extension BrowserInfo {
    /// Used when the fingerprint HTML is missing or the web view failed.
    static func fallback() -> BrowserInfo {
        #if canImport(UIKit)
        let bounds = UIScreen.main.nativeBounds
        let width = Int(bounds.width), height = Int(bounds.height)
        #else
        let width = 390, height = 844
        #endif
        return BrowserInfo(
            screenWidth: width, screenHeight: height,
            timezoneOffset: -TimeZone.current.secondsFromGMT() / 60,
            language: Locale.preferredLanguages.first ?? "en-US",
            userAgent: "Paysio iOS SDK/\(PaysioSDK.version)"
        )
    }
}
