import SwiftUI

/// Minimal SwiftUI host for the Paysio Mobile SDK. Add this folder as an iOS App
/// target in Xcode and add the local `Paysio` package as a dependency.
@main
struct PaysioExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
