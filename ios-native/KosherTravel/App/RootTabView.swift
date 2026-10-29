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
        // After sign-in: a new account (or one with no username yet) chooses its username (Features/Auth/UsernameGate).
        .usernameGate()
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
        // Universal links (www.yourkoshertravel.com, apple-app-site-association): SwiftUI hands most to onOpenURL;
        // this catches the ones delivered as a browsing activity.
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            if let url = activity.webpageURL { _ = DeepLinks.handle(url) }
        }
        // Every link a native screen opens goes through one opener (maps chooser, Safari in-app, affiliate rewrite).
        .environment(\.openURL, OpenURLAction { url in LinkOpener.handle(url) })
        // My Travel is the live site's page: load it in the background right after launch and again after a
        // sign-in or sign-out, so the tab opens instantly (MyTravelWarm.swift). Waits for Firebase to report the
        // sign-in first, so the page is never loaded (and its stored data wiped) for a signed-out moment at launch.
        .task(id: auth.ready ? (auth.uid ?? "-") : "?") {
            guard auth.ready else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)   // after the first screen is up
            await WarmWebPage.myTravel.warm(uid: auth.uid)
        }
        // V2-FULL-1029: the Explore tab (the website's Explore page) loads first, right away; the Stories page a moment
        // later, behind the app's screen, so its first open shows posts instead of a placeholder.
        .task(id: auth.ready ? (auth.uid ?? "-") : "?") {
            guard auth.ready else { return }
            await WarmWebPage.explore.warm(uid: auth.uid)
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await WarmWebPage.stories.warm(uid: auth.uid)
        }
        // A Stories request from another tab's page (Share from a city, a post): the Stories page opens it.
        .onChange(of: router.storiesRequest) { _, json in
            guard let json, !json.isEmpty else { return }
            router.storiesRequest = nil
            Task { await WarmWebPage.stories.warm(uid: auth.uid) }
            WarmWebPage.stories.run(js: "(function(){try{return !!(window.__ktShellStories && window.__ktShellStories(" + json + "));}catch(e){return false;}})()")
        }
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
