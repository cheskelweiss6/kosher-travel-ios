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
    @State private var expanded = Set<PlaceCategory>()
    @State private var routed = false
    @State private var activeChip: PlaceCategory?
    @State private var openHub: CityHub?
    @State private var webSection: WebRoute?
    @State private var scrollToGuides = false
    @State private var addingGuide = false
    @State private var confirmUnsave = false
    @State private var todoHubPhoto: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
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
        .confirmationDialog("Remove \(page.name) from your saved places?", isPresented: $confirmUnsave, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { bucket.toggle(page.destId) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $addingGuide) {
            AddTourGuideSheet(page: page) { g in
                TourGuideStore.shared.add(g)
                ShellRouter.shared.showToast("Tour Guide \"\(g.guideName)\" added successfully!")
            }
        }
        .navigationTitle(page.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                // Web: Save / Saved heart (the bucket list shown in My Travel).
                let saved = bucket.contains(page.destId)
                // Cheskel's rule (Oct 23 9:20): every removal asks first, in red.
                Button { if saved { confirmUnsave = true } else { bucket.toggle(page.destId) } } label: {
                    // Website (App.tsx 10058-10068): a pill with the heart and the words "Save" / "Saved".
                    Label(saved ? "Saved" : "Save", systemImage: saved ? "heart.fill" : "heart")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Color.navy)
                }
                .sensoryFeedback(.success, trigger: saved)
                // The native-only Map button is gone (the website's city header has none); "<key>/map" links still open it.
                Button {
                    // Website: setWizardCity(name) + the planner tab, i.e. "Plan a trip" with the city in "Where to?".
                    ShellRouter.shared.plannerTripCity = page.name
                    ShellRouter.shared.open(tab: "planner")
                } label: {
                    // Website: "Plan" on a phone, "Plan Trip" on wider screens.
                    Label(sizeClass == .regular ? "Plan Trip" : "Plan", systemImage: "sparkles")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.navy)
                .accessibilityLabel("Plan a trip to \(page.name)")
            }
        }
        .refreshable { await loadLive(page, force: true) }
        .task(id: auth.uid) { await bucket.bind(uid: auth.uid) }
        .task(id: baseKey) {
            applyRoute(page)
            // Website: the Things to Do hub card shows getEnrichedAttractions(...)[0]'s photo.
            todoHubPhoto = await CityTodoStore.shared.entry(for: page.key)?.attractions.first?.photo
            await loadLive(page, force: false)
        }
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
        .navigationDestination(item: $webSection) { route in
            WebScreen(route: route)
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
            .environment(\.cityHero, AnyView(heroBlock(page)))
            // Web breadcrumb: "Denver / Restaurants" (just the city on pages without a crumb word).
            .navigationTitle(hub.crumb.isEmpty ? page.name : "\(page.name) / \(hub.crumb)")
            .navigationBarTitleDisplayMode(.inline)
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
        } else if CityHub.nativePages.contains(hub) {
            CityHubPage(hub: hub, page: page, sections: sections(page),
                        summary: { summary(for: $0) }, onSelect: { selected = $0 },
                        onReviewsChanged: { updateSummary($0, $1) })
        } else {
            listSubPage(hub, page: page)
        }
    }

    @ViewBuilder
    private func listSubPage(_ hub: CityHub, page: CityPage) -> some View {
        let secs = sections(page).filter { hub.categories.contains($0.category) }
        ScrollView {
            CitySubPageHero()
            LazyVStack(alignment: .leading, spacing: 0) {
                if hub == .hasidic {
                    hasidicCard(page.hasidic)
                } else if secs.isEmpty {
                    EmptyNote(title: "Nothing listed in \(page.name) yet", detail: "Know a kosher place here? Share it in a story.",
                              systemImage: "mappin.and.ellipse")
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.top, 16)
                }
                ForEach(secs) { section in
                    sectionView(section, page: page)
                }
                if hub == .shuls, let e = page.eruv { eruvCard(e) }
            }
            .padding(.bottom, 36)
        }
        .background(Color.white)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: hero (web: full-width photo, region / state / country pills, the name and the description over it)

    private func heroBlock(_ page: CityPage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if !page.area.isEmpty {
                    Text(page.area.uppercased())
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
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 280, alignment: .bottomLeading)
        .background {
            RemoteImage(url: page.photo, maxPixel: 1600, venue: true)
                .overlay {
                    LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.6), .black.opacity(0.95)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .clipped()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func facts(_ page: CityPage) -> some View {
        let airport = [page.airport, page.airportDistance].filter { !$0.isEmpty }.joined(separator: " · ")
        let rows: [FactRow] = [
            FactRow(icon: "airplane", text: airport),
            FactRow(icon: "cloud.sun", text: page.weather),
        ].filter { !$0.text.isEmpty }
        if !rows.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Rectangle().fill(Color.hairline).frame(width: 0.5).padding(.vertical, 10) }
                        factCell(row, oneLine: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Divider().overlay(Color.hairline) }
                        factCell(row, oneLine: false)
                    }
                }
            }
            .hairline(radius: 14)
        }
    }

    private func factCell(_ row: FactRow, oneLine: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.navy)
            Text(row.text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.navy)
                .fixedSize(horizontal: oneLine, vertical: !oneLine)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    // MARK: chip bar

    private func chipBar(_ secs: [CitySection], proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(secs) { s in
                    Button {
                        activeChip = s.category
                        withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("sec-\(s.id)", anchor: .top) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: s.category.systemImage).font(.system(size: 12, weight: .regular))
                            Text(s.category.chip).font(.footnote.weight(.semibold))
                            if s.items.count > 0 {
                                Text("\(s.items.count)").font(.caption2.weight(.semibold)).foregroundStyle(activeChip == s.category ? Color.white.opacity(0.8) : Color.textSecondary)
                            }
                        }
                        .foregroundStyle(activeChip == s.category ? Color.white : Color.navy)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(activeChip == s.category ? Color.navy : Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(activeChip == s.category ? Color.navy : Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(s.category.title), \(s.items.count)")
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 10)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 0.5) }
        .sensoryFeedback(.selection, trigger: activeChip)
    }

    // MARK: sections

    private static let listLimit = 6

    @ViewBuilder
    private func sectionView(_ section: CitySection, page: CityPage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Anchor for the chip bar: tall enough that the pinned bar does not cover the section title.
            Color.clear.frame(height: 52).id("sec-\(section.id)")
            SectionHeader(title: section.category.title, count: section.items.count)
                .padding(.horizontal, Theme.pagePadding)
            if section.category == .takeout {
                Text("These are local Chabad-organized meal packages, tourist catering, or home-cooked delivery services rather than commercial restaurants. Ideal for Shabbos and midweek dining!")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Theme.pagePadding)
            }
            if section.category == .traveler {
                Text("Added by travelers in their stories and approved by Kosher Travel.")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Theme.pagePadding)
            }
            if section.category.usesCards {
                cards(section.items)
            } else {
                list(section)
            }
            if section.category == .mikvah, let eruv = page.eruv {
                eruvCard(eruv)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, section.items.isEmpty ? 0 : 6)
            }
        }
    }

    @ViewBuilder
    private func list(_ section: CitySection) -> some View {
        let all = section.items
        let open = expanded.contains(section.category)
        let shown = open ? all : Array(all.prefix(Self.listLimit))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown) { item in
                Button { selected = item } label: {
                    CityPlaceRow(item: item, summary: summary(for: item))
                }
                .buttonStyle(.plain)
                .contextMenu { contextActions(item) }
                if item.id != shown.last?.id { Divider().overlay(Color.hairline).padding(.leading, 68) }
            }
            if all.count > Self.listLimit {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if open { expanded.remove(section.category) } else { expanded.insert(section.category) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(open ? "Show fewer" : "Show all \(all.count)")
                        Image(systemName: open ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .hairline(radius: 12)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private func cards(_ items: [PlaceItem]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items) { item in
                    Button { selected = item } label: {
                        CityPlaceCard(item: item, summary: summary(for: item))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { contextActions(item) }
                    .containerRelativeFrame(.horizontal) { len, _ in Layout.peekWidth(len, min: 210, spacing: 12) }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }

    @ViewBuilder
    private func contextActions(_ item: PlaceItem) -> some View {
        if let tel = item.phoneURL {
            Link(destination: tel) { Label("Call", systemImage: "phone") }
        }
        if let d = item.directionsURL, !item.venue.address.isEmpty {
            Link(destination: d) { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
        }
        if let w = item.websiteURL {
            Link(destination: w) { Label("Website", systemImage: "safari") }
        }
        if let m = item.appleMapsURL {
            ShareLink(item: m, subject: Text(item.venue.name), message: Text(item.shareText)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func eruvCard(_ e: EruvInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(e.name.isEmpty ? "Eruv" : e.name, systemImage: "circle.dashed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.navy)
            Text(e.description).font(.footnote).foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if !e.boundary.isEmpty {
                Text("Boundary: \(e.boundary)").font(.footnote).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !e.notes.isEmpty {
                Text(e.notes).font(.footnote).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Check the eruv is up before Shabbat.").font(.caption).foregroundStyle(Color.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairline(radius: 14)
    }

    private func hasidicCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(height: 24)
            SectionHeader(title: "Jewish Community")
            Text(text).font(.subheadline).foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    // MARK: live data

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

/// One listing in a list: photo or category icon, name, hechsher or type, address, reviews line.
struct CityPlaceRow: View {
    let item: PlaceItem
    let summary: PlaceReviewSummary?
    @ScaledMetric(relativeTo: .subheadline) private var thumb: CGFloat = 56

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let p = item.photos.first {
                    RemoteImage(url: p, maxPixel: 240, venue: true, category: item.photoCategory)
                } else if PhotoFallback.category(item.photoCategory) != nil {
                    RemoteImage(url: "", maxPixel: 240, venue: true, category: item.photoCategory)
                } else {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.navy)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white)
                }
            }
            .frame(width: thumb, height: thumb)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .hairline(radius: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.venue.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if item.travelerCategory != nil {
                    Text([item.venue.kind, item.venue.kashrus].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
                } else if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                if !item.venue.address.isEmpty {
                    Text(item.venue.address).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
                } else if !item.venue.description.isEmpty {
                    Text(item.venue.description).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                if let summary {
                    if summary.count > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Color.navy)
                            Text(String(format: "%.1f", summary.avg)).font(.caption.weight(.semibold)).foregroundStyle(Color.navy)
                            Text("· \(summary.count) review\(summary.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        Text("No reviews yet").font(.caption).foregroundStyle(Color.textTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }
}

/// A photo card for things to do, hotels and rentals.
struct CityPlaceCard: View {
    let item: PlaceItem
    let summary: PlaceReviewSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: item.photos.first ?? "", maxPixel: 700, venue: true, category: item.photoCategory)
                .aspectRatio(4 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if item.photos.isEmpty && PhotoFallback.category(item.photoCategory) == nil {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.navy)
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.venue.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                let line = [item.venue.price ?? "", item.venue.description].first { !$0.isEmpty } ?? item.venue.address
                if !line.isEmpty {
                    Text(line).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                if let summary, summary.count > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Color.navy)
                        Text(String(format: "%.1f", summary.avg)).font(.caption.weight(.semibold)).foregroundStyle(Color.navy)
                        Text("· \(summary.count)").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details")
    }
}

struct FactRow: Identifiable {
    var id: String { icon }
    let icon: String
    let text: String
}

/// Compact row with call / website / directions buttons (kept for other screens; the city page uses CityPlaceRow).
struct VenueRow: View {
    let venue: Venue
    let systemImage: String
    @ScaledMetric(relativeTo: .subheadline) private var icon: CGFloat = 34

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.navy)
                .frame(width: icon, height: icon)
                .hairline(radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(venue.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                if !venue.kashrus.isEmpty {
                    Text(venue.kashrus).font(.caption).foregroundStyle(Color.textSecondary)
                }
                if !venue.address.isEmpty {
                    Text(venue.address).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
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

    /// Sub-pages with their own native page in the website's layout (CityHubPage).
    static let nativePages: Set<CityHub> = [.grocery, .chabad, .shuls, .hotels, .rentals, .businesses, .resources, .hasidic]

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

    /// Hubs the app still shows as the live page (web activeCitySubCategory names).
    var webSection: String {
        switch self {
        case .shabbat: return "shabbat"
        case .guides: return "guides"
        case .experience: return "experience"
        default: return rawValue
        }
    }
}
