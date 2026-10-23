import SwiftUI
import GoogleSignIn

/// A shared www.yourkoshertravel.com link opened in the app (universal links once the site serves
/// apple-app-site-association; also any own-site link handed to the app). Web: App.tsx ?story=, ?map=, ?shareKever=,
/// ?keverSearch=, ?keverCountry=, ?explore=true, ?shareItinerary=, ?trip=&invite=, ?contact=1.
enum DeepLinkTarget: Identifiable, Hashable {
    case story(String)
    case traveler(String)
    case web(WebRoute)

    var id: String {
        switch self {
        case .story(let s): return "story:" + s
        case .traveler(let s): return "traveler:" + s
        case .web(let r): return "web:" + r.id
        }
    }
}

enum DeepLinks {
    static func target(for url: URL) -> DeepLinkTarget? {
        guard WebSession.isOwn(url) else { return nil }
        if let id = PlannerLinks.storyId(url) { return .story(id) }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ k: String) -> String? { items.first { $0.name == k }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        if let s = q("story") { return .story(s) }
        if let m = q("map") { return .traveler(m) }
        if q("shareKever") != nil || q("keverSearch") != nil || q("keverCountry") != nil || q("explore") == "true" {
            return .web(WebRoute.kivrei.with(query: query))
        }
        if q("shareItinerary") != nil { return .web(WebRoute.myTravel.with(query: query)) }
        // Shared trips (Oct 23 2026): ?trip=<id>&invite=<token> opens My Travel with the query, so the website's
        // Join trip sheet shows inside the app.
        if q("trip") != nil { return .web(WebRoute.myTravel.with(query: query)) }
        if q("contact") != nil { return .web(WebRoute.profileWeb.with(query: query)) }
        return nil
    }

    /// Handles a URL the system hands the app. Returns true when it was ours.
    @MainActor
    static func handle(_ url: URL) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) { return true }
        guard WebSession.isOwn(url) else { return false }
        if let t = target(for: url) { ShellRouter.shared.deepLink = t } else { ShellRouter.shared.selectedTab = .explore }
        return true
    }
}

/// The sheet a shared link opens over the current tab (closing it returns to where you were).
struct DeepLinkSheet: View {
    let target: DeepLinkTarget
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.navy)
                        }
                        .accessibilityLabel("Close")
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch target {
        case .story(let id): StoryDetailView(postId: id)
        case .traveler(let uid): TravelerView(uid: uid, name: "", photo: "")
        case .web(let route): WebScreen(route: route)
        }
    }
}
