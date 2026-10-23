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
        let secs = sections(page)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    hero(page)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.bottom, 14)
                    Section {
                        if secs.isEmpty {
                            EmptyNote(title: "No listings for \(page.name) yet", detail: "Know a kosher place here? Share it in a story.",
                                      systemImage: "mappin.and.ellipse")
                                .padding(.horizontal, Theme.pagePadding)
                                .padding(.top, 16)
                        }
                        ForEach(secs) { section in
                            sectionView(section, page: page)
                        }
                        if !page.hasidic.isEmpty { hasidicCard(page.hasidic) }
                        TravelerArticlesSection(kind: .city, placeName: page.name)
                            .padding(.top, 32)
                    } header: {
                        if !secs.isEmpty { chipBar(secs, proxy: proxy) }
                    }
                }
                .padding(.bottom, 36)
            }
        }
        .background(Color.white)
        .navigationTitle(page.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMap = true } label: {
                    Label("Map", systemImage: "map")
                }
                .accessibilityLabel("Map of \(page.name)")
            }
        }
        .refreshable { await loadLive(page, force: true) }
        .task(id: baseKey) {
            applyRoute(page)
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
            CityMapView(page: page, items: secs.flatMap(\.items), onOpenStory: { id in openStoryLater(id) })
        }
        .navigationDestination(item: $openStory) { id in
            StoryDetailView(postId: id)
        }
    }

    // MARK: hero, facts

    private func hero(_ page: CityPage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RemoteImage(url: page.photo, maxPixel: 1400)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .accessibilityHidden(true)
            Text(page.subtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            if !page.description.isEmpty {
                Text(page.description)
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            facts(page)
        }
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

    private func applyRoute(_ page: CityPage) {
        guard !routed else { return }
        routed = true
        guard let sub = subRoute else { return }
        if sub == "map" {
            showMap = true
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
