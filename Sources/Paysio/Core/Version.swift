import Foundation

/// Version and platform identifiers the SDK reports to Paysio.
///
/// Every request carries `X-Paysio-SDK: ios/<version>` (CONTRACT.md, intro) so the
/// backend can keep old SDKs working when the contract evolves.
public enum PaysioSDK {
    /// Semantic version of this SDK. Bump together with `Paysio.podspec`.
    public static let version = "0.1.0"

    /// Platform tag used in the `X-Paysio-SDK` header and `clientMetadata.platform`.
    public static let platform = "ios"

    /// Value of the `X-Paysio-SDK` request header, for example `ios/0.1.0`.
    public static var headerValue: String { "\(platform)/\(version)" }

    /// `clientMetadata.sdk` value, for example `ios/0.1.0`.
    public static var clientMetadataSDK: String { headerValue }
}
