import SwiftUI

/// A Caribbean / Central America country or island page, as the website shows it (App.tsx country page): the
/// travelers' articles row, "Explore Kosher life & travel across {country}" (not for Mexico), the tabs (Cities & Areas,
/// Things to Do, Kosher Restaurants and Chabad with their counts, Travel Guides), the tour guides box, and each tab.
struct CountryPageView: View {
    let country: CaribbeanCountry

    @Environment(StoryFeed.self) private var feed
    @Environment(AuthStore.self) private var auth
    private var store: StatePageStore { StatePageStore.shared }

    @State private var tab = "destinations"
    @State private var todoCategory: String?
    @State private var selected: PlaceItem?
    @State private var openStory: String?
    @State private var query = ""

    private var name: String { country.name }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TravelerArticlesSection(kind: .country, placeName: name)
                    .padding(.bottom, 4)
                // Web PlaceStories: the travelers' tips come right after the articles row (Oct 23 2026).
                TravelerTipsSection(scope: TipScope(kind: .country, name: name),
                                    insets: EdgeInsets(top: 0, leading: Theme.pagePadding, bottom: 0, trailing: Theme.pagePadding))
                if name != "Mexico" {
                    Text("Explore Kosher life & travel across \(name)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, Theme.pagePadding)
                }
                if let d = store.country(name) {
                    SPTabStrip(items: tabItems(d), selection: $tab)
                        .padding(.horizontal, Theme.pagePadding)
                    VStack(alignment: .leading, spacing: 28) {
                        if tab == "destinations" { citiesTab(d) }
                        guidesBox
                        switch tab {
                        case "todo": todoTab(d)
                        case "kosher": restaurantsTab(d)
                        case "chabad": chabadTab(d)
                        case "guides": guidesBox
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                } else if store.failed {
                    SPEmptyBox(title: "Travel data could not be read.").padding(.horizontal, Theme.pagePadding)
                } else {
                    SPSkeleton().padding(.horizontal, Theme.pagePadding)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .overlay {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                RegionSearchResults(scope: .country(name), query: $query)
            }
        }
        .background(Color.white)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(name)")
        .refreshable { await feed.refresh() }
        .task { await store.load() }
        .task { await feed.loadIfNeeded() }
        .task { await TravelerTipsStore.shared.fetch() }
        .task(id: auth.uid) { await BucketList.shared.bind(uid: auth.uid) }
        .onChange(of: tab) { _, _ in todoCategory = nil }
        .sheet(item: $selected) { item in
            PlaceDetailView(item: item, onOpenStory: { id in
                selected = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openStory = id }
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $openStory) { id in StoryDetailView(postId: id) }
    }

    private func tabItems(_ d: SPCountryData) -> [SPTabStrip.Item] {
        [
            .init(id: "destinations", title: "Cities & Areas"),
            .init(id: "todo", title: "Things to Do", count: d.attractions.count),
            .init(id: "kosher", title: "Kosher Restaurants", count: d.restaurants.count),
            .init(id: "chabad", title: "Chabad", count: d.chabad.count),
            .init(id: "guides", title: "Travel Guides"),
        ]
    }

    private func open(_ l: SPListing, _ category: PlaceCategory, _ index: Int) {
        selected = l.item(category, index: index, fallbackCity: name)
    }

    // MARK: Cities & Areas

    @ViewBuilder
    private func citiesTab(_ d: SPCountryData) -> some View {
        if d.cities.isEmpty {
            SPNoDestinations(place: name, systemImage: "beach.umbrella",
                             line: "Our research team is currently validating active Chabad houses, shabbat meal delivery options, and kosher eateries in \(name).",
                             example: "e.g., Chabad resort in Nassau...")
        } else {
            LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                // The country-wide card (curated sights across the whole country). The app has no city page for it, so
                // it opens the country's Things to Do, which lists the same places.
                if let wide = d.wide {
                    SPCityCardView(card: wide, onOpenWide: { withAnimation { tab = "todo"; todoCategory = "all" } })
                }
                ForEach(d.cities) { c in SPCityCardView(card: c) }
            }
        }
    }

    private var guidesBox: some View {
        VStack(alignment: .leading, spacing: 14) {
            SPTabHeader(systemImage: "safari", title: "Tour Guides in \(name)",
                        subtitle: "Local guides, customized kosher tours, and Jewish heritage experts in \(name).")
            SPGuidesDirectoryBox(title: "\(name) Tour Guides Directory",
                                 detail: "Curated verified kosher travel guides and local excursions in \(name) are being finalized for this directory.")
        }
    }

    // MARK: Things to Do

    private func todoTab(_ d: SPCountryData) -> some View {
        let all = Array(d.attractions.enumerated())
        let cats = SPTodoCategory.list(country: true)
        return VStack(alignment: .leading, spacing: 18) {
            if let catId = todoCategory, let cat = cats.first(where: { $0.id == catId }) {
                let shown = all.filter { SPTodoCategory.matches($0.element.tags ?? [], catId) }
                SPTabHeader(title: "\(cat.name) in \(name)", subtitle: "Showing \(shown.count) attractions in this category.") {
                    Button { todoCategory = nil } label: {
                        Text("← Back to Categories").font(.caption.weight(.bold)).foregroundStyle(Color.navy)
                            .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if shown.isEmpty {
                    SPEmptyBox(title: "No attractions in this category listed yet for \(name).")
                } else {
                    LazyVGrid(columns: SPGrid.tiles, alignment: .leading, spacing: 16) {
                        ForEach(shown, id: \.offset) { i, l in
                            SPTodoTile(l: l, fallbackCity: name) { open(l, .todo, i) }
                        }
                    }
                }
            } else {
                SPTabHeader(title: "Things to Do in \(name)",
                            subtitle: "Select a category below to explore curated experiences across the country.")
                if all.isEmpty {
                    SPEmptyBox(title: "No attractions listed yet for \(name).")
                } else {
                    VStack(spacing: 12) {
                        ForEach(cats) { cat in
                            let n = all.filter { SPTodoCategory.matches($0.element.tags ?? [], cat.id) }.count
                            if n > 0 || cat.id == "all" {
                                SPCategoryCard(cat: cat, count: n, country: true) { todoCategory = cat.id }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Kosher Restaurants, Chabad

    private func restaurantsTab(_ d: SPCountryData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SPTabHeader(title: "Kosher Restaurants in \(name)", subtitle: "Discover certified kosher dining options across all cities in the country.")
            if d.restaurants.isEmpty {
                SPEmptyBox(title: "No kosher restaurants recorded yet for \(name).",
                           detail: "Use our AI Planner chat to suggest options or verify custom caterers.")
            } else {
                LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                    ForEach(Array(d.restaurants.enumerated()), id: \.offset) { i, l in
                        SPRestaurantCard(l: l) { open(l, .restaurant, i) }
                    }
                }
            }
        }
    }

    private func chabadTab(_ d: SPCountryData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SPTabHeader(title: "Chabad Directory in \(name)", subtitle: "Contact details, rabbi names, and Shabbat meals across the entire country.")
            if d.chabad.isEmpty {
                SPEmptyBox(title: "No recorded Chabad houses for \(name).",
                           detail: "Please consult our AI Planner chat to check adjacent regions or directories.")
            } else {
                LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                    ForEach(Array(d.chabad.enumerated()), id: \.offset) { i, l in
                        SPChabadCard(l: l, full: false) { open(l, .chabad, i) }
                    }
                }
            }
        }
    }
}
