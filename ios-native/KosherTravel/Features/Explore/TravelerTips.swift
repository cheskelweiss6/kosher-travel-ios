import SwiftUI
import Observation

/// "Tips from travelers" (website src/components/stories/TravelerTips.tsx + travelerIndex.ts, Oct 23 2026): the tips
/// the AI server read out of live posts, in the traveler's own words, on the city, state or country page they are
/// about. Each opens its post. Hidden when there are none. Same feed as the website: <ai server>/api/traveler-index.
struct TravelerTip: Identifiable, Hashable, Decodable {
    var id: String
    var postId: String
    var author: String
    var when: String
    var text: String
    var place: String
    var cityName: String
    var citySub: String
    var state: String
    var country: String
    var guess: Bool

    enum CodingKeys: String, CodingKey { case id, postId, author, when, text, place, cityName, citySub, state, country, guess }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { ((try? c.decodeIfPresent(String.self, forKey: k)) ?? nil) ?? "" }
        id = s(.id); postId = s(.postId); author = s(.author); when = s(.when); text = s(.text); place = s(.place)
        cityName = s(.cityName); citySub = s(.citySub); state = s(.state); country = s(.country)
        guess = ((try? c.decodeIfPresent(Bool.self, forKey: .guess)) ?? nil) ?? false
    }
}

/// The web's TipScope.
struct TipScope: Hashable {
    enum Kind: Hashable { case city, state, country, place }
    var kind: Kind
    var name: String
    var region: String = ""
    var stateCode: String = ""
}

@MainActor
@Observable
final class TravelerTipsStore {
    static let shared = TravelerTipsStore()
    static let url = URL(string: "https://kosher-travel-ai.sites.tab.bot/api/traveler-index")!

    private(set) var tips: [TravelerTip] = []
    @ObservationIgnored private var fetchedAt: Date?
    @ObservationIgnored private var running: Task<Void, Never>?

    private struct Index: Decodable { var tips: [TravelerTip]? }

    /// Like the website: read at most every 3 minutes; a failed read keeps the last list.
    func fetch() async {
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < 180 { return }
        if let running { await running.value; return }
        let job = Task { [weak self] in
            var req = URLRequest(url: Self.url, timeoutInterval: 7)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let res = try? await URLSession.shared.data(for: req),
                  (res.1 as? HTTPURLResponse)?.statusCode == 200,
                  let idx = try? JSONDecoder().decode(Index.self, from: res.0), let list = idx.tips else { return }
            self?.tips = list
            self?.fetchedAt = Date()
        }
        running = job
        await job.value
        running = nil
    }

    /// The web's normTip.
    static func norm(_ x: String) -> String {
        var s = x.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        s = s.replacingOccurrences(of: "['\u{2019}`]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
        if s.hasPrefix("the ") { s.removeFirst(4) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// The web's sameName: equal, or one is the other plus words.
    static func sameName(_ a: String, _ b: String) -> Bool {
        let x = norm(a), y = norm(b)
        if x.isEmpty || y.isEmpty { return false }
        if x == y { return true }
        let (s, l) = x.count <= y.count ? (x, y) : (y, x)
        return s.split(separator: " ").count >= 2 && l.hasPrefix(s + " ")
    }

    /// The web's tipsFor (model-read tips only; duplicates of the same words dropped).
    func tips(for scope: TipScope) -> [TravelerTip] {
        let n = Self.norm(scope.name)
        let r = Self.norm(scope.region)
        var seen = Set<String>()
        return tips.filter { t in
            if t.guess || t.text.isEmpty { return false }
            let firstSub = Self.norm(t.citySub.split(separator: ",", omittingEmptySubsequences: false).first.map(String.init) ?? "")
            var ok = false
            switch scope.kind {
            case .place:
                ok = !t.place.isEmpty && Self.sameName(t.place, scope.name)
            case .city:
                ok = Self.norm(t.cityName) == n && (r.isEmpty || t.citySub.isEmpty || Self.norm(t.citySub).contains(r) || firstSub.count <= 3)
            case .state:
                ok = (!scope.stateCode.isEmpty && t.state == scope.stateCode)
                    || (firstSub == n && t.citySub.range(of: "united states", options: .caseInsensitive) != nil)
            case .country:
                ok = n != "united states" && (Self.norm(t.country) == n
                    || t.citySub.split(separator: ",", omittingEmptySubsequences: false).contains { Self.norm(String($0)) == n })
            }
            if !ok { return false }
            let k = Self.norm(t.text)
            if seen.contains(k) { return false }
            seen.insert(k)
            return true
        }
    }
}

/// The section on a city / state / country page (web TravelerTips).
struct TravelerTipsSection: View {
    let scope: TipScope
    /// Space around the section when it shows (none when there are no tips, so the page doesn't gain a gap).
    var insets = EdgeInsets()
    private let store = TravelerTipsStore.shared
    @State private var showAll = false

    var body: some View {
        let tips = store.tips(for: scope)
        // A Group, so an empty section adds no gap. The page itself calls TravelerTipsStore.shared.fetch().
        Group {
            if !tips.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Tips from travelers", systemImage: "lightbulb")
                            .font(.system(.subheadline, design: .serif).weight(.black))
                            .foregroundStyle(Color.primary)
                            .labelStyle(TipsLabelStyle())
                        Spacer()
                        Text("\(tips.count)").font(.caption.weight(.bold)).foregroundStyle(Color.textSecondary)
                    }
                    ForEach(showAll ? tips : Array(tips.prefix(3))) { t in
                        NavigationLink(value: ExploreRoute.story(t.postId)) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\u{201C}\(t.text)\u{201D}")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(credit(t))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .hairline(radius: 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Tip from \(t.author.isEmpty ? "a traveler" : t.author): \(t.text). Open the post")
                    }
                    if tips.count > 3 {
                        Button { showAll.toggle() } label: {
                            Text(showAll ? "Show fewer" : "See all \(tips.count) tips")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.navy)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Travelers\u{2019} own words, not checked by the app.")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(insets)
            }
        }
    }

    private func credit(_ t: TravelerTip) -> String {
        let who = (t.author.isEmpty ? "A traveler" : t.author) + (t.when.isEmpty ? "" : ", visited \(t.when)")
        return [t.place, who].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }
}

private struct TipsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(Color.navy)
            configuration.title
        }
    }
}
