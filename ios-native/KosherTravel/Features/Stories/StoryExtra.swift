import Foundation
import FirebaseFirestore

// The parts of a `storyPosts` document the shared StoryPost model does not carry: who posted it, the like list,
// links, products, video settings, tagged places and the linked article. Parsed from the same raw document
// (same field names as the web's fromDoc in src/components/stories/storyService.ts).

/// A place tagged in an article (web TaggedPlace).
struct TaggedPlaceInfo: Hashable {
    var key: String
    var name: String
    var category: String      // restaurant | grocery | chabad | shul | hotel | todo | mikvah
    var cityName: String
    var link: String          // the poster's own link (booking / affiliate)
    var address: String
    var website: String
    var lat: Double?
    var lng: Double?
    var area: String

    var symbol: String {
        switch category {
        case "restaurant": return "fork.knife"
        case "grocery": return "cart"
        case "chabad": return "house"
        case "shul": return "building.columns"
        case "hotel": return "bed.double"
        case "mikvah": return "drop"
        default: return "binoculars"
        }
    }

    var categoryLabel: String {
        switch category {
        case "restaurant": return "Restaurant"
        case "grocery": return "Grocery"
        case "chabad": return "Chabad"
        case "shul": return "Shul"
        case "hotel": return "Hotel"
        case "mikvah": return "Mikvah"
        default: return "Things to do"
        }
    }

    /// Where a tap goes: the poster's link first, then the place's own site, then Apple Maps when it has a spot.
    var openURL: URL? {
        if let u = StoryExtra.httpsURL(link) { return u }
        if let u = StoryExtra.httpsURL(website) { return u }
        if let u = StoryExtra.googlePlaceURL(name: name, key: key) { return u }
        if let lat, let lng {
            var c = URLComponents(string: "https://maps.apple.com/")
            c?.queryItems = [URLQueryItem(name: "ll", value: "\(lat),\(lng)"), URLQueryItem(name: "q", value: name)]
            return c?.url
        }
        // no link and no spot: the map searches its name and town (the web's postPlaces() Google Maps search)
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return nil }
        let town = (area.isEmpty ? cityName : area).trimmingCharacters(in: .whitespaces)
        let q = !town.isEmpty && !n.lowercased().contains((town.split(separator: ",").first.map(String.init) ?? town).lowercased()) ? "\(n), \(town)" : n
        var c = URLComponents(string: "https://maps.apple.com/")
        c?.queryItems = [URLQueryItem(name: "q", value: q)]
        return c?.url
    }
}

/// One photo or video with the poster's settings (web StoryMediaItem).
struct StoryMediaInfo: Hashable {
    var type: String
    var url: String
    var thumb: String
    var w: Double
    var h: Double
    var muted: Bool
    var trimStart: Double?
    var trimEnd: Double?
    var placeName: String
    var placeLink: String
    var placeUrl: String
    /// a smaller copy of a video for slow connections, when the post carries one (optional; Oct 25 2026)
    var lowUrl: String = ""
    /// video only (Oct 25 2026): the frame the poster picked as the cover, in seconds of the file (web media.coverTime)
    var coverTime: Double? = nil
    var isVideo: Bool { type == "video" }
    var still: String { isVideo ? thumb : (url.isEmpty ? thumb : url) }
    var small: String { thumb.isEmpty ? (isVideo ? "" : url) : thumb }
}

struct StoryLinkInfo: Hashable {
    var url: String
    var label: String
    var date: String
    var thumb: String
    var host: String {
        guard let h = URL(string: url)?.host else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}

struct StoryProductInfo: Hashable {
    var name: String
    var url: String
    var price: String
    var img: String
}

struct StoryStopInfo: Hashable {
    var cityId: String
    var cityName: String
    var citySub: String
    var dates: String
    var text: String
    var mediaIdx: [Int]
    var places: [TaggedPlaceInfo]
}

struct StoryDayInfo: Hashable {
    var date: String
    var place: String
    var places: [TaggedPlaceInfo]
    var mediaIdx: [Int]
    var stopIdxs: [Int]
    var cityName: String
}

struct StoryExtra: Hashable {
    var id: String
    var userId: String
    var authorName: String
    var authorPhoto: String
    var likesCount: Int
    var likedUserIds: [String]
    var viewsCount: Int
    var tags: [String]
    var links: [StoryLinkInfo]
    var products: [StoryProductInfo]
    var linkedArticleId: String
    var media: [StoryMediaInfo]
    var stops: [StoryStopInfo]
    var days: [StoryDayInfo]
    var startDate: String
    var endDate: String
    var status: String

    init(id: String, data d: [String: Any]) {
        func s(_ k: String) -> String { (d[k] as? String) ?? "" }
        self.id = id
        userId = s("userId")
        authorName = s("authorName").isEmpty ? "Traveler" : s("authorName")
        authorPhoto = s("authorPhoto")
        let liked = ((d["likedUserIds"] as? [Any]) ?? []).compactMap { $0 as? String }
        likedUserIds = liked
        likesCount = Self.num(d["likesCount"]).map { Int($0) } ?? liked.count
        viewsCount = Int(Self.num(d["viewsCount"]) ?? 0)
        tags = ((d["tags"] as? [Any]) ?? []).compactMap { $0 as? String }
        linkedArticleId = s("linkedArticleId")
        startDate = s("startDate")
        endDate = s("endDate")
        status = s("status")
        links = Self.maps(d["links"]).compactMap { (m: [String: Any]) -> StoryLinkInfo? in
            let url = (m["url"] as? String) ?? ""
            guard Self.httpsURL(url) != nil else { return nil }
            let label = (m["label"] as? String) ?? ""
            return StoryLinkInfo(url: url, label: label, date: (m["date"] as? String) ?? "",
                                 thumb: (m["thumb"] as? String) ?? ((m["img"] as? String) ?? ""))
        }
        products = Self.maps(d["products"]).compactMap { (m: [String: Any]) -> StoryProductInfo? in
            let url = (m["url"] as? String) ?? ""
            let name = (m["name"] as? String) ?? ""
            guard Self.httpsURL(url) != nil, !name.isEmpty else { return nil }
            return StoryProductInfo(name: name, url: url, price: (m["price"] as? String) ?? "",
                                    img: (m["thumb"] as? String) ?? ((m["img"] as? String) ?? ""))
        }
        media = Self.maps(d["media"]).map { (m: [String: Any]) -> StoryMediaInfo in
            var info = StoryMediaInfo(type: (m["type"] as? String) == "video" ? "video" : "image",
                      url: (m["url"] as? String) ?? "",
                      thumb: (m["thumb"] as? String) ?? "",
                      w: Self.num(m["w"]) ?? 0,
                      h: Self.num(m["h"]) ?? 0,
                      muted: (m["muted"] as? Bool) ?? false,
                      trimStart: Self.num(m["trimStart"]),
                      trimEnd: Self.num(m["trimEnd"]),
                      placeName: (m["placeName"] as? String) ?? "",
                      placeLink: (m["placeLink"] as? String) ?? "",
                      placeUrl: (m["placeUrl"] as? String) ?? "")
            info.lowUrl = (m["lowUrl"] as? String) ?? ""
            info.coverTime = Self.num(m["coverTime"])
            return info
        }
        stops = Self.maps(d["stops"]).map { (m: [String: Any]) -> StoryStopInfo in
            StoryStopInfo(cityId: (m["cityId"] as? String) ?? "",
                     cityName: (m["cityName"] as? String) ?? "",
                     citySub: (m["citySub"] as? String) ?? "",
                     dates: (m["dates"] as? String) ?? "",
                     text: (m["text"] as? String) ?? "",
                     mediaIdx: Self.ints(m["mediaIdx"]),
                     places: Self.places(m["places"]))
        }
        days = Self.maps(d["days"]).map { (m: [String: Any]) -> StoryDayInfo in
            var idxs = Self.ints(m["stopIdxs"])
            if idxs.isEmpty { idxs = [Int(Self.num(m["stopIdx"]) ?? 0)] }
            return StoryDayInfo(date: (m["date"] as? String) ?? "",
                           place: (m["place"] as? String) ?? "",
                           places: Self.places(m["places"]),
                           mediaIdx: Self.ints(m["mediaIdx"]),
                           stopIdxs: idxs,
                           cityName: (m["cityName"] as? String) ?? "")
        }
    }

    // MARK: helpers

    var isFullArticle: Bool { !days.isEmpty || !stops.isEmpty }

    func media(at i: Int) -> StoryMediaInfo? { (i >= 0 && i < media.count) ? media[i] : nil }

    /// "Jan 18 – 21, 2024" from the trip's start and end dates.
    var dateRange: String {
        guard let a = Self.ymd(startDate) else { return "" }
        let b = Self.ymd(endDate) ?? a
        let cal = Calendar(identifier: .gregorian)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        if cal.isDate(a, inSameDayAs: b) { f.dateFormat = "MMM d, yyyy"; return f.string(from: a) }
        let sameYear = cal.component(.year, from: a) == cal.component(.year, from: b)
        let sameMonth = sameYear && cal.component(.month, from: a) == cal.component(.month, from: b)
        f.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        let left = f.string(from: a)
        f.dateFormat = sameMonth ? "d, yyyy" : "MMM d, yyyy"
        return "\(left) – \(f.string(from: b))"
    }

    /// Links whose date is this day (articles); the rest show with the trip.
    func links(on date: String) -> [StoryLinkInfo] { links.filter { !date.isEmpty && $0.date == date } }
    var tripLinks: [StoryLinkInfo] {
        let dayDates = Set(days.map(\.date))
        return links.filter { $0.date.isEmpty || !dayDates.contains($0.date) }
    }

    static func ymd(_ s: String) -> Date? {
        guard s.count >= 10 else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    /// "Thursday, Jan 18"
    static func dayLabel(_ s: String) -> String {
        guard let d = ymd(s) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: d)
    }

    /// A place picked from Google (key "gp:<place id>") opens its Google page (web placeLinkOf / googlePlaceUrl).
    static func googlePlaceURL(name: String, key: String) -> URL? {
        guard key.hasPrefix("gp:"), key.count > 3 else { return nil }
        var c = URLComponents(string: "https://www.google.com/maps/search/")
        c?.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: name),
                         URLQueryItem(name: "query_place_id", value: String(key.dropFirst(3)))]
        return c?.url
    }

    static func httpsURL(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasPrefix("https://"), let u = URL(string: t), u.host != nil else { return nil }
        return u
    }

    static func num(_ v: Any?) -> Double? {
        if let x = v as? Double { return x }
        if let x = v as? Int { return Double(x) }
        if let x = v as? Int64 { return Double(x) }
        if let x = v as? NSNumber { return x.doubleValue }
        if let x = v as? String { return Double(x) }
        return nil
    }

    static func ints(_ v: Any?) -> [Int] {
        ((v as? [Any]) ?? []).compactMap { num($0).map { Int($0) } }
    }

    static func maps(_ v: Any?) -> [[String: Any]] {
        ((v as? [Any]) ?? []).compactMap { $0 as? [String: Any] }
    }

    static func places(_ v: Any?) -> [TaggedPlaceInfo] {
        maps(v).compactMap { (m: [String: Any]) -> TaggedPlaceInfo? in
            let name = (m["name"] as? String) ?? ""
            guard !name.isEmpty else { return nil }
            let custom = (m["custom"] as? [String: Any]) ?? [:]
            let geo = (m["geo"] as? [String: Any]) ?? [:]
            return TaggedPlaceInfo(key: (m["key"] as? String) ?? "",
                                   name: name,
                                   category: (m["category"] as? String) ?? "todo",
                                   cityName: (m["cityName"] as? String) ?? "",
                                   link: (m["link"] as? String) ?? "",
                                   address: (custom["address"] as? String) ?? "",
                                   website: (custom["website"] as? String) ?? "",
                                   lat: num(geo["lat"]),
                                   lng: num(geo["lng"]),
                                   area: (geo["area"] as? String) ?? "")
        }
    }
}

// MARK: - reading raw story documents (Firebase SDK first, the public REST endpoint as the fallback)

enum StoryDocs {
    typealias Raw = (id: String, data: [String: Any])

    static let restDocs = "https://firestore.googleapis.com/v1/projects/kosher-travel-app/databases/(default)/documents"
    static let restKey = "AIzaSyAqIbbxAIfqwuTaE31czStjZXDKJMynkEs"

    /// Live posts (status == live), newest first is done by the caller.
    static func live(limit: Int = 300) async throws -> [Raw] {
        if FirebaseBoot.isConfigured {
            do {
                let base = Firestore.firestore().collection("storyPosts").whereField("status", isEqualTo: "live")
                let snap = try await base.limit(to: limit).getDocuments()
                return snap.documents.map { (id: $0.documentID, data: $0.data()) }
            } catch {
                print("[KT] stories sdk read failed: \(error)")
            }
        }
        return try await restQuery(filters: [("status", "live")], limit: limit)
    }

    /// A traveler's live posts.
    static func byAuthor(_ uid: String) async throws -> [Raw] {
        if FirebaseBoot.isConfigured {
            do {
                let snap = try await Firestore.firestore().collection("storyPosts")
                    .whereField("userId", isEqualTo: uid)
                    .whereField("status", isEqualTo: "live")
                    .limit(to: 200).getDocuments()
                return snap.documents.map { (id: $0.documentID, data: $0.data()) }
            } catch {
                print("[KT] author sdk read failed: \(error)")
            }
        }
        return try await restQuery(filters: [("userId", uid), ("status", "live")], limit: 200)
    }

    /// One post by id (nil when it is gone or not readable).
    static func one(_ id: String) async -> Raw? {
        if FirebaseBoot.isConfigured {
            if let snap = try? await Firestore.firestore().collection("storyPosts").document(id).getDocument(),
               let data = snap.data() {
                return (id: id, data: data)
            }
        }
        guard let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(restDocs)/storyPosts/\(enc)?key=\(restKey)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue(Bundle.main.bundleIdentifier ?? "com.yourkoshertravel.app", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        req.timeoutInterval = 15
        guard let pair = try? await URLSession.shared.data(for: req),
              let http = pair.1 as? HTTPURLResponse, http.statusCode == 200,
              let doc = (try? JSONSerialization.jsonObject(with: pair.0)) as? [String: Any] else { return nil }
        return (id: id, data: restFields((doc["fields"] as? [String: Any]) ?? [:]))
    }

    private static func restQuery(filters: [(String, String)], limit: Int) async throws -> [Raw] {
        guard let url = URL(string: "\(restDocs):runQuery?key=\(restKey)") else { return [] }
        let ff: [[String: Any]] = filters.map { (f: (String, String)) -> [String: Any] in
            let inner: [String: Any] = ["field": ["fieldPath": f.0], "op": "EQUAL", "value": ["stringValue": f.1]]
            return ["fieldFilter": inner]
        }
        let composite: [String: Any] = ["op": "AND", "filters": ff]
        let whereClause: [String: Any] = ff.count == 1 ? ff[0] : ["compositeFilter": composite]
        let structured: [String: Any] = [
            "from": [["collectionId": "storyPosts"]],
            "where": whereClause,
            "limit": limit,
        ]
        let query: [String: Any] = ["structuredQuery": structured]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Bundle.main.bundleIdentifier ?? "com.yourkoshertravel.app", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        req.httpBody = try JSONSerialization.data(withJSONObject: query)
        req.timeoutInterval = 20
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return rows.compactMap { (row: [String: Any]) -> Raw? in
            guard let doc = row["document"] as? [String: Any], let name = doc["name"] as? String else { return nil }
            let fields = restFields((doc["fields"] as? [String: Any]) ?? [:])
            return (id: String(name.split(separator: "/").last ?? ""), data: fields)
        }
    }

    static func restFields(_ f: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (k, v) in f { if let val = restValue(v) { out[k] = val } }
        return out
    }

    private static func restValue(_ raw: Any) -> Any? {
        guard let v = raw as? [String: Any] else { return nil }
        if let s = v["stringValue"] as? String { return s }
        if let s = v["integerValue"] as? String { return Double(s) ?? 0 }
        if let d = v["doubleValue"] as? Double { return d }
        if let d = v["doubleValue"] as? NSNumber { return d.doubleValue }
        if let b = v["booleanValue"] as? Bool { return b }
        if let t = v["timestampValue"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: t) { return d }
            f.formatOptions = [.withInternetDateTime]
            return f.date(from: t)
        }
        if let a = v["arrayValue"] as? [String: Any] {
            let values: [Any] = (a["values"] as? [Any]) ?? []
            return values.compactMap { restValue($0) }
        }
        if let m = v["mapValue"] as? [String: Any] {
            return restFields((m["fields"] as? [String: Any]) ?? [:])
        }
        return nil
    }
}
