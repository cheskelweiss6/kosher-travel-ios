import SwiftUI

/// The state page, as the website shows it (App.tsx, state page): the travelers' articles row, the section tabs
/// (Cities & Areas, Things to Do, State Parks, National Parks and Tribal & Scenic Landmarks when the state has any,
/// Kosher Grocery, Shuls when there are any, Chabad, Hotels, Attractions, Travel Guides), the compact zmanim card for
/// the state, and each tab's lists. No hero photo and no travel-times line (the website has neither on this page).
struct StatePageView: View {
    let state: USState

    @Environment(StoryFeed.self) private var feed
    @Environment(AuthStore.self) private var auth
    private var store: StatePageStore { StatePageStore.shared }
    private var parks: ParkStore { ParkStore.shared }
    private var sights: SharedSights { SharedSights.shared }

    @State private var tab = "destinations"
    @State private var todoCategory: String?
    @State private var selected: PlaceItem?
    @State private var openStory: String?
    @State private var compose: WebRoute?
    @State private var addingGuide = false
    @State private var query = ""
    @State private var guides = TourGuideStore.shared

    private var name: String { state.name }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TravelerArticlesSection(kind: .state, placeName: name)
                        .padding(.bottom, 4)
                    tabStrip.id("tabs")
                    // Zmanim for the state's main city (Cheskel, Oct 21 2026)
                    ZmanimCard(place: ZmanimPlace(state: name), compact: true)
                        .padding(.horizontal, Theme.pagePadding)
                    if let data = store.state(name) {
                        content(data, proxy: proxy)
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
                    RegionSearchResults(scope: .state(name), query: $query)
                }
            }
        }
        .background(Color.white)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search \(name)")
        .refreshable { await feed.refresh() }
        .task {
            await store.load()
            sights.ensureLoaded()
            await parks.load()
        }
        .task { await feed.loadIfNeeded() }
        .task(id: auth.uid) { await BucketList.shared.bind(uid: auth.uid) }
        .onChange(of: tab) { _, _ in todoCategory = nil }
        .sheet(item: $selected) { item in
            PlaceDetailView(item: item, onOpenStory: { id in openStoryAfterSheet(id) })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $addingGuide) {
            AddTourGuideSheet(page: guidePage) { g in
                guides.add(g)
                ShellRouter.shared.showToast("Tour Guide \"\(g.guideName)\" added successfully!")
            }
        }
        .navigationDestination(item: $openStory) { id in StoryDetailView(postId: id) }
        .navigationDestination(item: $compose) { route in WebScreen(route: route) }
    }

    private func openStoryAfterSheet(_ id: String) {
        selected = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openStory = id }
    }

    // MARK: tabs

    private var stateParkCount: Int { parks.stateParks(in: name).count }

    private var tabItems: [SPTabStrip.Item] {
        var items: [SPTabStrip.Item] = [
            .init(id: "destinations", title: "Cities & Areas"),
            .init(id: "todo", title: "Things to Do"),
            .init(id: "state-parks", title: "State Parks"),
        ]
        if parks.hasNationalParks(in: name) { items.append(.init(id: "national-parks", title: "National Parks")) }
        if parks.hasTribalAndScenic(in: name) { items.append(.init(id: "tribal-scenic", title: "Tribal & Scenic Landmarks")) }
        items.append(.init(id: "grocery", title: "Kosher Grocery"))
        if !(store.state(name)?.shuls.isEmpty ?? true) { items.append(.init(id: "synagogues", title: "Shuls")) }
        items += [
            .init(id: "chabad", title: "Chabad"),
            .init(id: "hotels", title: "Hotels"),
            .init(id: "attractions", title: "Attractions"),
            .init(id: "guides", title: "Travel Guides"),
        ]
        return items
    }

    private var tabStrip: some View {
        SPTabStrip(items: tabItems, selection: $tab)
            .padding(.horizontal, Theme.pagePadding)
    }

    @ViewBuilder
    private func content(_ d: SPStateData, proxy: ScrollViewProxy) -> some View {
        switch tab {
        case "todo": todoTab(d)
        case "state-parks": stateParksTab(d)
        case "national-parks": NationalParksTab(stateName: name)
        case "tribal-scenic": TribalScenicTab(stateName: name)
        case "grocery": groceryTab(d)
        case "synagogues": shulsTab(d)
        case "chabad": chabadTab(d)
        case "hotels": hotelsTab(d)
        case "attractions": attractionsTab(d)
        case "guides": guidesTab
        default: citiesTab(d, proxy: proxy)
        }
    }

    private func select(_ tabId: String, _ proxy: ScrollViewProxy) {
        tab = tabId
        withAnimation { proxy.scrollTo("tabs", anchor: .top) }
    }

    private func open(_ l: SPListing, _ category: PlaceCategory, _ index: Int) {
        selected = l.item(category, index: index, fallbackCity: name)
    }

    // MARK: Cities & Areas

    private func citiesTab(_ d: SPStateData, proxy: ScrollViewProxy) -> some View {
        let towns = TravelerFilters.notBuiltIn(sights.townsIn(state: name), existingNames: d.cities.map(\.name) + [name])
        return VStack(alignment: .leading, spacing: 32) {
            if d.cities.isEmpty && towns.isEmpty {
                SPNoDestinations(place: name, systemImage: "map",
                                 line: "Our research team is currently validating active Chabad houses, eruv systems, and kosher dining in \(name).",
                                 example: "e.g., Kosher resort in Orlando...")
            } else {
                LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                    ForEach(d.cities) { c in SPCityCardView(card: c) }
                    ForEach(towns) { t in
                        TravelerTownCard(town: t, stateName: name, onOpen: {
                            selected = t.asPlaceItem(stateName: name)
                        })
                    }
                }
            }
            StateParksSection(stateName: name) { select("state-parks", proxy) }
            NationalParksSection(stateName: name) { select("national-parks", proxy) }
            ParkActivitiesSection(stateName: name)
            travelerStories
            tourGuidesSection
        }
    }

    /// "Traveler Stories" (the website's old article cards; travelers' posts live in the Articles row at the top, so
    /// this shows the website's empty note and the Share Your Trip button).
    private var travelerStories: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Color.hairline).frame(height: 1)
            SPTabHeader(systemImage: "suitcase", title: "Traveler Stories",
                        subtitle: "Travel stories, personal highlights, and community experiences in \(name).", divider: false) {
                SPNavyButton(title: "Share Your Trip", systemImage: "square.and.pencil", action: shareTrip)
            }
            VStack(spacing: 12) {
                Text("No traveler experiences yet — share yours!")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                SPNavyButton(title: "Share Your Trip", systemImage: "square.and.pencil", action: shareTrip)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
        }
    }

    /// web handleOpenShareTrip('United States', state): a guest signs in first ("Sign in to share your story"); a
    /// signed-in traveler gets the story composer with the state filled in.
    private func shareTrip() {
        let route = WebRoute.compose(city: name, region: "United States")
        if auth.isSignedIn { compose = route; return }
        ShellRouter.shared.requireSignIn("Sign in to share your story") { compose = route }
    }

    private var stateGuides: [TourGuide] {
        let s = name.lowercased()
        let cityNames = Set((store.state(name)?.cities ?? []).map { $0.name.lowercased() })
        return guides.guides.filter { g in
            ((g.state ?? "").lowercased().trimmingCharacters(in: .whitespaces) == s)
                || (!g.city.isEmpty && cityNames.contains(g.city.lowercased()))
        }
    }

    private var tourGuidesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(Color.hairline).frame(height: 1)
            SPTabHeader(systemImage: "safari", title: "Tour Guides in \(name)",
                        subtitle: "Local guides, customized kosher tours, and Jewish heritage experts in \(name).", divider: false) {
                SPNavyButton(title: "Add Tour Guide", systemImage: "plus") { addingGuide = true }
            }
            let list = stateGuides
            if list.isEmpty {
                SPGuidesDirectoryBox(title: "\(name) Tour Guides Directory",
                                     detail: "No tour guides listed yet for \(name). Know a great local guide or excursion? Add them to the directory!",
                                     action: (title: "Add Tour Guide", run: { addingGuide = true }))
            } else {
                LazyVGrid(columns: SPGrid.columns, spacing: 14) {
                    ForEach(list) { g in SPTourGuideCard(g: g) }
                }
            }
        }
    }

    /// The add-guide sheet starts with the state filled in and no city (web openAddGuideModal('', state, …)).
    private var guidePage: CityPage {
        var p = CityPage(key: "state:\(state.id)", destId: "", name: "", region: name, subtitle: "\(name), United States",
                         photo: "", description: "", airport: "", airportDistance: "", weather: "", center: nil,
                         sections: [], eruv: nil, hasidic: "")
        p.area = "North America"; p.stateName = name; p.country = "United States"
        return p
    }

    // MARK: Things to Do

    private enum TodoEntry: Identifiable {
        case traveler(SharedSight)
        case listing(SPListing, Int)
        var id: String {
            switch self {
            case .traveler(let s): return "t-\(s.id)"
            case .listing(let l, let i): return "a-\(i)-\(l.name)"
            }
        }
        var tags: [String] {
            if case .listing(let l, _) = self { return l.tags ?? [] }
            return []
        }
    }

    /// web stateTodoAttractions: places travelers added (not already listed) first, then the state's attractions.
    private func todoEntries(_ d: SPStateData) -> [TodoEntry] {
        let fresh = TravelerFilters.notBuiltIn(sights.section(.todo, of: sights.forState(name)), existingNames: d.attractions.map(\.name))
        return fresh.map { TodoEntry.traveler($0) } + d.attractions.enumerated().map { TodoEntry.listing($0.element, $0.offset) }
    }

    @ViewBuilder
    private func todoTile(_ e: TodoEntry) -> some View {
        switch e {
        case .traveler(let s):
            TravelerTile(sight: s, onOpen: { selected = s.asPlaceItem(cityName: s.cityName.isEmpty ? name : s.cityName) })
        case .listing(let l, let i):
            SPTodoTile(l: l, fallbackCity: name) { open(l, .todo, i) }
        }
    }

    private func todoTab(_ d: SPStateData) -> some View {
        let all = todoEntries(d)
        let fresh = all.filter { if case .traveler = $0 { return true }; return false }
        let cats = SPTodoCategory.list(country: false)
        return VStack(alignment: .leading, spacing: 18) {
            if let catId = todoCategory, let cat = cats.first(where: { $0.id == catId }) {
                let shown = all.filter { SPTodoCategory.matches($0.tags, catId) }
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
                        ForEach(shown) { e in todoTile(e) }
                    }
                }
                Button { todoCategory = nil } label: {
                    Label("Back to Categories Overview", systemImage: "chevron.left")
                        .font(.footnote.weight(.bold)).foregroundStyle(Color.navy)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            } else {
                SPTabHeader(title: "Things to Do in \(name)",
                            subtitle: "Select a category below to explore curated experiences across the entire state.")
                // Oct 22 2026 (Cheskel couldn't find Devil's Bridge): places travelers just added show first.
                if !fresh.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Added by travelers").font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
                            Spacer()
                            if fresh.count > 4 {
                                Button("See all \(fresh.count)") { todoCategory = "all" }
                                    .font(.caption.weight(.bold)).foregroundStyle(Color.navy).frame(minHeight: 44)
                            }
                        }
                        LazyVGrid(columns: SPGrid.columns, alignment: .leading, spacing: 12) {
                            ForEach(Array(fresh.prefix(4))) { e in todoTile(e) }
                        }
                    }
                }
                if all.isEmpty {
                    SPEmptyBox(title: "No attractions listed yet for \(name).")
                } else {
                    VStack(spacing: 12) {
                        ForEach(cats) { cat in
                            let n = all.filter { SPTodoCategory.matches($0.tags, cat.id) }.count
                            if n > 0 || cat.id == "all" {
                                SPCategoryCard(cat: cat, count: n, country: false) { todoCategory = cat.id }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: State Parks (travelers' parks first)

    private func stateParksTab(_ d: SPStateData) -> some View {
        let names = parks.stateParks(in: name).map(\.name) + parks.nationalParks(in: name).map(\.name) + d.attractions.map(\.name)
        let tParks = TravelerFilters.notBuiltIn(sights.section(.park, of: sights.forState(name)), existingNames: names)
        return StateParksTab(stateName: name, travelerParkCount: tParks.count) {
            ForEach(tParks) { s in
                TravelerParkCard(sight: s, onOpen: { selected = s.asPlaceItem(cityName: s.cityName.isEmpty ? name : s.cityName) })
            }
        }
    }

    // MARK: Grocery, Shuls, Chabad, Hotels, Attractions, Travel Guides

    private func groceryTab(_ d: SPStateData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SPTabHeader(title: "Kosher Groceries in \(name)", subtitle: "Supermarkets, bakeries, and stores carrying kosher products.")
            if d.groceries.isEmpty {
                SPEmptyBox(title: "No recorded kosher grocery stores for \(name).",
                           detail: "Please check the Chabad centers or major local supermarkets for kosher sections.")
            } else {
                LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                    ForEach(Array(d.groceries.enumerated()), id: \.offset) { i, l in
                        SPGroceryCard(l: l) { open(l, .grocery, i) }
                    }
                }
            }
        }
    }

    private func shulsTab(_ d: SPStateData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SPTabHeader(title: "Shuls in \(name)", subtitle: "Shuls, minyan services, and community congregations.")
            if d.shuls.isEmpty {
                SPEmptyBox(title: "No recorded independent synagogues for \(name).",
                           detail: "Please check the Chabad list for minyanim and services.")
            } else {
                LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                    ForEach(Array(d.shuls.enumerated()), id: \.offset) { i, l in
                        SPShulCard(l: l) { open(l, .shul, i) }
                    }
                }
            }
        }
    }

    private func chabadTab(_ d: SPStateData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SPTabHeader(title: "Chabad Directory in \(name)", subtitle: "Contact details, rabbi names, and Shabbat meals across the entire state.")
            if d.chabad.isEmpty {
                SPEmptyBox(title: "No recorded Chabad houses for \(name).",
                           detail: "Please consult our AI Planner chat to check adjacent regions or directories.")
            } else {
                LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                    ForEach(Array(d.chabad.enumerated()), id: \.offset) { i, l in
                        SPChabadCard(l: l) { open(l, .chabad, i) }
                    }
                }
            }
        }
    }

    private func hotelsTab(_ d: SPStateData) -> some View {
        let stays = TravelerFilters.notBuiltIn(sights.section(.stay, of: sights.forState(name)), existingNames: d.hotels.map(\.name))
        return VStack(alignment: .leading, spacing: 16) {
            SPTabHeader(title: "Recommended Hotels in \(name)", subtitle: "Lodging convenient to kosher dining, Chabad houses, or eruv systems.")
            if d.hotels.isEmpty && stays.isEmpty {
                SPEmptyBox(title: "No explicitly recommended hotels for \(name).",
                           detail: "Please view specific city guides or consult the Chabad map for lodging options.")
            } else {
                LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                    ForEach(Array(d.hotels.enumerated()), id: \.offset) { i, l in
                        SPHotelCard(l: l) { open(l, .hotel, i) }
                    }
                    // Oct 21 2026: places to stay travelers tagged in this state
                    ForEach(stays) { s in
                        TravelerStayCard(sight: s, onOpen: { selected = s.asPlaceItem(cityName: s.cityName.isEmpty ? name : s.cityName) })
                    }
                }
            }
        }
    }

    private func attractionsTab(_ d: SPStateData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            SPTabHeader(title: "Sightseeing & Attractions in \(name)", subtitle: "List of top landmarks, outdoor activities, and historic sites.")
            if d.attractions.isEmpty {
                SPEmptyBox(title: "No recorded attractions for \(name).")
            } else {
                LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                    ForEach(Array(d.attractions.enumerated()), id: \.offset) { i, l in
                        SPAttractionCard(l: l) { open(l, .todo, i) }
                    }
                }
            }
        }
    }

    private var guidesTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SPTabHeader(systemImage: "safari", title: "Tour Guides in \(name)",
                        subtitle: "Local guides, customized kosher tours, and Jewish heritage experts in \(name).")
            SPGuidesDirectoryBox(title: "\(name) Tour Guides Directory",
                                 detail: "Curated verified kosher travel guides and historical tours across \(name) are being finalized for this directory.")
        }
    }
}

/// Four grey rows while a region page's lists are gathered (web isAggregatingStateData skeleton).
struct SPSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 4).fill(Color.hairline).frame(width: 120, height: 16)
            LazyVGrid(columns: SPGrid.columns, spacing: 16) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12).fill(Color.hairline).frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 4).fill(Color.hairline).frame(height: 14).padding(.trailing, 40)
                            RoundedRectangle(cornerRadius: 4).fill(Color.surface).frame(height: 12).padding(.trailing, 90)
                        }
                    }
                    .padding(16)
                    .hairline(radius: 16)
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Loading")
    }
}
