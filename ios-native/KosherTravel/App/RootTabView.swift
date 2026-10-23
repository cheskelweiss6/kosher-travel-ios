import SwiftUI

/// The web's 4 tabs (Cheskel's parity rule): Explore, AI Planner, My Travel, Stories. Profile opens from the header
/// button on each tab (ShellRouter.showProfile), as on the website.
enum AppTab: Hashable {
    case explore, planner, myTravel, stories
}

struct RootTabView: View {
    @Bindable private var router = ShellRouter.shared
    @Environment(AuthStore.self) private var auth

    var body: some View {
        TabView(selection: $router.selectedTab) {
            ExploreTab()
                .tabItem { Label("Explore", systemImage: "safari").environment(\.symbolVariants, .none) }
                .tag(AppTab.explore)
            PlannerTab()
                .tabItem { Label("AI Planner", systemImage: "sparkles").environment(\.symbolVariants, .none) }
                .tag(AppTab.planner)
            MyTravelTab()
                .tabItem { Label("My Travel", systemImage: "calendar").environment(\.symbolVariants, .none) }
                .tag(AppTab.myTravel)
            StoriesTab()
                .tabItem { Label("Stories", systemImage: "camera").environment(\.symbolVariants, .none) }
                .tag(AppTab.stories)
        }
        // Brand: outline icons, also for the selected tab.
        .environment(\.symbolVariants, .none)
        // Any screen (native or embedded) can ask for the native sign-in.
        .sheet(item: $router.signIn) { mode in
            SignInSheet(mode: mode)
        }
        .sheet(item: $router.deepLink) { target in
            DeepLinkSheet(target: target)
        }
        .sheet(isPresented: $router.showProfile) {
            ProfileTab(presented: true)
                .presentationDragIndicator(.visible)
        }
        // Shared links (universal links) and the Google sign-in callback.
        .onOpenURL { url in _ = DeepLinks.handle(url) }
        // Every link a native screen opens goes through one opener (maps chooser, Safari in-app, affiliate rewrite).
        .environment(\.openURL, OpenURLAction { url in LinkOpener.handle(url) })
        .onAppear {
            router.auth = auth
            ToastWindow.install()
            NetworkWatch.start()
            if let route = LaunchRoute.current, route.hasPrefix("tab:") {
                // "tab:<name>" or "tab:<name>/<screen>" (the tab's own view reads the rest)
                switch route.dropFirst(4).split(separator: "/").first.map(String.init) ?? "" {
                case "planner": router.selectedTab = .planner
                case "mytravel": router.selectedTab = .myTravel
                case "stories": router.selectedTab = .stories
                case "profile": router.showProfile = true
                default: router.selectedTab = .explore
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
