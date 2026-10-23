// Where the Zmanim card computes for, ported from the website's ZmanimCard.tsx (resolveZmanimPlace, tzNear,
// searchPlaces, lev) and storyCities.ts (searchStoryCities, nearestStoryCity).
import Foundation

/// The page's place, as the website passes it: `place={{ id, name, state }}` on a city page, `place={{ state }}` on a
/// state page. Empty strings count as missing. Explicit coordinates (lat/lng/tz) win when given.
struct ZmanimPlace: Equatable, Hashable {
    var id: String
    var name: String
    var state: String
    var lat: Double? = nil
    var lng: Double? = nil
    var tz: String? = nil

    init(id: String = "", name: String = "", state: String = "", lat: Double? = nil, lng: Double? = nil, tz: String? = nil) {
        self.id = id; self.name = name; self.state = state; self.lat = lat; self.lng = lng; self.tz = tz
    }
}

/// A resolved place: coordinates, time zone and the label shown on the card.
struct ZmanimWhere: Equatable {
    let lat: Double
    let lng: Double
    let tz: String
    let label: String
}

/// The traveler's own zmanim location (prefs.ts ZmanimSavedPlace).
struct ZmanimSavedPlace: Equatable {
    var name: String
    var lat: Double
    var lng: Double
    var tz: String
    var at: Double = 0
    var gps: Bool = false
}

enum ZmanimPlaces {
    static func slug(_ s: String) -> String {
        let folded = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let noPunct = folded.replacingOccurrences(of: "['’.]", with: "", options: .regularExpression)
        let dashed = noPunct.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return dashed.replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
    }
    static var guessTz: String { TimeZone.current.identifier.isEmpty ? "America/New_York" : TimeZone.current.identifier }

    /// resolveZmanimPlace: explicit coordinates, the app's city id, the city name, or a state's main city.
    static func resolve(_ p: ZmanimPlace) -> ZmanimWhere? {
        let label = [p.name, p.state].filter { !$0.isEmpty }.joined(separator: ", ")
        if let lat = p.lat, let lng = p.lng, lat.isFinite, lng.isFinite {
            return ZmanimWhere(lat: lat, lng: lng, tz: (p.tz?.isEmpty == false ? p.tz! : guessTz), label: label.isEmpty ? "this place" : label)
        }
        var keys: [String] = []
        if !p.id.isEmpty { keys.append(p.id) }
        if !p.name.isEmpty { keys.append(slug(p.name)) }
        if !p.name.isEmpty && !p.state.isEmpty { keys.append("\(slug(p.state))-\(slug(p.name))") }
        for k in keys where !k.isEmpty {
            if let g = ZmanimData.cityGeo[k] {
                return ZmanimWhere(lat: g.lat, lng: g.lng, tz: g.tz, label: !label.isEmpty ? label : (!p.name.isEmpty ? p.name : k))
            }
        }
        if p.name.isEmpty, !p.state.isEmpty, let s = ZmanimData.stateMain[p.state] {
            return ZmanimWhere(lat: s.lat, lng: s.lng, tz: s.tz, label: "\(s.city), \(p.state)")
        }
        if !p.state.isEmpty, !p.name.isEmpty, let s = ZmanimData.stateMain[p.state], slug(s.city) == slug(p.name) {
            return ZmanimWhere(lat: s.lat, lng: s.lng, tz: s.tz, label: label)
        }
        return nil
    }

    static func km(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        let R = 6371.0, r = Double.pi / 180
        let s1 = sin((c - a) * r / 2), s2 = sin((d - b) * r / 2)
        let x = s1 * s1 + cos(a * r) * cos(c * r) * s2 * s2
        return 2 * R * asin(sqrt(x))
    }
    /// Time zone for a point: the nearest city we know within 250 km, else the phone's own zone.
    static func tzNear(_ lat: Double, _ lng: Double, fallback: String? = nil) -> String {
        var best = "", bd = Double.infinity
        for (_, g) in ZmanimData.cityGeoOrdered {
            let d = km(lat, lng, g.lat, g.lng)
            if d < bd { bd = d; best = g.tz }
        }
        return bd <= 250 ? best : (fallback ?? guessTz)
    }

    // MARK: storyCities.ts

    static func norm(_ s: String) -> String {
        let folded = s.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let spaced = folded.replacingOccurrences(of: "[^a-z0-9 ]+", with: " ", options: .regularExpression)
        return spaced.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    private static let alias: [String: String] = [
        "boro park": "Brooklyn", "borough park": "Brooklyn", "williamsburg": "Brooklyn", "flatbush": "Brooklyn", "crown heights": "Brooklyn",
        "los cabos": "Cabo San Lucas", "cabo": "Cabo San Lucas", "surfside": "Miami", "miami beach": "Miami", "nyc": "New York City", "disney": "Orlando",
    ]
    static func searchStoryCities(_ q: String, limit: Int = 8) -> [ZmanimData.StoryCity] {
        let n = norm(q)
        if n.isEmpty { return [] }
        var out: [ZmanimData.StoryCity] = []
        if let a = alias[n], let c = ZmanimData.storyCities.first(where: { $0.name == a }) { out.append(c) }
        let words = n.components(separatedBy: " ")
        var starts: [ZmanimData.StoryCity] = [], rest: [ZmanimData.StoryCity] = []
        for c in ZmanimData.storyCities {
            if out.contains(where: { $0.id == c.id && $0.name == c.name }) { continue }
            let hay = norm(c.name + " " + c.sub)
            if !words.allSatisfy({ hay.contains($0) }) { continue }
            if norm(c.name).hasPrefix(n) { starts.append(c) } else { rest.append(c) }
        }
        return Array((out + starts + rest).prefix(limit))
    }
    static func nearestStoryCity(_ lat: Double, _ lon: Double, maxKm: Double = 150) -> ZmanimData.StoryCity? {
        var best: ZmanimData.StoryCity? = nil
        var bd = Double.infinity
        for c in ZmanimData.storyCities {
            guard let clat = c.lat, let clon = c.lon else { continue }
            let dLat = (clat - lat) * Double.pi / 180, dLon = (clon - lon) * Double.pi / 180
            let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat * Double.pi / 180) * cos(clat * Double.pi / 180) * sin(dLon / 2) * sin(dLon / 2)
            let k = 6371 * 2 * atan2(sqrt(a), sqrt(1 - a))
            if k < bd { bd = k; best = c }
        }
        return bd <= maxKm ? best : nil
    }

    // MARK: location search (searchPlaces)

    struct Hit: Identifiable, Equatable { let key: String; let name: String; let sub: String; let lat: Double; let lng: Double; let tz: String; var id: String { key } }

    static func short(_ sub: String) -> String {
        sub.hasSuffix(", United States") ? String(sub.dropLast(", United States".count)) : sub
    }

    static func search(_ q: String) -> [Hit] {
        let t = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return [] }
        var out: [Hit] = []
        for (st, s) in ZmanimData.stateMainOrdered {
            let l = st.lowercased()
            if l.hasPrefix(t) || (t.count >= 4 && l.contains(t)) {
                out.append(Hit(key: "st:" + st, name: st, sub: "Times for \(s.city)", lat: s.lat, lng: s.lng, tz: s.tz))
            }
        }
        for c in searchStoryCities(q, limit: 10) {
            guard let lat = c.lat, let lon = c.lon else { continue }
            let tz = ZmanimData.cityGeo[c.id]?.tz ?? tzNear(lat, lon)
            out.append(Hit(key: c.id, name: c.name, sub: short(c.sub), lat: lat, lng: lon, tz: tz))
        }
        // Tolerant: "Sedna" still finds Sedona (a typo or two in the first letters of the name).
        if out.count < 4 && t.count >= 3 {
            let seen = Set(out.map(\.key))
            let maxD = t.count >= 6 ? 2 : 1
            var scored: [(Int, Hit)] = []
            let tc = Array(t)
            for c in ZmanimData.storyCities {
                guard let lat = c.lat, let lon = c.lon, !seen.contains(c.id) else { continue }
                let n = Array(c.name.lowercased())
                let d = min(lev(tc, Array(n.prefix(tc.count))), lev(tc, Array(n.prefix(tc.count + 1))), lev(tc, n))
                if d <= maxD {
                    let tz = ZmanimData.cityGeo[c.id]?.tz ?? tzNear(lat, lon)
                    scored.append((d, Hit(key: c.id, name: c.name, sub: short(c.sub), lat: lat, lng: lon, tz: tz)))
                }
            }
            // A stable sort, like the website's Array.sort.
            let sorted = scored.enumerated().sorted { $0.element.0 != $1.element.0 ? $0.element.0 < $1.element.0 : $0.offset < $1.offset }
            for (_, h) in sorted.prefix(6).map(\.element) { out.append(h) }
        }
        return Array(out.prefix(10))
    }

    static func lev(_ a: [Character], _ b: [Character]) -> Int {
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var prev = Array(0...n)
        for i in 1...m {
            var cur = [i] + Array(repeating: 0, count: n)
            for j in 1...n {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[n]
    }
}
