import Foundation

/// One listing (restaurant, grocery, shul, Chabad, hotel, sight). Every field is a plain string; empty when unknown.
struct Venue: Codable, Hashable {
    var name: String
    var address: String
    var phone: String
    var website: String
    var description: String
    var photo: String
    var kashrus: String
    var kind: String
    // Added for the place details sheet and the city map (all optional: older explore.json still decodes).
    var photos: [String]? = nil
    var hours: String? = nil
    var rabbi: String? = nil
    var email: String? = nil
    var price: String? = nil
    var notes: String? = nil
    var features: String? = nil
    var directions: String? = nil
    var tags: [String]? = nil
    var lat: Double? = nil
    var lng: Double? = nil
    var distance: String? = nil
    var shabbatMeals: Bool? = nil
    var isDedicated: Bool? = nil
    var kosherNotes: String? = nil
    var cityName: String? = nil
}

/// A city's eruv, as the website lists it.
struct EruvInfo: Codable, Hashable {
    var name: String
    var boundary: String
    var description: String
    var notes: String
}

struct USState: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var image: String
    var description: String
    var lat: Double
    var lng: Double
    var cities: [String]
}

struct CityInfo: Codable, Identifiable, Hashable {
    var id: String
    var state: String
    var name: String
    var description: String
    var lat: Double
    var lng: Double
    var photo: String
    var airport: String
    var airportDistance: String
    var weather: String
    var chabad: [Venue]
    var restaurants: [Venue]
    var groceries: [Venue]
    var shuls: [Venue]
    var hotels: [Venue]
    var attractions: [Venue]
    // Community listings (optional; only cities that list them carry them)
    var catering: [Venue]? = nil
    var rentals: [Venue]? = nil
    var businesses: [Venue]? = nil
    var resources: [Venue]? = nil
    var mikvah: Venue? = nil
    var eruv: EruvInfo? = nil
    var hasidic: String? = nil
}

struct CaribbeanCountry: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var image: String
    var description: String
    var lat: Double
    var lng: Double
    var cities: [String]
}

struct Destination: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var state: String
    var country: String
    var region: String
    var image: String
    var description: String
    var weather: String
    var airport: String
    var airportDistance: String
    var chabad: [Venue]
    var restaurants: [Venue]
    var groceries: [Venue]
    var shuls: [Venue]
    var hotels: [Venue]
    var attractions: [Venue]
    // Community listings (optional; only cities that list them carry them)
    var catering: [Venue]? = nil
    var rentals: [Venue]? = nil
    var businesses: [Venue]? = nil
    var resources: [Venue]? = nil
    var mikvah: Venue? = nil
    var eruv: EruvInfo? = nil
    var hasidic: String? = nil
    var lat: Double? = nil
    var lng: Double? = nil
}

struct ExploreData: Codable {
    var generatedAt: String
    var states: [USState]
    var cities: [CityInfo]
    var caribbean: [CaribbeanCountry]
    var destinations: [Destination]
}

/// A city / area card on a state or country page.
struct AreaCard: Identifiable, Hashable {
    var id: String          // route key: "us:<id>", "dest:<id>" or "name:<text>" (no page yet)
    var name: String
    var subtitle: String
    var photo: String
    var hasGrocery: Bool
    var hasChabad: Bool
    var hasPage: Bool
}

/// Everything a city page shows, from either data source.
struct AreaDetail: Hashable {
    var name: String
    var subtitle: String
    var photo: String
    var description: String
    var airport: String
    var airportDistance: String
    var weather: String
    var sections: [AreaSection]
}

struct AreaSection: Hashable, Identifiable {
    var id: String { title }
    var title: String
    var systemImage: String
    var venues: [Venue]
}

enum ExploreRoute: Hashable {
    case unitedStates
    case caribbean
    case mexicoCentralAmerica // Oct 23 2026: Mexico and Central America, no longer under the Caribbean
    case state(String)       // state id
    case country(String)     // Caribbean country id
    case area(String)        // AreaCard.id
    case story(String)       // story post id
    case web(WebRoute)       // a screen of the live app inside the native shell (Features/Shell)
}
