import SwiftUI
import Foundation

// Pieces of the place sheet (PlaceDetailView), matching the website's PlaceDetailsModal.

/// The website's place types (PlaceDetailsModal `type`), from the app's section.
enum PlaceSheetType: String {
    case attraction, restaurant, chabad, synagogue, grocery, deep_experience, hotel

    /// web getCategoryLabel()
    var label: String {
        switch self {
        case .restaurant: return "Kosher Restaurant"
        case .grocery: return "Kosher Grocery Store"
        case .chabad: return "Chabad Lubavitch Center"
        case .synagogue: return "Synagogue / Minyan"
        case .deep_experience: return "Curated Experience"
        case .hotel: return "Kosher-Friendly Resort / Hotel"
        case .attraction: return "Tourist Attraction"
        }
    }

    init(_ c: PlaceCategory) {
        switch c {
        case .restaurant, .takeout, .catering: self = .restaurant
        case .grocery: self = .grocery
        case .chabad: self = .chabad
        case .shul, .mikvah: self = .synagogue
        case .hotel, .rental: self = .hotel
        case .todo, .business, .resource, .traveler: self = .attraction
        }
    }
}

extension PlaceItem {
    /// The website's modal type for this listing (a traveler's place uses what it is).
    var sheetType: PlaceSheetType { PlaceSheetType(travelerCategory ?? category) }
    /// The city the sheet names (web cityName).
    var sheetCity: String { cityName.isEmpty ? (venue.cityName ?? "") : cityName }
}

/// What the website's sheet reads from a place, filled from what the app's data carries. Fields the app's bundled data
/// does not carry yet (explore.json) stay empty, so their sections hide exactly as the website's do when a place lacks them.
struct PlaceSheetFacts {
    var description: String
    var kosherFriendlyNotes: String
    var estimatedVisitTime = ""      // web estimatedDuration (not in explore.json)
    var bestTimeToVisit = ""         // web bestTime / bestSeason (not in explore.json)
    var admissionCost: String        // web admissionCost || admissionFee || price
    var openingHours: String         // web openingHours || hours
    var whyVisit = ""                // web whyVisit || mustDo (not in explore.json)
    var whatToDo: [String] = []      // web whatToDo / activities / experiences (not in explore.json)
    var aiTips = ""                  // web aiTips (not in explore.json)
    var bookingLink = ""             // web bookingLink (not in explore.json)

    init(item: PlaceItem) {
        let v = item.venue
        description = v.description.trimmingCharacters(in: .whitespacesAndNewlines)
        kosherFriendlyNotes = (v.kosherNotes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        admissionCost = (v.price ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        openingHours = (v.hours ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// web: rating is never shown (nothing fake), so the box shows only for a real visit time, best time or cost.
    var hasVisitSpecs: Bool { !estimatedVisitTime.isEmpty || !bestTimeToVisit.isEmpty || !admissionCost.isEmpty }

    /// web getAiTravelTips(): the place's own tips, else the fixed tip for its type.
    func travelTips(_ type: PlaceSheetType) -> String {
        if !aiTips.isEmpty { return aiTips }
        switch type {
        case .restaurant:
            return "Reservations are highly recommended during peak summer/winter vacation seasons. Always verify active kashrus certificates on the wall upon arrival as supervision details may change. Let the staff know if you require Pas Yisroel or Yoshon."
        case .grocery:
            return "Arrive early on Thursday evenings or Friday mornings for the freshest Shabbat baked goods, challahs, and prepared food items. Check with local guides regarding eruv boundaries if you plan to carry groceries on Shabbat."
        case .chabad:
            return "To secure your spot for Friday night Shabbat dinner, please book through their website at least 4-5 days in advance. Contributions are deeply appreciated to help support vital local outreach and traveler services."
        case .synagogue:
            return "Please carry ID/passport copy for security validation when entering local synagogues. Minyan times can fluctuate according to seasonal sunrise/sunset, so we recommend confirming via active group chats or phone beforehand."
        case .hotel:
            return "Notify the concierge at least 72 hours prior to arrival regarding your kosher meal requirements. For Shabbat, request a mechanical physical room key and ensure room motion sensors or electronic door locks are adjusted appropriately."
        case .attraction, .deep_experience:
            return "Budget at least 2 hours to avoid rushing. Wear comfortable walking shoes. For heritage landmarks and holy sites, dress respectfully (covered shoulders and knees). Keep hydration handy during midday heat."
        }
    }
}

/// The website's links (PlaceDetailsModal 209-216, 671, 710).
enum PlaceSheetLinks {
    private static func enc(_ s: String) -> String {
        // encodeURIComponent
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// `https://www.google.com/maps/search/?api=1&query=…`
    static func googleSearch(_ q: String) -> URL? {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(enc(q))")
    }

    /// "Search the website": `https://www.google.com/search?q=<name city>`
    static func googleWebSearch(_ q: String) -> URL? {
        URL(string: "https://www.google.com/search?q=\(enc(q))")
    }

    /// "Find Bookings & Tickets": `https://www.booking.com/searchresults.html?ss=<name city>`
    static func bookingSearch(_ q: String) -> URL? {
        URL(string: "https://www.booking.com/searchresults.html?ss=\(enc(q))")
    }

    /// A listing's website or booking link: 'N/A' and empty mean none; without a scheme it gets https://.
    static func website(_ raw: String) -> URL? {
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if w.isEmpty || w == "N/A" { return nil }
        let lower = w.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return URL(string: w) }
        if w.contains(":") { return nil }
        return URL(string: "https://" + w)
    }
}

/// web handleToggleSave: localStorage `saved_place_<name>` holds the place as JSON with `savedAt`.
enum PlaceSheetFavorites {
    static func key(_ name: String) -> String { "saved_place_\(name)" }

    static func isSaved(_ name: String) -> Bool { UserDefaults.standard.object(forKey: key(name)) != nil }

    /// Saves or removes it; returns whether it is saved now.
    @discardableResult
    static func toggle(name: String, venue: Venue) -> Bool {
        let k = key(name)
        if UserDefaults.standard.object(forKey: k) != nil {
            UserDefaults.standard.removeObject(forKey: k)
            return false
        }
        var obj: [String: Any] = [:]
        if let data = try? JSONEncoder().encode(venue),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { obj = dict }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        obj["savedAt"] = f.string(from: Date())
        let json = (try? JSONSerialization.data(withJSONObject: obj)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        UserDefaults.standard.set(json, forKey: k)
        return true
    }
}

enum PlaceSheetNearbyTab: Hashable { case attractions, restaurants, hotels }

/// "Explore the Local Area": the lists App.tsx passes (the city's restaurants and hotels, and its things to do
/// without this place), found by the listing's city id, else by the city's name.
struct PlaceSheetNearby {
    var attractions: [Venue] = []
    var restaurants: [Venue] = []
    var hotels: [Venue] = []

    init(item: PlaceItem, data: ExploreData?) {
        guard let data else { return }
        let me = item.venue.name
        let cityLower = item.sheetCity.lowercased().trimmingCharacters(in: .whitespaces)
        func take(_ r: [Venue], _ h: [Venue], _ a: [Venue]) {
            restaurants = r
            hotels = h
            attractions = a.filter { $0.name != me }
        }
        if !item.destId.isEmpty, let c = data.cities.first(where: { $0.id == item.destId }) {
            take(c.restaurants, c.hotels, c.attractions)
        } else if !item.destId.isEmpty, let d = data.destinations.first(where: { $0.id == item.destId }) {
            take(d.restaurants, d.hotels, d.attractions)
        } else if !cityLower.isEmpty, let c = data.cities.first(where: { $0.name.lowercased().trimmingCharacters(in: .whitespaces) == cityLower }) {
            take(c.restaurants, c.hotels, c.attractions)
        } else if !cityLower.isEmpty, let d = data.destinations.first(where: { $0.name.lowercased().trimmingCharacters(in: .whitespaces) == cityLower }) {
            take(d.restaurants, d.hotels, d.attractions)
        }
    }

    /// web: the first tab that has something (attractions, restaurants, hotels).
    var defaultTab: PlaceSheetNearbyTab {
        if !attractions.isEmpty { return .attractions }
        if !restaurants.isEmpty { return .restaurants }
        if !hotels.isEmpty { return .hotels }
        return .attractions
    }
}

/// A section title in the website's small uppercase style; `strong` is its dark variant, else the grey one.
struct PlaceSheetHeading: View {
    let title: String
    let icon: String
    var strong = true

    var body: some View {
        Label {
            Text(title.uppercased())
                .tracking(strong ? 0.6 : 1.1)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(strong ? Color.navy : Color.textTertiary)
        }
        .font(.caption.weight(.heavy))
        .foregroundStyle(strong ? Color.navy : Color.textTertiary)
        .accessibilityAddTraits(.isHeader)
    }
}

/// web VerifyNote (app only, next to hours and certification).
struct PlaceSheetVerifyNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 12))
            Text("Hours and kosher certification can change. Verify before you go.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(Color.textSecondary)
    }
}

struct PlaceSheetRowIcon: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(Color.textTertiary)
            .frame(width: 18)
    }
}

struct PlaceSheetLinkButton: View {
    let title: String
    let strong: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Image(systemName: "arrow.up.right.square").font(.system(size: 10, weight: .bold))
            }
            .font(.caption.weight(strong ? .bold : .semibold))
            .foregroundStyle(strong ? Color.navy : Color.textSecondary)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PlaceSheetPillButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Image(systemName: "arrow.up.right.square").font(.system(size: 10, weight: .bold))
            }
            .font(.caption.weight(.heavy))
            .foregroundStyle(Color.navy)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .hairline(radius: 8)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PlaceSheetIconBox: View {
    let name: String
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Color.navy)
            .frame(width: 44, height: 44)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .hairline(radius: 8)
    }
}
