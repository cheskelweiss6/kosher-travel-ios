import SwiftUI

/// One card on the Things to Do page (types.ts DeepExperience, as DeepExperiencesView fills it).
struct CityExperience: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var shortDescription: String
    var exactLocation: String
    var photo: String
    var bookingLink: String
    var gpsDirections: String
    var aiTips: String
    /// The listing behind a Top Attractions card, for the place sheet.
    var item: PlaceItem?
    /// A place travelers tagged in their posts (shown first under Top Attractions).
    var sight: SharedSight? = nil
    /// The card's swipeable photos, as the website's PlacePhotosGallery resolves them (empty: just `photo`).
    var photos: [String] = []
}

/// The city's Things to Do page (DeepExperiencesView.tsx): category chips, the cards, and the website's loading,
/// error and empty words. Top Attractions are the website's own list for this city (getEnrichedAttractions:
/// CURATED_ATTRACTIONS + NEW_THINGS_TO_DO, precomputed into Resources/citytodo.json by CityTodoStore), with the
/// destination's travel tips box under the chips; other categories ask the website's discover-experiences endpoint,
/// exactly as the website does.
struct CityThingsToDoView: View {
    let page: CityPage
    let attractions: [PlaceItem]
    /// Names the city already lists (attractions, hotels, shuls, Chabad, restaurants), to drop duplicates.
    var listedNames: [String] = []
    let onSelect: (PlaceItem) -> Void
    private let sights = SharedSights.shared

    static let categoryList = [
        "Top Attractions", "Hidden Gems", "Nature", "Hiking", "Beaches", "Water Sports",
        "Boat Tours & Cruises", "Snorkeling & Scuba Diving", "Kayaking & Canoeing",
        "Wildlife Experiences", "Waterfalls", "Volcanoes & Hot Springs", "ATV & Off-Road Adventures",
        "Adventure Activities", "Fishing", "Bike Tours", "Helicopter Tours", "Hot Air Balloon Rides",
        "Food & Drink", "Shopping & Local Markets", "History & Culture", "Photography Spots",
        "Sunset & Sunrise Views", "Family-Friendly Activities", "Romantic Experiences",
        "Nightlife & Evening Activities", "Festivals & Local Events", "Unique Local Experiences",
    ]

    @State private var active = "Top Attractions"
    @State private var fetched: [CityExperience] = []
    @State private var loading = false
    @State private var error = ""
    /// The website's Top Attractions + travelTips for this city (nil until read, or when the file has no entry).
    @State private var todo: CityTodoEntry?
    @State private var todoLoaded = false
    @Environment(\.openURL) private var openURL

    private var isCaribbean: Bool { page.area == "Caribbean" || page.area == "Central America" }
    private var categories: [String] { isCaribbean ? ["Top Attractions", "Family-Friendly Activities"] : Self.categoryList }

    private var top: [CityExperience] {
        guard todoLoaded else { return [] }
        if let list = todo?.attractions, !list.isEmpty {
            // The city's own listing with the same name keeps the place sheet's extra details (phone, hours, map).
            var own: [String: PlaceItem] = [:]
            for a in attractions { own[Self.simplify(a.venue.name)] = own[Self.simplify(a.venue.name)] ?? a }
            return list.map { t in
                var item: PlaceItem? = nil
                if let m = own[Self.simplify(t.name)] {
                    var v = m.venue
                    if !t.photo.isEmpty { v.photo = t.photo; v.photos = nil }
                    item = PlaceItem(id: m.id, category: m.category, venue: v, destId: m.destId, cityName: m.cityName)
                }
                return CityExperience(name: t.name, shortDescription: t.description, exactLocation: t.location,
                                      photo: t.photo, bookingLink: t.website, gpsDirections: "", aiTips: "", item: item,
                                      photos: t.gallery)
            }
        }
        return attractions.map { a in
            CityExperience(name: a.venue.name, shortDescription: a.venue.description, exactLocation: a.venue.address,
                           photo: a.photos.first ?? "", bookingLink: a.venue.website, gpsDirections: "", aiTips: "", item: a)
        }
    }
    /// Website getEnrichedAttractions' name match: lowercased, accents and anything not a letter or digit removed.
    static func simplify(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
    private var travelTips: [String] { todo?.travelTips ?? [] }
    /// Website: travelers' sights and parks for this city join Top Attractions first.
    private var citySights: [CityExperience] {
        let region = page.stateName.isEmpty ? page.country : page.stateName
        let list = sights.forCity(page.name, region: region).filter { $0.section == .todo || $0.section == .park }
        return TravelerFilters.dedupe(list, existingNames: top.map(\.name) + listedNames + attractions.map(\.venue.name)).map { s in
            CityExperience(name: s.name, shortDescription: "", exactLocation: s.area, photo: s.photo ?? "",
                           bookingLink: "", gpsDirections: "", aiTips: "", item: nil, sight: s)
        }
    }
    private var shown: [CityExperience] { active == "Top Attractions" ? citySights + top : fetched }

    var body: some View {
        ScrollView {
          VStack(spacing: 0) {
            CitySubPageHero()
            VStack(alignment: .leading, spacing: 20) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categories, id: \.self) { c in
                            Button { active = c } label: {
                                Text(c).font(.footnote.weight(.semibold))
                                    .padding(.horizontal, 14).frame(minHeight: 36)
                                    .foregroundStyle(active == c ? Color.white : Color.navy)
                                    .background(active == c ? Color.navy : Color.white, in: Capsule())
                                    .overlay(Capsule().strokeBorder(active == c ? Color.clear : Color.hairline, lineWidth: 1))
                                    .animation(Motion.select, value: active == c)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
                .padding(.horizontal, -Theme.pagePadding)

                if !travelTips.isEmpty { CityTodoAdvisories(tips: travelTips) }

                if loading {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large).tint(Color.navy)
                        Text("Deep researching \(active.lowercased()) in \(page.name)...")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 80)
                } else if !error.isEmpty {
                    Label(error, systemImage: "info.circle")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Color.alert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.alert.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else if active == "Top Attractions" && !todoLoaded {
                    Color.clear.frame(height: 1)
                } else if shown.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "leaf").font(.system(size: 28)).foregroundStyle(Color.textTertiary)
                        Text("No curated local experiences found in this category for \(page.name).")
                            .font(.footnote.weight(.bold)).foregroundStyle(Color.textSecondary)
                        Text("Our AI is still researching unique local gems here. Try checking the \"Attractions & Sights\" tab in the Hub for general activities!")
                            .font(.caption).foregroundStyle(Color.textTertiary)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .hairline(radius: 16)
                    .padding(.vertical, 30)
                } else {
                    LazyVStack(spacing: 18) {
                        ForEach(shown) { exp in card(exp) }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 36)
          }
        }
        .background(Color.white)
        .task(id: active) { await load() }
        .task(id: page.key) {
            let e = await CityTodoStore.shared.entry(for: page.key)
            todo = e
            todoLoaded = true
        }
        .onAppear { sights.ensureLoaded() }
    }

    private func select(_ exp: CityExperience) {
        if let item = exp.item { onSelect(item); return }
        if let s = exp.sight { onSelect(s.asPlaceItem(destId: page.destId, cityName: page.name)); return }
        let v = Venue(name: exp.name, address: exp.exactLocation, phone: "", website: exp.bookingLink == "N/A" ? "" : exp.bookingLink,
                      description: exp.shortDescription, photo: exp.photo, kashrus: "", kind: "Experience")
        onSelect(PlaceItem(id: "exp:\(exp.name)", category: .todo, venue: v, destId: page.destId, cityName: page.name))
    }

    private func card(_ exp: CityExperience) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CityCardGallery(name: exp.name, photos: exp.photos.isEmpty ? [exp.photo] : exp.photos,
                            height: 192, cornerRadius: 12, onTap: { select(exp) })
                .frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exp.name).font(.title3.weight(.heavy)).foregroundStyle(Color.navy)
                    if !exp.exactLocation.isEmpty {
                        Label(exp.exactLocation, systemImage: "mappin").font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
                    }
                    if let s = exp.sight { FromTravelersLink(sight: s).padding(.top, 2) }
                }
                Spacer(minLength: 0)
                Label("EXPERIENCE", systemImage: "sparkles")
                    .font(.system(size: 9, weight: .black)).tracking(0.6)
                    .foregroundStyle(Color.navy)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
            }
            if !exp.shortDescription.isEmpty {
                Text(exp.shortDescription).font(.subheadline).foregroundStyle(Color.textSecondary)
            }
            if !exp.aiTips.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI TRAVEL TIP").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.6).foregroundStyle(Color.navy)
                    Text("\"\(exp.aiTips)\"").font(.caption).italic().foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Divider().overlay(Color.hairline)
            if let s = exp.sight {
                TravelerActionsRow(sight: s)
            } else {
                actionRow(exp)
            }
        }
        .padding(18)
        .background(Color.white)
        .hairline(radius: 16)
        .contentShape(Rectangle())
        .onTapGesture { select(exp) }
    }

    private func actionRow(_ exp: CityExperience) -> some View {
            HStack(spacing: 10) {
                if !exp.bookingLink.isEmpty, exp.bookingLink != "N/A", let u = URL(string: exp.bookingLink) {
                    Button { openURL(u) } label: {
                        Label("Book / Info", systemImage: "arrow.up.right.square").font(.caption.weight(.bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Color.navy).frame(minHeight: 36)
                }
                Spacer(minLength: 0)
                Button { select(exp) } label: {
                    Label("View Details", systemImage: "arrow.right").font(.caption.weight(.black))
                        .padding(.horizontal, 12).frame(minHeight: 36)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain).foregroundStyle(Color.navy)
                if !exp.gpsDirections.isEmpty, exp.gpsDirections != "N/A", let u = URL(string: exp.gpsDirections) {
                    Button { openURL(u) } label: {
                        Label("GPS", systemImage: "map").font(.caption.weight(.bold))
                            .padding(.horizontal, 12).frame(minHeight: 36)
                            .foregroundStyle(.white)
                            .background(Color.navy, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
    }

    @MainActor
    private func load() async {
        guard active != "Top Attractions" else { loading = false; error = ""; return }
        let cat = active
        loading = true; error = ""
        defer { if cat == active { loading = false } }
        var c = URLComponents(string: "https://www.yourkoshertravel.com/api/discover-experiences")!
        c.queryItems = [.init(name: "destination", value: page.name), .init(name: "category", value: cat)]
        do {
            let (data, _) = try await URLSession.shared.data(from: c.url!)
            guard cat == active else { return }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                error = "Failed to fetch experiences"; return
            }
            if let e = obj["error"] as? String { error = e; return }
            let list = (obj["experiences"] as? [[String: Any]]) ?? []
            fetched = list.map { d in
                func s(_ k: String) -> String { (d[k] as? String) ?? "" }
                return CityExperience(name: s("name"), shortDescription: s("shortDescription"), exactLocation: s("exactLocation"),
                                      photo: ((d["photos"] as? [String]) ?? []).first ?? "", bookingLink: s("bookingLink"),
                                      gpsDirections: s("gpsDirections"), aiTips: s("aiTips"), item: nil)
            }
        } catch {
            if cat == active { self.error = "Failed to fetch experiences" }
        }
    }
}
