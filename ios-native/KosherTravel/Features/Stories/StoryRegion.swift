import Foundation

/// The web's cardRegion.ts: the small place line of a post is the STATE (United States) or the COUNTRY (anywhere else),
/// never the city again, read from each stop's stored citySub ("Colorado, United States", "Wy, United States", "Aruba").
/// Cheskel, Oct 23 2026: an article showed "Wy, Wyoming".
enum StoryRegion {
    static let stateByCode: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado", "CT": "Connecticut",
        "DE": "Delaware", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana", "IA": "Iowa",
        "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan",
        "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire",
        "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
        "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
        "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
        "WI": "Wisconsin", "WY": "Wyoming", "DC": "Washington, D.C.", "PR": "Puerto Rico",
    ]
    private static let usNames: Set<String> = ["united states", "united states of america", "usa", "us", "u.s.a", "u.s.a.", "u.s", "u.s.", "america"]

    static func norm(_ x: String) -> String {
        x.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// "Colorado, United States" -> "Colorado"; "Wy, United States" -> "Wyoming"; "Aruba" -> "Aruba"; "Ontario, Canada" -> "Canada".
    static func of(_ citySub: String) -> String {
        let parts = citySub.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let last = parts.last else { return "" }
        if usNames.contains(last.lowercased()) {
            guard parts.count >= 2 else { return "United States" }
            let st = parts[0]
            let code = st.replacingOccurrences(of: ".", with: "").uppercased()
            if let name = stateByCode[code] { return name }
            return (st == st.lowercased() || st == st.uppercased()) ? st.capitalized : st
        }
        return last
    }
}

extension StoryPost {
    /// The web's cardRegion(): the post's state / country (an article with stops in several: "Arizona, Utah"), or ""
    /// when it would only repeat the title or the city.
    var regionLine: String { regionText(hiding: [title, cityName]) }

    /// Oct 25 2026 (Cheskel: "La Fortuna doesn't say the country"): a card that shows the CITY as its name hides the
    /// line only when it repeats that name. The La Fortuna post is titled "Costa Rica", so the title rule hid "Costa Rica".
    func cardRegionLine(shown: String) -> String { regionText(hiding: [shown]) }

    private func regionText(hiding names: [String]) -> String {
        let subs = isGuide && !stops.isEmpty ? stops.map(\.citySub) : [citySub]
        var seen: Set<String> = []
        var out: [String] = []
        for sub in subs {
            let r = StoryRegion.of(sub)
            if !r.isEmpty && !seen.contains(StoryRegion.norm(r)) { seen.insert(StoryRegion.norm(r)); out.append(r) }
        }
        let line = out.prefix(3).joined(separator: ", ")
        if line.isEmpty { return "" }
        if out.count == 1 && names.contains(where: { StoryRegion.norm($0) == StoryRegion.norm(line) }) { return "" }
        return line
    }
}
