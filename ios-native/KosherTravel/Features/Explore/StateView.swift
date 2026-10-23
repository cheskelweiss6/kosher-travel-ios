import SwiftUI

/// A state page: photo, about, traveler articles (live), cities & areas.
struct StateView: View {
    @Environment(ExploreStore.self) private var store
    @Environment(StoryFeed.self) private var feed
    let stateId: String

    var body: some View {
        Group {
            if let state = store.state(stateId) {
                PlacePage(title: state.name, image: state.image, about: state.description,
                          articleKind: .state, areaTitle: "Cities & Areas", areas: store.areas(in: state))
            } else {
                ContentUnavailableView("Not found", systemImage: "map", description: Text("This state is not in the app yet."))
            }
        }
        .refreshable { await feed.refresh() }
        .task { await feed.loadIfNeeded() }
    }
}

/// A Caribbean island / country page.
struct CountryView: View {
    @Environment(ExploreStore.self) private var store
    @Environment(StoryFeed.self) private var feed
    let countryId: String

    var body: some View {
        Group {
            if let c = store.country(countryId) {
                PlacePage(title: c.name, image: c.image, about: c.description,
                          articleKind: .country, areaTitle: "Destinations", areas: store.areas(in: c))
            } else {
                ContentUnavailableView("Not found", systemImage: "map", description: Text("This place is not in the app yet."))
            }
        }
        .refreshable { await feed.refresh() }
        .task { await feed.loadIfNeeded() }
    }
}

struct PlacePage: View {
    let title: String
    let image: String
    let about: String
    let articleKind: StoryPost.PlaceKind
    let areaTitle: String
    let areas: [AreaCard]

    private var columns: [GridItem] { [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 12, alignment: .top)] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    RemoteImage(url: image, maxPixel: 1400)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    if !about.isEmpty {
                        Text(about)
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.pagePadding)

                TravelerArticlesSection(kind: articleKind, placeName: title)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: areaTitle, count: areas.count)
                    if areas.isEmpty {
                        EmptyNote(title: "No areas listed yet", systemImage: "map")
                    } else {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(areas) { area in
                                if area.hasPage {
                                    NavigationLink(value: ExploreRoute.area(area.id)) { AreaCardView(area: area) }
                                        .buttonStyle(.plain)
                                } else {
                                    AreaCardView(area: area)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .background(Color.white)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

struct AreaCardView: View {
    let area: AreaCard
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: area.photo, maxPixel: 600)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(area.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.navy)
                .lineLimit(1)
            Text(area.subtitle)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            if area.hasGrocery || area.hasChabad {
                HStack(spacing: 6) {
                    if area.hasGrocery { TagLabel(text: "Grocery") }
                    if area.hasChabad { TagLabel(text: "Chabad") }
                }
                .padding(.top, 2)
            }
        }
        .contentShape(Rectangle())
    }
}
