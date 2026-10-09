import SwiftUI
import Paysio

/// Example: pick an API base, mint a sandbox session, open the sheet.
///
/// "New sandbox session" calls `POST /api/dev/mobile-session` (CONTRACT.md section 7), a
/// sandbox-only helper that exists when the backend runs with
/// `MOBILE_SDK_DEV_WORKSPACE_ID`, so no secret key lives in the app. It answers
/// `201 { slug, url, sandbox, expires_at }`. Paste a slug from your own server otherwise.
struct ContentView: View {
    enum Preset: String, CaseIterable, Identifiable {
        case staging = "https://staging.paysio.com"
        case production = "https://api.paysio.com"
        case local = "http://127.0.0.1:3000"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .staging: return "Staging"
            case .production: return "Production"
            case .local: return "Local"
            }
        }
    }

    @State private var preset: Preset = .staging
    @State private var slug: String = ""
    @State private var status: String = ""
    @State private var showSheet = false
    @State private var dark = false
    @State private var events: [String] = []
    @FocusState private var slugFocused: Bool

    private var apiBase: URL { URL(string: preset.rawValue)! }

    var body: some View {
        NavigationStack {
            Form {
                Section("API") {
                    Picker("Base", selection: $preset) {
                        ForEach(Preset.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Session slug (api-...)", text: $slug)
                        .focused($slugFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("New sandbox session") { Task { await newSession() } }
                    Toggle("Dark theme", isOn: $dark)
                }

                Section("Test cards (sandbox)") {
                    ForEach(testCards, id: \.0) { card in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(card.0).font(.system(.body, design: .monospaced))
                            Text(card.1).font(.footnote).foregroundColor(.secondary)
                        }
                    }
                    Text("Bank (NMI sandbox): routing 490000018, account 24413815, Checking, Personal")
                        .font(.footnote).foregroundColor(.secondary)
                }

                Section {
                    Button("Open payment sheet") {
                        slugFocused = false
                        showSheet = true
                    }
                        .disabled(slug.isEmpty)
                }

                if !status.isEmpty {
                    Section("Result") { Text(status) }
                }
                if !events.isEmpty {
                    Section("Events") {
                        ForEach(events.indices, id: \.self) { Text(events[$0]).font(.footnote) }
                    }
                }
            }
            .navigationTitle("Paysio SDK")
        }
        // Without this, focus is restored to the slug field when the sheet closes and the
        // keyboard pops back up.
        .onChange(of: showSheet) { open in
            if !open {
                slugFocused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .sheet(isPresented: $showSheet, onDismiss: { slugFocused = false }) {
            PaysioPaymentSheet(
                sessionSlug: slug,
                apiBase: apiBase,
                theme: dark ? .dark : .light,
                customer: PaysioCustomer(email: "buyer@example.com", firstName: "Test", lastName: "Buyer"),
                billingAddress: PaysioAddress(address1: "1 Main St", city: "Austin", state: "TX", postalCode: "78701", country: "US"),
                onEvent: { event in
                    Task { @MainActor in events.append(String(describing: event)) }
                },
                onSuccess: { result in
                    status = "Paid: \(result.orderLabel ?? result.transactionId) (\(result.status.rawValue))"
                    showSheet = false
                },
                onError: { error in
                    status = "Error \(error.code.rawValue): \(error.message)"
                },
                onCancel: { showSheet = false }
            )
        }
    }

    private let testCards: [(String, String)] = [
        ("4111 1111 1111 1111  12/30  123", "Plain purchase"),
        ("4147 4630 1111 0134  12/30  123", "3DS frictionless"),
        ("4016 3600 0000 0493  12/30  123", "3DS challenge (approve / deny)"),
        ("4111 1111 1111 1112", "Invalid number (Luhn)"),
    ]

    private func newSession() async {
        status = "Creating session..."
        do {
            var request = URLRequest(url: apiBase.appendingPathComponent("api/dev/mobile-session"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"amount":1999,"currency":"USD","name":"Mobile SDK test"}"#.utf8)
            let (data, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...201).contains(code),
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newSlug = json["slug"] as? String else {
                status = "Session helper answered \(code). Paste a slug instead."
                return
            }
            slug = newSlug
            let expires = (json["expires_at"] as? String) ?? ""
            status = "Session \(newSlug)" + (expires.isEmpty ? "" : " (expires \(expires))")
        } catch {
            status = "Could not create a session: \(error.localizedDescription)"
        }
    }
}
