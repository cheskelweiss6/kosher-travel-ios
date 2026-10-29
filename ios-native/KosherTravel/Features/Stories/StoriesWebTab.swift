import SwiftUI

/// The Stories tab (V2-FULL-1029, Cheskel Oct 29 2026: "everything exactly the same as the website"): the website's own
/// Stories page (Get Inspired, Articles, posts, comments, travelers, Share, the admin's remove-with-a-reason), kept warm
/// like My Travel (MyTravelWarm.swift). The page shows its own "Stories" heading and Share button, so the bar carries only
/// the account corner. Requests from other tabs (Share from a city, a post) reach the page through
/// ShellRouter.storiesRequest (RootTabView).
struct StoriesTab: View {
    var body: some View {
        NavigationStack {
            WarmWebScreen(page: .stories, tab: .stories, fixedTitle: "")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { AccountToolbarButtons() }
                }
        }
    }
}
