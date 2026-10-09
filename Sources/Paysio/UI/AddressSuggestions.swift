import SwiftUI

/// Street address suggestions for the billing / shipping stack (RN
/// `ui/AddressSuggestions.tsx`, the mobile twin of the hosted checkout's
/// AddressAutocomplete): 250 ms debounce, 3 character minimum, one Places session token
/// per pick, a cache of the last 100 queries, a map-pin row per suggestion with the typed
/// text in semibold. No "Powered by Google" row. The list sits inline under the field
/// and pushes the rows below it down (the payment picker clips its panels).
@MainActor
final class AddressSuggestionsModel: ObservableObject {
    @Published private(set) var suggestions: [PaysioAddressSuggestion] = []
    @Published private(set) var loading = false

    private var sessionToken = UUID().uuidString.lowercased()
    private var cache: [String: [PaysioAddressSuggestion]] = [:]
    private var cacheOrder: [String] = []
    private var task: Task<Void, Never>?

    /// Re-run whenever the query, country, base or enabled flag changes.
    func update(apiBase: URL?, query: String, country: String, enabled: Bool) {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiBase, enabled, q.count >= PaysioAddressSuggest.minQuery else {
            suggestions = []
            loading = false
            return
        }
        let key = "\(country)|\(q.lowercased())"
        if let cached = cache[key] {
            suggestions = cached
            loading = false
            return
        }
        loading = true
        let token = sessionToken
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: PaysioAddressSuggest.debounceNanoseconds)
            if Task.isCancelled { return }
            let next = await PaysioAddressSuggest.suggest(apiBase: apiBase, query: q, country: country, sessionToken: token)
            guard !Task.isCancelled, let self else { return }
            self.store(key, next)
            self.suggestions = next
            self.loading = false
        }
    }

    private func store(_ key: String, _ value: [PaysioAddressSuggestion]) {
        if cache.count >= 100, let oldest = cacheOrder.first {
            cacheOrder.removeFirst()
            cache[oldest] = nil
        }
        cache[key] = value
        cacheOrder.append(key)
    }

    /// Resolves the picked place, then starts a fresh Places session.
    func resolve(_ s: PaysioAddressSuggestion, apiBase: URL?) async -> PaysioAddressSuggestion {
        let token = sessionToken
        sessionToken = UUID().uuidString.lowercased()
        task?.cancel()
        suggestions = []
        guard let apiBase else { return s }
        return await PaysioAddressSuggest.details(apiBase: apiBase, placeId: s.id, sessionToken: token) ?? s
    }
}

/// The inline list: margin top 4, 1 pt `border`, radius 12, padding 4, `card`
/// background, menu shadow 0 12 24 rgba(26,26,26,0.16); at most 5 rows.
struct AddressSuggestionList: View {
    let suggestions: [PaysioAddressSuggestion]
    let query: String
    let onPick: (PaysioAddressSuggestion) -> Void

    @Environment(\.paysioTheme) private var theme

    var body: some View {
        if !suggestions.isEmpty {
            let shape = RoundedRectangle(cornerRadius: 12, style: .circular)
            VStack(spacing: 0) {
                ForEach(suggestions.prefix(5)) { s in
                    Button { onPick(s) } label: {
                        HStack(spacing: 8) {
                            PaysioIcon(.mapPinSolid, size: 14, color: theme.colors.mutedForeground)
                            highlighted(s.label)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SuggestionRowStyle())
                    .accessibilityLabel(s.label)
                }
            }
            .padding(4)
            .background(shape.fill(theme.colors.card).shadow(color: Color(hex: 0x1A1A1A, opacity: 0.16), radius: 12, x: 0, y: 12))
            .overlay(shape.strokeBorder(theme.colors.border, lineWidth: 1))
            .padding(.top, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Address suggestions")
        }
    }

    private func highlighted(_ label: String) -> Text {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = theme.font(14)
        guard !q.isEmpty, let range = label.range(of: q, options: .caseInsensitive) else {
            return Text(label).font(base).foregroundColor(theme.colors.foreground)
        }
        return Text(String(label[..<range.lowerBound])).font(base).foregroundColor(theme.colors.foreground)
            + Text(String(label[range])).font(theme.font(14, weight: .semibold)).foregroundColor(theme.colors.foreground)
            + Text(String(label[range.upperBound...])).font(base).foregroundColor(theme.colors.foreground)
    }
}

private struct SuggestionRowStyle: ButtonStyle {
    @Environment(\.paysioTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? theme.colors.rowHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .circular))
    }
}
