import Foundation

/// The AI Planner chat, stored the same way the web stores it (src/types.ts Message / ChatSession), so a chat
/// saved on the phone opens on the website and the other way round (users/{uid}/chatConversations/{id}).

/// This chat's on-screen trip picks (web: components/planner/tripFilters.ts TripFilters). Only set fields are stored.
struct TripFilters: Codable, Hashable {
    var destination: String?
    var startDate: String?      // YYYY-MM-DD
    var endDate: String?        // YYYY-MM-DD
    var days: Int?
    var adults: Int?
    var kids: Int?
    var budget: Int?
    var budgetPlus: Bool?
    var stays: [String]?
    var kosher: [String]?
    var interests: [String]?
    var pace: String?

    var isEmpty: Bool { dictionary.isEmpty }

    /// Firestore / JSON form without empty fields (the web's cleanFilters).
    var dictionary: [String: Any] {
        var d: [String: Any] = [:]
        if let destination, !destination.isEmpty { d["destination"] = destination }
        if let startDate, !startDate.isEmpty { d["startDate"] = startDate }
        if let endDate, !endDate.isEmpty { d["endDate"] = endDate }
        if let days { d["days"] = days }
        if let adults { d["adults"] = adults }
        if let kids { d["kids"] = kids }
        if let budget { d["budget"] = budget }
        if let budgetPlus { d["budgetPlus"] = budgetPlus }
        if let stays, !stays.isEmpty { d["stays"] = stays }
        if let kosher, !kosher.isEmpty { d["kosher"] = kosher }
        if let interests, !interests.isEmpty { d["interests"] = interests }
        if let pace, !pace.isEmpty { d["pace"] = pace }
        return d
    }

    init() {}

    init(dictionary d: [String: Any]) {
        func int(_ k: String) -> Int? {
            if let v = d[k] as? Int { return v }
            if let v = d[k] as? Int64 { return Int(v) }
            if let v = d[k] as? Double { return Int(v) }
            if let v = d[k] as? NSNumber { return v.intValue }
            return nil
        }
        destination = d["destination"] as? String
        startDate = d["startDate"] as? String
        endDate = d["endDate"] as? String
        days = int("days")
        adults = int("adults")
        kids = int("kids")
        budget = int("budget")
        budgetPlus = d["budgetPlus"] as? Bool
        stays = d["stays"] as? [String]
        kosher = d["kosher"] as? [String]
        interests = d["interests"] as? [String]
        pace = d["pace"] as? String
    }
}

struct ChatMessage: Codable, Identifiable, Hashable {
    var id: String
    var role: String            // user | assistant
    var content: String
    var isEdited: Bool?
    var suggestions: [String]?  // quick replies from the chat server
    var kind: String?           // "filters": a trip-settings change note
    var label: String?
    var filters: TripFilters?
    var away: [String: Int]?    // miles from the asked place, per other city the answer names

    var isUser: Bool { role == "user" }
    var isAssistant: Bool { role == "assistant" }
    var isFiltersNote: Bool { kind == "filters" }

    init(id: String = ChatMessage.newId(), role: String, content: String, filters: TripFilters? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.filters = (filters?.isEmpty ?? true) ? nil : filters
    }

    /// Same ids as the web (Date.now()), kept unique when two are made in the same millisecond.
    static func newId() -> String {
        var ms = Int64(Date().timeIntervalSince1970 * 1000)
        if ms <= lastId { ms = lastId + 1 }
        lastId = ms
        return String(ms)
    }
    private static var lastId: Int64 = 0

    /// Firestore form: only the fields that are set (Firestore refuses undefined on the web).
    var dictionary: [String: Any] {
        var d: [String: Any] = ["id": id, "role": role, "content": content]
        if let isEdited, isEdited { d["isEdited"] = true }
        if let suggestions, !suggestions.isEmpty { d["suggestions"] = suggestions }
        if let kind, !kind.isEmpty { d["kind"] = kind }
        if let label, !label.isEmpty { d["label"] = label }
        if let filters, !filters.isEmpty { d["filters"] = filters.dictionary }
        if let away, !away.isEmpty { d["away"] = away }
        return d
    }

    init?(dictionary d: [String: Any]) {
        guard let role = d["role"] as? String, role == "user" || role == "assistant" else { return nil }
        self.role = role
        if let s = d["id"] as? String { id = s }
        else if let n = d["id"] as? NSNumber { id = n.stringValue }
        else { id = ChatMessage.newId() }
        content = (d["content"] as? String) ?? ""
        isEdited = d["isEdited"] as? Bool
        suggestions = (d["suggestions"] as? [Any])?.compactMap { $0 as? String }
        kind = d["kind"] as? String
        label = d["label"] as? String
        if let f = d["filters"] as? [String: Any] { filters = TripFilters(dictionary: f) }
        if let a = d["away"] as? [String: Any] {
            var out: [String: Int] = [:]
            for (k, v) in a {
                if let n = v as? NSNumber { out[k] = n.intValue }
                else if let m = v as? [String: Any], let n = m["mi"] as? NSNumber { out[k] = n.intValue }
            }
            away = out.isEmpty ? nil : out
        }
    }
}

struct ChatSession: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var date: String            // ISO 8601, when the chat started
    var updatedAt: String?      // ISO 8601, last new message (the list is ordered by this)
    var messages: [ChatMessage]
    var sessionType: String?    // planner | general
    var fixedDestination: String?

    var isPlanner: Bool { (sessionType ?? "planner") == "planner" }

    var sortDate: Date {
        ChatSession.parse(updatedAt) ?? ChatSession.parse(date) ?? .distantPast
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoPlain = ISO8601DateFormatter()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }

    static func nowString() -> String { iso.string(from: Date()) }

    /// The chat's title: its first question, one line, at most 80 characters (same as the web).
    static func title(for messages: [ChatMessage]) -> String {
        let first = messages.first(where: { $0.isUser && !$0.isFiltersNote })?.content ?? messages.first?.content ?? ""
        let one = first.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(one.prefix(80))
    }
}
