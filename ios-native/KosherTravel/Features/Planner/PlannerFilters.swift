import Foundation

/// Trip filters helpers shared with the web (components/planner/tripFilters.ts): the count on the Filters button,
/// the "Updated for: …" words and the message a filters change sends.
extension TripFilters {
    /// Only the fields that are set (web: cleanFilters).
    var cleaned: TripFilters {
        var f = self
        if (f.destination ?? "").isEmpty { f.destination = nil }
        if (f.startDate ?? "").isEmpty { f.startDate = nil }
        if (f.endDate ?? "").isEmpty { f.endDate = nil }
        if (f.stays ?? []).isEmpty { f.stays = nil }
        if (f.kosher ?? []).isEmpty { f.kosher = nil }
        if (f.interests ?? []).isEmpty { f.interests = nil }
        if (f.pace ?? "").isEmpty { f.pace = nil }
        return f
    }

    var tripDays: Int? { TripBuilderSheet.daysBetween(startDate, endDate) ?? days }

    private static func plural(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    private var shortDatesText: String {
        guard let a = TripBuilderSheet.date(startDate) else { return "" }
        guard let b = TripBuilderSheet.date(endDate) else {
            let mon = DateFormatter()
            mon.locale = Locale(identifier: "en_US")
            mon.dateFormat = "MMM d"
            return "From " + mon.string(from: a)
        }
        return TripBuilderSheet.shortDates(a, b)
    }

    private var whoText: String {
        if adults == nil && kids == nil { return "" }
        var parts: [String] = []
        if let a = adults { parts.append(Self.plural(a, "adult", "adults")) }
        if let k = kids, k > 0 { parts.append(Self.plural(k, "child", "kids")) }
        return parts.joined(separator: ", ")
    }

    private var budgetText: String {
        guard let b = budget else { return "" }
        return TripBuilderSheet.money(Double(b)) + ((budgetPlus ?? false) ? "+" : "")
    }

    private var daysText: String {
        let n = tripDays
        let d = shortDatesText
        if !d.isEmpty, let n { return "\(d), \(Self.plural(n, "day", "days"))" }
        if !d.isEmpty { return d }
        return n.map { Self.plural($0, "day", "days") } ?? ""
    }

    /// The short chips (web: filterChips); the Filters button shows how many.
    var chipLabels: [String] {
        var out: [String] = []
        if let d = destination, !d.isEmpty { out.append(d.components(separatedBy: ",")[0]) }
        let sd = shortDatesText
        if !sd.isEmpty { out.append(sd) }
        if let n = tripDays, n > 0 { out.append(Self.plural(n, "day", "days")) }
        if !whoText.isEmpty { out.append(whoText) }
        if !budgetText.isEmpty { out.append(budgetText) }
        if let s = stays, !s.isEmpty { out.append(s.joined(separator: ", ")) }
        if let k = kosher, !k.isEmpty { out.append(k.count == 1 ? k[0] : "Kosher: \(k.count)") }
        if let i = interests, !i.isEmpty { out.append(i.joined(separator: ", ")) }
        return out
    }

    private static func sameList(_ a: [String]?, _ b: [String]?) -> Bool { (a ?? []).sorted() == (b ?? []).sorted() }

    /// What changed, in plain words, for the "Updated for: …" note. Empty = nothing changed (web: describeChange).
    static func describeChange(_ prev: TripFilters, _ next: TripFilters) -> String {
        var out: [String] = []
        if (prev.destination ?? "") != (next.destination ?? ""), let d = next.destination, !d.isEmpty {
            out.append(d.components(separatedBy: ",")[0])
        }
        let datesChanged = (prev.startDate ?? "") != (next.startDate ?? "") || (prev.endDate ?? "") != (next.endDate ?? "")
        if datesChanged || prev.tripDays != next.tripDays {
            let l = next.daysText
            if !l.isEmpty { out.append(l) } else if datesChanged { out.append("No set dates") }
        }
        if prev.adults != next.adults || (prev.kids ?? 0) != (next.kids ?? 0) {
            let w = next.whoText
            if !w.isEmpty { out.append(w) }
        }
        if prev.budget != next.budget || (prev.budgetPlus ?? false) != (next.budgetPlus ?? false) {
            let b = next.budgetText
            if !b.isEmpty { out.append("\(b) budget") }
        }
        if !sameList(prev.stays, next.stays) {
            out.append((next.stays ?? []).isEmpty ? "Any place to stay" : "Stay: \((next.stays ?? []).joined(separator: ", "))")
        }
        if !sameList(prev.kosher, next.kosher) {
            out.append((next.kosher ?? []).isEmpty ? "No kosher needs picked" : "Kosher: \((next.kosher ?? []).joined(separator: ", "))")
        }
        if !sameList(prev.interests, next.interests) {
            out.append((next.interests ?? []).isEmpty ? "Any interests" : "Interests: \((next.interests ?? []).joined(separator: ", "))")
        }
        if (prev.pace ?? "") != (next.pace ?? ""), let p = next.pace, !p.isEmpty { out.append("\(p) pace") }
        return out.joined(separator: ", ")
    }

    /// The message a settings change sends; the chat shows only the small "Updated for" note (web: updateRequestText).
    static func updateRequestText(_ label: String) -> String {
        "I changed my settings: \(label). Redo your last answer with these settings: same place, and the same days unless the days or dates changed. Show the whole adjusted day-by-day list again."
    }
}
