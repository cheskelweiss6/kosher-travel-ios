import Foundation
import FirebaseFirestore

struct StoryMedia: Hashable {
    var type: String      // image | video
    var url: String
    var thumb: String
    var isVideo: Bool { type == "video" }
    /// What a card shows: the small cover first, the full file if there is no cover.
    var cardImage: String {
        if !thumb.isEmpty { return thumb }
        return isVideo ? "" : url
    }
}

struct StoryStop: Hashable {
    var cityId: String
    var cityName: String
    var citySub: String
    var text: String
}

struct StoryDay: Hashable {
    var date: String
    var place: String
    var mediaIdx: [Int]
}

/// A traveler's post from Firestore `storyPosts` (read-only here). Mirrors fromDoc() in the web app.
struct StoryPost: Identifiable, Hashable {
    var id: String
    var type: String              // quick (Inspiration) | guide (Article)
    var title: String
    var caption: String
    var intro: String
    var authorName: String
    var authorPhoto: String
    var cityId: String
    var cityName: String
    var citySub: String
    var placeName: String
    var media: [StoryMedia]
    var stops: [StoryStop]
    var days: [StoryDay]
    var status: String
    var createdAtMs: Double
    var likesCount: Int
    var viewsCount: Int
    var reportCount: Int

    var isGuide: Bool { type == "guide" }
    var cover: StoryMedia? { media.first(where: { !$0.cardImage.isEmpty }) }
    var hasVideo: Bool { media.contains(where: { $0.isVideo }) }

    /// "Colorado" / "Arizona, Utah": the places of the trip, without the country.
    var placeLine: String {
        var seen: [String] = []
        for st in allStops {
            let first = st.citySub.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            let label = first.isEmpty ? st.cityName : first
            if !label.isEmpty && !seen.contains(label) { seen.append(label) }
        }
        return seen.joined(separator: ", ")
    }

    var allStops: [StoryStop] {
        if !stops.isEmpty { return stops }
        return [StoryStop(cityId: cityId, cityName: cityName, citySub: citySub, text: caption)]
    }

    init?(id: String, data d: [String: Any]) {
        func s(_ k: String) -> String { (d[k] as? String) ?? "" }
        func n(_ k: String) -> Double {
            if let v = d[k] as? Double { return v }
            if let v = d[k] as? Int { return Double(v) }
            if let v = d[k] as? Int64 { return Double(v) }
            if let v = d[k] as? NSNumber { return v.doubleValue }
            return 0
        }
        self.id = id
        type = s("type") == "guide" ? "guide" : "quick"
        title = s("title")
        caption = s("caption")
        intro = s("intro")
        authorName = s("authorName").isEmpty ? "Traveler" : s("authorName")
        authorPhoto = s("authorPhoto")
        cityId = s("cityId")
        cityName = s("cityName")
        citySub = s("citySub")
        placeName = s("placeName")
        status = s("status").isEmpty ? "pending" : s("status")
        likesCount = Int(n("likesCount"))
        viewsCount = Int(n("viewsCount"))
        reportCount = Int(n("reportCount"))
        var ms = n("createdAtMs")
        if ms == 0 {
            if let ts = d["createdAt"] as? Timestamp { ms = ts.dateValue().timeIntervalSince1970 * 1000 }
            else if let date = d["createdAt"] as? Date { ms = date.timeIntervalSince1970 * 1000 }
        }
        createdAtMs = ms
        media = ((d["media"] as? [Any]) ?? []).compactMap { (raw: Any) -> StoryMedia? in
            guard let m = raw as? [String: Any] else { return nil }
            return StoryMedia(type: (m["type"] as? String) == "video" ? "video" : "image",
                              url: (m["url"] as? String) ?? "",
                              thumb: (m["thumb"] as? String) ?? "")
        }
        stops = ((d["stops"] as? [Any]) ?? []).compactMap { (raw: Any) -> StoryStop? in
            guard let m = raw as? [String: Any] else { return nil }
            return StoryStop(cityId: (m["cityId"] as? String) ?? "", cityName: (m["cityName"] as? String) ?? "",
                             citySub: (m["citySub"] as? String) ?? "", text: (m["text"] as? String) ?? "")
        }
        days = ((d["days"] as? [Any]) ?? []).compactMap { (raw: Any) -> StoryDay? in
            guard let m = raw as? [String: Any] else { return nil }
            let idx = ((m["mediaIdx"] as? [Any]) ?? []).compactMap { v -> Int? in
                if let i = v as? Int { return i }
                if let i = v as? Int64 { return Int(i) }
                if let x = v as? Double { return Int(x) }
                if let x = v as? NSNumber { return x.intValue }
                return nil
            }
            return StoryDay(date: (m["date"] as? String) ?? "", place: (m["place"] as? String) ?? "", mediaIdx: idx)
        }
    }

    // MARK: matching a post to a page (same rules as storyMatchesPlace on the web)

    enum PlaceKind { case city, state, country }

    func matches(kind: PlaceKind, name: String, region: String? = nil) -> Bool {
        let target = Self.norm(name)
        return allStops.contains { st in
            let parts = st.citySub.split(separator: ",").map { Self.norm(String($0)) }
            switch kind {
            case .city:
                guard Self.norm(st.cityName) == target else { return false }
                if let region { return parts.contains(Self.norm(region)) || parts.isEmpty }
                return true
            case .state:
                return parts.first == target && (parts.count > 1 && parts[1].contains("united states"))
            case .country:
                return parts.contains(target) || (target == "united states" && parts.contains("united states"))
            }
        }
    }

    static func norm(_ x: String) -> String {
        let folded = x.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US")).lowercased()
        return folded.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
