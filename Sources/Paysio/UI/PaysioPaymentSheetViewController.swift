import SwiftUI
import UIKit

/// UIKit host for `PaysioPaymentSheet`. Present it modally or push it:
///
/// ```swift
/// let vc = PaysioPaymentSheetViewController(sessionSlug: slug,
///     onSuccess: { result in /* ... */ },
///     onError: { error in /* ... */ })
/// present(vc, animated: true)
/// ```
public final class PaysioPaymentSheetViewController: UIHostingController<AnyView> {
    public init(
        sessionSlug: String,
        apiBase: URL = PaysioClient.defaultAPIBase,
        theme: PaysioTheme = .auto,
        customer: PaysioCustomer = .empty,
        billingAddress: PaysioAddress = .empty,
        savedAddresses: [PaysioSavedAddress] = [],
        savedMethods: [PaysioSavedMethod] = [],
        savedMethodAuthorizer: PaysioSavedMethodAuthorizer? = nil,
        appId: String? = Bundle.main.bundleIdentifier,
        disableAddressSuggestions: Bool = false,
        sheetComponents: PaysioSheetComponents? = nil,
        onEvent: PaysioEventHandler? = nil,
        onSuccess: @escaping (PaysioPayResult) -> Void,
        onError: @escaping (PaysioError) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        let sheet = PaysioPaymentSheet(
            sessionSlug: sessionSlug, apiBase: apiBase, theme: theme, customer: customer,
            billingAddress: billingAddress, savedAddresses: savedAddresses, savedMethods: savedMethods,
            savedMethodAuthorizer: savedMethodAuthorizer, appId: appId,
            disableAddressSuggestions: disableAddressSuggestions, sheetComponents: sheetComponents, onEvent: onEvent,
            onSuccess: onSuccess, onError: onError, onCancel: onCancel)
        super.init(rootView: AnyView(sheet))
        modalPresentationStyle = .pageSheet
        if let sheetController = sheetPresentationController {
            sheetController.detents = [.large()]
            sheetController.prefersGrabberVisible = false
        }
    }

    @available(*, unavailable)
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
