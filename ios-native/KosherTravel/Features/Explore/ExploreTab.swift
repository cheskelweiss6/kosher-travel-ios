import SwiftUI

/// The Explore tab (V2-FULL-1029, Cheskel Oct 29 2026: "Make sure that the app is fully comparable with the website,
/// everything is exactly the same"): the website's own Explore page — search (English, Hebrew, Yiddish), Browse Regions
/// (United States, Caribbean, Mexico & Central America, Europe, Asia), Get Inspired, Stories & Articles, What's New,
/// your upcoming trips, and every region, country, state, city and listing page under it — kept warm like My Travel
/// (MyTravelWarm.swift), so it opens at once and every website update reaches the app without a new build.
/// The native Explore screens (ExploreHomeView, StateView, AreaView…) stay in the project for the native rebuild.
struct ExploreTab: View {
    @State private var path: [ExploreRoute] = []
    @State private var composing = false   // Share: the native chooser, then the website's composer

    var body: some View {
        NavigationStack(path: $path) {
            WarmWebScreen(page: .explore, tab: .explore)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { composing = true } label: {
                            Label("Share", systemImage: "photo.badge.plus").labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel("Share your story")
                        .accessibilityIdentifier("explore-share")
                    }
                    ToolbarItem(placement: .topBarTrailing) { AccountToolbarButtons() }
                }
                .composeFlow(isPresented: $composing)
                .navigationDestination(for: ExploreRoute.self) { route in
                    ExploreDestination(route: route)
                }
        }
        .onAppear(perform: applyLaunchRoute)
    }

    /// QA screenshots open a screen directly: state:<id>, country:<id>, area:<key>, europe, kivrei, search, news
    /// (each the website's page, as everywhere in the app now).
    private func applyLaunchRoute() {
        guard path.isEmpty, let full = LaunchRoute.current else { return }
        let r = full.hasSuffix("#native") ? String(full.dropLast(7)) : full
        if r.hasPrefix("state:") { path = [.state(String(r.dropFirst(6)))] }
        else if r.hasPrefix("country:") { path = [.country(String(r.dropFirst(8)))] }
        else if r.hasPrefix("area:") { path = [.area(String(r.dropFirst(5)))] }
        else if r == "europe" { path = [.web(.europe)] }
        else if r == "kivrei" { path = [.web(.kivrei)] }
        else if r == "search" { path = [.web(.exploreSearch)] }
        else if r == "news" { path = [.web(.news)] }
    }
}
