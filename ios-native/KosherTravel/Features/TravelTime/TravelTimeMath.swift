// Port of the website's src/lib/travelTime.ts maths and "where places are" (Cheskel, Oct 22 2026).
// Times are approximate and labelled "~":
//   flight = great-circle km / 800 km/h + 40 min (taxi, climb, landing), nearest 5 min; none under 300 km.
//   drive (only when both ends are in the US) = great-circle km x road factor (1.2 short, 1.15 long) / average speed
//   (45 km/h under 50 km, 75 under 150, 95 under 500, else 108); none over 40h.
import Foundation

struct TravelTimes: Equatable {
    var flight: String?
    var drive: String?
    var isEmpty: Bool { flight == nil && drive == nil }
}

struct TTPoint: Equatable {
    var lat: Double
    var lng: Double
    var us: Bool
}

enum TTMath {
    /// JavaScript's Math.round (halves go up, also for negative numbers).
    static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    /// Same as the website's round(n, d).
    static func round(_ n: Double, _ d: Int = 2) -> Double {
        let p = pow(10.0, Double(d))
        return jsRound(n * p) / p
    }

    /// Rough "is this point in the 50 states" test (contiguous US, Alaska, Hawaii).
    static func inUS(_ lat: Double, _ lng: Double) -> Bool {
        if lat >= 24.3 && lat <= 49.0 && lng >= -125 && lng <= -66.8 {
            if lng > -82.4 && lng < -79.5 && lat > 42.5 { return false }   // SW Ontario
            if lng >= -79.5 && lng < -76.4 && lat > 43.6 { return false }  // Toronto, Kingston
            if lng >= -76.4 && lng < -71 && lat > 45.02 { return false }   // Ottawa, Montreal, Quebec City
            if lng > -67.8 && lat > 45.6 { return false }                   // New Brunswick
            if lng > -123.8 && lng < -123.25 && lat > 48.3 { return false } // Victoria BC
            return true
        }
        if lat >= 51 && lat <= 71.5 && lng >= -170 && lng <= -129.9 { return true } // Alaska
        if lat >= 18.8 && lat <= 22.4 && lng >= -160.6 && lng <= -154.7 { return true } // Hawaii
        return false
    }

    static func isHawaii(_ lat: Double, _ lng: Double) -> Bool { lat < 23 && lng < -154 }

    static func km(_ aLat: Double, _ aLng: Double, _ bLat: Double, _ bLng: Double) -> Double {
        let r = 6371.0, toR = Double.pi / 180
        let dLat = (bLat - aLat) * toR, dLng = (bLng - aLng) * toR
        let s = pow(sin(dLat / 2), 2) + cos(aLat * toR) * cos(bLat * toR) * pow(sin(dLng / 2), 2)
        return 2 * r * asin(min(1, s.squareRoot()))
    }

    static func fmt(_ minutes: Double, _ step: Int) -> String {
        let m = max(step, Int(jsRound(minutes / Double(step))) * step)
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r)m" }
        return r != 0 ? "\(h)h \(r)m" : "\(h)h"
    }

    /// Approximate flight / drive time from the origin to a point. `placeUS` says the place is in the United States.
    static func times(from o: TravelOriginValue?, toLat lat: Double, lng: Double, placeUS: Bool) -> TravelTimes {
        guard let o, lat.isFinite, lng.isFinite else { return TravelTimes() }
        let d = km(o.lat, o.lng, lat, lng)
        var t = TravelTimes()
        if d >= 300 { t.flight = fmt(d / 800 * 60 + 40, 5) }
        let bothUS = o.us && placeUS && inUS(lat, lng)
        let islands = (isHawaii(o.lat, o.lng) || isHawaii(lat, lng)) && d > 60
        if bothUS && !islands {
            let road = d * (d < 300 ? 1.2 : 1.15)
            let speed: Double = d < 50 ? 45 : d < 150 ? 75 : d < 500 ? 95 : 108
            let mins = road / speed * 60 + (d < 150 ? 10 : 0)
            if mins <= 40 * 60 { t.drive = mins < 60 ? fmt(mins, 5) : mins < 180 ? fmt(mins, 15) : fmt(mins, 60) }
        }
        return t
    }

    // MARK: states

    static let abbr: [(String, String)] = [
        ("al", "alabama"), ("ak", "alaska"), ("az", "arizona"), ("ar", "arkansas"), ("ca", "california"), ("co", "colorado"),
        ("ct", "connecticut"), ("de", "delaware"), ("fl", "florida"), ("ga", "georgia"), ("hi", "hawaii"), ("id", "idaho"),
        ("il", "illinois"), ("in", "indiana"), ("ia", "iowa"), ("ks", "kansas"), ("ky", "kentucky"), ("la", "louisiana"),
        ("me", "maine"), ("md", "maryland"), ("ma", "massachusetts"), ("mi", "michigan"), ("mn", "minnesota"),
        ("ms", "mississippi"), ("mo", "missouri"), ("mt", "montana"), ("ne", "nebraska"), ("nv", "nevada"),
        ("nh", "new hampshire"), ("nj", "new jersey"), ("nm", "new mexico"), ("ny", "new york"), ("nc", "north carolina"),
        ("nd", "north dakota"), ("oh", "ohio"), ("ok", "oklahoma"), ("or", "oregon"), ("pa", "pennsylvania"),
        ("ri", "rhode island"), ("sc", "south carolina"), ("sd", "south dakota"), ("tn", "tennessee"), ("tx", "texas"),
        ("ut", "utah"), ("vt", "vermont"), ("va", "virginia"), ("wa", "washington"), ("wv", "west virginia"),
        ("wi", "wisconsin"), ("wy", "wyoming"), ("dc", "district of columbia"),
    ]
    private static let abbrMap: [String: String] = Dictionary(abbr.map { ($0.0, $0.1) }, uniquingKeysWith: { a, _ in a })

    static func trimLower(_ s: String?) -> String { (s ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }

    static func fullState(_ s: String?) -> String {
        let k = trimLower(s)
        return abbrMap[k] ?? k
    }

    /// "New York" -> "NY"; unknown names come back as given.
    static func stateAbbr(_ s: String?) -> String {
        let f = fullState(s)
        if let e = abbr.first(where: { $0.1 == f }) { return e.0.uppercased() }
        return s ?? ""
    }
}

/// Where places are, from the app's own data (the same numbers the website uses).
enum TTGeo {
    private static let coordsByKey: [String: (Double, Double)] = {
        var m: [String: (Double, Double)] = [:]
        for (k, a, b) in TTData.placeCoordsList where m[k] == nil { m[k] = (a, b) }
        return m
    }()

    static func usCity(_ name: String, state: String?, cities: [CityInfo]) -> (lat: Double, lng: Double)? {
        let n = TTMath.trimLower(name), st = TTMath.fullState(state)
        guard let c = cities.first(where: { TTMath.trimLower($0.name) == n && (st.isEmpty || TTMath.fullState($0.state) == st) }),
              c.lat.isFinite else { return nil }
        return (c.lat, c.lng)
    }

    /// A US state is placed at its main city (the first of the first two cities the app lists that it knows), else its centre.
    static func stateCoords(_ stateName: String, states: [USState], cities: [CityInfo]) -> (lat: Double, lng: Double)? {
        let want = stateName.lowercased()
        guard let s = states.first(where: { $0.name.lowercased() == want }) else { return nil }
        for c in s.cities.prefix(2) {
            if let p = usCity(c, state: s.name, cities: cities) { return p }
        }
        return s.lat.isFinite ? (s.lat, s.lng) : nil
    }

    /// Where a destination (city / area) is. Nil when unknown (then no chip shows).
    static func placeCoords(name: String, country: String?, state: String?, states: [USState], cities: [CityInfo]) -> TTPoint? {
        let ctry = TTMath.trimLower(country)
        let us = ctry == "united states" || ctry == "usa" || ctry == "us"
        if us {
            if let p = usCity(name, state: state, cities: cities) ?? usCity(name, state: nil, cities: cities) {
                return TTPoint(lat: p.lat, lng: p.lng, us: true)
            }
        }
        let n = TTMath.trimLower(name)
        var hit: (Double, Double)?
        if us {
            hit = coordsByKey["\(n)|united states|\(TTMath.fullState(state))"]
            if hit == nil, let e = TTData.placeCoordsList.first(where: { $0.0.hasPrefix(n + "|united states|") }) { hit = (e.1, e.2) }
        } else {
            hit = coordsByKey["\(n)|\(ctry)"]
        }
        if let hit { return TTPoint(lat: hit.0, lng: hit.1, us: us) }
        if us, let state, !state.isEmpty, let s = stateCoords(TTMath.fullState(state), states: states, cities: cities) {
            return TTPoint(lat: s.lat, lng: s.lng, us: true)
        }
        if let cc = TTData.countryCoords[ctry] { return TTPoint(lat: cc.0, lng: cc.1, us: us) }
        return nil
    }

    static func nearestUSCityLabel(_ lat: Double, _ lng: Double, cities: [CityInfo]) -> String {
        var best: CityInfo?
        var bd = Double.infinity
        for c in cities where c.lat.isFinite {
            let d = TTMath.km(lat, lng, c.lat, c.lng)
            if d < bd { bd = d; best = c }
        }
        if let best, bd < 80 { return "\(best.name), \(TTMath.stateAbbr(best.state))" }
        return "your location"
    }

    struct Hit: Identifiable, Equatable {
        let id: String
        let label: String
        let sub: String
        let lat: Double
        let lng: Double
        let us: Bool
    }

    /// The "Or pick your home city" search: US cities first, then the destinations, at most 8, unique labels.
    static func search(_ q: String, states: [USState], cities: [CityInfo]) -> [Hit] {
        let s = TTMath.trimLower(q)
        if s.count < 2 { return [] }
        var out: [Hit] = []
        var seen = Set<String>()
        func add(_ h: Hit) {
            let k = h.label.lowercased()
            if seen.contains(k) { return }
            seen.insert(k)
            out.append(h)
        }
        func starts(_ name: String) -> Bool {
            let l = name.lowercased()
            return l.hasPrefix(s) || l.contains(" " + s)
        }
        for c in cities {
            if out.count >= 8 { break }
            if !c.name.isEmpty && c.lat.isFinite && starts(c.name) {
                add(Hit(id: "us:" + c.id, label: "\(c.name), \(TTMath.stateAbbr(c.state))", sub: c.state, lat: c.lat, lng: c.lng, us: true))
            }
        }
        for d in TTData.searchDests {
            if out.count >= 8 { break }
            if d.name.isEmpty || !starts(d.name) { continue }
            guard let p = placeCoords(name: d.name, country: d.country, state: d.state, states: states, cities: cities) else { continue }
            let us = d.country == "United States"
            add(Hit(id: "d:" + d.id, label: us ? "\(d.name), \(TTMath.stateAbbr(d.state))" : "\(d.name), \(d.country)",
                    sub: us ? d.state : d.country, lat: p.lat, lng: p.lng, us: p.us))
        }
        return out
    }
}
