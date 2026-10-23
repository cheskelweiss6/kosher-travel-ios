import SwiftUI

/// United States: traveler articles, then every state.
struct UnitedStatesView: View {
    @Environment(ExploreStore.self) private var store
    @Environment(StoryFeed.self) private var feed

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                TravelerArticlesSection(kind: .country, placeName: "United States")
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "States", count: store.states.count)
                    ForEach(Array(store.states.enumerated()), id: \.element.id) { i, state in
                        NavigationLink(value: ExploreRoute.state(state.id)) {
                            PlaceRow(title: state.name, detail: state.description, image: state.image,
                                     tag: "\(state.cities.count) \(state.cities.count == 1 ? "city" : "cities")")
                        }
                        .buttonStyle(.plain)
                        if i < store.states.count - 1 { Divider().overlay(Color.hairline).padding(.leading, 88) }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .navigationTitle("United States")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await feed.refresh() }
        .task { await feed.loadIfNeeded() }
    }
}

/// Caribbean: every island / country.
struct CaribbeanView: View {
    @Environment(ExploreStore.self) private var store
    @Environment(StoryFeed.self) private var feed

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Islands & Countries", count: store.caribbean.count)
                    ForEach(Array(store.caribbean.enumerated()), id: \.element.id) { i, c in
                        NavigationLink(value: ExploreRoute.country(c.id)) {
                            PlaceRow(title: c.name, detail: c.description, image: c.image,
                                     tag: c.cities.isEmpty ? nil : "\(c.cities.count) \(c.cities.count == 1 ? "area" : "areas")")
                        }
                        .buttonStyle(.plain)
                        if i < store.caribbean.count - 1 { Divider().overlay(Color.hairline).padding(.leading, 88) }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .navigationTitle("Caribbean")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await feed.refresh() }
        .task { await feed.loadIfNeeded() }
    }
}

/// A list row with a square photo: states, countries.
struct PlaceRow: View {
    let title: String
    let detail: String
    let image: String
    var tag: String? = nil
    @ScaledMetric(relativeTo: .headline) private var thumb: CGFloat = 74

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RemoteImage(url: image, maxPixel: 300)
                .frame(width: thumb, height: thumb)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                if let tag { TagLabel(text: tag) }
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.navy)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
