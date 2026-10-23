import Foundation

/// App places an answer names, shown as photo cards that open the city page (web: findMentionedDestinations).
struct PlannerPlace: Identifiable, Hashable {
    var id: String       // AreaCard key: "us:<id>" or "dest:<id>"
    var name: String
    var state: String
    var country: String
    var photo: String

    var subtitle: String { !state.isEmpty && state != name ? state : country }
}

enum PlannerMatches {
    private static func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }

    private static func contains(_ text: String, word name: String, caseInsensitive: Bool = false) -> Bool {
        let pattern = "(^|[^A-Za-z])\(esc(name))(?![A-Za-z])"
        return text.range(of: pattern, options: caseInsensitive ? [.regularExpression, .caseInsensitive] : [.regularExpression]) != nil
    }

    /// Every place the app has a page and a real photo for.
    static func places(_ data: ExploreData?) -> [PlannerPlace] {
        guard let data else { return [] }
        var out: [PlannerPlace] = []
        var seen = Set<String>()
        for c in data.cities where !c.photo.isEmpty {
            let key = c.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(PlannerPlace(id: "us:\(c.id)", name: c.name, state: c.state, country: "United States", photo: c.photo))
        }
        for d in data.destinations where !d.image.isEmpty {
            let key = d.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(PlannerPlace(id: "dest:\(d.id)", name: d.name, state: d.state, country: d.country, photo: d.image))
        }
        return out
    }

    /// Up to four places named in an answer. A bare city name also needs its state / country in the same answer
    /// (so "Palm Beach" in Florida does not bring Aruba), unless the place is its own country.
    static func mentioned(in text: String, places: [PlannerPlace]) -> [PlannerPlace] {
        let clean = PlannerText.sanitize(text).replacingOccurrences(of: #"\*\*|__|#"#, with: "", options: .regularExpression)
        var out: [PlannerPlace] = []
        for p in places.filter({ $0.name.count >= 4 }).sorted(by: { $0.name.count > $1.name.count }) {
            if out.count >= 4 { break }
            guard contains(clean, word: p.name) else { continue }
            let ctx = [p.state, p.country].filter { !$0.isEmpty && $0 != p.name }
            let selfNamed = p.name == p.country || p.name == p.state
            let withCode = clean.range(of: "\(esc(p.name)),\\s?[A-Z]{2}\\b", options: .regularExpression) != nil
            if !selfNamed && !ctx.contains(where: { clean.contains($0) }) && !withCode { continue }
            // "Miami" inside "Miami Beach" when Miami Beach was already picked
            if out.contains(where: { $0.name.contains(p.name) }) { continue }
            out.append(p)
        }
        return out
    }

    // MARK: Articles from travelers (web: ChatArticles.tsx, simplified)

    struct Articles: Hashable {
        var label: String
        var posts: [StoryPost]
        var route: ExploreRoute?
    }

    static let stateNames: Set<String> = [
        "alabama", "alaska", "arizona", "arkansas", "california", "colorado", "connecticut", "delaware", "florida", "georgia",
        "hawaii", "idaho", "illinois", "indiana", "iowa", "kansas", "kentucky", "louisiana", "maine", "maryland", "massachusetts",
        "michigan", "minnesota", "mississippi", "missouri", "montana", "nebraska", "nevada", "new hampshire", "new jersey",
        "new mexico", "new york", "north carolina", "north dakota", "ohio", "oklahoma", "oregon", "pennsylvania", "rhode island",
        "south carolina", "south dakota", "tennessee", "texas", "utah", "vermont", "virginia", "washington", "west virginia",
        "wisconsin", "wyoming",
    ]

    /// "Arizona" for "Sedona, Arizona, United States", "Aruba" for "Aruba".
    static func region(of citySub: String) -> String {
        let parts = citySub.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let last = parts.last else { return "" }
        if last.range(of: #"^(united states|usa|us|u\.s\.a?\.?)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return parts.count >= 2 ? parts[0] : "United States"
        }
        return last
    }

    /// The live posts for one answer: cities named (question first, then answer), then their states / countries.
    /// Guides first within each place, at most six.
    static func articles(question: String, answer: String, posts: [StoryPost], explore: ExploreStore) -> Articles? {
        let q = question.replacingOccurrences(of: #"\*\*|__|#"#, with: " ", options: .regularExpression)
        let a = answer.replacingOccurrences(of: #"\*\*|__|#"#, with: " ", options: .regularExpression)
        let both = q + "\n" + a
        struct Place { var city: String; var region: String; var at: Int }
        func pos(_ name: String, caseSensitiveInAnswer: Bool) -> Int? {
            guard name.count >= 3 else { return nil }
            if contains(q, word: name, caseInsensitive: true) { return 0 }
            if contains(a, word: name, caseInsensitive: !caseSensitiveInAnswer) { return 1 }
            return nil
        }
        var cities: [String: Place] = [:]
        var regions: [String: Place] = [:]
        for p in posts {
            for st in p.allStops {
                let r = region(of: st.citySub)
                let rk = StoryPost.norm(r)
                if !r.isEmpty, rk != "united states", regions[rk] == nil, let at = pos(r, caseSensitiveInAnswer: false) {
                    regions[rk] = Place(city: "", region: r, at: at)
                }
                let city = st.cityName.trimmingCharacters(in: .whitespaces)
                guard !city.isEmpty, StoryPost.norm(city) != rk else { continue }
                let key = StoryPost.norm(city) + "|" + rk
                guard cities[key] == nil, let at = pos(city, caseSensitiveInAnswer: true) else { continue }
                // its state / country named too (a bare city name is often another place)
                guard !r.isEmpty, contains(both, word: r, caseInsensitive: true) || at == 0 else { continue }
                cities[key] = Place(city: city, region: r, at: at)
            }
        }
        if cities.isEmpty && regions.isEmpty { return nil }
        let ordered = cities.values.sorted { $0.at < $1.at } + regions.values.sorted { $0.at < $1.at }
        let rank: (StoryPost) -> Int = { $0.isGuide ? 0 : 1 }
        func sorted(_ list: [StoryPost]) -> [StoryPost] {
            list.sorted { x, y in
                if rank(x) != rank(y) { return rank(x) < rank(y) }
                if x.likesCount != y.likesCount { return x.likesCount > y.likesCount }
                return x.createdAtMs > y.createdAtMs
            }
        }
        var picked: [StoryPost] = []
        var seen = Set<String>()
        var used: [Place] = []
        for pl in ordered {
            let list: [StoryPost]
            if !pl.city.isEmpty {
                list = posts.filter { p in p.allStops.contains { StoryPost.norm($0.cityName) == StoryPost.norm(pl.city)
                    && StoryPost.norm(region(of: $0.citySub)) == StoryPost.norm(pl.region) } }
            } else {
                list = posts.filter { p in p.allStops.contains { StoryPost.norm(region(of: $0.citySub)) == StoryPost.norm(pl.region) } }
            }
            var n = 0
            for p in sorted(list) where picked.count < 6 && !seen.contains(p.id) {
                seen.insert(p.id)
                picked.append(p)
                n += 1
            }
            if n > 0 { used.append(pl) }
        }
        guard let first = used.first, !picked.isEmpty else { return nil }
        let label: String
        if !first.city.isEmpty && (used.count == 1 || (used.count == 2 && used[1].city.isEmpty
                                                       && StoryPost.norm(used[1].region) == StoryPost.norm(first.region))) {
            label = "\(first.city), \(first.region)"
        } else {
            let names = used.prefix(3).map { $0.city.isEmpty ? $0.region : $0.city }
            label = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "") : (names.first ?? "")
        }
        // "See all": the page of the first place the app can open
        var route: ExploreRoute?
        for pl in used {
            if !pl.city.isEmpty, let key = areaKey(city: pl.city, region: pl.region, explore: explore) { route = .area(key); break }
            if let st = explore.states.first(where: { StoryPost.norm($0.name) == StoryPost.norm(pl.region) }) { route = .state(st.id); break }
            if let c = explore.caribbean.first(where: { StoryPost.norm($0.name) == StoryPost.norm(pl.region) }) { route = .country(c.id); break }
        }
        return Articles(label: label, posts: picked, route: route)
    }

    private static func areaKey(city: String, region: String, explore: ExploreStore) -> String? {
        guard let data = explore.data else { return nil }
        let c = StoryPost.norm(city), r = StoryPost.norm(region)
        if let x = data.cities.first(where: { StoryPost.norm($0.name) == c && StoryPost.norm($0.state) == r }) { return "us:\(x.id)" }
        if let x = data.destinations.first(where: { StoryPost.norm($0.name) == c
            && (StoryPost.norm($0.state) == r || StoryPost.norm($0.country) == r) && !$0.image.isEmpty }) { return "dest:\(x.id)" }
        return nil
    }
}
