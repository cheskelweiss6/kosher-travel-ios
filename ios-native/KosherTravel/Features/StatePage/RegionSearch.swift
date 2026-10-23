import SwiftUI
import Observation

// The in-page search on the United States, Caribbean, state and country pages: a port of the website's
// components/RegionSearch.tsx and searchIndex.ts. Scoped to the page and everything under it; instant, offline
// matching on the website's own listing index (statesearch.json, exported by scripts/export-statepages.sh) plus the
// page's parks, the places and towns travelers tagged, and travelers' articles and posts.

/// Where an in-page search looks (web RegionScope).
enum SPSearchScope: Hashable {
    case unitedStates, caribbean
    case state(String)
    case country(String)

    var label: String {
        switch self {
        case .unitedStates: return "United States"
        case .caribbean: return "Caribbean"
        case .state(let n), .country(let n): return n
        }
    }
    /// web scope.region
    var region: String {
        switch self {
        case .unitedStates, .state: return "North America"
        case .caribbean, .country: return "Caribbean"
        }
    }
    var countryName: String? {
        switch self {
        case .unitedStates, .state: return "United States"
        case .country(let n): return n
        case .caribbean: return nil
        }
    }
    var stateName: String? { if case .state(let n) = self { return n }; return nil }
}

// MARK: - Matching (web searchIndex.ts)

enum SPSearchText {
    static let wordCanon: [String: String] = [
        "borough": "boro", "bch": "beach", "saint": "st", "fort": "ft", "mount": "mt", "centre": "center", "ctr": "center",
        "mikveh": "mikvah", "mikva": "mikvah", "mikvaos": "mikvah", "mikvaot": "mikvah", "mikvot": "mikvah", "mikvah": "mikvah",
        "synagogue": "shul", "synagogues": "shul", "shuls": "shul", "shtiebel": "shul", "shtiebels": "shul", "minyan": "shul",
        "minyanim": "shul", "temple": "shul", "congregation": "shul",
        "supermarket": "grocery", "supermarkets": "grocery", "groceries": "grocery", "grocer": "grocery",
        "pizzeria": "pizza", "pizzas": "pizza", "pizzerias": "pizza",
        "restaurants": "restaurant", "restaurant": "restaurant", "resturant": "restaurant", "eatery": "restaurant",
        "hotels": "hotel", "motel": "hotel", "resort": "hotel", "resorts": "hotel", "inn": "hotel",
        "cafe": "cafe", "coffee": "cafe", "chabbad": "chabad", "lubavitch": "chabad",
    ]
    static let phraseExpand: [String: [String]] = [
        "nyc": ["new", "york"], "ny": ["new", "york"], "nj": ["new", "jersey"], "la": ["los", "angeles"], "dc": ["washington"],
        "sf": ["san", "francisco"], "lv": ["las", "vegas"], "phila": ["philadelphia"], "philly": ["philadelphia"],
    ]
    static let filler: Set<String> = ["in", "the", "of", "near", "at", "a", "an", "and", "kosher", "me", "for", "best"]

    static func canon(_ w: String) -> String {
        if let c = wordCanon[w] { return c }
        if w.count > 4 && w.hasSuffix("s") && !w.hasSuffix("ss") && !w.hasSuffix("us") && !w.hasSuffix("is") {
            let s = String(w.dropLast())
            return wordCanon[s] ?? s
        }
        return w
    }

    /// web normalizeSearchText
    static func normalize(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.decomposedStringWithCanonicalMapping.lowercased().unicodeScalars {
            let v = u.value
            if (0x300...0x36F).contains(v) || (0x591...0x5C7).contains(v) { continue }
            if "'\u{2019}\u{2018}`\u{05F3}\u{05F4}\"".unicodeScalars.contains(u) { continue }
            if u == "&" { out.append(contentsOf: " and ".unicodeScalars); continue }
            let keep = (0x61...0x7A).contains(v) || (0x30...0x39).contains(v) || (0x5D0...0x5EA).contains(v)
            out.append(keep ? u : " ")
        }
        return String(out).split(separator: " ").joined(separator: " ")
    }

    /// web nn (RegionSearch)
    static func nn(_ s: String) -> String { normalize(s) }

    static func words(_ parts: String?...) -> [String] { words(parts) }
    static func words(_ parts: [String?]) -> [String] {
        var out: [String] = []
        for p in parts { guard let p, !p.isEmpty else { continue }
            for w in normalize(p).split(separator: " ") { out.append(canon(String(w))) }
        }
        return out
    }

    static func tokens(_ q: String, expand: Bool = true, fold: Bool = true) -> [String] {
        let ws = normalize(q).split(separator: " ").map(String.init)
        var out: [String] = []
        for w in ws {
            if expand, let e = phraseExpand[w], w != "la" || ws.count > 1 { out += e } else { out.append(fold ? canon(w) : w) }
        }
        let kept = out.filter { !filler.contains($0) }
        return kept.isEmpty ? out : kept
    }

    /// The query's forms, each row keeping its best score: expanded, and unfolded ("la fort" -> La Fortuna: a half-typed
    /// "fort" is not "ft"). A shortcut word followed by more words ("la fortuna", "la jolla") may start a name, so the
    /// query as typed is tried too; at the end ("pizza la") it stays the shortcut. (Cheskel's 9:34 AM video, Oct 23 2026.)
    static func tokenForms(_ q: String) -> [[String]] {
        let ws = normalize(q).split(separator: " ").map(String.init)
        var forms = [tokens(q), tokens(q, fold: false)]
        if ws.dropLast().contains(where: { phraseExpand[$0] != nil }) {
            forms += [tokens(q, expand: false), tokens(q, expand: false, fold: false)]
        }
        var out: [[String]] = []
        for f in forms where !out.contains(f) { out.append(f) }
        return out
    }

    static func within1(_ a: [Character], _ b: [Character]) -> Bool {
        if a == b { return true }
        let la = a.count, lb = b.count
        if abs(la - lb) > 1 { return false }
        var i = 0, j = 0, edits = 0
        while i < la && j < lb {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if la > lb { i += 1 } else if lb > la { j += 1 } else { i += 1; j += 1 }
        }
        return edits + (la - i) + (lb - j) <= 1
    }

    static func wordScore(_ token: String, _ words: [String], _ fuzzy: Bool) -> Double {
        var best = 0.0
        let tc = token.count
        for w in words {
            if w == token { return 3 }
            if w.hasPrefix(token) { best = max(best, tc >= 2 ? 2 : 1) }
            else if tc >= 4 && w.contains(token) { best = max(best, 1) }
            else if fuzzy && tc >= 5 && w.count >= 4 {
                let a = Array(token), b = Array(w)
                if within1(a, b) || within1(a, Array(b.prefix(tc))) { best = max(best, 1) }
            }
        }
        return best
    }

    static func matchesAllWords(_ q: String, _ fields: String?...) -> Bool {
        let forms = tokenForms(q)
        if forms[0].isEmpty { return true }
        let w = words(fields)
        return forms.contains { t in t.allSatisfy { wordScore($0, w, false) > 0 } }
    }
}

enum SPSearchKind: String, CaseIterable {
    case destination, restaurant, synagogue, chabad, mikvah, hotel, grocery, attraction
    var typeWords: [String] {
        switch self {
        case .destination: return ["city", "destination"]
        case .restaurant: return ["restaurant", "food", "eat", "dining"]
        case .synagogue: return ["shul"]
        case .chabad: return ["chabad", "house"]
        case .mikvah: return ["mikvah"]
        case .hotel: return ["hotel", "stay", "lodging"]
        case .grocery: return ["grocery", "market", "store", "shop"]
        case .attraction: return ["attraction", "things", "todo"]
        }
    }
    var category: PlaceCategory {
        switch self {
        case .restaurant: return .restaurant
        case .synagogue, .mikvah: return .shul
        case .chabad: return .chabad
        case .hotel: return .hotel
        case .grocery: return .grocery
        case .destination, .attraction: return .todo
        }
    }
}

enum SPSearchGroup: String, CaseIterable {
    case areas, parks, todo, hotels, food, shuls, grocery, stories, inside
    var label: String {
        switch self {
        case .areas: return "Cities & Areas"
        case .todo: return "Things to Do"
        case .parks: return "Parks"
        case .hotels: return "Hotels"
        case .food: return "Restaurants"
        case .shuls: return "Shuls & Chabad"
        case .grocery: return "Groceries"
        case .stories: return "Posts & articles"
        case .inside: return "Places"
        }
    }
    var systemImage: String {
        switch self {
        case .areas, .inside: return "mappin"
        case .todo: return "building.columns"
        case .parks: return "tree"
        case .hotels: return "bed.double"
        case .food: return "fork.knife"
        case .shuls: return "building.2"
        case .grocery: return "basket"
        case .stories: return "book"
        }
    }
    var kindLine: String {
        switch self {
        case .todo: return "Things to do"
        case .parks: return "Park"
        case .hotels: return "Hotel"
        case .food: return "Restaurant"
        case .shuls: return "Shul"
        case .grocery: return "Grocery"
        default: return ""
        }
    }
    var isPlace: Bool { self != .areas && self != .stories }
    static func of(_ k: SPSearchKind) -> SPSearchGroup {
        switch k {
        case .destination: return .areas
        case .attraction: return .todo
        case .hotel: return .hotels
        case .restaurant: return .food
        case .synagogue, .chabad, .mikvah: return .shuls
        case .grocery: return .grocery
        }
    }
}

/// What a result opens (web RegionHit).
enum SPSearchHit {
    case city(key: String, name: String, sub: String)
    case place(PlaceItem)
    case nationalPark(NationalPark)
    case statePark(StatePark)
    case area(ExploreRoute)
    case story(String)
}

struct SPSearchRow: Identifiable {
    let id: String
    let kind: SPSearchKind
    let group: SPSearchGroup
    let name: String
    let subtitle: String
    let nameWords: [String]
    let nameNorm: String
    let typeWords: [String]
    let placeWords: [String]
    let extraWords: [String]
    let aliasNorm: String
    let thumb: String
    let hit: SPSearchHit

    /// web scoreEntry
    func score(_ tokens: [String], _ qNorm: String, fuzzy: Bool) -> Double {
        var total = 0.0
        for t in tokens {
            let sName = SPSearchText.wordScore(t, nameWords, fuzzy) * 3
            let sType = SPSearchText.wordScore(t, typeWords, fuzzy) * 2
            let sPlace = SPSearchText.wordScore(t, placeWords, fuzzy) * 1.5
            let sExtra = kind == .destination ? (fuzzy ? SPSearchText.wordScore(t, extraWords, false) * 0.4 : 0)
                                              : SPSearchText.wordScore(t, extraWords, false) * 0.6
            let s = max(sName, sType, sPlace, sExtra)
            if s == 0 { return 0 }
            total += s
        }
        if nameNorm == qNorm { total += 12 }
        else if nameNorm.hasPrefix(qNorm) { total += 6 }
        else if qNorm.count >= 3 && nameNorm.contains(qNorm) { total += 3 }
        if kind == .destination {
            total += 1
            if !aliasNorm.isEmpty && (" " + aliasNorm + " ").contains(" " + qNorm + " ") { total += 10 }
        }
        return total
    }
}

struct SPSearchSection: Identifiable {
    let group: SPSearchGroup
    let rows: [SPSearchRow]
    let label: String
    var id: String { group.rawValue }
}

struct SPSearchOutcome {
    var groups: [SPSearchSection] = []
    var exact = true
    var total: Int { groups.reduce(0) { $0 + $1.rows.count } }
}

// MARK: - The listing index (statesearch.json)

private struct SPSearchFile: Decodable {
    struct Dest: Decodable { var id: String; var key: String; var name: String; var state: String; var country: String; var region: String; var sub: String; var image: String }
    struct Entry: Decodable { var k: String; var n: String; var s: String; var c: String; var d: Int; var nw: String; var tw: String; var pw: String; var ew: String?; var an: String?; var th: String?; var it: SPListing? }
    var dests: [Dest]
    var entries: [Entry]
}

@MainActor
@Observable
final class SPSearchIndex {
    static let shared = SPSearchIndex()
    @ObservationIgnored fileprivate var file: SPSearchFile?
    private(set) var loaded = false
    @ObservationIgnored private var loading = false
    /// A search carried to a wider page ("Search all of United States").
    @ObservationIgnored var carry: [String: String] = [:]

    func load() async {
        if loaded || loading { return }
        loading = true
        let f: SPSearchFile? = await Task.detached(priority: .userInitiated) {
            guard let url = Bundle.main.url(forResource: "statesearch", withExtension: "json"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SPSearchFile.self, from: data)
        }.value
        file = f
        loaded = true
        loading = false
    }
}

// MARK: - Building a page's rows (web RegionSearch `rows`)

@MainActor
enum SPSearchRows {
    static let stateCodes: [String: String] = {
        let raw = "alabama:AL|alaska:AK|arizona:AZ|arkansas:AR|california:CA|colorado:CO|connecticut:CT|delaware:DE|district of columbia:DC|florida:FL|georgia:GA|hawaii:HI|idaho:ID|illinois:IL|indiana:IN|iowa:IA|kansas:KS|kentucky:KY|louisiana:LA|maine:ME|maryland:MD|massachusetts:MA|michigan:MI|minnesota:MN|mississippi:MS|missouri:MO|montana:MT|nebraska:NE|nevada:NV|new hampshire:NH|new jersey:NJ|new mexico:NM|new york:NY|north carolina:NC|north dakota:ND|ohio:OH|oklahoma:OK|oregon:OR|pennsylvania:PA|rhode island:RI|south carolina:SC|south dakota:SD|tennessee:TN|texas:TX|utah:UT|vermont:VT|virginia:VA|washington:WA|west virginia:WV|wisconsin:WI|wyoming:WY"
        var m: [String: String] = [:]
        for pair in raw.split(separator: "|") {
            let p = pair.split(separator: ":")
            m[String(p[0])] = String(p[1])
        }
        return m
    }()
    static let codeState: [String: String] = Dictionary(uniqueKeysWithValues: stateCodes.map { ($1, $0) })
    static let stateOrder: [String] = stateCodes.keys.sorted()

    static func stateKey(_ s: String) -> String {
        let n = SPSearchText.nn(s)
        if stateCodes[n] != nil { return n }
        return codeState[n.uppercased()] ?? n
    }
    static func titleCase(_ s: String) -> String {
        var out = ""
        var prevWord = false
        for ch in s {
            let isWord = ch.isLetter || ch.isNumber || ch == "_"
            out.append(isWord && !prevWord ? Character(ch.uppercased()) : ch)
            prevWord = isWord
        }
        return out
    }
    static let parkPattern = try? NSRegularExpression(
        pattern: "\\b(state park|national park|national monument|recreation area|national forest|preserve|wildlife refuge)s?\\b",
        options: [.caseInsensitive])
    static func isPark(_ s: String) -> Bool {
        guard let p = parkPattern else { return false }
        return p.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func build(scope: SPSearchScope) -> [SPSearchRow] {
        let st = scope.stateName.map(stateKey) ?? ""
        let ctry = SPSearchText.nn(scope.countryName ?? "")
        let reg = scope.region
        let isUS = ctry == "united states"
        var out: [SPSearchRow] = []
        var seen = Set<String>()
        func add(_ r: SPSearchRow) {
            let k = r.group.rawValue + "|" + SPSearchText.nn(r.name)
                + (r.group == .parks || r.group == .hotels ? "" : "|" + String(SPSearchText.nn(r.subtitle).prefix(24)))
            if seen.insert(k).inserted { out.append(r) }
        }
        func mk(_ g: SPSearchGroup, _ kind: SPSearchKind, _ rid: String, _ name: String, _ sub: String, _ hit: SPSearchHit,
                type: [String] = [], place: [String?] = [], extra: [String?] = [], thumb: String? = nil) -> SPSearchRow {
            let nw = SPSearchText.words(name)
            return SPSearchRow(id: rid, kind: kind, group: g, name: name, subtitle: sub, nameWords: nw, nameNorm: nw.joined(separator: " "),
                               typeWords: type, placeWords: SPSearchText.words(place), extraWords: SPSearchText.words(extra),
                               aliasNorm: "", thumb: thumb ?? "", hit: hit)
        }
        var regionCountries = Set<String>()
        let pages = StatePageStore.shared

        // the listing index
        if let f = SPSearchIndex.shared.file {
            for (i, e) in f.entries.enumerated() {
                guard e.d >= 0 && e.d < f.dests.count, let kind = SPSearchKind(rawValue: e.k) else { continue }
                let d = f.dests[e.d]
                let inScope: Bool = {
                    if !st.isEmpty { return d.region == "North America" && SPSearchText.nn(d.country) == "united states" && stateKey(d.state) == st }
                    if !ctry.isEmpty { return SPSearchText.nn(d.country) == ctry && (isUS ? d.region == "North America" : true) }
                    return d.region == reg || (reg == "Caribbean" && d.region == "Central America")
                }()
                if !inScope { continue }
                if st.isEmpty && ctry.isEmpty && !d.country.isEmpty && reg != "North America" {
                    if SPSearchText.nn(d.country) != "united states" { regionCountries.insert(SPSearchText.nn(d.country)) }
                    if !d.state.isEmpty { regionCountries.insert(SPSearchText.nn(d.state)) }
                }
                let hit: SPSearchHit
                if let l = e.it {
                    hit = .place(l.item(kind.category, index: i, fallbackCity: e.c))
                } else {
                    hit = .city(key: d.key.isEmpty ? "" : (kind == .mikvah ? "\(d.key)/hub:shuls" : d.key), name: d.name, sub: d.sub)
                }
                let thumb = e.th ?? e.it?.photo ?? ""
                add(SPSearchRow(id: "i:\(i)", kind: kind, group: .of(kind), name: e.n, subtitle: e.s,
                                nameWords: e.nw.split(separator: " ").map(String.init), nameNorm: SPSearchText.normalize(e.n),
                                typeWords: e.tw.split(separator: " ").map(String.init), placeWords: e.pw.split(separator: " ").map(String.init),
                                extraWords: (e.ew ?? "").split(separator: " ").map(String.init), aliasNorm: e.an ?? "",
                                thumb: thumb, hit: hit))
            }
        }

        // states (United States page) or countries (the Caribbean page)
        struct SubArea { let name: String; let image: String; let state: Bool; let route: ExploreRoute }
        var subAreas: [SubArea] = []
        switch scope {
        case .unitedStates:
            subAreas = pages.usStates.map { SubArea(name: $0.name, image: $0.image, state: true, route: .state($0.id)) }
        case .caribbean:
            var seenC = Set<String>()
            for d in SPSearchIndex.shared.file?.dests ?? [] where d.region == "Caribbean" || d.region == "Central America" {
                let k = d.country.lowercased()
                if d.country.isEmpty || !seenC.insert(k).inserted { continue }
                let tile = pages.caribbean.first { $0.name.lowercased() == k }
                let route: ExploreRoute = tile.map { ExploreRoute.country($0.id) } ?? .web(.country(d.country))
                subAreas.append(SubArea(name: d.country, image: tile?.image ?? "", state: false, route: route))
            }
        default: break
        }
        if st.isEmpty && ctry.isEmpty { for a in subAreas where SPSearchText.nn(a.name) != "united states" { regionCountries.insert(SPSearchText.nn(a.name)) } }
        for a in subAreas {
            let line = a.state ? "State · United States" : "Country · Caribbean"
            add(mk(.areas, .destination, "a:\(a.state ? "state" : "country"):\(a.name)", a.name, line, .area(a.route),
                   type: [a.state ? "state" : "country"], place: [a.state ? "North America" : "Caribbean"], thumb: a.image))
        }

        // parks (US state pages and the United States page)
        let parks = ParkStore.shared
        if isUS {
            for s in (st.isEmpty ? stateOrder : [st]) {
                let sName = titleCase(s)
                for p in parks.nationalParks(in: sName) + parks.tribalAndScenic(in: sName) {
                    add(mk(.parks, .attraction, "np:\(p.id.isEmpty ? p.name : p.id)", p.name,
                           [p.designation.isEmpty ? "National Park" : p.designation, sName].joined(separator: " · "), .nationalPark(p),
                           type: ["park", "national", "parks"], place: [sName, p.address], extra: [p.designation, p.shortDescription], thumb: p.image))
                }
                for p in parks.stateParks(in: sName) {
                    add(mk(.parks, .attraction, "sp:\(p.id.isEmpty ? p.name : p.id)", p.name, "State Park · \(sName)", .statePark(p),
                           type: ["park", "state", "parks"], place: [sName], extra: [p.shortDescription], thumb: p.image))
                }
            }
        }

        // places travelers tagged
        let sights = SharedSights.shared
        for s in sights.all {
            let code = s.state
            let sub = SPSearchText.nn(s.citySub)
            let lastPart = SPSearchText.nn(s.citySub.split(separator: ",").last.map(String.init) ?? "")
            let ok: Bool = !st.isEmpty ? code == (stateCodes[st] ?? "-")
                : isUS ? (!code.isEmpty || sub.contains("united states"))
                : !ctry.isEmpty ? (lastPart == ctry || sub.contains(ctry))
                : regionCountries.contains(lastPart)
            if !ok { continue }
            let cat = s.category
            let park = isPark(s.name) || isPark(s.kind)
            let g: SPSearchGroup = cat == "hotel" ? .hotels : (cat == "shul" || cat == "chabad") ? .shuls : cat == "restaurant" ? .food
                : cat == "grocery" ? .grocery : park ? .parks : .todo
            let kind: SPSearchKind = g == .hotels ? .hotel : g == .shuls ? .synagogue : g == .food ? .restaurant : g == .grocery ? .grocery : .attraction
            let stateName = code.isEmpty ? "" : titleCase(codeState[code] ?? "")
            let whereLine = [s.cityName, code.isEmpty ? "" : (stateName.isEmpty ? code : stateName)].filter { !$0.isEmpty }.joined(separator: ", ")
            let place = s.asPlaceItem(cityName: s.cityName.isEmpty ? scope.label : s.cityName)
            let kindLine = titleCase(s.kind)
            add(mk(g, kind, "ts:\(s.id)", s.name,
                   [kindLine.isEmpty ? (g.kindLine.isEmpty ? "Place" : g.kindLine) : kindLine, whereLine.isEmpty ? s.area : whereLine]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                   .place(place),
                   type: [g == .hotels ? "hotel" : g == .parks ? "park" : "things"] + (kind == .hotel ? ["stay", "lodging"] : []),
                   place: [s.cityName, s.area, codeState[code]], extra: [s.kind], thumb: s.photo))
        }

        // towns travelers tagged (US)
        if isUS {
            for t in sights.towns {
                if !st.isEmpty && t.state != (stateCodes[st] ?? "-") { continue }
                let sName = titleCase(codeState[t.state] ?? t.state)
                add(mk(.areas, .destination, "tt:\(t.id)", t.name, "Town · \(sName)", .place(t.asPlaceItem(stateName: sName)),
                       type: ["town", "city"], place: [sName], thumb: t.photo))
            }
        }
        return out
    }

    /// travelers' articles and posts (web x.stories), added on top of the rest
    static func stories(scope: SPSearchScope, posts: [StoryPost], regionCountries: Set<String>) -> [SPSearchRow] {
        let st = scope.stateName.map(stateKey) ?? ""
        let ctry = SPSearchText.nn(scope.countryName ?? "")
        var out: [SPSearchRow] = []
        for s in posts {
            let stops = s.allStops
            let parts = stops.map { $0.citySub.split(separator: ",").map { SPSearchText.nn(String($0)) } }
            let ok = parts.contains { pp in
                if !st.isEmpty { return stateKey(pp.first ?? "") == st && (pp.count > 1 ? pp[1] : "").contains("united states") }
                if !ctry.isEmpty { return pp.contains(ctry) }
                return pp.contains { regionCountries.contains($0) }
            }
            if !ok { continue }
            let place = !s.placeName.isEmpty ? s.placeName : (stops.first?.cityName ?? s.cityName)
            let name = !s.title.isEmpty ? s.title : (!place.isEmpty ? place : "Traveler post")
            let m0 = s.media.first
            let nw = SPSearchText.words(name)
            out.append(SPSearchRow(id: "st:\(s.id)", kind: .attraction, group: .stories, name: name,
                                   subtitle: [s.isGuide ? "Article" : "Post", place, s.authorName].filter { !$0.isEmpty }.joined(separator: " · "),
                                   nameWords: nw, nameNorm: nw.joined(separator: " "),
                                   typeWords: s.isGuide ? ["article", "story", "guide"] : ["post", "story"],
                                   placeWords: SPSearchText.words([place, s.cityName, s.citySub] + stops.map { $0.cityName }),
                                   extraWords: SPSearchText.words(String(s.caption.prefix(300)), s.authorName),
                                   aliasNorm: "", thumb: m0.map { $0.thumb.isEmpty ? $0.url : $0.thumb } ?? "", hit: .story(s.id)))
        }
        return out
    }

    static let generic: Set<String> = ["restaurant", "food", "eat", "dining", "shul", "chabad", "house", "mikvah", "hotel", "stay", "lodging",
        "grocery", "market", "store", "shop", "attraction", "things", "todo", "thing", "do", "pizza", "cafe", "sushi", "deli", "bakery", "park",
        "beach", "museum", "kosher", "the", "a", "of", "in", "and", "meat", "dairy", "grill", "bagel", "national", "state", "center", "resort",
        "inn", "lodge", "tour", "trail", "lake"]

    /// web strongName: the place's own name was typed
    static func strongName(_ q: String, _ r: SPSearchRow) -> Bool {
        let tokens = SPSearchText.tokens(q)
        let specific = tokens.filter { !generic.contains($0) }
        if specific.isEmpty || specific.joined().count < 4 { return false }
        if !SPSearchText.matchesAllWords(q, r.name) { return false }
        let qn = SPSearchText.nn(q)
        return SPSearchText.nn(r.name).hasPrefix(qn) || Double(tokens.count) / Double(max(1, r.nameWords.count)) >= 0.5
    }

    /// web searchIndex + RegionSearch `grouped`
    static func search(_ rows: [SPSearchRow], _ query: String) -> SPSearchOutcome {
        let forms = SPSearchText.tokenForms(query)
        if forms[0].isEmpty { return SPSearchOutcome() }
        let qNorm = SPSearchText.normalize(query)
        func run(_ fuzzy: Bool) -> [(SPSearchRow, Double)] {
            rows.compactMap { r in
                let s = forms.map { r.score($0, qNorm, fuzzy: fuzzy) }.max() ?? 0
                return s > 0 ? (r, s) : nil
            }
        }
        var exact = true
        var scored = run(false)
        if scored.isEmpty { scored = run(true) }
        for tokens in forms where scored.isEmpty && tokens.count > 1 {
            exact = false
            let placeTokens = tokens.filter { t in rows.contains { $0.kind == .destination && SPSearchText.wordScore(t, $0.placeWords, false) >= 2 } }
            for e in rows {
                var matched = 0, total = 0.0, placeOk = true
                for t in tokens {
                    let s = max(SPSearchText.wordScore(t, e.nameWords, true) * 3, SPSearchText.wordScore(t, e.typeWords, true) * 2,
                                SPSearchText.wordScore(t, e.placeWords, true) * 1.5,
                                e.kind == .destination ? 0 : SPSearchText.wordScore(t, e.extraWords, false) * 0.6)
                    if s > 0 { matched += 1; total += s } else if placeTokens.contains(t) { placeOk = false }
                }
                if placeOk && matched >= tokens.count - 1 && matched > 0 { scored.append((e, total)) }
            }
        }
        scored.sort { a, b in a.1 != b.1 ? a.1 > b.1 : a.0.name.localizedCompare(b.0.name) == .orderedAscending }
        // searchIndex's groups: by kind in its order, the best hit's kind first
        var kinds = SPSearchKind.allCases.filter { k in scored.contains { $0.0.kind == k } }
        if kinds.count > 1, let top = scored.first?.0.kind, let i = kinds.firstIndex(of: top), i > 0 { kinds.insert(kinds.remove(at: i), at: 0) }
        var by: [SPSearchGroup: [SPSearchRow]] = [:]
        var first: SPSearchGroup?
        for k in kinds { for (r, _) in scored where r.kind == k {
            if first == nil { first = r.group }
            by[r.group, default: []].append(r)
        } }
        if let p = by[.parks], let todoRows = by[.todo] {
            let parkNames = Set(p.map { SPSearchText.nn($0.name) })
            let todo = todoRows.filter { !parkNames.contains(SPSearchText.nn($0.name)) }
            if todo.isEmpty { by[.todo] = nil } else { by[.todo] = todo }
            if first == .todo && todo.isEmpty { first = .parks }
        }
        if first == .stories {
            if let g = SPSearchGroup.allCases.first(where: { x in
                guard x.isPlace, let top = by[x]?.first else { return false }
                return strongName(query, top) && SPSearchText.nn(top.name).hasPrefix(SPSearchText.nn(query))
            }) { first = g } else if by[.areas] != nil { first = .areas }
        } else if let f = first, f.isPlace, let area = by[.areas]?.first, SPSearchText.matchesAllWords(query, area.name),
                  let top = by[f]?.first, !strongName(query, top) {
            first = .areas
        }
        var candidates: [SPSearchGroup] = []
        if let f = first { candidates.append(f) }
        candidates += [.areas, .stories]
        candidates += SPSearchGroup.allCases
        var order: [SPSearchGroup] = []
        for g in candidates where !order.contains(g) { order.append(g) }
        let topArea: SPSearchRow? = {
            guard first == .areas, let a = by[.areas]?.first, SPSearchText.matchesAllWords(query, a.name) else { return nil }
            return a
        }()
        var outcome = SPSearchOutcome(exact: exact)
        for g in order {
            guard let rs = by[g], !rs.isEmpty else { continue }
            let label = g == .stories ? "Posts & articles" + (topArea.map { " in \($0.name)" } ?? "") : g.label
            outcome.groups.append(SPSearchSection(group: g, rows: rs, label: label))
        }
        return outcome
    }
}

// MARK: - The results panel

/// The in-page search's results, covering the page while the field has words in it.
struct RegionSearchResults: View {
    let scope: SPSearchScope
    @Binding var query: String

    @Environment(StoryFeed.self) private var feed
    private var index: SPSearchIndex { SPSearchIndex.shared }
    @State private var base: [SPSearchRow] = []
    @State private var builtKey = ""
    @State private var debounced = ""
    @State private var outcome = SPSearchOutcome()
    @State private var open: Set<SPSearchGroup> = []
    @State private var selected: PlaceItem?
    @State private var nationalPark: NationalPark?
    @State private var statePark: StatePark?
    private static let perGroup = 4

    /// The data the rows are built from; a change rebuilds them (web extraTick).
    private var dataKey: String {
        "\(index.loaded)|\(StatePageStore.shared.usStates.count)|\(SharedSights.shared.all.count)|\(SharedSights.shared.towns.count)|\(ParkStore.shared.isLoaded)|\(feed.posts.count)"
    }

    private var wider: (label: String, scope: SPSearchScope, route: ExploreRoute)? {
        switch scope {
        case .state: return ("United States", .unitedStates, .unitedStates)
        case .country: return ("Caribbean", .caribbean, .caribbean)
        default: return nil
        }
    }

    private var q: String { debounced.trimmingCharacters(in: .whitespaces) }
    private var settling: Bool { query.trimmingCharacters(in: .whitespaces) != q }
    private var loadingExtra: Bool { !index.loaded || !SharedSights.shared.isLoaded || !feed.loadedOnce }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if q.isEmpty || (settling && outcome.total == 0) || (outcome.total == 0 && loadingExtra) {
                    Text("Searching \(scope.label)…")
                        .font(.footnote).foregroundStyle(Color.textSecondary)
                } else if outcome.total == 0 {
                    empty
                } else {
                    Text(outcome.exact ? "\(outcome.total) result\(outcome.total == 1 ? "" : "s") in \(scope.label)"
                                       : "No exact match for “\(q)” in \(scope.label). Closest matches:")
                        .font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
                        .accessibilityAddTraits(.updatesFrequently)
                    ForEach(outcome.groups) { g in section(g.group, g.rows, g.label) }
                }
            }
            .padding(Theme.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.immediately)
        .background(Color.white)
        .task {
            await index.load()
            await StatePageStore.shared.load()
            SharedSights.shared.ensureLoaded()
            if scope == .unitedStates || scope.stateName != nil { await ParkStore.shared.load() }
        }
        .task(id: dataKey) { rebuild() }
        .task(id: query) {
            let text = query
            if text.trimmingCharacters(in: .whitespaces).isEmpty { debounced = ""; return }
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            debounced = text
            open = []
            refresh()
        }
        .sheet(item: $selected) { item in
            PlaceDetailView(item: item, onOpenStory: nil)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $nationalPark) { NationalParkSheet(park: $0) }
        .sheet(item: $statePark) { StateParkSheet(park: $0) }
    }

    private func rebuild() {
        var rows = SPSearchRows.build(scope: scope)
        // the region's countries, for the posts filter (web regionCountries)
        var countries = Set<String>()
        if scope == .caribbean {
            for r in rows where r.group == .areas && r.id.hasPrefix("a:country:") { countries.insert(SPSearchText.nn(r.name)) }
            for d in index.file?.dests ?? [] where d.region == "Caribbean" || d.region == "Central America" {
                if !d.country.isEmpty && SPSearchText.nn(d.country) != "united states" { countries.insert(SPSearchText.nn(d.country)) }
                if !d.state.isEmpty { countries.insert(SPSearchText.nn(d.state)) }
            }
        }
        var seen = Set(rows.map { $0.group.rawValue + "|" + SPSearchText.nn($0.name) + "|" + String(SPSearchText.nn($0.subtitle).prefix(24)) })
        for r in SPSearchRows.stories(scope: scope, posts: feed.posts, regionCountries: countries)
        where seen.insert(r.group.rawValue + "|" + SPSearchText.nn(r.name) + "|" + String(SPSearchText.nn(r.subtitle).prefix(24))).inserted {
            rows.append(r)
        }
        base = rows
        refresh()
    }

    private func refresh() {
        outcome = q.isEmpty ? SPSearchOutcome() : SPSearchRows.search(base, debounced)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.title2.weight(.light)).foregroundStyle(Color.textTertiary)
            Text("No results for “\(q)”").font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
            Text("Check the spelling or try a shorter word, like a city or a place name.")
                .font(.footnote).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            if let w = wider {
                NavigationLink(value: w.route) {
                    HStack(spacing: 4) {
                        Text("Search all of \(w.label)")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.footnote.weight(.bold)).foregroundStyle(Color.navy)
                    .padding(.horizontal, 16).frame(minHeight: 44)
                    .background(Color.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { index.carry[w.scope.label] = q })
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func section(_ g: SPSearchGroup, _ rows: [SPSearchRow], _ label: String) -> some View {
        let isOpen = open.contains(g)
        let shown = isOpen ? rows : Array(rows.prefix(Self.perGroup))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label.uppercased()).font(.caption2.weight(.heavy)).tracking(0.8).foregroundStyle(Color.textSecondary)
                Text("\(rows.count)").font(.caption2.weight(.bold)).foregroundStyle(Color.textTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(shown) { r in
                    resultRow(r, g)
                    if r.id != shown.last?.id { Rectangle().fill(Color.hairline).frame(height: 1).padding(.leading, 64) }
                }
            }
            .background(Color.white)
            .hairline(radius: 16)
            if rows.count > Self.perGroup {
                Button(isOpen ? "Show less" : "Show all \(rows.count)") {
                    withAnimation(.easeOut(duration: 0.2)) { if isOpen { open.remove(g) } else { open.insert(g) } }
                }
                .font(.footnote.weight(.bold)).foregroundStyle(Color.navy).frame(minHeight: 44)
            }
        }
    }

    private func rowLabel(_ r: SPSearchRow, _ g: SPSearchGroup) -> some View {
        HStack(spacing: 12) {
            SPImage(urls: [r.thumb], maxPixel: 160, noPhoto: AnyView(
                Image(systemName: g.systemImage).font(.body).foregroundStyle(Color.navy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.surface)))
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy).lineLimit(2).multilineTextAlignment(.leading)
                if !r.subtitle.isEmpty {
                    Text(r.subtitle).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func resultRow(_ r: SPSearchRow, _ g: SPSearchGroup) -> some View {
        switch r.hit {
        case .city(let key, let name, let sub):
            NavigationLink(value: key.isEmpty ? ExploreRoute.web(.city(name, sub: sub)) : ExploreRoute.area(key)) { rowLabel(r, g) }
                .buttonStyle(.plain)
        case .area(let route):
            NavigationLink(value: route) { rowLabel(r, g) }.buttonStyle(.plain)
        case .story(let id):
            NavigationLink(value: ExploreRoute.story(id)) { rowLabel(r, g) }.buttonStyle(.plain)
        case .place(let item):
            Button { selected = item } label: { rowLabel(r, g) }.buttonStyle(.plain)
        case .nationalPark(let p):
            Button { nationalPark = p } label: { rowLabel(r, g) }.buttonStyle(.plain)
        case .statePark(let p):
            Button { statePark = p } label: { rowLabel(r, g) }.buttonStyle(.plain)
        }
    }
}
