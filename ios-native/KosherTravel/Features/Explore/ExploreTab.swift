import SwiftUI

struct ExploreTab: View {
    @State private var path: [ExploreRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ExploreHomeView()
                .navigationDestination(for: ExploreRoute.self) { route in
                    switch route {
                    case .unitedStates: UnitedStatesView()
                    case .caribbean: CaribbeanView()
                    case .state(let id): StateView(stateId: id)
                    case .country(let id): CountryView(countryId: id)
                    case .area(let key): AreaView(areaKey: key)
                    case .story(let id): StoryDetailView(postId: id)
                    }
                }
        }
        .onAppear(perform: applyLaunchRoute)
    }

    /// QA screenshots open a screen directly: usa, caribbean, state:<id>, country:<id>, area:<key>.
    private func applyLaunchRoute() {
        guard path.isEmpty, let r = LaunchRoute.current else { return }
        if r == "usa" { path = [.unitedStates] }
        else if r == "caribbean" { path = [.caribbean] }
        else if r.hasPrefix("state:") { path = [.unitedStates, .state(String(r.dropFirst(6)))] }
        else if r.hasPrefix("country:") { path = [.caribbean, .country(String(r.dropFirst(8)))] }
        else if r.hasPrefix("area:") { path = [.area(String(r.dropFirst(5)))] }
    }
}
