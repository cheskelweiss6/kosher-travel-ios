import Foundation
import Observation

// Port of the website's "places travelers tagged in their posts" layer (Oct 21-22 2026):
//   src/components/stories/travelerSights.ts  (deriveTravelerSights, deriveTravelerTowns, sightAllowed, notBuiltIn, stateCodeOf)
//   src/components/stories/sharedSights.ts    (fetchSharedPlaces, sightsForCity, dedupeSights, normPlaceName, stayLabel, sightLine)
//   src/components/stories/travelerPlaces.tsx (travelerSection, useTravelerPlaces, useTravelerTowns, travelerAsPlace)
// Read from the live posts themselves (Firestore `storyPosts`, status == live, newest 300), nothing stored. When the posts
// cannot be read, the sights saved in `places` (source osm) stand in, like the website. Read-only: nothing is written.
// The app cities come from the same storyCities.ts table the Zmanim port bundles (ZmanimData.storyCities).

/// A place a traveler tagged in a live post (web `SharedSight` / `TravelerSight`).
struct SharedSight: Identifiable, Hashable, Sendable {
    var id: String            // 'osm-N304716872' / 'gp-ChIJ...' / 'name-...'
    var src: String           // 'osm:N304716872' / 'gp:ChIJ...'
    var name: String
    var area: String
    var kind: String
    var category: String      // the website's PlaceCategory word: 'todo' | 'hotel' | 'shul' | 'chabad'
    var lat: Double
    var lng: Double
    var cityId: String
    var cityName: String
    var citySub: String
    var cityGuessed: Bool = false
    var state: String = ""    // 'UT' when in the US, else ''
    var posts: [String] = []  // live posts that tag it, newest first
    var url: String? = nil    // Google Maps link of a Google place
    var link: String? = nil   // the poster's own link for it (hotel booking / affiliate)
    var photo: String? = nil  // a traveler's photo of it

    /// Which section of a region it belongs in (web travelerSection).
    var section: TravelerSection { TravelerSection.of(name: name, kind: kind, category: category) }
    /// "Campground", "RV park", "Cabins"… else "Hotel" (web stayLabel).
    var stayLabel: String { TravelerRules.stayLabel(name: name, kind: kind) }
    /// "Geyser · Lower Geyser Basin, Yellowstone National Park, WY" (web sightLine).
    var line: String { [kind, area].filter { !$0.isEmpty }.joined(separator: " · ") }
    /// The park card's line: kind with capital words, then the area (web `[kindLabel(kind), area]`).
    var kindLine: String { [TravelerRules.kindLabel(kind), area].filter { !$0.isEmpty }.joined(separator: " · ") }
    /// "Book" for a place to stay, else "Open" (the poster's own link).
    var linkVerb: String { category == "hotel" ? "Book" : "Open" }
    /// The app's section for the place sheet.
    var placeCategory: PlaceCategory { PlaceCategory.fromTraveler(category) }
    /// Its map link (web travelerMapUrl): the Google place when it is one, else Apple Maps by name and location.
    var mapURL: URL? {
        if let u = url, let x = URL(string: u) { return x }
        return MapLinks.url(.apple, MapTarget(name: name, query: nil, lat: lat, lng: lng))
    }
    var linkURL: URL? { link.flatMap { URL(string: $0) } }
    /// "In 1 story" / "In 3 stories".
    var storiesLabel: String { posts.count == 1 ? "In 1 story" : "In \(posts.count) stories" }
}

/// A town a traveler tagged inside a US state (web `TravelerTown`).
struct TravelerTown: Identifiable, Hashable, Sendable {
    var id: String
    var src: String
    var name: String
    var lat: Double
    var lng: Double
    var state: String
    var posts: [String] = []
    var url: String? = nil
    var photo: String? = nil

    var mapURL: URL? {
        if let u = url, let x = URL(string: u) { return x }
        return MapLinks.url(.apple, MapTarget(name: name, query: nil, lat: lat, lng: lng))
    }
    var storiesLabel: String { posts.count == 1 ? "In 1 story" : "In \(posts.count) stories" }

    /// The town in the shape of a traveler's place (web townAsPlace), for the place sheet.
    func asSight(stateName: String) -> SharedSight {
        SharedSight(id: id, src: src, name: name, area: "\(stateName), USA", kind: "Town", category: "todo", lat: lat, lng: lng,
                    cityId: "", cityName: name, citySub: stateName, state: state, posts: posts, url: url, link: nil, photo: photo)
    }
}

/// web `TravelerSection`
enum TravelerSection: String, Sendable {
    case stay, park, todo, shul, chabad

    static func of(name: String, kind: String, category: String) -> TravelerSection {
        if category == "hotel" { return .stay }
        if category == "shul" { return .shul }
        if category == "chabad" { return .chabad }
        if TravelerRules.parkName.test(name) || TravelerRules.parkKind.test(kind) { return .park }
        return .todo
    }
}

// MARK: - Regex helper (JS `/…/i` semantics through NSRegularExpression)

struct TPRegex: @unchecked Sendable {
    let re: NSRegularExpression
    init(_ pattern: String, caseInsensitive: Bool = true) {
        if let r = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) {
            re = r
        } else {
            re = try! NSRegularExpression(pattern: "(?!)", options: [])
        }
    }
    func test(_ s: String) -> Bool {
        return re.firstMatch(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s)) != nil
    }
    func group(_ s: String, _ i: Int) -> String? {
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s)),
              m.numberOfRanges > i, let r = Range(m.range(at: i), in: s) else { return nil }
        return String(s[r])
    }
}

// MARK: - The website's rules, word for word

enum TravelerRules {
    static let jewish = TPRegex(#"synagog|\bshul\b|chabad|\bbeth?\b|\bbeit\b|\bbais\b|congregation|kehil|young israel|jewish|torah|yeshiv|kotel|western wall|mikv|minyan|kosher"#)
    static let notKosherName = TPRegex(#"\b(church|cathedral|chapel|basilica|abbey|monastery|convent|mosque|shrine|pagoda|cemetery|graveyard|memorial park|funeral|mortuary|nightclub|night club|strip club|adult|pub|tavern|saloon|brewery|winery|bar|casino|liquor)\b|\btemple\b(?! (beth|beit|emanu|israel|sinai|shalom|judea|tifereth|b'nai))"#)
    static let nature = TPRegex(#"\b(peak|mountain|mount|butte|mesa|rock|arch|canyon|viewpoint|overlook|point|trail|trailhead|falls|waterfall|lake|river|creek|spring|geyser|cave|park|reserve|beach|island|valley|ridge|cliff|dune|basin|natural)\b"#)
    static let stay = TPRegex(#"\b(resorts?|hotels?|inns?|lodges?|lodging|motels?|suites|cabins?|chalets?|cottages?|bungalows?|villas?|hostels?|guest ?house|guest ranch|dude ranch|b ?& ?b|bed (and|&) breakfast|camp ?grounds?|camp ?sites?|camping|caravan (site|park)|rv park|rv resort|glamping|yurts?|vacation rentals?|airbnb)\b"#)
    static let stayStrong = TPRegex(#"\b(resorts?|hotels?|motels?|hostels?|campgrounds?|rv park|rv resort|glamping|bed (and|&) breakfast|airbnb)\b"#)
    static let activity = TPRegex(#"\b(tours?|touring|adventures?|outfitters?|expeditions?|excursions?|rafting|kayak(ing)?|canoe(ing)?|paddle|jeep|atv|off ?road|safaris?|zip ?lines?|horseback|trail rides?|stables|scenic flights?|helicopter|balloon|cruises?|boat (tours?|rides?)|snorkel(ing)?|scuba|diving|ski area|ski resort|marina)\b"#)
    static let personalKind = TPRegex(#"\b(restaurant|cafe|caf\u00e9|coffee|pizza|takeout|take-out|bakery|ice cream|deli|food|grocery|supermarket|market|shop|store|mall|outlet|airport|station|subway|metro|bus|ferry terminal|car rental|gas|fuel|parking|hospital|pharmacy|clinic|school|university|office|bank|atm|town|village|region|road|street|address|neighborhood|neighbourhood|suburb)\b"#)
    static let personalName = TPRegex(#"\b(restaurant|grill|cafe|caf\u00e9|coffee|pizza|pizzeria|bakery|deli|diner|bistro|steakhouse|sushi|burger|bagels?|kitchen|eatery|supermarket|grocery|market|mall|outlet|store|shop|airport|station|gas)\b"#)
    static let photoSight = TPRegex(#"\b(arch|arches|rock|falls|point|overlook|viewpoint|vista|geyser|geysers|hot springs?|lake|canyon|butte|mesa|peak|mountain|cave|caverns?|bridge|monument|tower|lighthouse|beach|park|garden|museum|zoo|aquarium|castle|fort|dam|gorge|glacier|volcano|island|national|state park|trail|valley|basin|terraces?|preserve|reserve|sanctuary|wildlife|observatory)\b"#)
    static let photoNoise = TPRegex(#"\b(creek|river|canal|ditch|stream|brook|run|fork|branch|wash|road|street|trailhead parking|parking)\b"#)
    static let ourStay = TPRegex(#"^(my|our|the) (hotel|room|cabin|tent|camp|stay|place|house|airbnb)\b"#)
    static let srcOK = TPRegex(#"^(osm:[NWR]\d+|gp:[A-Za-z0-9_-]{6,})$"#, caseInsensitive: false)
    static let appKey = TPRegex(#"^(osm|gp):"#, caseInsensitive: false)
    static let okLinkRe = TPRegex(#"^https://[^\s/]+\.[^\s]+$"#)
    static let stateArea = TPRegex(#",\s*([A-Z]{2})\s*$"#, caseInsensitive: false)
    static let unitedStates = TPRegex(#"united states"#)
    static let townKind = TPRegex(#"^(town|city|village|hamlet|locality|municipality|borough|small town|resort town|census[- ]designated place)$"#)
    static let digit = TPRegex(#"\d"#, caseInsensitive: false)
    static let mediaPhoto = TPRegex(#"^(https:|data:image/)"#, caseInsensitive: false)
    static let httpsPhoto = TPRegex(#"^https:"#, caseInsensitive: false)
    static let parkName = TPRegex(#"\b(state park|national park|national monument|national (recreation|conservation) area|state recreation area|recreation area|national forest|state forest|national preserve|nature preserve|state natural area|state historic (park|site)|national historic(al)? (park|site)|wilderness area|national seashore|national lakeshore|state beach|state reserve|national wildlife refuge)s?\b"#)
    static let parkKind = TPRegex(#"\b(national park|state park|national monument|protected area|nature reserve|recreation area|national forest|wildlife refuge)\b"#)

    static let okCategories: Set<String> = ["todo", "hotel", "shul", "chabad"]
    /// web SIGHT_CITY_KM
    static let sightCityKm = 80.0
    /// web SIGHT_COMMISSION_NOTE
    static let commissionNote = "Some links may earn us a commission."

    /// web normPlaceName / normSightName: lower case, accents off, anything else a space, a leading "the " off.
    static func norm(_ x: String) -> String {
        let lower = x.lowercased().decomposedStringWithCanonicalMapping
        var out = String.UnicodeScalarView()
        var gap = false
        for u in lower.unicodeScalars {
            if u.value >= 0x300 && u.value <= 0x36F { continue }
            let ok = (u.value >= 97 && u.value <= 122) || (u.value >= 48 && u.value <= 57)
            if ok {
                if gap { out.append(" "); gap = false }
                out.append(u)
            } else {
                gap = true
            }
        }
        if gap { out.append(" ") }
        var s = String(out)
        if s.hasPrefix("the ") { s.removeFirst(4) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// web kindLabel: the first letter of each word in capitals.
    static func kindLabel(_ k: String) -> String {
        var out = ""
        var prevWord = false
        for ch in k {
            let isWord = ch.isASCII && (ch.isLetter || ch.isNumber || ch == "_")
            out += (isWord && !prevWord) ? ch.uppercased() : String(ch)
            prevWord = isWord
        }
        return out
    }

    /// web stayLabel
    static func stayLabel(name: String, kind: String) -> String {
        let t = "\(name) \(kind)"
        if TPRegex(#"\b(rv park|rv resort|caravan)\b"#).test(t) { return "RV park" }
        if TPRegex(#"\bglamping|yurts?\b"#).test(t) { return "Glamping" }
        if TPRegex(#"\bcamp ?(grounds?|sites?)|camping\b"#).test(t) { return "Campground" }
        if TPRegex(#"\b(cabins?|chalets?|cottages?|bungalows?)\b"#).test(t) { return "Cabins" }
        if TPRegex(#"\bresorts?\b"#).test(t) { return "Resort" }
        if TPRegex(#"\blodges?\b"#).test(t) { return "Lodge" }
        if TPRegex(#"\b(villas?|vacation rentals?|airbnb)\b"#).test(t) { return "Rental" }
        if TPRegex(#"\b(b ?& ?b|bed (and|&) breakfast|guest ?house|inns?)\b"#).test(t) { return "Inn" }
        return "Hotel"
    }

    static func okLink(_ u: Any?) -> String? {
        guard let s = u as? String, s.utf16.count <= 500, okLinkRe.test(s) else { return nil }
        return s
    }

    /// web sightAllowed
    static func sightAllowed(name: String, kind: String, category: String?, fromPhoto: Bool) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.utf16.count < 2 || n.utf16.count > 120 { return false }
        if let c = category, !c.isEmpty, !okCategories.contains(c) { return false }
        let isStay = category == "hotel" || stay.test(n) || stay.test(kind)
        if !isStay && !kind.isEmpty && personalKind.test(kind) { return false }
        if !isStay && fromPhoto && kind.isEmpty && personalName.test(n) { return false }
        if !isStay && !jewish.test(n) && notKosherName.test(n) && !(nature.test(n) || nature.test(kind)) { return false }
        if !isStay && !kind.isEmpty && notKosherName.test(kind) && !jewish.test(kind) { return false }
        return true
    }

    private static let stateCodes: [String: String] = {
        var d: [String: String] = [:]
        let raw = "alabama:AL|alaska:AK|arizona:AZ|arkansas:AR|california:CA|colorado:CO|connecticut:CT|delaware:DE|district of columbia:DC|florida:FL|georgia:GA|hawaii:HI|idaho:ID|illinois:IL|indiana:IN|iowa:IA|kansas:KS|kentucky:KY|louisiana:LA|maine:ME|maryland:MD|massachusetts:MA|michigan:MI|minnesota:MN|mississippi:MS|missouri:MO|montana:MT|nebraska:NE|nevada:NV|new hampshire:NH|new jersey:NJ|new mexico:NM|new york:NY|north carolina:NC|north dakota:ND|ohio:OH|oklahoma:OK|oregon:OR|pennsylvania:PA|rhode island:RI|south carolina:SC|south dakota:SD|tennessee:TN|texas:TX|utah:UT|vermont:VT|virginia:VA|washington:WA|west virginia:WV|wisconsin:WI|wyoming:WY"
        for pair in raw.split(separator: "|") {
            let p = pair.split(separator: ":")
            if p.count == 2 { d[String(p[0])] = String(p[1]) }
        }
        return d
    }()

    /// web stateCodeOf: "Utah" -> "UT" (a state page's name), '' when not a US state.
    static func stateCode(_ name: String) -> String {
        let n = norm(name)
        if let c = stateCodes[n] { return c }
        if n.utf16.count == 2, stateCodes.values.contains(n.uppercased()) { return n.uppercased() }
        return ""
    }

    // MARK: distances (each the website's own formula)

    /// travelerSights.ts kmBetween
    static func kmSights(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let r = Double.pi / 180, x = (c - a) * r, y = (d - b) * r
        let h = pow(sin(x / 2), 2) + cos(a * r) * cos(c * r) * pow(sin(y / 2), 2)
        return 12742 * asin(sqrt(h))
    }
    /// storyCities.ts kmBetween
    static func kmCities(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let r = Double.pi / 180
        let x = pow(sin((c - a) * r / 2), 2) + cos(a * r) * cos(c * r) * pow(sin((d - b) * r / 2), 2)
        return 6371 * 2 * atan2(sqrt(x), sqrt(1 - x))
    }

    // MARK: JS value helpers

    /// web `num`: a finite number, or a numeric string.
    static func num(_ v: Any?) -> Double {
        guard let v else { return .nan }
        if v is Bool { return .nan }
        if let i = v as? Int { return Double(i) }
        if let d = v as? Double { return d.isFinite ? d : .nan }
        if let n = v as? NSNumber { let d = n.doubleValue; return d.isFinite ? d : .nan }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return .nan }
            if let d = Double(t), d.isFinite { return d }
        }
        return .nan
    }
    static func str(_ v: Any?) -> String { (v as? String) ?? "" }
    static func slice(_ s: String, _ n: Int) -> String {
        if s.utf16.count <= n { return s }
        return String(s.utf16.prefix(n)) ?? String(s.prefix(n))
    }
    /// JS Math.round(x * 1e6) / 1e6
    static func round6(_ x: Double) -> Double { ((x * 1e6) + 0.5).rounded(.down) / 1e6 }
    /// JS Number.prototype.toFixed(2): rounded on the number's exact value, ties up (44.915 is 44.91499… so "44.91").
    static func fixed2(_ x: Double) -> String {
        guard x.isFinite else { return "NaN" }
        let exact = String(format: "%.60f", abs(x))
        let parts = exact.split(separator: ".", omittingEmptySubsequences: false)
        let whole = parts.first.map(String.init) ?? "0"
        let frac = Array(parts.count > 1 ? String(parts[1]) : "")
        func digit(_ i: Int) -> Int { i < frac.count ? Int(String(frac[i])) ?? 0 : 0 }
        var cents = digit(0) * 10 + digit(1)
        var w = Int(whole) ?? 0
        let tail = frac.count > 2 ? String(frac[2...]) : ""
        // up when the rest is half or more (exactly half goes up, like the website)
        if let first = tail.first, first >= "5" { cents += 1 }
        if cents >= 100 { cents -= 100; w += 1 }
        return (x < 0 ? "-" : "") + "\(w)." + (cents < 10 ? "0\(cents)" : "\(cents)")
    }
    /// JS encodeURIComponent
    static func encodeURIComponent(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
    static func googleUrl(_ name: String, _ id: String) -> String {
        "https://www.google.com/maps/search/?api=1&query=\(encodeURIComponent(name.isEmpty ? "place" : name))&query_place_id=\(encodeURIComponent(id))"
    }
    /// JS localeCompare order, stable.
    static func nameSorted<T>(_ list: [T], _ name: (T) -> String) -> [T] {
        let en = Locale(identifier: "en")
        return list.enumerated().sorted { a, b in
            let r = name(a.element).compare(name(b.element), options: [], range: nil, locale: en)
            if r == .orderedSame { return a.offset < b.offset }
            return r == .orderedAscending
        }.map { $0.element }
    }
}

// MARK: - App cities (storyCities.ts homeCityFor, through the Zmanim port's table)

enum TravelerCities {
    struct Home: Hashable { var cityId: String; var cityName: String; var citySub: String }

    static func byId(_ id: String?) -> ZmanimData.StoryCity? {
        guard let id, !id.isEmpty else { return nil }
        return ZmanimData.storyCities.first { $0.id == id }
    }

    /// web homeCityFor
    static func home(lat: Double, lng: Double, stop: [String: Any]?) -> Home? {
        let sid = TravelerRules.str(stop?["cityId"]), sname = TravelerRules.str(stop?["cityName"])
        let sc = byId(sid) ?? (sname.isEmpty ? nil : ZmanimPlaces.searchStoryCities(sname, limit: 1).first)
        func asCity(_ c: ZmanimData.StoryCity) -> Home { Home(cityId: c.id, cityName: c.name, citySub: c.sub) }
        if let sc, let la = sc.lat, let lo = sc.lon, TravelerRules.kmCities(la, lo, lat, lng) <= TravelerRules.sightCityKm { return asCity(sc) }
        if let near = ZmanimPlaces.nearestStoryCity(lat, lng, maxKm: TravelerRules.sightCityKm) { return asCity(near) }
        if let sc { return asCity(sc) }
        if !sid.isEmpty && !sname.isEmpty { return Home(cityId: sid, cityName: sname, citySub: TravelerRules.str(stop?["citySub"])) }
        return nil
    }
}

// MARK: - deriveTravelerSights / deriveTravelerTowns

enum TravelerDerive {
    typealias Doc = [String: Any]

    private static func arr(_ v: Any?) -> [Any] { (v as? [Any]) ?? [] }
    private static func idx(_ v: Any?) -> Int? {
        if v is Bool { return nil }
        if let i = v as? Int { return i }
        if let d = v as? Double, d == d.rounded(.down) { return Int(d) }
        if let s = v as? String, let i = Int(s) { return i }
        return nil
    }
    private static func truthy(_ v: Any?) -> Bool {
        guard let v else { return false }
        if v is NSNull { return false }
        if let b = v as? Bool { return b }
        if let s = v as? String { return !s.isEmpty }
        if let i = v as? Int { return i != 0 }
        if let d = v as? Double { return d != 0 && !d.isNaN }
        return true
    }

    /// The live posts the website reads, newest first (status live, not report-hidden, author not muted).
    static func livePosts(_ posts: [Doc], muted: Set<String>) -> [Doc] {
        let live = posts.filter { p in
            TravelerRules.str(p["status"]) == "live" && (idx(p["reportCount"]) ?? 0) < 3 && !muted.contains(TravelerRules.str(p["userId"]))
        }
        return live.enumerated().sorted { a, b in
            let x = createdMs(a.element), y = createdMs(b.element)
            if x == y { return a.offset < b.offset }
            return x > y
        }.map { $0.element }
    }

    static func createdMs(_ p: Doc) -> Double {
        let ms = TravelerRules.num(p["createdAtMs"])
        if ms.isFinite && ms != 0 { return ms }
        if let t = p["createdAt"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: t) ?? ISO8601DateFormatter().date(from: t) { return (d.timeIntervalSince1970 * 1000).rounded(.down) }
        }
        return 0
    }

    private static func media(_ post: Doc) -> [Any] { arr(post["media"]) }

    /// a photo of the place for its card (web photoOf)
    private static func photoOf(_ post: Doc, _ i: Int?) -> String {
        let list = media(post)
        let k = (i ?? -1) >= 0 ? i! : 0
        guard k < list.count, let m = list[k] as? Doc else { return "" }
        let thumb = m["thumb"]
        let u: Any? = truthy(thumb) ? thumb : (TravelerRules.str(m["type"]) != "video" ? m["url"] : "")
        guard let s = u as? String, TravelerRules.mediaPhoto.test(s) else { return "" }
        return s
    }

    private final class Row {
        var s: SharedSight
        var postSet: [String] = []
        let order: Int
        init(_ s: SharedSight, _ order: Int) { self.s = s; self.order = order }
        func addPost(_ id: String) { if !postSet.contains(id) { postSet.append(id) } }
    }

    private struct Tag {
        var name: String
        var lat: Any?
        var lng: Any?
        var src: String
        var area: String
        var kind: String
        var category: String?
        var link: Any?
        var photo: String
    }

    /// `textPlaces`: the AI server's index `places` (/api/traveler-index): map spots a post's words name (Oct 23 2026,
    /// web deriveTravelerSights textPlaces), filed as extra tagged places of that post.
    static func sights(_ posts: [Doc], muted: Set<String> = [], textPlaces: [Doc] = []) -> [SharedSight] {
        var bySrc: [String: Row] = [:]
        var order = 0
        let R = TravelerRules.self

        func add(_ post: Doc, _ p: Tag, _ stop: Doc?, _ fromPhoto: Bool) {
            let name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let lat = R.num(p.lat), lng = R.num(p.lng)
            if name.isEmpty || !lat.isFinite || !lng.isFinite || abs(lat) > 90 || abs(lng) > 180 { return }
            let src = R.srcOK.test(p.src) ? p.src : ""
            if src.isEmpty && !fromPhoto { return }
            if !R.sightAllowed(name: name, kind: p.kind, category: p.category, fromPhoto: fromPhoto) { return }
            let key = src.isEmpty ? "name:\(R.norm(name))@\(R.fixed2(lat)),\(R.fixed2(lng))" : src
            let postId = R.str(post["id"])
            if let hit = bySrc[key] {
                hit.addPost(postId)
                if hit.s.kind.isEmpty && !p.kind.isEmpty { hit.s.kind = p.kind }
                if hit.s.area.isEmpty && !p.area.isEmpty { hit.s.area = p.area }
                if hit.s.link == nil, let l = R.okLink(p.link) { hit.s.link = l }
                if hit.s.photo == nil && !p.photo.isEmpty { hit.s.photo = p.photo }
                if let c = p.category, !c.isEmpty, hit.s.category == "todo", c != "todo" { hit.s.category = c }
                return
            }
            // only a city really near it (80 km)
            let stopOrPost: Doc = stop ?? ["cityId": post["cityId"] ?? "", "cityName": post["cityName"] ?? "", "citySub": post["citySub"] ?? ""]
            let home = TravelerCities.home(lat: lat, lng: lng, stop: stopOrPost)
            var city = home
            if let h = home, let hc = TravelerCities.byId(h.cityId), let la = hc.lat, let lo = hc.lon,
               R.kmSights(la, lo, lat, lng) > R.sightCityKm { city = nil }
            var state = TravelerStateShapes.stateAt(lat, lng) ?? ""
            if state.isEmpty, let m = R.stateArea.group(p.area, 1), let c = city, R.unitedStates.test(c.citySub) { state = m }
            let category: String
            if let c = p.category, !c.isEmpty, c != "todo", R.okCategories.contains(c) { category = c }
            else { category = (R.stay.test(p.kind) || R.stayStrong.test(name) || (R.stay.test(name) && !R.nature.test(name))) ? "hotel" : "todo" }
            let rawId = src.isEmpty ? key : src
            let id: String = {
                guard let r = rawId.range(of: ":") else { return R.slice(rawId, 120) }
                return R.slice(rawId.replacingCharacters(in: r, with: "-"), 120)
            }()
            var s = SharedSight(id: id, src: rawId, name: R.slice(name, 120), area: R.slice(p.area, 160), kind: R.slice(p.kind, 40),
                                category: category, lat: R.round6(lat), lng: R.round6(lng),
                                cityId: city?.cityId ?? "", cityName: city?.cityName ?? "", citySub: city?.citySub ?? "", state: state)
            if src.hasPrefix("gp:") { s.url = R.googleUrl(name, String(src.dropFirst(3))) }
            if let l = R.okLink(p.link) { s.link = l }
            if !p.photo.isEmpty { s.photo = p.photo }
            let row = Row(s, order)
            order += 1
            row.addPost(postId)
            bySrc[key] = row
        }

        func tagged(_ post: Doc, _ plAny: Any?, _ stop: Doc?) {
            guard let pl = plAny as? Doc, let geo = pl["geo"] as? Doc, !truthy(pl["key"]) else { return }
            let plName = R.str(pl["name"])
            let n = R.norm(plName)
            let mi = media(post).firstIndex { m in
                guard let m = m as? Doc else { return false }
                return R.norm(R.str(m["placeName"])) == n
            }
            let cat = pl["category"] as? String
            add(post, Tag(name: plName, lat: geo["lat"], lng: geo["lng"], src: R.str(geo["src"]), area: R.str(geo["area"]),
                          kind: R.str(geo["kind"]), category: cat, link: pl["link"], photo: mi.map { photoOf(post, $0) } ?? ""),
                stop, false)
        }

        let list = livePosts(posts, muted: muted)
        for s in list {
            let stops = arr(s["stops"]).map { ($0 as? Doc) ?? [:] }
            for st in stops { for pl in arr(st["places"]) { tagged(s, pl, st) } }
            for dAny in arr(s["days"]) {
                guard let d = dAny as? Doc else { continue }
                var st: Doc? = nil
                if let i = idx(d["stopIdx"]), i >= 0, i < stops.count { st = stops[i] }
                if st == nil, truthy(d["cityId"]) { st = ["cityId": d["cityId"] ?? "", "cityName": d["cityName"] ?? "", "citySub": ""] }
                for pl in arr(d["places"]) { tagged(s, pl, st) }
            }
            for (i, mAny) in media(s).enumerated() {
                guard let m = mAny as? Doc, let pn = m["placeName"] as? String else { continue }
                let n = pn.trimmingCharacters(in: .whitespacesAndNewlines)
                if n.isEmpty { continue }
                let k = truthy(m["placeKey"]) ? "\(m["placeKey"]!)" : ""
                if !k.isEmpty && !R.appKey.test(k) { continue } // an app listing
                let stayOrTour = R.stay.test(n) || R.activity.test(n)
                if !k.hasPrefix("gp:") && !stayOrTour && !(R.photoSight.test(n) && !R.photoNoise.test(n)) { continue }
                if k.isEmpty && R.ourStay.test(n) { continue } // "our hotel": no name to file
                let st = stops.first { x in arr(x["mediaIdx"]).contains { idx($0) == i } }
                add(s, Tag(name: n, lat: m["lat"], lng: m["lng"], src: k, area: "", kind: "", category: nil, link: m["placeLink"],
                           photo: photoOf(s, i)), st, true)
            }
            // places the post's text names (web, Oct 23 2026): only map spots the server found by name near the post's town
            let sid = R.str(s["id"])
            for tp in textPlaces where R.str(tp["postId"]) == sid {
                let src = R.str(tp["src"])
                guard src.range(of: "^osm:[NWR][0-9]+$", options: .regularExpression) != nil else { continue }
                let cid = R.str(tp["cityId"])
                var st: Doc? = cid.isEmpty ? nil : stops.first { R.str($0["cityId"]) == cid }
                if st == nil, !cid.isEmpty {
                    st = ["cityId": cid, "cityName": R.str(tp["cityName"]), "citySub": R.str(tp["citySub"])]
                }
                let pl: Doc = [
                    "name": R.str(tp["name"]), "category": R.str(tp["category"]) == "hotel" ? "hotel" : "todo",
                    "cityName": R.str(tp["cityName"]),
                    "geo": ["lat": tp["lat"] ?? NSNull(), "lng": tp["lng"] ?? NSNull(), "src": src,
                            "area": R.str(tp["area"]), "kind": R.str(tp["kind"])] as Doc,
                ]
                tagged(s, pl, st)
            }
        }

        // the same place found twice: same name (or the longer name of the same place) within 2 km, one row
        let rows = bySrc.values.sorted { $0.order < $1.order }
        var out: [Row] = []
        for r in rows {
            let n = R.norm(r.s.name)
            let twin = out.first { o in
                let m = R.norm(o.s.name)
                return (m == n || (sameStem(m, n) && o.s.category == r.s.category)) && R.kmSights(o.s.lat, o.s.lng, r.s.lat, r.s.lng) <= 2
            }
            if let twin {
                if R.norm(r.s.name).utf16.count < R.norm(twin.s.name).utf16.count {
                    twin.s.name = r.s.name
                    if !r.s.kind.isEmpty { twin.s.kind = r.s.kind }
                }
                for p in r.postSet { twin.addPost(p) }
                if twin.s.kind.isEmpty { twin.s.kind = r.s.kind }
                if twin.s.area.isEmpty { twin.s.area = r.s.area }
                if twin.s.url == nil, let u = r.s.url { twin.s.url = u }
                if twin.s.link == nil, let l = r.s.link { twin.s.link = l }
                if twin.s.photo == nil, let ph = r.s.photo { twin.s.photo = ph }
                continue
            }
            out.append(r)
        }
        var rank: [String: Int] = [:]
        for (i, s) in list.enumerated() { let id = R.str(s["id"]); if rank[id] == nil { rank[id] = i } }
        return out.map { r in
            var s = r.s
            s.posts = r.postSet.enumerated().sorted { a, b in
                let x = rank[a.element] ?? 0, y = rank[b.element] ?? 0
                return x == y ? a.offset < b.offset : x < y
            }.map { $0.element }
            return s
        }
    }

    /// "muley point" / "muley point overlook": one name is the other plus words (two words at least in the shorter one).
    static func sameStem(_ a: String, _ b: String) -> Bool {
        let (x, y) = a.utf16.count <= b.utf16.count ? (a, b) : (b, a)
        return x.split(separator: " ", omittingEmptySubsequences: false).count >= 2 && y.hasPrefix(x + " ")
    }

    /// web deriveTravelerTowns: a real town picked on the map, inside a US state by its coordinates.
    static func towns(_ posts: [Doc], muted: Set<String> = []) -> [TravelerTown] {
        let R = TravelerRules.self
        final class TRow { var t: TravelerTown; var postSet: [String] = []; init(_ t: TravelerTown) { self.t = t } }
        var rows: [String: TRow] = [:]
        var keys: [String] = []
        let list = livePosts(posts, muted: muted)
        var rank: [String: Int] = [:]
        for (i, s) in list.enumerated() { let id = R.str(s["id"]); if rank[id] == nil { rank[id] = i } }
        func photoFor(_ post: Doc, _ name: String) -> String {
            let n = R.norm(name)
            guard let m = media(post).first(where: { m in
                guard let m = m as? Doc else { return false }
                return R.norm(R.str(m["placeName"])) == n
            }) as? Doc else { return "" }
            let thumb = m["thumb"]
            let u: Any? = truthy(thumb) ? thumb : (R.str(m["type"]) != "video" ? m["url"] : "")
            guard let s = u as? String, R.httpsPhoto.test(s) else { return "" }
            return s
        }
        func take(_ post: Doc, _ plAny: Any?) {
            guard let pl = plAny as? Doc, let g = pl["geo"] as? Doc, !truthy(pl["key"]) else { return }
            let name = R.str(pl["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let gsrc = R.str(g["src"])
            let src = R.srcOK.test(gsrc) ? gsrc : ""
            if src.isEmpty || !R.townKind.test(R.str(g["kind"]).trimmingCharacters(in: .whitespacesAndNewlines)) { return }
            if name.isEmpty || name.utf16.count > 60 || R.digit.test(name) || name.contains(",") { return }
            let lat = R.num(g["lat"]), lng = R.num(g["lng"])
            if !lat.isFinite || !lng.isFinite { return }
            let state = TravelerStateShapes.stateAt(lat, lng) ?? ""
            if state.isEmpty { return }
            let key = "\(R.norm(name))|\(state)"
            let postId = R.str(post["id"])
            if let hit = rows[key] {
                if !hit.postSet.contains(postId) { hit.postSet.append(postId) }
                if hit.t.photo == nil { let ph = photoFor(post, name); if !ph.isEmpty { hit.t.photo = ph } }
                return
            }
            let id: String = {
                guard let r = src.range(of: ":") else { return R.slice(src, 120) }
                return R.slice(src.replacingCharacters(in: r, with: "-"), 120)
            }()
            var t = TravelerTown(id: id, src: src, name: name, lat: R.round6(lat), lng: R.round6(lng), state: state)
            if src.hasPrefix("gp:") { t.url = R.googleUrl(name, String(src.dropFirst(3))) }
            let ph = photoFor(post, name)
            if !ph.isEmpty { t.photo = ph }
            let row = TRow(t)
            row.postSet.append(postId)
            rows[key] = row
            keys.append(key)
        }
        for s in list {
            for st in arr(s["stops"]) { for pl in arr((st as? Doc)?["places"]) { take(s, pl) } }
            for d in arr(s["days"]) { for pl in arr((d as? Doc)?["places"]) { take(s, pl) } }
        }
        let built: [TravelerTown] = keys.compactMap { k in
            guard let r = rows[k] else { return nil }
            var t = r.t
            t.posts = r.postSet.enumerated().sorted { a, b in
                let x = rank[a.element] ?? 0, y = rank[b.element] ?? 0
                return x == y ? a.offset < b.offset : x < y
            }.map { $0.element }
            return t
        }
        return R.nameSorted(built) { $0.name }
    }
}

// MARK: - Filters (sharedSights.ts / travelerSights.ts)

enum TravelerFilters {
    /// web sightsForCity: same city name, and the region line agrees when both are known (short forms like "Wy" pass).
    static func forCity(_ list: [SharedSight], cityName: String, region: String? = nil, category: String? = nil) -> [SharedSight] {
        let R = TravelerRules.self
        let c = R.norm(cityName), r = R.norm(region ?? "")
        return list.filter { s in
            if let category, !category.isEmpty, s.category != category { return false }
            if s.cityName.isEmpty || R.norm(s.cityName) != c { return false }
            if r.isEmpty || s.citySub.isEmpty { return true }
            let firstPart = s.citySub.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let first = R.norm(firstPart)
            return R.norm(s.citySub).contains(r) || first.utf16.count <= 3
        }
    }

    /// web dedupeSights: drops sights already listed by name (or a twin of another sight), A to Z.
    static func dedupe(_ list: [SharedSight], existingNames: [String] = []) -> [SharedSight] {
        let R = TravelerRules.self
        let have = Set(existingNames.map(R.norm).filter { !$0.isEmpty })
        var seen = Set<String>()
        let kept = list.filter { s in
            let k = R.norm(s.name)
            if k.isEmpty || have.contains(k) || seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
        return R.nameSorted(kept) { $0.name }
    }

    /// web notBuiltIn: drops places the page already lists by name, exactly or as the longer of two names.
    static func notBuiltIn<T>(_ list: [T], existingNames: [String], name: (T) -> String) -> [T] {
        let R = TravelerRules.self
        let have = existingNames.map(R.norm).filter { !$0.isEmpty }
        let set = Set(have)
        func words(_ s: String) -> Int { s.split(separator: " ", omittingEmptySubsequences: false).count }
        return list.filter { item in
            let n = R.norm(name(item))
            if n.isEmpty || set.contains(n) { return false }
            return !have.contains { h in
                (words(h) >= 2 && words(n) >= 2) && (h.hasPrefix(n + " ") || n.hasPrefix(h + " ")) && abs(h.utf16.count - n.utf16.count) <= 14
            }
        }
    }
    static func notBuiltIn(_ list: [SharedSight], existingNames: [String]) -> [SharedSight] {
        notBuiltIn(list, existingNames: existingNames) { $0.name }
    }
    static func notBuiltIn(_ list: [TravelerTown], existingNames: [String]) -> [TravelerTown] {
        notBuiltIn(list, existingNames: existingNames) { $0.name }
    }
}

// MARK: - The shared list (web fetchSharedPlaces + onSharedPlaces + useTravelerPlaces / useTravelerTowns)

@MainActor
@Observable
final class SharedSights {
    static let shared = SharedSights()

    /// Every place travelers tagged in a live post. Empty until loaded.
    private(set) var all: [SharedSight] = []
    /// Every town travelers tagged inside a US state.
    private(set) var towns: [TravelerTown] = []
    private(set) var isLoaded = false
    /// True when neither the posts nor the saved places could be read (the pages show their own places only).
    private(set) var failed = false

    /// Authors whose posts are left out (web isMutedAuthor: blocked by this person, or banned). Set it from the app's
    /// block list; the list is read again with the change.
    @ObservationIgnored var mutedAuthors: Set<String> = [] {
        didSet { if mutedAuthors != oldValue, isLoaded { Task { await self.fetch(force: true) } } }
    }

    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var kicked = false

    init() {}

    /// Loads once (like the website); `force` reads the posts again (a post was just published or pulled to refresh).
    func fetch(force: Bool = false) async {
        if let running { await running.value; if !force { return } }
        if isLoaded && !force { return }
        let muted = mutedAuthors
        let job = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { await SharedSights.load(muted: muted) }.value
            guard let self else { return }
            if let result {
                self.all = result.0
                self.towns = result.1
                self.isLoaded = true
                self.failed = false
            } else if !self.isLoaded {
                self.failed = true // try again next time
            }
        }
        running = job
        await job.value
        running = nil
    }

    /// Starts the first load without waiting (safe to call from a view's body).
    func ensureLoaded() {
        if isLoaded || kicked { return }
        kicked = true
        Task {
            await self.fetch()
            if !self.isLoaded { self.kicked = false } // try again next time
        }
    }

    // MARK: what a page shows

    /// web useTravelerPlaces({ state }) or ({ city, region }): a state's (by where they really are) or a city's, A to Z.
    func places(state: String? = nil, city: String? = nil, region: String? = nil) -> [SharedSight] {
        ensureLoaded()
        let st = state ?? "", c = city ?? ""
        let code = st.isEmpty ? "" : TravelerRules.stateCode(st)
        if code.isEmpty && c.isEmpty { return [] }
        let mine = !code.isEmpty ? all.filter { $0.state == code } : TravelerFilters.forCity(all, cityName: c, region: region)
        return TravelerFilters.dedupe(mine)
    }
    func forState(_ name: String) -> [SharedSight] { places(state: name) }
    func forCity(_ name: String, region: String? = nil) -> [SharedSight] { places(city: name, region: region) }

    /// One section of a list (web `list.filter(s => travelerSection(s) === …)`).
    func section(_ section: TravelerSection, of list: [SharedSight]) -> [SharedSight] { list.filter { $0.section == section } }

    /// web useTravelerTowns(state): towns travelers tagged inside this state.
    func townsIn(state name: String) -> [TravelerTown] {
        ensureLoaded()
        let code = TravelerRules.stateCode(name)
        if code.isEmpty { return [] }
        return towns.filter { $0.state == code }
    }

    /// The traveler's place behind a place sheet (web TravelerPlaceExtra): the sight itself, or an app place travelers
    /// tagged by the same name nearby.
    func sight(for item: PlaceItem) -> SharedSight? {
        ensureLoaded()
        if item.id.hasPrefix(SharedSight.placeIdPrefix) {
            let id = String(item.id.dropFirst(SharedSight.placeIdPrefix.count))
            if let s = all.first(where: { $0.id == id }) { return s }
            if let t = towns.first(where: { $0.id == id }) { return t.asSight(stateName: item.venue.cityName ?? "") }
        }
        let n = TravelerRules.norm(item.venue.name)
        if n.isEmpty { return nil }
        let lat = item.venue.lat ?? .nan, lng = item.venue.lng ?? .nan
        return all.first { x in
            TravelerRules.norm(x.name) == n && (!lat.isFinite || !lng.isFinite || lat == 0 || abs(x.lat - lat) + abs(x.lng - lng) < 0.6)
        }
    }

    // MARK: reading

    private nonisolated static func load(muted: Set<String>) async -> ([SharedSight], [TravelerTown])? {
        // The AI server's index (places a post's words name) is read beside the posts, with a 3-second limit.
        async let index = indexPlaces()
        if let posts = try? await readLivePosts() {
            let textPlaces = await index
            return (TravelerDerive.sights(posts, muted: muted, textPlaces: textPlaces), TravelerDerive.towns(posts, muted: muted))
        }
        // The posts could not be read: the sights saved in `places` stand in (web fetchSharedPlaces).
        if let saved = try? await PlaceFirestore.query("places", [.init(field: "status", value: "live"), .init(field: "source", value: "osm")], limit: 1000) {
            let list: [SharedSight] = saved.compactMap { row in
                let id = row.0, x = row.1
                let R = TravelerRules.self
                let s = SharedSight(id: id, src: "\(x["sourceId"] ?? "")", name: R.str(x["name"]), area: R.str(x["area"]), kind: R.str(x["kind"]),
                                    category: (x["category"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "todo",
                                    lat: R.num(x["lat"]), lng: R.num(x["lng"]),
                                    cityId: R.str(x["cityId"]), cityName: R.str(x["cityName"]), citySub: R.str(x["citySub"]))
                guard !s.name.isEmpty, s.lat.isFinite, s.lng.isFinite else { return nil }
                return withCity(s)
            }
            return (list, [])
        }
        return nil
    }

    /// `places` of https://kosher-travel-ai.sites.tab.bot/api/traveler-index (web fetchTravelerIndex), [] when slow or down.
    private nonisolated static func indexPlaces() async -> [TravelerDerive.Doc] {
        var req = URLRequest(url: URL(string: "https://kosher-travel-ai.sites.tab.bot/api/traveler-index")!, timeoutInterval: 3)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let res = try? await URLSession.shared.data(for: req), (res.1 as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let places = j["places"] as? [[String: Any]] else { return [] }
        return places
    }

    /// Sights saved before the city was stored go under the nearest app city within 80 km (web withCity).
    private nonisolated static func withCity(_ s: SharedSight) -> SharedSight {
        if !s.cityName.isEmpty { return s }
        guard let c = ZmanimPlaces.nearestStoryCity(s.lat, s.lng, maxKm: 80) else { return s }
        var x = s
        x.cityId = c.id
        x.cityName = c.name
        x.citySub = c.sub
        x.cityGuessed = true
        return x
    }

    /// The whole live posts (web sharedLiveFeed: REST runQuery, status == live, newest 300).
    nonisolated static func readLivePosts(max: Int = 300) async throws -> [[String: Any]] {
        do { return try await runQuery(max: max, ordered: true) } catch let e as TPQueryError where e.code == 400 {
            return try await runQuery(max: max, ordered: false)
        }
    }

    struct TPQueryError: Error { let code: Int }

    private nonisolated static func runQuery(max: Int, ordered: Bool) async throws -> [[String: Any]] {
        guard let url = URL(string: "\(StoryFeed.restDocs):runQuery?key=\(StoryFeed.restKey)") else { throw TPQueryError(code: 0) }
        var sq: [String: Any] = [
            "from": [["collectionId": "storyPosts"]],
            "where": ["fieldFilter": ["field": ["fieldPath": "status"], "op": "EQUAL", "value": ["stringValue": "live"]]],
            "limit": max,
        ]
        if ordered { sq["orderBy"] = [["field": ["fieldPath": "createdAt"], "direction": "DESCENDING"]] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": sq])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw TPQueryError(code: 0) }
        guard (200..<300).contains(http.statusCode) else { throw TPQueryError(code: http.statusCode) }
        let rows = (try JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let doc = row["document"] as? [String: Any], let name = doc["name"] as? String else { return nil }
            let fields: [String: Any] = (doc["fields"] as? [String: Any]) ?? [:]
            var out: [String: Any] = [:]
            for (k, x) in fields { out[k] = restValue(x) ?? NSNull() }
            out["id"] = String(name.split(separator: "/").last ?? "")
            return out
        }
    }

    private nonisolated static func restValue(_ v: Any?) -> Any? {
        guard let m = v as? [String: Any] else { return nil }
        if let s = m["stringValue"] as? String { return s }
        if let s = m["integerValue"] { return Int("\(s)") ?? 0 }
        if let d = m["doubleValue"] { return (d as? Double) ?? Double("\(d)") ?? 0 }
        if let b = m["booleanValue"] as? Bool { return b }
        if m["nullValue"] != nil { return NSNull() }
        if let t = m["timestampValue"] as? String { return t }
        if let a = m["arrayValue"] as? [String: Any] {
            return ((a["values"] as? [Any]) ?? []).map { restValue($0) ?? NSNull() }
        }
        if let mv = m["mapValue"] as? [String: Any] {
            var o: [String: Any] = [:]
            for (k, x) in (mv["fields"] as? [String: Any]) ?? [:] { o[k] = restValue(x) ?? NSNull() }
            return o
        }
        if let g = m["geoPointValue"] { return g }
        return nil
    }
}

// MARK: - The place sheet (web travelerAsPlace)

extension SharedSight {
    static let placeIdPrefix = "sight:"

    /// The sight in the shape the app's place sheet reads (name, photo, address, location, directions).
    func asPlaceItem(destId: String = "", cityName city: String = "") -> PlaceItem {
        let kl = TravelerRules.kindLabel(kind)
        let venue = Venue(name: name, address: area, phone: "", website: "",
                          description: [kl, area].filter { !$0.isEmpty }.joined(separator: " · "),
                          photo: photo ?? "", kashrus: "", kind: kl,
                          photos: photo.map { [$0] }, directions: mapURL?.absoluteString, tags: [],
                          lat: lat, lng: lng, cityName: cityName)
        let section: PlaceCategory
        switch category {
        case "hotel": section = .hotel
        case "shul": section = .shul
        case "chabad": section = .chabad
        default: section = .todo
        }
        return PlaceItem(id: SharedSight.placeIdPrefix + id, category: section, venue: venue, destId: destId,
                         cityName: city.isEmpty ? cityName : city)
    }
}

extension TravelerTown {
    /// web townAsPlace
    func asPlaceItem(stateName: String, destId: String = "") -> PlaceItem {
        asSight(stateName: stateName).asPlaceItem(destId: destId, cityName: name)
    }
}
