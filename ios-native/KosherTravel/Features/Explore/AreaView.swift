import SwiftUI

/// A city / destination page, like the website's: hero photo, description, quick facts, a chip bar of the sections
/// that have listings, every section (restaurants, grocery, Chabad, shuls, mikvah and eruv, things to do, hotels,
/// rentals, catering, businesses, community, places travelers added), articles from travelers, and a map.
/// Tapping a listing opens its sheet (details, directions, call, website, share, reviews).
/// QA sub-routes after the key: `<key>/map` opens the map, `<key>/place:<n>` opens the n-th listing's sheet.
struct AreaView: View {
    @Environment(ExploreStore.self) private var store
    let areaKey: String

    private let baseKey: String
    private let subRoute: String?

    @State private var traveler: [PlaceItem] = []
    @State private var summaries: [String: PlaceReviewSummary]?
    @State private var selected: PlaceItem?
    @State private var showMap = false
    @State private var openStory: String?
    @State private var routed = false
    @State private var openHub: CityHub?
    @State private var scrollToGuides = false
    @State private var addingGuide = false
    @State private var todoHubPhoto: String?
    @Environment(AuthStore.self) private var auth
    private let bucket = BucketList.shared

    init(areaKey: String) {
        self.areaKey = areaKey
        if let slash = areaKey.firstIndex(of: "/") {
            baseKey = String(areaKey[..<slash])
            let rest = String(areaKey[areaKey.index(after: slash)...])
            subRoute = rest.isEmpty ? nil : rest
        } else {
            baseKey = areaKey
            subRoute = nil
        }
    }

    private var page: CityPage? {
        guard let data = store.data else { return nil }
        return CityPage.build(key: baseKey, data: data)
    }

    var body: some View {
        if let page {
            content(page)
        } else {
            ContentUnavailableView("Not found", systemImage: "map", description: Text("This place is not in the app yet."))
        }
    }

    private func sections(_ page: CityPage) -> [CitySection] {
        var out = page.sections
        if !traveler.isEmpty { out.append(CitySection(category: .traveler, items: traveler)) }
        return out
    }

    @ViewBuilder
    private func content(_ page: CityPage) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroBlock(page)
                // Web order: the articles row first, then the facts, needs and hubs.
                TravelerArticlesSection(kind: .city, placeName: page.name,
                                        region: page.stateName.isEmpty ? page.country : page.stateName)
                    .padding(.top, 14)
                if !traveler.isEmpty {
                    addedByTravelers.padding(.horizontal, Theme.pagePadding).padding(.top, 14)
                }
                // Web PlaceStories ends with the travelers' tips about this city (Oct 23 2026).
                TravelerTipsSection(scope: TipScope(kind: .city, name: page.name,
                                                    region: page.stateName.isEmpty ? page.country : page.stateName),
                                    insets: EdgeInsets(top: 14, leading: Theme.pagePadding, bottom: 0, trailing: Theme.pagePadding))
                // Web: Zmanim for this city, computed on the phone (compact card), right after the articles.
                ZmanimCard(place: ZmanimPlace(id: page.destId, name: page.name,
                                              state: page.stateName.isEmpty ? page.country : page.stateName),
                           compact: true)
                    .padding(.horizontal, Theme.pagePadding).padding(.top, 14)
                VStack(alignment: .leading, spacing: 14) {
                    CityNeedsBlock(page: page, sections: sections(page))
                    if hubs(page).isEmpty == false {
                        LazyVStack(spacing: 12) {
                            ForEach(hubs(page)) { hub in
                                if hub == .guides { guidesCard(page) } else { hubCard(hub, page: page) }
                            }
                        }
                    }
                    // Website: "Tour Guides in {city}" sits on the hub under the cards; the Travel Guides card scrolls here.
                    CityTourGuidesSection(page: page)
                        .padding(.top, 10)
                        .id("city-tour-guides-section")
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 14)
            }
            .padding(.bottom, 36)
        }
        .onChange(of: scrollToGuides) { _, go in
            guard go else { return }
            withAnimation(.smooth) { proxy.scrollTo("city-tour-guides-section", anchor: .top) }
            scrollToGuides = false
        }
        }
        .background(Color.white)
        .sheet(isPresented: $addingGuide) {
            AddTourGuideSheet(page: page) { g in
                TourGuideStore.shared.add(g)
                ShellRouter.shared.showToast("Tour Guide \"\(g.guideName)\" added successfully!")
            }
        }
        // Website: Back, Save and Plan Trip sit on the hero photo (CityHeroBar), so the iOS bar is hidden here.
        // The title stays for the long-press back menu; the edge swipe still goes back.
        .navigationTitle(page.name)
        .toolbar(.hidden, for: .navigationBar)
        .background(PopGestureEnabler().frame(width: 0, height: 0))
        .refreshable { await loadLive(page, force: true) }
        .task(id: auth.uid) { await bucket.bind(uid: auth.uid) }
        .task(id: baseKey) {
            applyRoute(page)
            // Website: the Things to Do hub card shows getEnrichedAttractions(...)[0]'s photo.
            todoHubPhoto = await CityTodoStore.shared.entry(for: page.key)?.attractions.first?.photo
            await loadLive(page, force: false)
        }
        .task { await TravelerTipsStore.shared.fetch() }
        .sheet(item: $selected) { item in
            PlaceDetailView(item: item, onOpenStory: { id in openStoryLater(id) }, onReviewsChanged: { key, list in
                updateSummary(key, list)
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $showMap) {
            CityMapView(page: page, items: sections(page).flatMap(\.items), onOpenStory: { id in openStoryLater(id) })
        }
        .navigationDestination(item: $openStory) { id in
            StoryDetailView(postId: id)
        }
        .navigationDestination(item: $openHub) { hub in
            subPage(hub, page: page)
        }
    }

    // MARK: hub (web: the city page's photo cards, each opening its own page)

    private func hubs(_ page: CityPage) -> [CityHub] {
        let secs = sections(page)
        func has(_ c: PlaceCategory) -> Bool { secs.contains { $0.category == c && !$0.items.isEmpty } }
        var out: [CityHub] = []
        // Web: the Restaurants card needs a public restaurant; Chabad takeout sits on the Chabad page.
        if has(.restaurant) { out.append(.restaurants) }
        if has(.grocery) { out.append(.grocery) }
        if has(.chabad) { out.append(.chabad) }
        if has(.shul) { out.append(.shuls) }
        out.append(.todo)
        out.append(.hotels)
        out.append(.shabbat)
        if !page.hasidic.isEmpty { out.append(.hasidic) }
        if has(.rental) { out.append(.rentals) }
        if has(.business) { out.append(.businesses) }  // web: businessesAndServicesList only
        if has(.resource) { out.append(.resources) }
        out.append(.guides)
        if page.area == "Caribbean" || page.area == "Europe" { out.append(.experience) }
        return out
    }

    private func hubPhoto(_ hub: CityHub, page: CityPage) -> (url: String, category: String?) {
        let secs = sections(page)
        // Website: the FIRST listing's photo (allGroceries[0]?.photo || fallback), not the first listing that has one.
        func first(_ c: PlaceCategory) -> String? {
            guard let p = secs.first(where: { $0.category == c })?.items.first?.photos.first,
                  !p.isEmpty, !PhotoFallback.isPlaceholder(p) else { return nil }
            return p
        }
        switch hub {
        case .restaurants: return (page.photo, nil)
        case .grocery: return (first(.grocery) ?? "", "grocery")
        case .chabad: return ("", "chabad")
        case .shuls: return ("", "shul")
        case .todo:
            if let p = todoHubPhoto, !p.isEmpty { return (p, nil) }
            return (first(.todo) ?? page.photo, nil)
        case .hotels: return (first(.hotel) ?? page.photo, nil)
        case .shabbat: return ("https://kosher-travel-img.sites.tab.bot/wm/f88a9d27526e390c.webp", nil)
        default: return (page.photo, nil)
        }
    }

    /// The Travel Guides card (App.tsx 10714-10776): photo with the title, the text, then "Add Guide" and "View".
    /// The photo, the text and View scroll down to "Tour Guides in {city}" on this page.
    private func guidesCard(_ page: CityPage) -> some View {
        let hub = CityHub.guides
        let photo = hubPhoto(hub, page: page)
        return VStack(alignment: .leading, spacing: 0) {
            Button { scrollToGuides = true } label: {
                RemoteImage(url: photo.url, maxPixel: 900, venue: true, category: photo.category)
                    .frame(height: 128)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottomLeading) {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.3), .clear], startPoint: .bottom, endPoint: .top)
                            Text(hub.title).font(.footnote.weight(.heavy)).foregroundStyle(.white).padding(12)
                        }
                    }
                    .clipped()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(hub.title)
            VStack(alignment: .leading, spacing: 10) {
                Button { scrollToGuides = true } label: {
                    Text(hub.text(page))
                        .font(.caption).foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Divider().overlay(Color.hairline)
                // Website: navy "Add Guide" button on the left, a "View ›" text link on the right.
                HStack(spacing: 8) {
                    Button { addingGuide = true } label: {
                        Label("Add Guide", systemImage: "plus")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 10).frame(minHeight: 32)
                            .foregroundStyle(.white)
                            .background(Color.navy, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 8)
                    Button { scrollToGuides = true } label: {
                        HStack(spacing: 2) {
                            Text("View")
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.navy)
                        .frame(minWidth: 44, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
    }

    private func hubCard(_ hub: CityHub, page: CityPage) -> some View {
        let photo = hubPhoto(hub, page: page)
        return Button {
            switch hub {
            default:
                openHub = hub
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                RemoteImage(url: photo.url, maxPixel: 900, venue: true, category: photo.category)
                    .frame(height: 128)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottomLeading) {
                        ZStack(alignment: .bottomLeading) {
                            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.3), .clear], startPoint: .bottom, endPoint: .top)
                            Text(hub.title)
                                .font(.footnote.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(12)
                        }
                    }
                    .clipped()
                HStack(alignment: .center, spacing: 8) {
                    Text(hub.text(page))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(12)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hub.title)
    }

    @ViewBuilder
    private func subPage(_ hub: CityHub, page: CityPage) -> some View {
        subPageBody(hub, page: page)
            // Web: the hero (with the "Denver / Restaurants" back pill, Save and Plan) tops every sub-page.
            .environment(\.cityHero, AnyView(heroBlock(page, crumb: hub.crumb)))
            .navigationTitle(hub.crumb.isEmpty ? page.name : "\(page.name) / \(hub.crumb)")
            .toolbar(.hidden, for: .navigationBar)
            .background(PopGestureEnabler().frame(width: 0, height: 0))
    }

    @ViewBuilder
    private func subPageBody(_ hub: CityHub, page: CityPage) -> some View {
        if hub == .restaurants {
            CityRestaurantsView(items: sections(page).first { $0.category == .restaurant }?.items ?? [],
                                cityName: page.name,
                                summary: { summary(for: $0) },
                                onSelect: { selected = $0 },
                                onReviewsChanged: { updateSummary($0, $1) })
        } else if hub == .guides {
            CityGuidesView(page: page)
        } else if hub == .shabbat {
            CityShabbatView(page: page, hasChabad: !(sections(page).first { $0.category == .chabad }?.items.isEmpty ?? true))
        } else if hub == .experience {
            CityExperienceView(page: page)
        } else if hub == .todo {
            CityThingsToDoView(page: page, attractions: sections(page).first { $0.category == .todo }?.items ?? [],
                               listedNames: page.listedNames, onSelect: { selected = $0 })
        } else {
            CityHubPage(hub: hub, page: page, sections: sections(page),
                        summary: { summary(for: $0) }, onSelect: { selected = $0 },
                        onReviewsChanged: { updateSummary($0, $1) })
        }
    }

    // MARK: hero (web: full-width photo, region / state / country pills, the name and the description over it)

    private func heroBlock(_ page: CityPage, crumb: String = "") -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CityHeroBar(cityName: page.name, destId: page.destId, crumb: crumb)
            Spacer(minLength: 12)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if !page.area.isEmpty {
                    Text(TravelRegions.label(region: page.area, country: page.country).uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.2), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                }
                if !page.stateName.isEmpty {
                    Text(page.stateName).font(.caption.weight(.heavy)).foregroundStyle(.white)
                }
                if !page.country.isEmpty {
                    Text("• \(page.country)").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            Text(page.name)
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
            TravelChip(name: page.name, country: page.country.isEmpty ? nil : page.country,
                       state: page.stateName.isEmpty ? nil : page.stateName, tone: .dark, words: true)
            if !page.description.isEmpty {
                Text(page.description)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .bottomLeading)
        .background {
            // The photo runs up under the status bar, as on the website (pt = the safe-area inset).
            RemoteImage(url: page.photo, maxPixel: 1600, venue: true)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.6), .black.opacity(0.95)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea(edges: .top)
                .clipped()
        }
    }

    private func summary(for item: PlaceItem) -> PlaceReviewSummary? {
        guard let key = item.reviewKey, let summaries else { return nil }
        return summaries[key] ?? PlaceReviewSummary([])
    }

    private func updateSummary(_ key: String, _ list: [PlaceReview]) {
        var s = summaries ?? [:]
        s[key] = PlaceReviewSummary(list)
        summaries = s
    }

    private func loadLive(_ page: CityPage, force: Bool) async {
        async let places = CityTravelerPlaces.forCity(page, force: force)
        let r = try? await PlaceReviewService.destReviews(destId: page.destId)
        let p = await places
        traveler = p
        if let r {
            summaries = r.mapValues { PlaceReviewSummary($0) }
        }
        print("[KT] city \(page.destId): traveler places=\(p.count) reviewed places=\(r?.count ?? -1)")
    }

    /// Web PlaceStories "Added by travelers": approved places travelers sent in, under the articles row.
    private var addedByTravelers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Added by travelers").font(.footnote.weight(.heavy)).foregroundStyle(Color.navy)
            ForEach(traveler) { tp in
                HStack(spacing: 12) {
                    Image(systemName: tp.systemImage).font(.system(size: 17)).foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tp.venue.name).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy).lineLimit(1)
                        Text([Self.webCategoryLabel(tp.travelerCategory), tp.venue.kashrus, tp.venue.address].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
                        Text("Added by a traveler").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.navy)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.surface, in: Capsule())
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                    let digits = tp.venue.phone.filter { $0.isNumber || $0 == "+" }
                    if !tp.venue.phone.isEmpty, let tel = URL(string: "tel:\(digits)") {
                        Link("Call", destination: tel).font(.caption.weight(.bold)).foregroundStyle(Color.navy)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                }
                .padding(12)
                .background(Color.white)
                .hairline(radius: 16)
                // Website: these rows are static (only Call is a link).
            }
        }
    }

    /// Website PLACE_CATEGORY_LABEL (storyService.ts).
    static func webCategoryLabel(_ c: PlaceCategory?) -> String {
        switch c {
        case .restaurant?: return "Restaurant"
        case .grocery?: return "Grocery"
        case .chabad?: return "Chabad"
        case .shul?: return "Shul"
        case .hotel?: return "Hotel"
        case .todo?: return "Things to do"
        case .mikvah?: return "Mikvah"
        default: return ""
        }
    }

    private func applyRoute(_ page: CityPage) {
        guard !routed else { return }
        routed = true
        guard let sub = subRoute else { return }
        if sub == "map" {
            showMap = true
        } else if sub.hasPrefix("hub:"), let h = CityHub(rawValue: String(sub.dropFirst(4))) {
            openHub = h
        } else if sub.hasPrefix("place:"), let n = Int(sub.dropFirst(6)) {
            let all = page.allItems
            if all.indices.contains(n) { selected = all[n] }
        }
    }

    private func openStoryLater(_ id: String) {
        selected = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { openStory = id }
    }
}

/// The city page's photo cards (web App.tsx city hub), in the website's order.
enum CityHub: String, Identifiable, Hashable {
    case restaurants, grocery, chabad, shuls, todo, hotels, shabbat, hasidic, rentals, businesses, resources, guides, experience, traveler
    var id: String { rawValue }

    var title: String {
        switch self {
        case .restaurants: return "Kosher Restaurants"
        case .grocery: return "Kosher Grocery"
        case .chabad: return "Chabad Directory"
        case .shuls: return "Shuls"
        case .todo: return "Things to Do"
        case .hotels: return "Hotels"
        case .shabbat: return "Shabbat Info"
        case .hasidic: return "Hasidic Community"
        case .rentals: return "Vacation Rentals"
        case .businesses: return "Businesses & Services"
        case .resources: return "Community Resources"
        case .guides: return "Travel Guides"
        case .experience: return "Travel Experience"
        case .traveler: return "Places Travelers Added"
        }
    }

    func text(_ page: CityPage) -> String {
        switch self {
        case .restaurants: return "Browse local certified kosher diners, cafes, and grill houses."
        case .grocery: return "Supermarkets and specialty stores stocked with kosher foods."
        case .chabad: return "Chabad house contacts, rabbi details, and Shabbat meals."
        case .shuls: return "Minyan schedules, local community centers, Mikvah and Eruv info."
        case .todo: return "Discover what makes \(page.name) truly unforgettable. Top attractions, activities, and local heritage."
        case .hotels: return "Recommended accommodations near kosher amenities."
        case .shabbat: return "Zmanim, candle lighting, Eruv map status and walking guidelines."
        case .hasidic: return page.hasidic
        case .rentals: return "Luxury homes with private pool barriers, kosher kitchens, and Shabbat setups."
        case .businesses: return "Scribes, Judaica book stores, and state-of-the-art Mikvaot."
        case .resources: return "Local community directories, WhatsApp forums, and visitor chats."
        case .guides: return "Verified kosher travel guides, walking tours, and excursions in \(page.name)."
        case .experience: return "Travel stories and community experiences in \(page.name)."
        case .traveler: return "Places travelers tagged in \(page.name)."
        }
    }

    /// The website's breadcrumb word after the city name (App.tsx back button).
    var crumb: String {
        switch self {
        case .restaurants: return "Restaurants"
        case .grocery: return "Groceries"
        case .chabad: return "Chabad"
        case .shuls: return "Synagogues"
        case .todo: return "Things to Do"
        case .hotels: return "Hotels"
        case .shabbat: return "Shabbat"
        case .guides: return "Travel Guides"
        case .experience: return "Travel Experience"
        default: return ""
        }
    }

    /// The listing sections a native sub-page shows.
    var categories: [PlaceCategory] {
        switch self {
        case .restaurants: return [.restaurant]
        case .grocery: return [.grocery]
        case .chabad: return [.chabad, .takeout]
        case .shuls: return [.shul, .mikvah]
        case .todo: return [.todo]
        case .hotels: return [.hotel]
        case .rentals: return [.rental]
        case .businesses: return [.business, .catering]
        case .resources: return [.resource]
        case .traveler: return [.traveler]
        default: return []
        }
    }
}
