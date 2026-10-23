import Foundation
import CoreLocation

/// The kinds of listing a city page shows, in the website's order.
enum PlaceCategory: String, CaseIterable, Hashable {
    case restaurant, takeout, grocery, chabad, shul, mikvah, todo, hotel, rental, catering, business, resource, traveler

    var title: String {
        switch self {
        case .restaurant: return "Kosher Restaurants"
        case .takeout: return "Chabad Takeout & Prepared Meals"
        case .grocery: return "Kosher Grocery"
        case .chabad: return "Chabad"
        case .shul: return "Shuls"
        case .mikvah: return "Mikvah"
        case .todo: return "Things to Do"
        case .hotel: return "Hotels"
        case .rental: return "Vacation Rentals"
        case .catering: return "Kosher Catering"
        case .business: return "Jewish Businesses and Services"
        case .resource: return "Community Resources"
        case .traveler: return "Places Travelers Added"
        }
    }

    /// Short label for the chip bar and tags.
    var chip: String {
        switch self {
        case .restaurant: return "Restaurants"
        case .takeout: return "Prepared meals"
        case .grocery: return "Grocery"
        case .chabad: return "Chabad"
        case .shul: return "Shuls"
        case .mikvah: return "Mikvah and Eruv"
        case .todo: return "Things to Do"
        case .hotel: return "Hotels"
        case .rental: return "Rentals"
        case .catering: return "Catering"
        case .business: return "Businesses"
        case .resource: return "Community"
        case .traveler: return "From travelers"
        }
    }

    /// Singular label shown on a place's sheet.
    var label: String {
        switch self {
        case .restaurant: return "Restaurant"
        case .takeout: return "Prepared meals"
        case .grocery: return "Grocery"
        case .chabad: return "Chabad"
        case .shul: return "Shul"
        case .mikvah: return "Mikvah"
        case .todo: return "Things to do"
        case .hotel: return "Hotel"
        case .rental: return "Vacation rental"
        case .catering: return "Kosher catering"
        case .business: return "Business"
        case .resource: return "Community resource"
        case .traveler: return "Added by a traveler"
        }
    }

    /// Outline SF Symbol.
    var systemImage: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .takeout: return "takeoutbag.and.cup.and.straw"
        case .grocery: return "cart"
        case .chabad: return "house"
        case .shul: return "building.columns"
        case .mikvah: return "drop"
        case .todo: return "binoculars"
        case .hotel: return "bed.double"
        case .rental: return "key"
        case .catering: return "frying.pan"
        case .business: return "briefcase"
        case .resource: return "person.2"
        case .traveler: return "mappin.and.ellipse"
        }
    }

    /// Photo-led sections show as sideways cards; the rest as a list.
    var usesCards: Bool { self == .todo || self == .hotel || self == .rental }

    /// The prefix the website uses for review ids (`res-<destId>-<name>`); nil = the website has no reviews here.
    var reviewPrefix: String? {
        switch self {
        case .restaurant, .takeout: return "res"
        case .grocery: return "groc"
        case .chabad: return "chab"
        case .shul: return "shul"
        case .hotel: return "hotel"
        default: return nil
        }
    }

    /// The website's `placeKind` for a review.
    var reviewKind: String {
        switch self {
        case .restaurant, .takeout: return "restaurant"
        case .grocery: return "grocery"
        case .chabad: return "chabad"
        default: return "place"
        }
    }

    /// A traveler's place category (`places.category`) to a section.
    static func fromTraveler(_ c: String) -> PlaceCategory {
        switch c {
        case "restaurant": return .restaurant
        case "grocery": return .grocery
        case "chabad": return .chabad
        case "shul": return .shul
        case "hotel": return .hotel
        case "mikvah": return .mikvah
        default: return .todo
        }
    }
}

/// One listing on a city page, with everything the sheet, the map and the reviews need.
struct PlaceItem: Identifiable, Hashable {
    let id: String              // "<category>:<index>" or "traveler:<doc id>"
    let category: PlaceCategory
    let venue: Venue
    let destId: String
    let cityName: String
    /// For a traveler's place: what it is (restaurant, hotel…) and the post it came from.
    var travelerCategory: PlaceCategory? = nil
    var travelerPostId: String = ""

    /// Same id the website gives this place in `placeReviews` (nil when the website has no reviews for it).
    var reviewPlaceId: String? {
        guard let p = category.reviewPrefix, !destId.isEmpty, travelerCategory == nil else { return nil }
        return PlaceKey.placeId(prefix: p, destId: destId, name: venue.name)
    }

    var reviewKey: String? { reviewPlaceId.map(PlaceKey.key) }

    /// Icon for the row and the map marker.
    var systemImage: String { (travelerCategory ?? category).systemImage }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = venue.lat, let lng = venue.lng, lat != 0 || lng != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var photos: [String] {
        var out: [String] = []
        for p in [venue.photo] + (venue.photos ?? []) where !p.isEmpty && !out.contains(p) { out.append(p) }
        return out
    }

    /// The words the website's default-photo rule reads (Chabad / shul / grocery): the section and the venue's type.
    var photoCategory: String { "\(category.rawValue) \(venue.kind)" }

    /// The second line under the name: hechsher, else type, else a short address.
    var subtitle: String {
        if !venue.kashrus.isEmpty { return venue.kashrus }
        if !venue.kind.isEmpty, category != .todo { return venue.kind }
        return ""
    }

    var phoneURL: URL? {
        let digits = venue.phone.filter { $0.isNumber || $0 == "+" }
        return digits.count >= 7 ? URL(string: "tel:\(digits)") : nil
    }

    var websiteURL: URL? {
        let w = venue.website.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return nil }
        if w.lowercased().hasPrefix("http://") || w.lowercased().hasPrefix("https://") { return URL(string: w) }
        if w.contains(":") { return nil }   // other schemes are never opened (same rule as the website)
        return URL(string: "https://" + w)
    }

    var websiteHost: String {
        guard let host = websiteURL?.host else { return venue.website }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Apple Maps for this place: by address when there is one, else by name in the city.
    var appleMapsURL: URL? {
        var c = URLComponents(string: "https://maps.apple.com/")
        if let co = coordinate {
            c?.queryItems = [URLQueryItem(name: "q", value: venue.name), URLQueryItem(name: "ll", value: "\(co.latitude),\(co.longitude)")]
        } else if !venue.address.isEmpty {
            c?.queryItems = [URLQueryItem(name: "q", value: venue.name), URLQueryItem(name: "address", value: venue.address)]
        } else {
            c?.queryItems = [URLQueryItem(name: "q", value: [venue.name, cityName].filter { !$0.isEmpty }.joined(separator: ", "))]
        }
        return c?.url
    }

    var directionsURL: URL? {
        var c = URLComponents(string: "https://maps.apple.com/")
        if let co = coordinate {
            c?.queryItems = [URLQueryItem(name: "daddr", value: "\(co.latitude),\(co.longitude)"), URLQueryItem(name: "q", value: venue.name)]
        } else if !venue.address.isEmpty {
            c?.queryItems = [URLQueryItem(name: "daddr", value: venue.address)]
        } else { return appleMapsURL }
        return c?.url
    }

    /// What the share sheet sends: name, address and a link.
    var shareText: String {
        [venue.name, venue.address, venue.phone].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func == (a: PlaceItem, b: PlaceItem) -> Bool { a.id == b.id && a.destId == b.destId }
    func hash(into h: inout Hasher) { h.combine(id); h.combine(destId) }
}

struct CitySection: Identifiable, Hashable {
    var id: String { category.rawValue }
    let category: PlaceCategory
    var items: [PlaceItem]
}

/// Everything the native city page shows, built from the bundled data (same sources and merges as the website).
struct CityPage: Hashable {
    let key: String
    let destId: String
    let name: String
    let region: String       // state, or country
    let subtitle: String
    let photo: String
    let description: String
    let airport: String
    let airportDistance: String
    let weather: String
    let center: CLLocationCoordinate2D?
    var sections: [CitySection]
    let eruv: EruvInfo?
    let hasidic: String
    /// The website's region ("North America", "Caribbean"…), state and country, for the hero pills.
    var area: String = ""
    var stateName: String = ""
    var country: String = ""

    static func == (a: CityPage, b: CityPage) -> Bool { a.key == b.key && a.sections == b.sections }
    func hash(into h: inout Hasher) { h.combine(key) }

    var allItems: [PlaceItem] { sections.flatMap(\.items) }

    /// Names already listed, for de-duplicating places travelers added (website: PlaceStories existingNames).
    var listedNames: [String] {
        sections.filter { $0.category != .traveler }.flatMap { $0.items.map(\.venue.name) }
    }

    static func build(key: String, data: ExploreData) -> CityPage? {
        if key.hasPrefix("us:"), let c = data.cities.first(where: { "us:\($0.id)" == key }) {
            let center = (c.lat != 0 || c.lng != 0) ? CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng) : nil
            var p = make(key: key, destId: c.id, name: c.name, region: c.state, subtitle: "\(c.state), United States",
                        photo: c.photo, description: c.description, airport: c.airport, airportDistance: c.airportDistance,
                        weather: c.weather, center: center,
                        restaurants: c.restaurants, groceries: c.groceries, chabad: c.chabad, shuls: c.shuls,
                        mikvah: c.mikvah, attractions: c.attractions, hotels: c.hotels, rentals: c.rentals ?? [],
                        catering: c.catering ?? [], businesses: c.businesses ?? [], resources: c.resources ?? [],
                        eruv: c.eruv, hasidic: c.hasidic ?? "")
            p.area = "North America"; p.stateName = c.state; p.country = "United States"
            return p
        }
        if key.hasPrefix("dest:"), let d = data.destinations.first(where: { "dest:\($0.id)" == key }) {
            let sub = d.state.isEmpty ? d.country : "\(d.state), \(d.country)"
            var center: CLLocationCoordinate2D? = nil
            if let lat = d.lat, let lng = d.lng { center = CLLocationCoordinate2D(latitude: lat, longitude: lng) }
            // Website: a destination merges its US_CITIES twin (same name, same state when the destination has one,
            // else the first by name) into Restaurants, Grocery and Chabad (App.tsx matchedUSCity).
            let lower = d.name.lowercased()
            let twin = data.cities.first { $0.name.lowercased() == lower && (d.state.isEmpty || $0.state.lowercased() == d.state.lowercased()) }
                ?? data.cities.first { $0.name.lowercased() == lower }
            var p = make(key: key, destId: d.id, name: d.name, region: d.state.isEmpty ? d.country : d.state, subtitle: sub,
                        photo: d.image, description: d.description,
                        airport: d.airport.isEmpty ? (twin?.airport ?? "") : d.airport,
                        airportDistance: d.airportDistance.isEmpty ? (twin?.airportDistance ?? "") : d.airportDistance,
                        weather: d.weather, center: center,
                        restaurants: d.restaurants + (twin?.restaurants ?? []), groceries: d.groceries + (twin?.groceries ?? []),
                        chabad: d.chabad + (twin?.chabad ?? []), shuls: d.shuls,
                        mikvah: d.mikvah, attractions: d.attractions, hotels: d.hotels, rentals: d.rentals ?? [],
                        catering: d.catering ?? [], businesses: d.businesses ?? [], resources: d.resources ?? [],
                        eruv: d.eruv, hasidic: d.hasidic ?? "")
            p.area = d.region; p.stateName = d.state; p.country = d.country
            return p
        }
        return nil
    }

    // swiftlint:disable:next function_parameter_count
    private static func make(key: String, destId: String, name: String, region: String, subtitle: String, photo: String,
                             description: String, airport: String, airportDistance: String, weather: String,
                             center: CLLocationCoordinate2D?,
                             restaurants: [Venue], groceries: [Venue], chabad: [Venue], shuls: [Venue], mikvah: Venue?,
                             attractions: [Venue], hotels: [Venue], rentals: [Venue], catering: [Venue],
                             businesses: [Venue], resources: [Venue], eruv: EruvInfo?, hasidic: String) -> CityPage {
        // Restaurants: one per name; Chabad takeout / prepared meals get their own section (website: isOfficialRestaurant)
        // One per name; a later copy (the twin city's) fills the fields the first left empty, like the website.
        let mergedRestaurants = Self.mergeByName(restaurants) { e, r in
            if e.photo.isEmpty { e.photo = r.photo }
            if e.phone.isEmpty { e.phone = r.phone }
            if e.website.isEmpty { e.website = r.website }
            if e.kind.isEmpty { e.kind = r.kind }
            if (e.distance ?? "").isEmpty, let d = r.distance, !d.isEmpty { e.distance = d }
            if e.kashrus.isEmpty { e.kashrus = r.kashrus }
            if e.address.isEmpty { e.address = r.address }
            if e.description.isEmpty { e.description = r.description }
        }
        var dining: [Venue] = []
        var meals: [Venue] = []
        for r in mergedRestaurants where !r.name.trimmingCharacters(in: .whitespaces).isEmpty {
            if Self.isOfficialRestaurant(r.name) { dining.append(r) } else { meals.append(r) }
        }
        let chabadMerged = Self.mergeByName(chabad) { e, c in
            if e.photo.isEmpty { e.photo = c.photo }
            if e.phone.isEmpty { e.phone = c.phone }
            if e.website.isEmpty { e.website = c.website }
            if (e.rabbi ?? "").isEmpty, let r = c.rabbi, !r.isEmpty { e.rabbi = r }
            if e.address.isEmpty { e.address = c.address }
            if e.shabbatMeals != true, c.shabbatMeals == true { e.shabbatMeals = true }
        }
        var groc = Set<String>()
        let groceriesUnique = groceries.filter { g in
            let k = g.name.lowercased().trimmingCharacters(in: .whitespaces)
            if groc.contains(k) { return false }
            groc.insert(k); return true
        }
        let lists: [(PlaceCategory, [Venue])] = [
            (.restaurant, dining), (.takeout, meals), (.grocery, groceriesUnique), (.chabad, chabadMerged), (.shul, shuls),
            (.mikvah, mikvah.map { [$0] } ?? []), (.todo, attractions), (.hotel, hotels), (.rental, rentals),
            (.catering, catering), (.business, businesses), (.resource, resources),
        ]
        var sections: [CitySection] = []
        for (cat, venues) in lists {
            let items = venues.enumerated().map { i, v in
                PlaceItem(id: "\(cat.rawValue):\(i)", category: cat, venue: v, destId: destId, cityName: name)
            }
            // Mikvah and Eruv share one section: it shows when either is listed.
            if !items.isEmpty || (cat == .mikvah && eruv != nil) { sections.append(CitySection(category: cat, items: items)) }
        }
        return CityPage(key: key, destId: destId, name: name, region: region, subtitle: subtitle, photo: photo,
                        description: description, airport: airport, airportDistance: airportDistance, weather: weather,
                        center: center, sections: sections, eruv: eruv, hasidic: hasidic)
    }

    /// Website `new Map(name.toLowerCase().trim())`: first copy wins, later copies fill its empty fields; first-seen order.
    private static func mergeByName(_ list: [Venue], fill: (inout Venue, Venue) -> Void) -> [Venue] {
        var order: [String] = []
        var byName: [String: Venue] = [:]
        for v in list {
            let k = v.name.lowercased().trimmingCharacters(in: .whitespaces)
            if var e = byName[k] { fill(&e, v); byName[k] = e } else { byName[k] = v; order.append(k) }
        }
        return order.compactMap { byName[$0] }
    }

    /// The website's test for a public restaurant vs. Chabad home catering / takeout (App.tsx isOfficialRestaurant).
    static func isOfficialRestaurant(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.isEmpty { return false }
        let chabadTerms = ["catering", "takeout", "meals", "prepared", "platter", "delivery", "provision", "food services",
                           "home catering", "platters", "lunch and dinner", "shabbat package"]
        if lower.contains("chabad") && chabadTerms.contains(where: { lower.contains($0) }) { return false }
        let general = ["travel meals", "prepared travel", "travel takeout", "kosher travel", "prepared meals", "prepared food"]
        return !general.contains(where: { lower.contains($0) })
    }
}

/// The website's review keys (src/components/reviews/reviewsCache.ts placeKeyOf, App.tsx place ids).
enum PlaceKey {
    /// `name.toLowerCase().replace(/\s+/g, '-')`
    static func slug(_ name: String) -> String {
        var out = ""
        var inSpace = false
        for ch in name.lowercased() {
            if ch.isWhitespace {
                if !inSpace { out.append("-"); inSpace = true }
            } else {
                out.append(ch); inSpace = false
            }
        }
        return out
    }

    static func placeId(prefix: String, destId: String, name: String) -> String {
        "\(prefix)-\(destId)-\(slug(name))"
    }

    /// A safe, stable document key for any place id (letters, digits, - and _ only, at most 100 characters).
    static func key(_ placeId: String) -> String {
        var mapped = ""
        var lastDash = false
        for u in placeId.lowercased().unicodeScalars {
            let ok = (u >= "a" && u <= "z") || (u >= "0" && u <= "9") || u == "_" || u == "-"
            if ok && u != "-" {
                mapped.unicodeScalars.append(u); lastDash = false
            } else if !lastDash {
                mapped.append("-"); lastDash = true
            }
        }
        while mapped.hasPrefix("-") { mapped.removeFirst() }
        while mapped.hasSuffix("-") { mapped.removeLast() }
        let base = mapped.isEmpty ? "place" : mapped
        if base.count <= 90 && base == placeId { return base }
        return "\(String(base.prefix(88)))-\(hash(placeId))"
    }

    /// FNV-1a over UTF-16 code units, base 36 (same as the website's hash()).
    static func hash(_ s: String) -> String {
        var h: UInt32 = 2_166_136_261
        for unit in s.utf16 {
            h ^= UInt32(unit)
            h = h &* 16_777_619
        }
        return String(h, radix: 36)
    }

    /// The website's normName: lower case, accents off, anything else becomes one space.
    static func norm(_ s: String) -> String {
        let folded = s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        var out = ""
        var gap = false
        for u in folded.unicodeScalars {
            if (u >= "a" && u <= "z") || (u >= "0" && u <= "9") {
                if gap && !out.isEmpty { out.append(" ") }
                out.unicodeScalars.append(u); gap = false
            } else { gap = true }
        }
        return out
    }
}
