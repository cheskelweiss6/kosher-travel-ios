import SwiftUI

enum AppTab: Hashable {
    case explore, planner, myTravel, stories, profile
}

struct RootTabView: View {
    @State private var selection: AppTab = .explore

    var body: some View {
        TabView(selection: $selection) {
            ExploreTab()
                .tabItem { Label("Explore", systemImage: "safari").environment(\.symbolVariants, .none) }
                .tag(AppTab.explore)
            PlannerTab()
                .tabItem { Label("AI Planner", systemImage: "sparkles").environment(\.symbolVariants, .none) }
                .tag(AppTab.planner)
            MyTravelTab()
                .tabItem { Label("My Travel", systemImage: "suitcase").environment(\.symbolVariants, .none) }
                .tag(AppTab.myTravel)
            StoriesTab()
                .tabItem { Label("Stories", systemImage: "photo.on.rectangle").environment(\.symbolVariants, .none) }
                .tag(AppTab.stories)
            ProfileTab()
                .tabItem { Label("Profile", systemImage: "person.crop.circle").environment(\.symbolVariants, .none) }
                .tag(AppTab.profile)
        }
        // Brand: outline icons, also for the selected tab.
        .environment(\.symbolVariants, .none)
        .onAppear {
            if let route = LaunchRoute.current, route.hasPrefix("tab:") {
                // "tab:<name>" or "tab:<name>/<screen>" (the tab's own view reads the rest)
                switch route.dropFirst(4).split(separator: "/").first.map(String.init) ?? "" {
                case "planner": selection = .planner
                case "mytravel": selection = .myTravel
                case "stories": selection = .stories
                case "profile": selection = .profile
                default: selection = .explore
                }
            }
        }
    }
}

/// Screenshot / QA deep link: `-ktRoute state:colorado` on launch (simctl launch arguments land in UserDefaults).
enum LaunchRoute {
    static var current: String? {
        let r = UserDefaults.standard.string(forKey: "ktRoute")
        return (r?.isEmpty ?? true) ? nil : r
    }
}
