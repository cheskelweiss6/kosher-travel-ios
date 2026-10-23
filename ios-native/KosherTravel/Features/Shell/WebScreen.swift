import SwiftUI

/// What an embedded screen pushes natively (a post, a traveler) or opens as another embedded screen.
enum ShellPush: Hashable {
    case story(String, comments: Bool)
    case traveler(uid: String, name: String, photo: String)
    case web(WebRoute)
}

/// One not-yet-native screen of the live app inside the native shell: native navigation bar with the back chevron
/// and edge swipe (pushed screens), or full screen with the page's own X / Back (composer, Get Inspired), a loading
/// state, an error screen with Retry, the native sign-in, and links routed to native screens or Safari.
struct WebScreen: View {
    let route: WebRoute
    /// Full screen (no native bar): the page shows its own close button and sends "close".
    var fullScreen = false

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var authScript: String?
    /// The signed-in account the page was loaded for ("" = signed out). The page reloads only when this changes.
    @State private var loadedUid: String?
    @State private var reloadToken = 0
    @State private var loading = true
    @State private var failed: String?
    @State private var pageTitle: String?
    @State private var safari: IdentifiedURL?
    @State private var push: ShellPush?
    @State private var signIn: SignInSheet.Mode?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if let authScript {
                ShellWebView(route: route, authScript: authScript, reloadToken: reloadToken, fullScreen: fullScreen,
                             onEvent: handle)
                    .ignoresSafeArea(edges: fullScreen ? .all : [])
                    .opacity(failed == nil ? 1 : 0)
                    .accessibilityHidden(failed != nil)
            }
            if failed != nil {
                ShellErrorView(retry: retry)
            } else if loading {
                ProgressView()
                    .controlSize(.large)
                    .tint(Color.navy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                    .accessibilityLabel("Loading")
            }
        }
        .navigationTitle(pageTitle ?? route.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(fullScreen ? .hidden : .automatic, for: .navigationBar)
        .sheet(item: $safari) { item in
            SafariSheet(url: item.url).ignoresSafeArea()
        }
        .sheet(item: $signIn) { mode in
            SignInSheet(mode: mode)   // presented from here so it also works over a full-screen embedded page
        }
        .navigationDestination(item: $push) { p in
            switch p {
            case .story(let id, _): StoryDetailView(postId: id)
            case .traveler(let uid, let name, let photo): TravelerView(uid: uid, name: name, photo: photo)
            case .web(let r): WebScreen(route: r)
            }
        }
        // Waits for the restored sign-in, then reloads only when the signed-in account changes: never because the
        // hourly Firebase token refresh changed the script (the page keeps its own session fresh), and never on a
        // return to the screen (same pattern as WarmWebPage in Features/MyTravel/MyTravelWarm.swift).
        .task(id: auth.ready ? (auth.uid ?? "-") : "?") {
            guard auth.ready else { return }
            await prepare()
        }
    }

    @MainActor
    private func prepare() async {
        let uid = auth.uid ?? ""
        if authScript != nil && loadedUid == uid { return }   // same account: keep the page as it is
        await WebSession.prepareStore(uid: auth.uid)
        let script = await WebSession.authScript()
        guard (auth.uid ?? "") == uid else { return }   // the account changed meanwhile; the newer task takes over
        if authScript == nil {
            authScript = script
            loadedUid = uid
        } else if loadedUid != uid {
            authScript = script
            loadedUid = uid
            loading = true
            reloadToken += 1   // signed in or out natively: load the page again with the new sign-in
        }
    }

    private func retry() {
        failed = nil
        loading = true
        reloadToken += 1
    }

    private func handle(_ e: ShellEvent) {
        switch e {
        case .ready:
            loading = false
        case .loaded:
            // A page that never says "ready" (an older website build) is still shown after a moment.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                loading = false
            }
        case .failed(let msg):
            failed = msg
            loading = false
        case .close:
            dismiss()
        case .signIn(let mode):
            signIn = mode
        case .tab(let name, let prompt):
            ShellRouter.shared.open(tab: name, prompt: prompt)
        case .story(let id, let comments):
            push = .story(id, comments: comments)
        case .traveler(let uid, let name, let photo):
            push = .traveler(uid: uid, name: name, photo: photo)
        case .title(let t):
            pageTitle = t
        case .link(let t):
            switch t {
            case .safari(let u), .ownSite(let u): safari = IdentifiedURL(url: u)
            case .system(let u): LinkOpener.openSystem(u)
            case .story(let id): push = .story(id, comments: false)
            }
        }
    }
}

/// A tab whose whole screen is still the live app's (My Travel today): its own navigation stack, no back button.
struct WebTabRoot: View {
    let route: WebRoute
    var body: some View {
        NavigationStack {
            WebScreen(route: route)
                .toolbar {
                    // Web: the header's account corner sits on every tab.
                    ToolbarItem(placement: .topBarTrailing) { AccountToolbarButtons() }
                }
        }
    }
}
