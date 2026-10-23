import SwiftUI
import UIKit
import FirebaseFirestore

// Work actions under AI Planner answers (Cheskel, Oct 23: "the AI chat should get upgrades with work capabilities").
// Make PDF, Maps (every place, one by one or all together), Share, Copy and Add to Calendar. Native app only:
// the chat server hears `client: "ios-native"` and tells the model these buttons exist; the website is unchanged.

/// One place an answer names. From the server: only app-listed places (name, address and phone come from the app data).
/// From the text: a bold place name the server did not list (searched by name and the trip's city, never an invented address).
struct PlannerMapPlace: Codable, Hashable, Identifiable {
    var name: String
    var kind: String
    var city: String
    var area: String
    var address: String?
    var phone: String?

    var id: String { name.lowercased() }

    init(name: String, kind: String, city: String, area: String, address: String? = nil, phone: String? = nil) {
        self.name = name
        self.kind = kind
        self.city = city
        self.area = area
        self.address = address
        self.phone = phone
    }

    init?(json: [String: Any]) {
        guard let n = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), n.count >= 2 else { return nil }
        name = String(n.prefix(120))
        kind = (json["kind"] as? String) ?? "place"
        city = (json["city"] as? String) ?? ""
        area = (json["area"] as? String) ?? ""
        let a = (json["address"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        address = a.isEmpty ? nil : a
        let p = (json["phone"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        phone = p.isEmpty ? nil : p
    }

    /// What Maps searches for: the name with its address, else the name with its city and state.
    var query: String {
        if let address, !address.isEmpty { return "\(name), \(address)" }
        let areaFirst = area.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return [name, city, areaFirst].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var kindLabel: String {
        switch kind {
        case "restaurant": return "Restaurant"
        case "hotel": return "Hotel"
        case "shul": return "Shul"
        case "chabad": return "Chabad"
        case "mikvah": return "Mikvah"
        case "grocery": return "Grocery"
        case "catering": return "Catering"
        case "sight": return "Things to do"
        case "rental": return "Rental"
        default: return "Place"
        }
    }

    var subtitle: String {
        if let address, !address.isEmpty { return "\(kindLabel) · \(address)" }
        let where_ = [city, area.components(separatedBy: ",").first ?? ""]
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return ([kindLabel] + [where_.joined(separator: ", ")]).filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var googleURL: URL { PlannerMaps.google(query) }
    var appleURL: URL { PlannerMaps.apple(query) }
}

enum PlannerMaps {
    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    static func google(_ query: String) -> URL {
        URL(string: "https://www.google.com/maps/search/?api=1&query=\(encode(query))")!
    }

    static func apple(_ query: String) -> URL {
        URL(string: "https://maps.apple.com/?q=\(encode(query))")!
    }

    /// Turn-by-turn to one place.
    static func directions(_ query: String) -> URL {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(encode(query))")!
    }

    /// All stops in order as one Google Maps route (Google takes up to 9 stops between the start and the end).
    static func route(_ places: [PlannerMapPlace]) -> URL? {
        let stops = Array(places.prefix(11))
        guard stops.count >= 2, let first = stops.first, let last = stops.last else { return nil }
        var s = "https://www.google.com/maps/dir/?api=1&origin=\(encode(first.query))&destination=\(encode(last.query))"
        let middle = stops.dropFirst().dropLast().map { encode($0.query) }
        if !middle.isEmpty { s += "&waypoints=" + middle.joined(separator: "%7C") }
        return URL(string: s)
    }

    /// Maps links open the Maps app (Google Maps when it's installed), not the in-app browser.
    static func isMapsURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "maps.apple.com" || host == "maps.google.com" { return true }
        if host == "google.com" || host == "www.google.com" { return url.path.hasPrefix("/maps") }
        return false
    }

    static func open(_ url: URL) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

/// The places the server listed for each answer, kept on this phone by the answer's text (the chat documents
/// in the account stay exactly the web's shape).
enum PlannerPlaceMemory {
    private static let key = "kt.planner.places.v1"
    private static let lock = NSLock()
    private static var cache: [String: [PlannerMapPlace]]?
    private static var order: [String] = []

    private struct Entry: Codable {
        var k: String
        var p: [PlannerMapPlace]
    }

    static func hash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 36) + "-" + String(s.utf8.count)
    }

    private static func load() {
        if cache != nil { return }
        var c: [String: [PlannerMapPlace]] = [:]
        var o: [String] = []
        if let data = UserDefaults.standard.data(forKey: key),
           let entries = try? JSONDecoder().decode([Entry].self, from: data) {
            for e in entries {
                c[e.k] = e.p
                o.append(e.k)
            }
        }
        cache = c
        order = o
    }

    static func remember(_ places: [PlannerMapPlace], forAnswer text: String) {
        guard !places.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        load()
        let k = hash(text)
        if cache?[k] == nil { order.append(k) }
        cache?[k] = places
        while order.count > 150 {
            let old = order.removeFirst()
            cache?[old] = nil
        }
        let entries = order.compactMap { k in cache?[k].map { Entry(k: k, p: $0) } }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func places(forAnswer text: String) -> [PlannerMapPlace] {
        lock.lock()
        defer { lock.unlock() }
        load()
        return cache?[hash(text)] ?? []
    }
}

/// A place the app lists: its name in an answer opens the app's own place sheet (directions, phone, website,
/// photos and reviews are there); if the app can't find it, Google Maps opens instead.
enum PlannerAppPlace {
    static let host = "place.kt-app.invalid"

    static func url(_ p: PlannerMapPlace) -> URL {
        let e = PlannerMaps.encode
        return URL(string: "https://\(host)/open?city=\(e(p.city))&name=\(e(p.name))&q=\(e(p.query))") ?? p.googleURL
    }

    static func isAppLink(_ url: URL) -> Bool { url.host?.lowercased() == host }

    private static func value(_ url: URL, _ key: String) -> String {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == key })?.value ?? ""
    }

    /// The app's own listing for the link, or the Google Maps search to open instead.
    static func resolve(_ url: URL, data: ExploreData?) -> (item: PlaceItem?, maps: URL) {
        let city = value(url, "city").lowercased()
        let name = value(url, "name").lowercased()
        let q = value(url, "q")
        let maps = PlannerMaps.google(q.isEmpty ? value(url, "name") : q)
        guard let data, !name.isEmpty else { return (nil, maps) }
        var keys: [String] = []
        for c in data.cities where c.name.lowercased() == city { keys.append("us:\(c.id)") }
        for d in data.destinations where d.name.lowercased() == city { keys.append("dest:\(d.id)") }
        for k in keys {
            guard let page = CityPage.build(key: k, data: data) else { continue }
            if let item = page.allItems.first(where: { $0.venue.name.lowercased() == name }) { return (item, maps) }
        }
        return (nil, maps)
    }
}

/// One day of a plan with the places it visits, in order.
struct PlannerDayRoute: Identifiable, Hashable {
    var label: String
    var places: [PlannerMapPlace]
    var id: String { label }
}

enum PlannerActions {
    /// "Day 1", "Day 2"… with the places each day names, in the order they come (2 or more places).
    static func dayRoutes(_ content: String, places: [PlannerMapPlace]) -> [PlannerDayRoute] {
        guard places.count >= 2 else { return [] }
        let dayRE = #"^\s*(?:#{1,4}\s*|[-*]\s+)?(?:\*\*|__)?\s*(?:\p{So}\x{FE0F}?\s*)?(day\s*\d{1,2})\b"#
        var blocks: [(String, String)] = []
        for line in PlannerText.sanitize(content).components(separatedBy: "\n") {
            if let r = line.range(of: dayRE, options: [.regularExpression, .caseInsensitive]) {
                let head = String(line[r]).replacingOccurrences(of: #"[#*_\-]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                let label = head.prefix(1).uppercased() + head.dropFirst().lowercased()
                blocks.append((label.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression), line))
            } else if !blocks.isEmpty {
                blocks[blocks.count - 1].1 += "\n" + line
            }
        }
        var out: [PlannerDayRoute] = []
        for (label, text) in blocks {
            let low = text.lowercased()
            let hits = places.compactMap { p -> (Int, PlannerMapPlace)? in
                guard let r = low.range(of: p.name.lowercased()) else { return nil }
                return (low.distance(from: low.startIndex, to: r.lowerBound), p)
            }
            let ordered = hits.sorted { $0.0 < $1.0 }.map { $0.1 }
            if ordered.count >= 2 && !out.contains(where: { $0.label == label }) {
                out.append(PlannerDayRoute(label: label, places: Array(ordered.prefix(11))))
            }
        }
        return out
    }

    private static var linkedCache: [String: String] = [:]
    private static var placesCache: [String: [PlannerMapPlace]] = [:]

    /// Bold words that are labels, not places ("**Stay:**", "**Day 1**", "**Shabbos Meals**").
    private static let labelWords: [String] = [
        "shabbos", "shabbat", "meal", "day ", "stay", "tip", "note", "option", "morning", "afternoon", "evening", "night",
        "lunch", "dinner", "breakfast", "budget", "getting", "transport", "flight", "drive", "weather", "pack", "why ",
        "how ", "what ", "where ", "when ", "eat", "kosher food", "minyan", "davening", "assuming", "day-", "arrival",
        "departure", "check-in", "check in", "rest", "free time", "travel", "itinerary", "summary", "total", "cost",
    ]

    private static func regex(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }

    private static func isLabel(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.count < 3 || t.count > 60 { return true }
        if t.hasSuffix(":") || t.contains(":") { return true }
        guard let first = t.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) else { return true }
        let low = " " + t.lowercased() + " "
        if low.range(of: #"\b(mon|tues|wednes|thurs|fri|satur|sun)day\b"#, options: .regularExpression) != nil { return true }
        if low.range(of: #"\d{1,2}(:\d\d)?\s*(am|pm)\b"#, options: .regularExpression) != nil { return true }
        if low.range(of: #"\bday\s*\d"#, options: .regularExpression) != nil { return true }
        return labelWords.contains { low.contains($0) }
    }

    /// The trip's city: the chat's trip settings, else the first app place the answer names.
    static func city(_ messages: [ChatMessage], server: [PlannerMapPlace], cards: [PlannerPlace]) -> String {
        if let d = PlannerText.filters(from: messages).destination?.trimmingCharacters(in: .whitespaces), !d.isEmpty { return d }
        if let p = server.first, !p.city.isEmpty {
            let st = p.area.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
            return [p.city, st].filter { !$0.isEmpty }.joined(separator: ", ")
        }
        if let c = cards.first { return c.state.isEmpty || c.state == c.name ? c.name : "\(c.name), \(c.state)" }
        return ""
    }

    /// Bold names at the start of list lines: "- **Wynwood Walls** — street-art murals", "🍽 **Silan** — ...".
    private static func boldNames(_ content: String) -> [String] {
        guard let re = regex(#"^\s*(?:[-*•]\s+|\d+[.)]\s+|(?:\p{So}|✦|✨)\x{FE0F}?\s*)\*\*([^*\n]{2,80})\*\*"#) else { return [] }
        var out: [String] = []
        for line in PlannerText.sanitize(content).components(separatedBy: "\n") {
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let name = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !isLabel(name) { out.append(name) }
        }
        return out
    }

    /// Every place an answer names, in order: the server's app-listed places, then bold names it didn't list.
    static func places(for msg: ChatMessage, messages: [ChatMessage], cards: [PlannerPlace]) -> [PlannerMapPlace] {
        let ck = msg.id + "|" + String(msg.content.count)
        if let c = placesCache[ck] { return c }
        let server = PlannerPlaceMemory.places(forAnswer: msg.content)
        var out = server
        var seen = Set(server.map { $0.id })
        let town = city(messages, server: server, cards: cards)
        let parts = town.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for n in boldNames(msg.content) where !seen.contains(n.lowercased()) {
            seen.insert(n.lowercased())
            out.append(PlannerMapPlace(name: n, kind: "place", city: parts.first ?? "", area: parts.dropFirst().joined(separator: ", ")))
        }
        let result = Array(out.prefix(40))
        if !server.isEmpty || !cards.isEmpty { placesCache[ck] = result }
        return result
    }

    private static func esc(_ s: String) -> String { NSRegularExpression.escapedPattern(for: s) }
    private static func escLabel(_ s: String) -> String {
        s.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
    }

    /// The answer with each place name as a Maps link: "**Silan**" becomes "**[Silan](google maps)**"; an app-listed
    /// place written without bold gets a plain link at its first mention.
    static func linked(_ msg: ChatMessage, messages: [ChatMessage], cards: [PlannerPlace]) -> String {
        let list = places(for: msg, messages: messages, cards: cards)
        let ck = msg.id + "|" + String(msg.content.count) + "|" + String(list.count)
        if let c = linkedCache[ck] { return c }
        var text = mailLinks(msg.content)
        guard !list.isEmpty else {
            linkedCache[ck] = text
            return text
        }
        let sorted = list.sorted { $0.name.count > $1.name.count }
        var done = Set<String>()
        for p in sorted {
            let url = (p.kind == "place" ? p.googleURL : PlannerAppPlace.url(p)).absoluteString
            guard let re = try? NSRegularExpression(pattern: #"\*\*\s*"# + esc(p.name) + #"\s*\*\*"#, options: [.caseInsensitive]) else { continue }
            let ns = text as NSString
            let ms = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
            if ms.isEmpty { continue }
            done.insert(p.id)
            var out = ""
            var cursor = 0
            for m in ms {
                out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                let shown = ns.substring(with: m.range).replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
                out += "**[\(escLabel(shown))](\(url))**"
                cursor = m.range.location + m.range.length
            }
            out += ns.substring(from: cursor)
            text = out
        }
        // App-listed places written in plain text: link the first mention, on a line with no link yet.
        for p in sorted where p.kind != "place" && !done.contains(p.id) {
            guard let re = try? NSRegularExpression(pattern: #"(?<![\p{L}\p{N}\[*])"# + esc(p.name) + #"(?![\p{L}\p{N}\]*])"#, options: [.caseInsensitive]) else { continue }
            var lines = text.components(separatedBy: "\n")
            for i in lines.indices where !lines[i].contains("](") {
                let ns = lines[i] as NSString
                guard let m = re.firstMatch(in: lines[i], range: NSRange(location: 0, length: ns.length)) else { continue }
                let shown = ns.substring(with: m.range)
                lines[i] = ns.replacingCharacters(in: m.range, with: "[\(escLabel(shown))](\(PlannerAppPlace.url(p).absoluteString))")
                break
            }
            text = lines.joined(separator: "\n")
        }
        linkedCache[ck] = text
        return text
    }

    /// Bare email addresses become mailto links (phones and web links are already tappable).
    static func mailLinks(_ s: String) -> String {
        guard s.contains("@"), let re = try? NSRegularExpression(pattern: #"(?<![\w.\[(/:-])([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})(?![\w\]])"#) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                           withTemplate: "[$1](mailto:$1)")
    }

    /// The plan the PDF and Calendar use: this answer when it's a plan (or long), else the latest plan before it.
    static func plan(for index: Int, messages: [ChatMessage]) -> ChatMessage? {
        guard messages.indices.contains(index) else { return nil }
        let msg = messages[index]
        if PlannerText.isItinerary(msg.content) || msg.content.count > 600 { return msg }
        for m in messages[...index].reversed() where m.isAssistant && PlannerText.isItinerary(m.content) { return m }
        return msg
    }

    /// Under a plan, under an answer that names places, and under the latest answer when it's a real answer.
    static func showsBar(for msg: ChatMessage, index: Int, messages: [ChatMessage], settled: Bool, cards: [PlannerPlace]) -> Bool {
        guard msg.isAssistant, !msg.isFiltersNote else { return false }
        if PlannerText.isItinerary(msg.content) { return true }
        if !places(for: msg, messages: messages, cards: cards).isEmpty && msg.content.count > 160 { return true }
        if index > 0, messages.indices.contains(index - 1) {
            let asked = messages[index - 1].content.lowercased()
            if asked.range(of: #"\b(pdf|print|export|download|file|map|maps|link|links|location|locations|directions|calendar|save)\b"#, options: .regularExpression) != nil { return true }
        }
        return settled && msg.content.count > 280
    }

    /// Plain text for Copy / Share / Calendar notes: no markdown marks; links keep their words.
    static func plainText(_ content: String) -> String {
        var t = PlannerText.sanitize(content)
        t = t.replacingOccurrences(of: #"\[([^\]\n]+)\]\((?:https?|tel):[^)\s]+\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        t = t.replacingOccurrences(of: #"(?m)^#{1,6}\s+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^(\s*)[-*]\s+"#, with: "$1• ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Miami Beach" for titles: the trip settings' place, else the first place the plan names.
    static func title(_ messages: [ChatMessage], plan: ChatMessage, cards: [PlannerPlace]) -> String {
        if let d = PlannerText.filters(from: messages).destination?.trimmingCharacters(in: .whitespaces), !d.isEmpty { return d }
        if let p = PlannerPlaceMemory.places(forAnswer: plan.content).first, !p.city.isEmpty { return p.city }
        if let c = cards.first { return c.name }
        return ""
    }
}


// MARK: Save to My Travel and Add to Bucket List (Oct 23 2026, SHARED-TRIPS)

/// The same Firestore documents the website writes (App.tsx savePlannerTrip / addPlaceToBucket):
/// a trip at users/{uid}/trips/{id} (source "ai-planner", the chat turned into a day-by-day route by the AI server's
/// /api/trip-extract, only places the chat named), and a place card in users/{uid}/userData/preferences
/// { bucketList[], bucketItems{id: {name, city, area, category, photo, summary, link, addedAt}} }.
enum PlannerTrips {
    static let extractURL = URL(string: "https://www.yourkoshertravel.com/kt-ai/api/trip-extract")!

    /// Web normN: lowercase, no accents, words joined by single spaces.
    static func norm(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US")).lowercased()
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    static func slug(_ s: String, _ max: Int) -> String {
        String(norm(s).replacingOccurrences(of: " ", with: "-").prefix(max))
    }

    /// The bucket list id: an app destination's own id, else place:<city>:<name> (web bucketIdFor).
    static func bucketId(name: String, city: String, destId: String?) -> String {
        if let destId, !destId.isEmpty { return destId }
        return "place:\(slug(city, 30)):\(slug(name, 60))"
    }

    /// "us:illinois-chicago" / "dest:cancun" (planner cards) -> the website's destination id.
    static func destId(fromCard id: String) -> String? {
        for p in ["us:", "dest:"] where id.hasPrefix(p) { return String(id.dropFirst(p.count)) }
        return nil
    }

    private static func chat(_ messages: [ChatMessage], last: Int? = nil) -> [[String: String]] {
        var list = messages.filter { ($0.role == "user" || $0.role == "assistant") && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if let last, list.count > last { list = Array(list.suffix(last)) }
        return list.map { ["role": $0.role, "content": $0.content] }
    }

    private static func post(_ body: [String: Any], timeout: TimeInterval = 60) async -> [String: Any]? {
        var req = URLRequest(url: extractURL, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        req.httpBody = data
        guard let (d, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return j
    }

    private static var nowMs: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    /// Day blocks of a plan, as the website saves them: "Day 1 ..." headings with their lines.
    static func days(_ content: String) -> (days: [[String: Any]], headed: Bool) {
        let lines = PlannerActions.plainText(content).components(separatedBy: "\n")
        var out: [(title: String, lines: [String])] = []
        let head = try? NSRegularExpression(pattern: #"^(?:•\s*)?day\s*(\d{1,2})\b\s*[:.\-–—)]?\s*(.*)$"#, options: [.caseInsensitive])
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let ns = line as NSString
            if let m = head?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let rest = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces) : ""
                out.append((rest, []))
                continue
            }
            let clean = line.replacingOccurrences(of: #"^[•☐☑]\s*"#, with: "", options: .regularExpression)
            if !out.isEmpty, !clean.isEmpty { out[out.count - 1].lines.append(clean) }
        }
        if out.isEmpty {
            let all = lines.map { $0.replacingOccurrences(of: #"^\s*[•☐☑]\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            let one: [String: Any] = ["day": 1, "theme": "Trip plan", "activities": Array(all.prefix(40))]
            return ([one], false)
        }
        let list: [[String: Any]] = out.enumerated().map { (i, d) -> [String: Any] in
            let theme = String((d.title.isEmpty ? "Day \(i + 1)" : d.title).prefix(120))
            return ["day": i + 1, "theme": theme, "activities": Array(d.lines.prefix(30))]
        }
        return (list, true)
    }

    /// Saves the plan to My Travel and then builds its route in the background. Returns the trip id.
    @MainActor
    static func save(uid: String, messages: [ChatMessage], plan: ChatMessage, title: String) -> String {
        let id = "itinerary-ai-\(Int(nowMs))"
        let d = days(plan.content)
        let f = PlannerText.filters(from: messages)
        var trip: [String: Any] = [
            "id": id,
            "title": title.isEmpty ? "AI trip plan" : (d.headed ? "\(d.days.count) days in \(title)" : title),
            "city": title,
            "style": "AI Planner",
            "days": d.days,
            "isUpcoming": true,
            "source": "ai-planner",
            "route": ["days": [], "status": "building"],
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        if let s = f.startDate, !s.isEmpty { trip["startDate"] = s }
        guard FirebaseBoot.isConfigured else { return id }
        let ref = Firestore.firestore().collection("users").document(uid).collection("trips").document(id)
        let msgs = chat(messages)
        var hints: [String: Any] = ["messages": msgs]
        if let v = f.destination, !v.isEmpty { hints["destination"] = v } else if !title.isEmpty { hints["destination"] = title }
        if let v = f.startDate, !v.isEmpty { hints["startDate"] = v }
        if let v = f.endDate, !v.isEmpty { hints["endDate"] = v }
        Task {
            try? await ref.setData(trip, merge: true)
            await MainActor.run { WarmWebPage.myTravel.retry(uid: uid) }
            var route: [String: Any] = ["days": [], "status": "failed"]
            for attempt in 0..<2 {
                if let j = await post(hints, timeout: 90), var r = j["route"] as? [String: Any], let ds = r["days"] as? [Any], !ds.isEmpty {
                    r["status"] = "ready"
                    r["builtAt"] = nowMs
                    r.removeValue(forKey: "model")
                    route = r
                    break
                }
                if attempt == 0 { try? await Task.sleep(nanoseconds: 1_500_000_000) }
            }
            try? await ref.setData(["route": route, "updatedAt": FieldValue.serverTimestamp()], merge: true)
            await MainActor.run { if !WarmWebPage.myTravel.visible { WarmWebPage.myTravel.retry(uid: uid) } }
        }
        return id
    }

    static func inBucket(_ id: String) -> Bool { BucketList.shared.contains(id) }

    /// Adds one place to the bucket list with a neat card (name, city, area, category, summary) written from the chat.
    @MainActor
    static func addToBucket(uid: String, name: String, city: String, area: String, kind: String, destId: String?, photo: String = "",
                            messages: [ChatMessage]) async -> Bool {
        await BucketList.shared.bind(uid: uid)
        let id = bucketId(name: name, city: city, destId: destId)
        if BucketList.shared.contains(id) { return false }
        if destId == nil, FirebaseBoot.isConfigured {
            var place: [String: Any] = ["name": name]
            if !city.isEmpty { place["city"] = city }
            if !area.isEmpty { place["area"] = area }
            if !kind.isEmpty { place["kind"] = kind }
            let card = (await post(["mode": "place", "messages": chat(messages, last: 12), "place": place], timeout: 40))?["place"] as? [String: Any]
            let cardCity = (card?["city"] as? String) ?? ""
            let cardArea = (card?["area"] as? String) ?? ""
            let item: [String: Any] = [
                "name": name,
                "city": cardCity.isEmpty ? city : cardCity,
                "area": cardArea.isEmpty ? area : cardArea,
                "category": (kind.isEmpty || kind == "place") ? ((card?["category"] as? String) ?? "place") : kind,
                "photo": photo,
                "summary": (card?["summary"] as? String) ?? "",
                "link": NSNull(),
                "addedAt": nowMs,
            ]
            try? await Firestore.firestore().collection("users").document(uid).collection("userData").document("preferences")
                .setData(["bucketItems": [id: item], "updatedAt": FieldValue.serverTimestamp()], merge: true)
        }
        if !BucketList.shared.contains(id) { BucketList.shared.toggle(id) }
        WarmWebPage.myTravel.retry(uid: uid)
        return true
    }
}
