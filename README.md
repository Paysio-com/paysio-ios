# Paysio Mobile SDK for iOS

Take a card or a US bank account inside your app, run 3-D Secure, and complete a Paysio
checkout session without leaving the app. Card numbers go straight from the VGS secure
fields to the VGS vault over TLS; your servers and Paysio only ever see aliases.

- iOS 16+, SwiftUI and UIKit.
- Depends on `VGSCollectSDK` 1.20 (Swift Package Manager or CocoaPods).
- Build with Xcode 26 or newer. VGSCollectSDK 1.18 and later use Swift 6.2 isolated
  conformances (`@MainActor` on a protocol conformance), which Xcode 16 cannot compile.
- Same API shape as `@paysio/react-native` and `com.paysio:paysio-android`.

## Quickstart

### 1. Install

Swift Package Manager: add `https://github.com/Paysio-com/paysio-ios.git` and select the
`Paysio` product. CocoaPods:

```ruby
pod 'Paysio', '~> 0.1'
```

### 2. Create a checkout session on your server

Never put a secret key in the app. On your server:

```sh
curl -X POST https://api.paysio.com/v1/checkout-sessions \
  -H "Authorization: Bearer sk_live_..." \
  -H "Content-Type: application/json" \
  -d '{"line_items":[{"product_id":"prod_...","quantity":1}],"customer_email":"a@b.co"}'
```

A line item is either `{ "product_id": "...", "quantity": 1 }` or an ad-hoc
`{ "name": "...", "amount": 1999, "currency": "USD", "quantity": 1 }`. Hand the returned
`slug` (`api-...`) to the app. A payment link slug works too. A session is single-use:
after one successful charge it answers 404 (`session_expired`); create a new one.

### 3. Render the sheet

SwiftUI:

```swift
import Paysio

PaysioPaymentSheet(
    sessionSlug: slug,
    onSuccess: { result in print("paid", result.transactionId, result.orderLabel ?? "") },
    onError: { error in print(error.code, error.message) }
)
```

UIKit:

```swift
let vc = PaysioPaymentSheetViewController(sessionSlug: slug,
    onSuccess: { result in /* ... */ },
    onError: { error in /* ... */ })
present(vc, animated: true)
```

Custom layout: use `PaysioCardFields`, `PaysioBankFields`, `PaysioBillingAddress`,
`PaymentMethodPicker` and `ContactFields` yourself, then call
`PaysioPay(client:session:threeDSHost:).pay(source:customer:billingAddress:)` with the
alias from `PaysioCardFieldsController.tokenize()`.

### 4. Handle the result

`onSuccess` receives a `PaysioPayResult` with `status == .pendingSettlement`,
`transactionId`, `orderLabel` and `confirmationToken`. Confirm fulfilment from your
webhook, as on the web. `onError` receives a `PaysioError` with one of the codes:
`invalid_fields`, `billing_address_required`, `contact_required`, `three_ds_failed`,
`three_ds_cancelled`, `three_ds_timeout`, `declined` (with `declineCode`; the declined
transaction row exists, no money moved), `session_expired` (the session is inactive,
expired or already paid: create a new one), `session_invalid`, `rate_limited`, `network`,
`unknown` (with the `idempotencyKey`; retrying with it never double charges),
`vault_unavailable`, `not_configured`.

### 5. Test cards (sandbox)

| Card | Scenario |
|---|---|
| 4111 1111 1111 1111, 12/30, 123 | Plain purchase (with 3DS on, the sandbox ACS challenges this card) |
| 4147 4630 1111 0134 | 3DS frictionless |
| 4016 3600 0000 0493 | 3DS challenge (choose approve or deny) |
| Routing 490000018, account 24413815 | Bank account (NMI sandbox test account; any other account is refused with decline code 300) |

Sandbox sessions relax the Luhn check because the 3DS test cards are not Luhn-valid.
A 3DS challenge needs a public API host: VGS rejects a redirect URL on a local address.

### 6. Go live

Create sessions with your live secret key. Live sessions use the live VGS vault
automatically (`vaultConfig` in the session). Keep the SDK up to date.

## App Store rules

Physical goods and real-world services may be paid with card entry in the app (App
Review Guideline 3.1.3(e)). Digital goods consumed in the app must use In-App Purchase.
Do not use this SDK for digital goods.

## 3-D Secure

When the workspace has 3DS on, the SDK fingerprints the device in a hidden web view
(3 seconds) and, if the issuer asks, shows a white "Verify your card" sheet with the
challenge. Cancelling it reports `three_ds_cancelled` and charges nothing.

## Theming

`PaysioTheme(scheme: .auto | .light | .dark, colors:, darkColors:, fontFamily:, radius:)`
with the tokens `primary`, `foreground`, `mutedForeground`, `card`, `background`,
`secondary`, `border`, `input`, `rowHover`, `ring`, `destructive`. Apply with
`.paysioTheme(theme)` or pass `theme:` to the sheet.

## PCI and privacy

Card data is entered into VGS-provided fields and transmitted directly to VGS's PCI DSS
Level 1 environment. It is not transmitted to or stored by your servers or Paysio's. The
app remains the point of entry: keep the SDK current, do not screenshot or record the
checkout screen, and the CVC field uses secure text entry.

Privacy manifest: `VGSCollectSDK` bundles its own `PrivacyInfo.xcprivacy`. The Paysio
package declares nothing extra (no tracking, no required-reason APIs).

Analytics: VGS collects integration analytics by default. Opt out with
`VGSAnalyticsClient.shared.shouldCollectAnalytics = false` before creating the sheet.

## Example app

`Example/` is a minimal SwiftUI app: API base presets, "New sandbox session" (calls
`POST /api/dev/mobile-session`, which answers `201 { slug, url, sandbox, expires_at }` and
exists only when the backend runs with `MOBILE_SDK_DEV_WORKSPACE_ID`), the test card list
and the sheet.

```sh
cd sdks/ios
xcodebuild -scheme Paysio -destination 'generic/platform=iOS Simulator' build
cd Example && xcodegen   # generates PaysioExample.xcodeproj from project.yml (not tracked)
```

`swift build` does not work for this package: it links UIKit, SwiftUI and WebKit, which
are iOS-only. Maestro UI flows for the test scenarios live in `Example/maestro/`
(`maestro test -e SLUG=<payment link or session slug> Example/maestro/d1_plain_purchase.yaml`).

## Changelog

- **0.1.0**: first release. Card and US bank account entry with VGS secure fields,
  3-D Secure, the drop-in sheet, street address suggestions (no Google key in the app),
  the focused field kept above the keyboard in step with its animation, searchable
  country and state sheets, and the Paysio card brand marks.

## License

MIT.
