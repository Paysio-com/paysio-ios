// swift-tools-version:5.9
//
// Paysio Mobile SDK for iOS.
//
// Build with: xcodebuild -scheme Paysio -destination 'generic/platform=iOS Simulator' build
// (Xcode 26+, see README.md). `swift build` cannot link UIKit/SwiftUI on macOS.

import PackageDescription

let package = Package(
    name: "Paysio",
    platforms: [
        // VGSCollectSDK 1.19+ requires iOS 16.
        .iOS(.v16),
    ],
    products: [
        .library(name: "Paysio", targets: ["Paysio"]),
    ],
    dependencies: [
        // VGS Collect iOS SDK. Product name `VGSCollectSDK` per the VGS docs:
        // "add the dependency https://github.com/verygoodsecurity/vgs-collect-ios.git
        //  in Xcode and choose the exact version. Then, select VGSCollectSDK".
        .package(url: "https://github.com/verygoodsecurity/vgs-collect-ios.git", from: "1.20.0"),
    ],
    targets: [
        .target(
            name: "Paysio",
            dependencies: [
                .product(name: "VGSCollectSDK", package: "vgs-collect-ios"),
            ],
            path: "Sources/Paysio"
        ),
    ]
)
