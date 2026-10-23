import Foundation
import Observation
import FirebaseCore
import FirebaseFirestore

/// Live traveler posts (Firestore `storyPosts`, status == live). Read-only.
@Observable
final class StoryFeed {
    private(set) var posts: [StoryPost] = []
    private(set) var isLoading = false
    private(set) var loadedOnce = false
    private(set) var errorMessage: String?
    /// "firestore" when read through the Firebase SDK, "https" when read over the public REST endpoint.
    private(set) var source = ""

    static let hideAtReports = 3

    var articles: [StoryPost] { posts.filter { $0.isGuide } }
    var inspiration: [StoryPost] { posts.filter { !$0.isGuide } }

    func post(_ id: String) -> StoryPost? { posts.first { $0.id == id } }

    func articles(kind: StoryPost.PlaceKind, name: String) -> [StoryPost] {
        articles.filter { $0.matches(kind: kind, name: name) }
    }

    @MainActor
    func loadIfNeeded() async {
        if !loadedOnce && !isLoading { await refresh() }
    }

    @MainActor
    func refresh() async {
        isLoading = true
        defer { isLoading = false; loadedOnce = true }
        var list: [StoryPost]?
        if FirebaseBoot.isConfigured {
            do { list = try await Self.loadWithSDK(); source = "firestore" }
            catch { print("[KT] firestore read failed: \(error)") }
        }
        if list == nil {
            do { list = try await Self.loadWithREST(); source = "https" }
            catch { print("[KT] https read failed: \(error)") }
        }
        guard let list else {
            errorMessage = posts.isEmpty ? "Traveler posts could not load. Pull down to try again." : nil
            return
        }
        errorMessage = nil
        print("[KT] feed source=\(source) docs=\(list.count) firebase=\(FirebaseApp.app() != nil)")
        posts = list
            .filter { $0.status == "live" && $0.reportCount < Self.hideAtReports }
            .sorted { $0.createdAtMs > $1.createdAtMs }
    }

    private static func loadWithSDK() async throws -> [StoryPost] {
        let base = Firestore.firestore().collection("storyPosts").whereField("status", isEqualTo: "live")
        let snap: QuerySnapshot
        do {
            snap = try await base.order(by: "createdAt", descending: true).limit(to: 300).getDocuments()
        } catch {
            // no composite index: read unordered and sort here (same fallback as the website)
            snap = try await base.limit(to: 300).getDocuments()
        }
        return snap.documents.compactMap { StoryPost(id: $0.documentID, data: $0.data()) }
    }

    // MARK: public REST read (same request the website makes)

    static let restDocs = "https://firestore.googleapis.com/v1/projects/kosher-travel-app/databases/(default)/documents"
    static let restKey = "AIzaSyAqIbbxAIfqwuTaE31czStjZXDKJMynkEs"

    private static func loadWithREST() async throws -> [StoryPost] {
        guard let url = URL(string: "\(restDocs):runQuery?key=\(restKey)") else { return [] }
        let query: [String: Any] = [
            "structuredQuery": [
                "from": [["collectionId": "storyPosts"]],
                "where": ["fieldFilter": ["field": ["fieldPath": "status"], "op": "EQUAL", "value": ["stringValue": "live"]]],
                "limit": 300,
            ],
        ]
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
        return rows.compactMap { (row: [String: Any]) -> StoryPost? in
            guard let doc = row["document"] as? [String: Any], let name = doc["name"] as? String else { return nil }
            let fields = restFields((doc["fields"] as? [String: Any]) ?? [:])
            return StoryPost(id: String(name.split(separator: "/").last ?? ""), data: fields)
        }
    }

    private static func restFields(_ f: [String: Any]) -> [String: Any] {
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
