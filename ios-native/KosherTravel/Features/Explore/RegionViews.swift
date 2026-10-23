import SwiftUI

/// United States, as the website shows it (App.tsx, United States page): the travelers' articles row, "Travel times
/// from …", then every state as a round photo with its city count, name and the first ten words of its description on
/// the photo, and a travel-time chip under it. A search field searches the whole page and everything under it.
struct UnitedStatesView: View {
    @Environment(ExploreStore.self) private var explore
    @Environment(StoryFeed.self) private var feed
    @State private var query = ""
    private var store: StatePageStore { StatePageStore.shared }

    /// web PREMIUM_STATES with getCitiesForState's count; the bundled list stands in for the first instant.
    private var tiles: [SPRegionTile] {
        if !store.usStates.isEmpty { return store.usStates }
        return explore.states.map { SPRegionTile(id: $0.id, name: $0.name, image: $0.image, description: $0.description, cityCount: $0.cities.count) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TravelerArticlesSection(kind: .country, placeName: "United States")
                VStack(alignment: .leading, spacing: 16) {
                    TravelOriginBar()
                    LazyVGrid(columns: SPRegionGrid.columns, alignment: .center, spacing: 24) {
                        ForEach(tiles) { t in
                            VStack(spacing: 8) {
                                NavigationLink(value: ExploreRoute.state(t.id)) {
                                    SPRegionCircle(tile: t, tenWords: true, caribbean: false)
                                }
                                .buttonStyle(.plain)
                                TravelChip(usState: t.name)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            .padding(.vertical, 12)
        }
        .overlay {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                RegionSearchResults(scope: .unitedStates, query: $query)
            }
        }
        .background(Color.white)
        .navigationTitle("United States")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search United States")
        .refreshable { await feed.refresh() }
        .task { await feed.loadIfNeeded() }
        .task { await store.load() }
    }
}

/// The Caribbean, as the website shows it (App.tsx, Caribbean page): "Explore Featured Islands & Countries", "Travel
/// times from …", then every island and country (Central America included) as a round photo with its city count, name
/// and description, and a travel-time chip under it.
struct CaribbeanView: View {
    @Environment(ExploreStore.self) private var explore
    @Environment(StoryFeed.self) private var feed
    @State private var query = ""
    private var store: StatePageStore { StatePageStore.shared }

    private var tiles: [SPRegionTile] {
        if !store.caribbean.isEmpty { return store.caribbean }
        return explore.caribbean.map { SPRegionTile(id: $0.id, name: $0.name, image: $0.image, description: $0.description,
                                                   cityCount: $0.cities.count, lat: $0.lat, lng: $0.lng) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Explore Featured Islands & Countries")
                        .font(.headline)
                        .foregroundStyle(Color.navy)
                        .accessibilityAddTraits(.isHeader)
                    Text("Verified kosher-friendly tropical getaways with active Jewish life.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                TravelOriginBar()
                LazyVGrid(columns: SPRegionGrid.columns, alignment: .center, spacing: 24) {
                    ForEach(tiles) { t in
                        VStack(spacing: 8) {
                            NavigationLink(value: ExploreRoute.country(t.id)) {
                                SPRegionCircle(tile: t, tenWords: false, caribbean: true)
                            }
                            .buttonStyle(.plain)
                            if let lat = t.lat, let lng = t.lng {
                                TravelChip(at: lat, lng, us: false)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 12)
        }
        .overlay {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                RegionSearchResults(scope: .caribbean, query: $query)
            }
        }
        .background(Color.white)
        .navigationTitle("Caribbean")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Caribbean")
        .refreshable { await feed.refresh() }
        .task { await feed.loadIfNeeded() }
        .task { await store.load() }
    }
}

/// The circles' grid: 2 across on a phone, 3 when there is room (web grid-cols-2 sm:grid-cols-3).
enum SPRegionGrid {
    static let columns = [GridItem(.adaptive(minimum: 140, maximum: 240), spacing: 16, alignment: .top)]
}
