import Foundation
import Observation

// What the website's United States, state, Caribbean and country/island pages show (src/App.tsx), exported by
// ios-native/scripts/export-statepages.sh into statepages.json (this folder). The export runs the website's own code:
// getCitiesForState, the state-wide aggregation of every city's listings, getCitiesForCountry, the country
// aggregations and getStateWideDestination, over the same base destination list the website builds.

/// A city / area card (web renderDestinationCard).
struct SPCityCard: Codable, Hashable, Identifiable {
    var id: String          // the website's destination id (bucket-list id)
    var key: String         // the native city page: "us:<id>" / "dest:<id>"; empty for the country-wide card
    var name: String
    var sub: String         // "{state}, {country or USA}" or "{city}, {country}"
    var state: String
    var country: String
    var region: String
    var image: String
    var fallback: String?   // the city hero photo, tried when `image` fails (handleCityHeroImageError)
    var groc: Bool
    var chab: Bool
    var wide: Bool?         // the country-wide ("state-wide") card
}

/// One listing on a state or country page, with the city it came from.
struct SPListing: Codable, Hashable {
    var name: String
    var address: String
    var phone: String
    var website: String
    var description: String
    var photo: String
    var kashrus: String
    var kind: String
    var photos: [String]? = nil
    var rabbi: String? = nil
    var shabbatMeals: Bool? = nil
    var tags: [String]? = nil
    var nusach: String? = nil
    var link: String? = nil
    var directions: String? = nil
    var location: String? = nil
    var hours: String? = nil
    var email: String? = nil
    var price: String? = nil
    var notes: String? = nil
    var kosherNotes: String? = nil
    var cityName: String? = nil
    var destId: String? = nil

    enum CodingKeys: String, CodingKey {
        case name, address, phone, website, description, photo, kashrus, kind, photos, rabbi, shabbatMeals, tags, nusach,
             link, directions, location, hours, email, price, notes, kosherNotes, cityName, destId
    }

    /// The export leaves empty text out; a missing field reads as empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
        func o(_ k: CodingKeys) -> String? { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil }
        name = s(.name); address = s(.address); phone = s(.phone); website = s(.website)
        description = s(.description); photo = s(.photo); kashrus = s(.kashrus); kind = s(.kind)
        photos = (try? c.decodeIfPresent([String].self, forKey: .photos)) ?? nil
        rabbi = o(.rabbi)
        shabbatMeals = (try? c.decodeIfPresent(Bool.self, forKey: .shabbatMeals)) ?? nil
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? nil
        nusach = o(.nusach); link = o(.link); directions = o(.directions); location = o(.location); hours = o(.hours)
        email = o(.email); price = o(.price); notes = o(.notes); kosherNotes = o(.kosherNotes)
        cityName = o(.cityName); destId = o(.destId)
    }

    var venue: Venue {
        Venue(name: name, address: address, phone: phone, website: website.isEmpty ? (link ?? "") : website,
              description: description, photo: photo, kashrus: kashrus, kind: kind, photos: photos, hours: hours, rabbi: rabbi,
              email: email, price: price, notes: notes, directions: directions, tags: tags, shabbatMeals: shabbatMeals,
              kosherNotes: kosherNotes, cityName: cityName)
    }

    /// The shared place sheet's item (web setSelectedPlaceForModal + type + city).
    func item(_ category: PlaceCategory, index: Int, fallbackCity: String) -> PlaceItem {
        PlaceItem(id: "sp-\(category.rawValue):\(index):\(name)", category: category, venue: venue, destId: destId ?? "",
                  cityName: (cityName ?? "").isEmpty ? fallbackCity : (cityName ?? ""))
    }
}

struct SPStateData: Codable, Hashable {
    var cities: [SPCityCard]
    var attractions: [SPListing]
    var chabad: [SPListing]
    var groceries: [SPListing]
    var shuls: [SPListing]
    var hotels: [SPListing]
}

struct SPCountryData: Codable, Hashable {
    var cityCount: Int
    var cities: [SPCityCard]
    var wide: SPCityCard?
    var attractions: [SPListing]
    var restaurants: [SPListing]
    var chabad: [SPListing]
}

/// A state circle on the United States page / an island circle on the Caribbean page.
struct SPRegionTile: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var image: String
    var description: String
    var cityCount: Int
    var lat: Double? = nil
    var lng: Double? = nil
}

struct SPFile: Codable {
    var generatedAt: String
    var usStates: [SPRegionTile]
    var caribbean: [SPRegionTile]
    var states: [String: SPStateData]
    var countries: [String: SPCountryData]
}

/// The state / country page data, read once when a region page first opens (never at launch).
@MainActor
@Observable
final class StatePageStore {
    static let shared = StatePageStore()
    private(set) var file: SPFile?
    private(set) var failed = false
    @ObservationIgnored private var loading = false

    func load() async {
        if file != nil || loading { return }
        loading = true
        let result: SPFile? = await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: "statepages", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SPFile.self, from: data)
        }.value
        file = result
        failed = result == nil
        loading = false
    }

    var usStates: [SPRegionTile] { file?.usStates ?? [] }
    var caribbean: [SPRegionTile] { file?.caribbean ?? [] }
    func state(_ name: String) -> SPStateData? { file?.states[name] }
    func country(_ name: String) -> SPCountryData? { file?.countries[name] }
}

/// The website's two Things to Do categories (App.tsx STATE_TODO_CATEGORIES / COUNTRY_TODO_CATEGORIES).
struct SPTodoCategory: Identifiable, Hashable {
    let id: String
    let name: String
    let systemImage: String
    let description: String

    static func list(country: Bool) -> [SPTodoCategory] {
        [
            SPTodoCategory(id: "all", name: country ? "All Country Activities" : "All State Activities", systemImage: "map",
                           description: "Browse the full comprehensive list of tourist attractions in this \(country ? "country" : "state")."),
            SPTodoCategory(id: "family-friendly", name: "Family-Friendly", systemImage: "figure.2.and.child.holdinghands",
                           description: "Fun, secure, and memorable activities perfect for all ages."),
        ]
    }

    /// web filterAttractionsByCategory (the country version is the same rule)
    static func matches(_ tags: [String], _ categoryId: String) -> Bool {
        if categoryId == "all" { return true }
        let t = tags.map { $0.lowercased() }
        let target = categoryId.lowercased()
        if t.contains(target) { return true }
        if target == "family-friendly" {
            return t.contains { ["family-friendly", "family friendly", "kids", "children"].contains($0) }
        }
        return false
    }
}
