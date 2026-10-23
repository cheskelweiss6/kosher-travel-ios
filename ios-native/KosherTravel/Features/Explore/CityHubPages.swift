import SwiftUI

/// The website's listing card on a city sub-page (grocery, Chabad, shuls, hotels, rentals, businesses, resources,
/// catering): the icon box, name, badges and rating line, the swipeable photo gallery, detail lines, and the action chips.
/// `isStatic` is the website's plain card (rentals, businesses, resources, catering, Chabad takeout): no tap, no photo,
/// no View Details, Reviews or Directions; only its link.
struct CityListingCard: View {
    struct Line: Identifiable {
        let icon: String
        let label: String?
        let text: String
        /// Makes the line a link (a phone number to call).
        var url: URL? = nil
        var id: String { (label ?? icon) + text }
    }

    let item: PlaceItem
    var badges: [String] = []
    var showPhoto = true
    var lines: [Line] = []
    var tags: [String] = []
    var notice: (title: String, text: String, strong: Bool)? = nil
    var linkLabel: String = "Website"
    var showReviews = true
    var showDirections = true
    /// A small button under the name (hotels: "Show Radius", App.tsx 12667-12675).
    var extra: (title: String, icon: String, action: () -> Void)? = nil
    /// The pill at the top right (hotels: the price; Chabad: "Shabbat Meals").
    var trailing: String? = nil
    var isStatic = false
    /// The city page's name: the website passes it to the photo gallery.
    var city: String = ""
    let summary: PlaceReviewSummary?
    let onSelect: () -> Void
    /// Opens the Reviews sheet (the rating line and the Reviews chip). Without it they open the place sheet.
    var onReviews: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL

    var body: some View {
        if isStatic {
            content.padding(16).background(Color.white).hairline(radius: 16)
                .accessibilityElement(children: .contain)
        } else {
            content
                .padding(16)
                .background(Color.white)
                .hairline(radius: 16)
                .contentShape(Rectangle())
                .onTapGesture { onSelect() }
                .accessibilityElement(children: .contain)
        }
    }

    private var openReviews: () -> Void { onReviews ?? onSelect }

    private var trailingPill: String? {
        if let trailing, !trailing.isEmpty { return trailing }
        if item.category == .hotel, let price = item.venue.price, !price.isEmpty { return price }
        return nil
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                if !isStatic {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.navy)
                        .frame(width: 32, height: 32)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .hairline(radius: 10)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.venue.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.navy)
                        .multilineTextAlignment(.leading)
                    if let e = extra {
                        Button(action: e.action) {
                            Label(e.title.uppercased(), systemImage: e.icon)
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(Color.navy)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Color.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .frame(minHeight: 36)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if !badges.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(badges.enumerated()), id: \.offset) { i, b in
                                if i == 0 && !isStatic {
                                    Text(b.uppercased())
                                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                        .tracking(1)
                                        .foregroundStyle(Color.navy)
                                } else {
                                    Text(b.uppercased())
                                        .font(.caption2.weight(.heavy))
                                        .tracking(0.6)
                                        .foregroundStyle(Color.navy)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .hairline(radius: 6)
                                }
                            }
                        }
                    }
                    if !isStatic, showReviews, item.reviewKey != nil {
                        CityCardRating(summary: summary, onOpen: openReviews)
                    }
                }
                Spacer(minLength: 0)
                if let t = trailingPill {
                    Text(t).font(.caption.weight(.bold)).foregroundStyle(Color.navy)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 8).padding(.vertical, 4).hairline(radius: 8)
                }
            }
            if showPhoto && !isStatic {
                CityCardGallery(name: item.venue.name,
                                photos: CityCardPhotos.forItem(item, city: city),
                                defaultCategory: CityCardPhotos.defaultCategory(name: item.venue.name,
                                                                                category: CityCardPhotos.webCategory(item.category)),
                                onTap: onSelect)
            }
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lines) { l in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: l.icon).font(.caption).foregroundStyle(Color.textTertiary).frame(width: 14).padding(.top, 2)
                            if let u = l.url {
                                Button { openURL(u) } label: {
                                    if let label = l.label {
                                        (Text(label + " ").fontWeight(.semibold) + Text(l.text))
                                    } else {
                                        Text(l.text).fontWeight(.semibold)
                                    }
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.navy)
                            } else if let label = l.label {
                                (Text(label + " ").fontWeight(.semibold).foregroundColor(Color.navy) + Text(l.text))
                            } else {
                                Text(l.text)
                            }
                        }
                    }
                }
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
            }
            if !tags.isEmpty {
                FlowActions(spacing: 6) {
                    ForEach(tags, id: \.self) { t in
                        Text(t).font(.caption2.weight(.semibold)).foregroundStyle(Color.navy)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.surface, in: Capsule())
                    }
                }
            }
            if let n = notice {
                VStack(alignment: .leading, spacing: 3) {
                    Label(n.title, systemImage: n.strong ? "exclamationmark.triangle" : "sparkles")
                        .font(.caption.weight(.bold))
                    Text(n.text).font(.caption)
                }
                .foregroundStyle(Color.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(n.strong ? Color.textTertiary : Color.hairline, lineWidth: n.strong ? 2 : 1))
            }
            if isStatic {
                if let w = item.websiteURL {
                    Divider().overlay(Color.hairline)
                    HStack {
                        Spacer(minLength: 0)
                        chip(linkLabel, "globe", on: true) { openURL(w) }
                    }
                }
            } else {
                Divider().overlay(Color.hairline)
                FlowActions {
                    chip("View Details", "arrow.right") { onSelect() }
                    if showReviews, item.reviewKey != nil { chip(CityCardReviews.label(summary), "star") { openReviews() } }
                    if showDirections, let d = item.directionsURL { chip("Directions", "location") { openURL(d) } }
                    if let w = item.websiteURL { chip(linkLabel, "globe", on: true) { openURL(w) } }
                }
            }
        }
    }

    static func reviewsLabel(_ s: PlaceReviewSummary?) -> String { CityCardReviews.label(s) }

    private func chip(_ title: String, _ icon: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .foregroundStyle(on ? Color.white : Color.navy)
                .background(on ? Color.navy : Color.white, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.clear : Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A city sub-page's header line (web: title on the left, "{n} locations" pill on the right).
struct CityHubHeader: View {
    let title: String
    let count: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(Color.navy)
            Spacer()
            if let count {
                Text(count).font(.caption2.weight(.heavy)).foregroundStyle(Color.navy)
                    .padding(.horizontal, 8).padding(.vertical, 3).hairline(radius: 6)
            }
        }
        .padding(.bottom, 4)
    }
}

/// Empty sub-page box (web: bold line + explainer, centred in a bordered card).
struct CityEmptyBox: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
            Text(detail).font(.footnote).foregroundStyle(Color.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
        .hairline(radius: 16)
    }
}

/// A plain note box above a list (web: small grey text in a bordered rounded box).
struct CityNoteBox: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .hairline(radius: 14)
    }
}

/// The native city sub-pages for Grocery, Chabad, Shuls, Hotels, Vacation Rentals, Businesses & Services,
/// Community Resources and the Hasidic community, in the website's words and order (App.tsx 11249-12680).
struct CityHubPage: View {
    let hub: CityHub
    let page: CityPage
    let sections: [CitySection]
    let summary: (PlaceItem) -> PlaceReviewSummary?
    let onSelect: (PlaceItem) -> Void
    /// Hands back a place's reviews (placeKey, list) after its Reviews sheet closes, so the cards' counts catch up.
    var onReviewsChanged: ((String, [PlaceReview]) -> Void)? = nil

    private let prefs = ProfileStore.shared
    @State private var addingChabadRestaurant = false
    @State private var radiusHotel: PlaceItem?
    @State private var reviewsFor: PlaceItem?

    private func items(_ c: PlaceCategory) -> [PlaceItem] { sections.first { $0.category == c }?.items ?? [] }
    /// A saved need that is filtering right now (saved and "My kosher filters" on).
    private func need(_ n: String) -> Bool {
        guard let p = prefs.kosherPrefs, p.filtersOn else { return false }
        return p.needs.contains(n)
    }
    /// A saved need, whether the filters are on or off (the website shows its chip either way).
    private func saved(_ n: String) -> Bool {
        prefs.kosherPrefs?.needs.contains(n) ?? false
    }
    private static let grid = [GridItem(.adaptive(minimum: 300), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Web: the city hero stays at the top of every sub-page (full width).
                CitySubPageHero()
                VStack(alignment: .leading, spacing: 14) {
                    content
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .background(Color.white)
        .sheet(item: $radiusHotel) { h in
            HotelRadiusMap(hotel: h, cityName: page.name, places: sections.flatMap(\.items))
        }
        .cityCardReviewsSheet($reviewsFor, onChanged: onReviewsChanged)
    }

    @ViewBuilder private var content: some View {
        switch hub {
        case .grocery: grocery
        case .chabad: chabad
        case .shuls: shuls
        case .hotels: hotels
        case .rentals: rentals
        case .businesses: businesses
        case .resources: resources
        case .hasidic: hasidic
        default: EmptyView()
        }
    }

    private func card(_ item: PlaceItem, badges: [String] = [], lines: [CityListingCard.Line] = [], tags: [String] = [],
                      notice: (title: String, text: String, strong: Bool)? = nil, link: String = "Website",
                      photo: Bool = true, reviews: Bool = true, directions: Bool = true,
                      extra: (title: String, icon: String, action: () -> Void)? = nil,
                      trailing: String? = nil, isStatic: Bool = false) -> some View {
        CityListingCard(item: item, badges: badges, showPhoto: photo, lines: lines, tags: tags, notice: notice,
                        linkLabel: link, showReviews: reviews, showDirections: directions, extra: extra,
                        trailing: trailing, isStatic: isStatic, city: page.name,
                        summary: summary(item), onSelect: { onSelect(item) },
                        onReviews: { reviewsFor = item })
    }

    private func addr(_ v: Venue) -> [CityListingCard.Line] {
        v.address.isEmpty ? [] : [.init(icon: "mappin", label: nil, text: v.address)]
    }
    private func phone(_ v: Venue, label: String? = nil, tappable: Bool = false) -> [CityListingCard.Line] {
        guard !v.phone.isEmpty else { return [] }
        let digits = v.phone.filter { $0.isNumber || $0 == "+" }
        let url = tappable && digits.count >= 7 ? URL(string: "tel:\(digits)") : nil
        return [.init(icon: "phone", label: label, text: v.phone, url: url)]
    }
    private func line(_ icon: String, _ label: String?, _ text: String?) -> [CityListingCard.Line] {
        guard let text, !text.isEmpty else { return [] }
        return [.init(icon: icon, label: label, text: text)]
    }

    // MARK: Grocery

    @ViewBuilder private var grocery: some View {
        let list = items(.grocery)
        CityHubHeader(title: "Kosher Grocery Stores", count: "\(list.count) locations")
        if list.isEmpty {
            CityEmptyBox(title: "No registered kosher groceries.",
                         detail: "There are no dedicated kosher grocery listings here. However, local supermarkets usually carry kosher-certified staples. Please consult local Chabad guides for lists of nearby supermarkets carrying certified items.")
        } else {
            LazyVGrid(columns: Self.grid, spacing: 14) {
                ForEach(list) { g in
                    card(g, badges: ["Grocery"] + (g.venue.isDedicated == true ? ["Dedicated Kosher"] : []),
                         lines: addr(g.venue) + phone(g.venue, label: "Phone:") + line("text.alignleft", nil, g.venue.description))
                }
            }
        }
    }

    // MARK: Chabad

    @ViewBuilder private var chabad: some View {
        let list = items(.chabad)
        let meals = items(.takeout)
        CityHubHeader(title: "Chabad Houses & Directory", count: "\(list.count) active directory")
        if list.isEmpty {
            CityEmptyBox(title: "No active Chabad directory listed.",
                         detail: "There are no recorded local Chabad Houses in \(page.name). Use the AI Planner to locate the closest regional Jewish network or synagogue hub.")
        } else {
            LazyVGrid(columns: Self.grid, spacing: 14) {
                ForEach(list) { c in
                    card(c, badges: ["Chabad Center"],
                         lines: addr(c.venue) + line("person", "Rabbi:", c.venue.rabbi) + phone(c.venue, label: "Phone:"),
                         link: "Contact", trailing: c.venue.shabbatMeals == true ? "Shabbat Meals" : nil)
                }
            }
        }
        if !meals.isEmpty {
            Divider().overlay(Color.hairline).padding(.top, 8)
            Text("Chabad Takeout & Prepared Meals").font(.subheadline.weight(.heavy)).foregroundStyle(Color.navy)
            Text("These are local Chabad-organized meal packages, tourist catering, or home-cooked delivery services rather than commercial restaurants. Ideal for Shabbos and midweek dining!")
                .font(.footnote).foregroundStyle(Color.textSecondary)
            LazyVGrid(columns: Self.grid, spacing: 14) {
                ForEach(meals) { m in
                    card(m, badges: ["Travel Food Services"],
                         lines: addr(m.venue)
                            + [.init(icon: "checkmark.shield", label: "Kashrus:", text: m.venue.kashrus.isEmpty ? "Chabad Local Rabbi" : m.venue.kashrus)]
                            + phone(m.venue, tappable: true),
                         link: "Order meals", photo: false, reviews: false, directions: false, isStatic: true)
                }
            }
        }
        if items(.restaurant).isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb").font(.title3).foregroundStyle(Color.navy)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirm a Chabad-run Restaurant?").font(.footnote.weight(.black)).foregroundStyle(Color.navy)
                        Text("Sometimes Chabad houses operate standalone public restaurants, delis, or cafes that aren't shown in the search. If you can confirm they run a real public eatery here, click below to post it to our directory!")
                            .font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
                    }
                }
                Button { addingChabadRestaurant = true } label: {
                    Label("Confirm & Post Chabad Restaurant", systemImage: "plus")
                        .font(.caption.weight(.black))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(Color.navy)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .hairline(radius: 16)
            .padding(.top, 8)
            .sheet(isPresented: $addingChabadRestaurant) {
                let first = list.first?.venue
                AddEstablishmentSheet(cityName: page.name, country: page.country.isEmpty ? "USA" : page.country,
                    cityId: page.destId, preset: .init(name: "Chabad of \(page.name) Kosher Cafe", category: "restaurant",
                                  subCategory: "Cafe & Deli / Grill",
                                  address: (first?.address).flatMap { $0.isEmpty ? nil : $0 } ?? "\(page.name) Chabad House",
                                  kashrus: "Chabad of \(page.name) (Rabbi \((first?.rabbi).flatMap { $0.isEmpty ? nil : $0 } ?? "Raskin"))",
                                  phone: first?.phone ?? "", website: first?.website ?? "",
                                  description: "Active public kosher restaurant and food service facility run directly by the Chabad center."))
            }
        }
    }

    // MARK: Shuls, eruv, mikvah

    @ViewBuilder private var shuls: some View {
        let all = items(.shul)
        let minyan = all.filter { CityNeeds.dailyMinyan($0.venue) }
        let wantsMinyan = saved("Daily minyan nearby")
        let filterOn = need("Daily minyan nearby")
        let list = (filterOn && !minyan.isEmpty) ? minyan : all
        CityHubHeader(title: "Shuls & Jewish Infrastructure", count: "\(all.count) listed")
        if all.isEmpty && page.eruv == nil && items(.mikvah).isEmpty {
            CityEmptyBox(title: "No synagogues or eruv registered yet.",
                         detail: "There are no recorded active synagogues, community minyanim, or Eruv boundaries in our system for \(page.name). Try the AI Planner for adjacent communities, regional Shabbat minyan lists, and family lodging options.")
        }
        if wantsMinyan && !all.isEmpty {
            if minyan.isEmpty {
                CityNoteBox(text: "No shul here lists a daily minyan yet, so all shuls are shown. Call ahead to check.")
            } else {
                KosherFilterChip(hidden: all.count - minyan.count, noun: "shuls", relevant: ["Daily minyan nearby"])
            }
        }
        if !list.isEmpty {
            Text("Minyan & Shul Locations").font(.subheadline.weight(.heavy)).foregroundStyle(Color.navy)
            LazyVGrid(columns: Self.grid, spacing: 14) {
                ForEach(list) { s in
                    let v = s.venue
                    let tags = v.tags ?? []
                    card(s, badges: ["Shul"],
                         lines: addr(v) + line("text.alignleft", nil, v.description) + line("clock", "Schedule:", v.hours)
                            + phone(v) + line("envelope", nil, v.email)
                            + line("lightbulb", "Traveler Note:", v.notes)
                            + (tags.isEmpty ? line("book", "Nusach:", v.kind) : []),
                         tags: tags)
                }
            }
        }
        if let e = page.eruv {
            VStack(alignment: .leading, spacing: 6) {
                Label("Eruv Information", systemImage: "circle.dashed").font(.subheadline.weight(.heavy)).foregroundStyle(Color.navy)
                VStack(alignment: .leading, spacing: 4) {
                    if !e.description.isEmpty { Text(e.description).font(.footnote).foregroundStyle(Color.textSecondary) }
                    Label("Always verify active Eruv status with the local rabbi or Chabad house hotlines before Shabbat.", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.navy)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .hairline(radius: 12)
            }
            .padding(.top, 6)
        }
        ForEach(items(.mikvah)) { m in
            VStack(alignment: .leading, spacing: 6) {
                Label("Mikvah Directory", systemImage: "drop").font(.subheadline.weight(.heavy)).foregroundStyle(Color.navy)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.venue.name).font(.footnote.weight(.bold)).foregroundStyle(Color.navy)
                        if !m.venue.address.isEmpty { Text(m.venue.address).font(.caption).foregroundStyle(Color.textSecondary) }
                        Text("Please contact the Chabad rabbi or local community leaders directly to schedule an appointment.")
                            .font(.caption).foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    if let d = m.directionsURL {
                        Link(destination: d) {
                            Label("Directions", systemImage: "location").font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).frame(minHeight: 36)
                                .foregroundStyle(Color.navy)
                                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
                        }
                    }
                }
                .padding(12)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .hairline(radius: 12)
                .contentShape(Rectangle())
                .onTapGesture { onSelect(m) }
            }
            .padding(.top, 6)
        }
    }

    // MARK: Hotels

    @ViewBuilder private var hotels: some View {
        let all = items(.hotel)
        let ownFood = need(SavedKosherPrefs.ownFood)
        let kitchen = all.filter { CityNeeds.mentionsKitchen($0.venue) }
        let list = ownFood ? kitchen + all.filter { !CityNeeds.mentionsKitchen($0.venue) } : all
        CityHubHeader(title: "Recommended Lodgings", count: all.isEmpty ? nil : "\(all.count) listings")
        if ownFood && !kitchen.isEmpty {
            let k = kitchen.count
            CityNoteBox(text: "Bringing your own food: \(k == 1 ? "the hotel" : "the \(k) hotels") that list a kitchen or fridge \(k == 1 ? "is" : "are") shown first.")
        }
        // Website: places to stay travelers tagged join right after the hotels, minus the city's own hotels.
        let region = page.stateName.isEmpty ? page.country : page.stateName
        let stays = TravelerFilters.notBuiltIn(SharedSights.shared.forCity(page.name, region: region).filter { $0.section == .stay },
                                               existingNames: all.map(\.venue.name))
        if list.isEmpty && stays.isEmpty {
            CityNoteBox(text: "No direct walk-to-synagogue lodging recommendations are indexed for this city yet.")
        } else if !list.isEmpty {
            LazyVGrid(columns: Self.grid, spacing: 14) {
                ForEach(list) { h in
                    let v = h.venue
                    let notes = v.kosherNotes ?? ""
                    let strong = notes.contains("MANDATORY ADVANCE") || notes.contains("Book At Least")
                    let notice: (title: String, text: String, strong: Bool)? = notes.isEmpty ? nil
                        : (title: strong ? "Advance Kosher Coordination Required" : "Kosher Hospitality:", text: notes, strong: strong)
                    card(h, badges: ["Lodging"],
                         lines: line("text.alignleft", nil, v.description) + addr(v) + phone(v),
                         notice: notice,
                         extra: (title: "Show Radius", icon: "scope", action: { radiusHotel = h }))
                }
            }
        }
        if !stays.isEmpty {
            LazyVGrid(columns: Self.grid, spacing: 14) {
                ForEach(stays) { st in
                    TravelerStayCard(sight: st, onOpen: { onSelect(st.asPlaceItem(destId: page.destId, cityName: page.name)) })
                }
            }
        }
    }

    // MARK: Rentals, businesses, resources

    @ViewBuilder private var rentals: some View {
        let list = items(.rental)
        CityHubHeader(title: "Kosher Vacation Rentals", count: "\(list.count) options")
        LazyVGrid(columns: Self.grid, spacing: 14) {
            ForEach(list) { r in
                let v = r.venue
                card(r, lines: addr(v) + line("text.alignleft", nil, v.description) + line("sparkles", "Kosher Amenities:", v.features)
                        + phone(v) + line("envelope", nil, v.email) + line("lightbulb", "Traveler Note:", v.notes),
                     tags: v.tags ?? [], link: "Book Rental", photo: false, reviews: false, directions: false, isStatic: true)
            }
        }
    }

    @ViewBuilder private var businesses: some View {
        let list = items(.business)
        CityHubHeader(title: "Jewish Businesses & Services", count: "\(list.count) registered")
        LazyVGrid(columns: Self.grid, spacing: 14) {
            ForEach(list) { b in
                let v = b.venue
                card(b, badges: v.kind.isEmpty ? [] : [v.kind],
                     lines: addr(v) + line("text.alignleft", nil, v.description) + phone(v) + line("lightbulb", "Traveler Note:", v.notes),
                     tags: v.tags ?? [], link: "Visit Site", photo: false, reviews: false, directions: false, isStatic: true)
            }
        }
    }

    @ViewBuilder private var resources: some View {
        let list = items(.resource)
        CityHubHeader(title: "Community Directories & Resources", count: "Official Connections")
        LazyVGrid(columns: Self.grid, spacing: 14) {
            ForEach(list) { r in
                let v = r.venue
                card(r, badges: v.kind.isEmpty ? [] : [v.kind], lines: line("text.alignleft", nil, v.description),
                     link: "Open Resource", photo: false, reviews: false, directions: false, isStatic: true)
            }
        }
    }

    // MARK: Hasidic community (with Kosher Catering & Meals)

    @ViewBuilder private var hasidic: some View {
        CityHubHeader(title: "Hasidic Jewish Community", count: "Orthodox & Hasidic")
        if !page.hasidic.isEmpty {
            Text(page.hasidic).font(.subheadline).foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14).hairline(radius: 16)
        }
        let catering = items(.catering)
        if !catering.isEmpty {
            Text("Kosher Catering & Meals").font(.subheadline.weight(.heavy)).foregroundStyle(Color.navy).padding(.top, 6)
            LazyVGrid(columns: Self.grid, spacing: 14) {
                ForEach(catering) { c in
                    let v = c.venue
                    card(c, lines: addr(v) + line("text.alignleft", nil, v.description) + line("clock", "Hours:", v.hours)
                            + phone(v) + line("envelope", nil, v.email) + line("lightbulb", "Traveler Note:", v.notes),
                         link: "Order Online", photo: false, reviews: false, directions: false, isStatic: true)
                }
            }
        }
    }
}
