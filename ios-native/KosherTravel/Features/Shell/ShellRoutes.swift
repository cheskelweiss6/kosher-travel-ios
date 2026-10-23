import SwiftUI

/// Which screens are native and which are still the live app's, from the parity checklist
/// (files/native/parity-checklist.md, Oct 23 2026). A screen switches to native only when it matches the web one in
/// every detail (Cheskel's parity rule); until then the shell shows the live screen, so nothing is missing.
enum ShellRoutes {
    /// State pages: native lacks most tabs (Things to Do, parks and their sheets, grocery, shuls, Chabad, hotels, guides).
    static let nativeStatePage = false
    /// Caribbean / Central America country pages: native lacks the tabs and the travel-time chips.
    static let nativeCountryPage = false
    /// City pages: the web is a hub with sub-pages (Restaurants Meat/Dairy/Parve, Shabbat, Kivrei, Tour Guides…).
    static let nativeCityPage = false
}

/// Every Explore / Planner push goes through here, so a screen flips from embedded to native in one place.
struct ExploreDestination: View {
    let route: ExploreRoute
    @Environment(ExploreStore.self) private var explore

    var body: some View {
        switch route {
        case .unitedStates: UnitedStatesView()
        case .caribbean: CaribbeanView()
        case .state(let id):
            if ShellRoutes.nativeStatePage { StateView(stateId: id) }
            else { WebScreen(route: .state(explore.state(id)?.name ?? Self.titled(id))) }
        case .country(let id):
            if ShellRoutes.nativeCountryPage { CountryView(countryId: id) }
            else { WebScreen(route: .country(explore.country(id)?.name ?? Self.titled(id))) }
        case .area(let key):
            if ShellRoutes.nativeCityPage { AreaView(areaKey: key) }
            else { WebScreen(route: cityRoute(key)) }
        case .story(let id): StoryDetailView(postId: id)
        case .web(let r): WebScreen(route: r)
        }
    }

    /// AreaCard ids: "us:<id>", "dest:<id>", "name:<stateId>:<name>".
    private func cityRoute(_ key: String) -> WebRoute {
        if let d = explore.detail(for: key) { return .city(d.name, sub: d.subtitle) }
        let parts = key.split(separator: ":", maxSplits: 2).map(String.init)
        if parts.count == 3, parts[0] == "name" {
            let state = explore.state(parts[1])?.name ?? Self.titled(parts[1])
            return .city(parts[2], sub: "\(state), United States")
        }
        return .city(Self.titled(parts.last ?? key), sub: "")
    }

    static func titled(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }
}
