import Foundation

/// One Top Attractions card as the website builds it (attractionsDatabase.ts getEnrichedAttractions, mapped by
/// DeepExperiencesView staticTopAttractions). Short keys keep Resources/citytodo.json small.
struct CityTodoAttraction: Decodable, Hashable {
    let n: String          // name
    let d: String?         // shortDescription
    let l: String?         // exactLocation
    let w: String?         // bookingLink (website; the website's "N/A" is left out)
    let p: String?         // photo (the gallery's photos: [photo])
    let vp: String?        // verifiedPhoto (the gallery's fallbackPhoto), only when it differs from p

    var name: String { n }
    var description: String { d ?? "" }
    var location: String { l ?? "" }
    var website: String { w ?? "" }
    var photo: String { p ?? "" }
    /// Website: fallbackPhoto = verifiedFallbackPhoto || photo.
    var fallbackPhoto: String { (vp?.isEmpty == false ? vp : p) ?? "" }
}

/// A city's Things to Do data: the website's Top Attractions, in its order, and the destination's travelTips
/// ("Essential Travel & Logistics Advisories").
struct CityTodoEntry: Decodable, Hashable {
    let a: [CityTodoAttraction]?
    let t: [String]?
    var attractions: [CityTodoAttraction] { a ?? [] }
    var travelTips: [String] { t ?? [] }
}

/// Resources/citytodo.json (written by ios-native/scripts/export-citytodo.sh from the website's own functions),
/// keyed by the app's city keys ("us:<id>", "dest:<id>"). Read lazily, off the main thread, the first time a
/// Things to Do page opens; never at launch.
actor CityTodoStore {
    static let shared = CityTodoStore()

    private struct File: Decodable { let cities: [String: CityTodoEntry] }
    private var cities: [String: CityTodoEntry]?
    private var loading: Task<[String: CityTodoEntry], Never>?

    /// The website's data for this city key. `nil` when the file has no entry (the page then falls back to the
    /// city's own attractions, as getEnrichedAttractions does with no curated match).
    func entry(for key: String) async -> CityTodoEntry? {
        await all()[Self.baseKey(key)]
    }

    private func all() async -> [String: CityTodoEntry] {
        if let cities { return cities }
        if loading == nil {
            loading = Task.detached(priority: .userInitiated) {
                guard let url = Bundle.main.url(forResource: "citytodo", withExtension: "json"),
                      let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                      let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
                return file.cities
            }
        }
        let loaded = await loading!.value
        cities = loaded
        return loaded
    }

    /// "us:miami/hub:todo" -> "us:miami" (sub-page route keys carry a suffix).
    static func baseKey(_ key: String) -> String {
        if let r = key.range(of: "/") { return String(key[..<r.lowerBound]) }
        return key
    }
}
