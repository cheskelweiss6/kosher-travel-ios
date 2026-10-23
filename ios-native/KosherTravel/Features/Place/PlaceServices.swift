import Foundation
import CoreLocation
import FirebaseFirestore

/// One review in Firestore `placeReviews/{placeKey}__{uid}` (same document the website reads and writes).
struct PlaceReview: Identifiable, Hashable, Sendable {
    var id: String
    var placeKey: String
    var placeId: String
    var placeName: String
    var placeKind: String
    var destId: String
    var userId: String
    /// The name saved with the review. Screens show `userName`: the reviewer's current username when they set one.
    var storedUserName: String
    var userPhoto: String
    var rating: Int
    var text: String
    var photoUrls: [String]
    var createdAtMs: Double
    var updatedAtMs: Double

    init(id: String, data d: [String: Any]) {
        func s(_ k: String) -> String { (d[k] as? String) ?? "" }
        func millis(_ k: String) -> Double {
            if let t = d[k] as? Timestamp { return t.dateValue().timeIntervalSince1970 * 1000 }
            if let n = d[k] as? Double { return n }
            return 0
        }
        self.id = id
        placeKey = s("placeKey"); placeId = s("placeId"); placeName = s("placeName")
        let kind = s("placeKind"); placeKind = kind.isEmpty ? "place" : kind
        destId = s("destId"); userId = s("userId")
        let name = s("userName"); storedUserName = name.isEmpty ? "Traveler" : name
        userPhoto = s("userPhoto")
        let r = (d["rating"] as? NSNumber)?.intValue ?? Int(s("rating")) ?? 5
        rating = max(1, min(5, r))
        text = s("text")
        photoUrls = (d["photoUrls"] as? [Any])?.compactMap { $0 as? String } ?? []
        let created = millis("createdAt")
        createdAtMs = created > 0 ? created : Date().timeIntervalSince1970 * 1000
        let updated = millis("updatedAt")
        updatedAtMs = updated > 0 ? updated : createdAtMs
    }

    /// Oct 23 2026 (Cheskel: "apply new user names the old posts"): the reviewer's current username
    /// (profiles/{uid}.username, read live), else the name saved with the review.
    var userName: String { StoriesStore.shared.name(uid: userId, stored: storedUserName) }
}

struct PlaceReviewSummary: Hashable {
    var count: Int
    var avg: Double
    init(_ list: [PlaceReview]) {
        count = list.count
        avg = list.isEmpty ? 0 : Double(list.reduce(0) { $0 + $1.rating }) / Double(list.count)
    }
}

struct PlaceTimeout: Error {}

/// Runs `op`, giving up after `seconds`.
func placeWithTimeout<T: Sendable>(_ seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await op() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw PlaceTimeout()
        }
        guard let first = try await group.next() else { throw PlaceTimeout() }
        group.cancelAll()
        return first
    }
}

/// Firestore reads the website also makes: the SDK first (from the server, never an empty cache), then the same
/// public query over HTTPS (Firestore's REST API) if the SDK is not set up or does not answer in time.
enum PlaceFirestore {
    struct Filter { let field: String; let value: String }

    static func query(_ collection: String, _ filters: [Filter], limit: Int) async throws -> [(String, [String: Any])] {
        if FirebaseBoot.isConfigured {
            do {
                let rows = try await placeWithTimeout(6) { () -> [SendableDoc] in
                    var q: Query = Firestore.firestore().collection(collection)
                    for f in filters { q = q.whereField(f.field, isEqualTo: f.value) }
                    let snap = try await q.limit(to: limit).getDocuments(source: .server)
                    return snap.documents.map { SendableDoc(id: $0.documentID, data: $0.data()) }
                }
                return rows.map { ($0.id, $0.data) }
            } catch {
                print("[KT] place query \(collection) via sdk failed: \(error)")
            }
        }
        return try await rest(collection, filters, limit: limit)
    }

    struct SendableDoc: @unchecked Sendable { let id: String; let data: [String: Any] }

    private static func rest(_ collection: String, _ filters: [Filter], limit: Int) async throws -> [(String, [String: Any])] {
        guard let url = URL(string: "\(StoryFeed.restDocs):runQuery?key=\(StoryFeed.restKey)") else { return [] }
        let fieldFilters: [[String: Any]] = filters.map {
            ["fieldFilter": ["field": ["fieldPath": $0.field], "op": "EQUAL", "value": ["stringValue": $0.value]]]
        }
        var sq: [String: Any] = ["from": [["collectionId": collection]], "limit": limit]
        if fieldFilters.count == 1 { sq["where"] = fieldFilters[0] }
        else if fieldFilters.count > 1 { sq["where"] = ["compositeFilter": ["op": "AND", "filters": fieldFilters]] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": sq])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let rows = (try JSONSerialization.jsonObject(with: data)) as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let doc = row["document"] as? [String: Any], let name = doc["name"] as? String else { return nil }
            let fields = doc["fields"] as? [String: Any] ?? [:]
            var out: [String: Any] = [:]
            for (k, v) in fields { if let x = restValue(v) { out[k] = x } }
            return (String(name.split(separator: "/").last ?? ""), out)
        }
    }

    private static func restValue(_ v: Any) -> Any? {
        guard let m = v as? [String: Any] else { return nil }
        if let s = m["stringValue"] as? String { return s }
        if let s = m["integerValue"] as? String { return NSNumber(value: Int(s) ?? 0) }
        if let d = m["doubleValue"] as? Double { return NSNumber(value: d) }
        if let b = m["booleanValue"] as? Bool { return b }
        if let t = m["timestampValue"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = f.date(from: t) ?? ISO8601DateFormatter().date(from: t)
            return date.map { Timestamp(date: $0) }
        }
        if let a = m["arrayValue"] as? [String: Any] {
            return (a["values"] as? [Any] ?? []).compactMap(restValue)
        }
        if let mv = m["mapValue"] as? [String: Any] {
            var o: [String: Any] = [:]
            for (k, x) in (mv["fields"] as? [String: Any] ?? [:]) { if let y = restValue(x) { o[k] = y } }
            return o
        }
        return nil
    }
}

/// Reading and writing place reviews exactly like src/components/reviews/placeReviews.ts.
enum PlaceReviewService {
    static let collection = "placeReviews"
    static let textMax = 1000
    /// The accounts told in the bell about new place reviews (website: REVIEW_NOTIFY_UIDS).
    static let notifyUids = ["ZilNixJYqChwhgBopF7OHFcyIX13", "oKMrTvuUxWPCH10hCHB1uZwHpYm1"]

    static func reviewId(placeId: String, uid: String) -> String { "\(PlaceKey.key(placeId))__\(uid)" }

    /// Everyone's reviews of one place, newest first.
    static func reviews(placeId: String) async throws -> [PlaceReview] {
        let rows = try await PlaceFirestore.query(collection, [.init(field: "placeKey", value: PlaceKey.key(placeId))], limit: 200)
        return rows.map { PlaceReview(id: $0.0, data: $0.1) }.sorted { $0.updatedAtMs > $1.updatedAtMs }
    }

    /// Every review in one destination, grouped by placeKey (one read for the whole city page).
    static func destReviews(destId: String) async throws -> [String: [PlaceReview]] {
        let rows = try await PlaceFirestore.query(collection, [.init(field: "destId", value: String(destId.prefix(80)))], limit: 1000)
        var out: [String: [PlaceReview]] = [:]
        for r in rows.map({ PlaceReview(id: $0.0, data: $0.1) }) where !r.placeKey.isEmpty {
            out[r.placeKey, default: []].append(r)
        }
        for k in out.keys { out[k]?.sort { $0.updatedAtMs > $1.updatedAtMs } }
        return out
    }

    /// Save (or edit) the signed-in person's review. Same fields, limits and timestamps as the website.
    static func save(item: PlaceItem, uid: String, name: String, photo: String, rating: Int, text: String) async throws {
        guard let placeId = item.reviewPlaceId, FirebaseBoot.isConfigured else { throw URLError(.cannotConnectToHost) }
        let id = reviewId(placeId: placeId, uid: uid)
        let ref = Firestore.firestore().collection(collection).document(id)
        let before = try? await ref.getDocument()
        let isNew = !(before?.exists ?? false)
        let old = before?.data() ?? [:]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt: Any = isNew ? FieldValue.serverTimestamp() : (old["createdAt"] ?? FieldValue.serverTimestamp())
        let keptPhotos: [String] = isNew ? [] : ((old["photoUrls"] as? [Any])?.compactMap { $0 as? String } ?? [])
        let data: [String: Any] = [
            "placeKey": PlaceKey.key(placeId),
            "placeId": String(placeId.prefix(200)),
            "placeName": String((item.venue.name.isEmpty ? "this place" : item.venue.name).prefix(120)),
            "placeKind": item.category.reviewKind,
            "destId": String(item.destId.prefix(80)),
            "userId": uid,
            "userName": String((name.isEmpty ? "Traveler" : name).prefix(80)),
            "userPhoto": String(photo.prefix(2000)),
            "rating": max(1, min(5, rating)),
            "text": String(trimmed.prefix(textMax)),
            "photoUrls": keptPhotos,
            "createdAt": createdAt,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        try await ref.setData(data)
        if isNew {
            // One bell note for the app owner's accounts (never for your own review). Fails softly, like the website.
            for owner in notifyUids where owner != uid {
                let note: [String: Any] = [
                    "kind": "review", "actorUid": uid, "actorName": String((name.isEmpty ? "Traveler" : name).prefix(80)),
                    "actorPhoto": String(photo.prefix(2000)), "reviewId": id, "placeId": String(placeId.prefix(200)),
                    "placeName": String((item.venue.name.isEmpty ? "this place" : item.venue.name).prefix(120)),
                    "placeKind": item.category.reviewKind, "destId": String(item.destId.prefix(80)),
                    "rating": max(1, min(5, rating)), "text": String(trimmed.prefix(140)),
                    "createdAt": FieldValue.serverTimestamp(), "read": false,
                ]
                Firestore.firestore().collection("users").document(owner).collection("notifications")
                    .document("r_" + id).setData(note) { err in
                        if let err { print("[KT] review note not written: \(err)") }
                    }
            }
        }
    }

    static func delete(reviewId: String) async throws {
        try await Firestore.firestore().collection(collection).document(reviewId).delete()
        for owner in notifyUids {
            Firestore.firestore().collection("users").document(owner).collection("notifications")
                .document("r_" + reviewId).delete { _ in }
        }
    }
}

/// Places travelers added (Firestore `places`, status live, source traveler), as the website reads them.
enum CityTravelerPlaces {
    struct Row: Hashable {
        let id: String
        let name: String
        let category: String
        let cityName: String
        let cityId: String
        let address: String
        let phone: String
        let website: String
        let hechsher: String
        let postId: String
    }

    private static var cache: [Row]?

    static func all(force: Bool = false) async -> [Row] {
        if let cache, !force { return cache }
        do {
            let rows = try await PlaceFirestore.query("places", [.init(field: "status", value: "live"), .init(field: "source", value: "traveler")], limit: 500)
            let list = rows.map { id, d -> Row in
                func s(_ k: String) -> String { ((d[k] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
                return Row(id: id, name: s("name"), category: s("category"), cityName: s("cityName"), cityId: s("cityId"),
                           address: s("address"), phone: s("phone"), website: s("website"), hechsher: s("hechsher"), postId: s("postId"))
            }.filter { !$0.name.isEmpty }
            cache = list
            return list
        } catch {
            print("[KT] traveler places did not load: \(error)")
            return []
        }
    }

    /// This city's places, minus any the app already lists (website: dedupeAgainst on normName, and name|cityId).
    static func forCity(_ page: CityPage, force: Bool = false) async -> [PlaceItem] {
        let rows = await all(force: force)
        let have = Set(page.listedNames.map(PlaceKey.norm))
        var seen = Set<String>()
        var out: [PlaceItem] = []
        for r in rows where r.cityName.lowercased() == page.name.lowercased() {
            let n = PlaceKey.norm(r.name)
            let k = n + "|" + r.cityId
            if have.contains(n) || seen.contains(k) { continue }
            seen.insert(k)
            let cat = PlaceCategory.fromTraveler(r.category)
            let v = Venue(name: r.name, address: r.address, phone: r.phone, website: r.website, description: "",
                          photo: "", kashrus: r.hechsher, kind: cat.label)
            out.append(PlaceItem(id: "traveler:\(r.id)", category: .traveler, venue: v, destId: page.destId,
                                 cityName: page.name, travelerCategory: cat, travelerPostId: r.postId))
        }
        return out
    }
}

/// Addresses to map pins, on the phone (CLGeocoder), remembered between launches. Never a made-up coordinate:
/// a place with no address, or one Apple Maps cannot find, gets no pin.
actor PlaceGeocoder {
    static let shared = PlaceGeocoder()
    private var memo: [String: [Double]] = [:]
    private var misses = Set<String>()
    private var loaded = false
    private var busy = false

    private var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("kt-geocode-v1.json")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let url = fileURL, let data = try? Data(contentsOf: url),
           let m = try? JSONDecoder().decode([String: [Double]].self, from: data) { memo = m }
    }

    private func save() {
        guard let url = fileURL, let data = try? JSONEncoder().encode(memo) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func cached(_ address: String) -> CLLocationCoordinate2D? {
        load()
        guard let c = memo[address.lowercased()], c.count == 2 else { return nil }
        return CLLocationCoordinate2D(latitude: c[0], longitude: c[1])
    }

    func coordinate(for address: String) async -> CLLocationCoordinate2D? {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard a.count >= 6 else { return nil }
        if let hit = cached(a) { return hit }
        if misses.contains(a.lowercased()) { return nil }
        // one request at a time (Apple's geocoder limits concurrent and rapid requests)
        while busy { try? await Task.sleep(nanoseconds: 150_000_000) }
        busy = true
        defer { busy = false }
        if let hit = cached(a) { return hit }
        let placemarks = try? await CLGeocoder().geocodeAddressString(a)
        guard let loc = placemarks?.first?.location?.coordinate else {
            misses.insert(a.lowercased())
            return nil
        }
        memo[a.lowercased()] = [loc.latitude, loc.longitude]
        save()
        return loc
    }
}
