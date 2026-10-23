import SwiftUI

struct ExploreTab: View {
    @State private var path: [ExploreRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ExploreHomeView()
                .navigationDestination(for: ExploreRoute.self) { route in
                    ExploreDestination(route: route)
                }
        }
        .onAppear(perform: applyLaunchRoute)
    }

    /// QA screenshots open a screen directly: usa, caribbean, state:<id>, country:<id>, area:<key>.
    private func applyLaunchRoute() {
        guard path.isEmpty, let full = LaunchRoute.current else { return }
        let r = full.hasSuffix("#native") ? String(full.dropLast(7)) : full
        if r == "usa" { path = [.unitedStates] }
        else if r == "caribbean" { path = [.caribbean] }
        else if r == "centralamerica" { path = [.mexicoCentralAmerica] }
        else if r.hasPrefix("state:") { path = [.unitedStates, .state(String(r.dropFirst(6)))] }
        else if r.hasPrefix("country:") { path = [.caribbean, .country(String(r.dropFirst(8)))] }
        else if r.hasPrefix("area:") { path = [.area(String(r.dropFirst(5)))] }
    }
}
