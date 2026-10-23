import SwiftUI

/// Where an in-page search looks (web RegionSearch scope).
enum SPSearchScope: Hashable {
    case unitedStates, caribbean
    case state(String)
    case country(String)

    var label: String {
        switch self {
        case .unitedStates: return "United States"
        case .caribbean: return "Caribbean"
        case .state(let n), .country(let n): return n
        }
    }
}

/// The in-page search's results, covering the page while the field has words in it.
struct RegionSearchResults: View {
    let scope: SPSearchScope
    @Binding var query: String
    var body: some View {
        ScrollView {
            Text("Searching \(scope.label)…")
                .font(.footnote).foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.pagePadding)
        }
        .background(Color.white)
    }
}
