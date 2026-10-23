import SwiftUI
import Observation
import FirebaseFirestore

// Explore home rows the web has under Stories & Articles (App.tsx 7194-7209):
//  - "What's New": the auto news (components/news/WhatsNew.tsx, newsService.ts, newsCategories.ts): header with
//    "Updated hourly" and See all, category chips, one featured story with a wide photo and 4 rows under it.
//  - "Your upcoming trips" (stories/ExploreStories.tsx tripsOnly): the signed-in person's trips (users/{uid}/trips,
//    not isPast), up to 3, each opening My Travel.

struct ExploreNewsItem: Identifiable, Hashable {
    var id: String
    var title: String
    var summary: String
    var url: String
    var source: String
    var publishedAt: String
    var category: String
    var image: String
    var sourceCount: Int

    var imageURL: String {
        if image.isEmpty { return "" }
        if image.hasPrefix("https://") { return image }
        return ExploreNewsStore.base + image
    }

    var publishedMs: Double {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: publishedAt) { return d.timeIntervalSince1970 * 1000 }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: publishedAt) { return d.timeIntervalSince1970 * 1000 }
        return 0
    }
}

/// newsCategories.ts: the chip order and names (the only place the app names them).
struct ExploreNewsCategory: Hashable, Identifiable {
    var id: String
    var label: String
    var icon: String

    static let all: [ExploreNewsCategory] = [
        ExploreNewsCategory(id: "kosher", label: "Kosher", icon: "fork.knife"),
        ExploreNewsCategory(id: "culture", label: "Jewish Culture", icon: "building.columns"),
        ExploreNewsCategory(id: "travel", label: "Travel", icon: "safari"),
        ExploreNewsCategory(id: "airline", label: "Airlines", icon: "airplane"),
        ExploreNewsCategory(id: "airport", label: "Airports", icon: "building.2"),
    ]
    static func label(_ id: String) -> String {
        if let c = all.first(where: { $0.id == id }) { return c.label }
        let t = id.isEmpty ? "News" : id.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }
    static func icon(_ id: String) -> String { all.first(where: { $0.id == id })?.icon ?? "safari" }
}

@Observable
final class ExploreNewsStore {
    static let shared = ExploreNewsStore()
    static let base = "https://kosher-travel-news.sites.tab.bot"
    private static let cacheKey = "kt.news.cache.v2"

    private(set) var items: [ExploreNewsItem] = []
    private(set) var loading = false
    private(set) var failed = false
    @ObservationIgnored private var loadedAt: Date?

    // Owner's rule (Oct 21 2026): nothing about Israel in the news; the server drops these, this is the app's net.
    private static let israel = try? NSRegularExpression(pattern: #"\b(?:israel\w*|eretz[\s-]+yisr[ao]e?l|yerushalayim|jerusalem|tel[\s-]?aviv|bnei[\s-]?brak|beit[\s-]?shemesh|beth[\s-]?shemesh|haifa|eilat|tiberias|teveria|safed|tzfat|tzfas|tzefat|netanya|herzliy?a|modi['’]?in|ashdod|ashkelon|beersheba|be['’]?er[\s-]?sheva|beer[\s-]?sheva|petah?[\s-]?tikva|petach[\s-]?tikva|ra['’]?anana|elad|kotel|western[\s-]+wall|idf|el[\s-]?al|arkia|israir|ben[\s-]?gurion|tlv|west[\s-]+bank|gaza|golan|knesset|judea|samaria|jaffa|dead[\s-]+sea|masada|netanyahu|hamas|hezbollah|holy[\s-]+land)\b"#, options: [.caseInsensitive])

    private static func aboutIsrael(_ x: [String: Any]) -> Bool {
        guard let re = israel else { return false }
        let url = (x["url"] as? String ?? "").replacingOccurrences(of: #"[-_/.+%=?&#:]+"#, with: " ", options: .regularExpression)
        let text = [x["title"], x["summary"], x["category"], x["city"], x["state"], x["country"]].compactMap { $0 as? String }.joined(separator: " ") + " " + url
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func parse(_ data: Data) -> [ExploreNewsItem] {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = j["items"] as? [[String: Any]] else { return [] }
        return arr.compactMap { x in
            guard let url = x["url"] as? String, url.hasPrefix("https://"), let title = x["title"] as? String, !title.isEmpty,
                  !aboutIsrael(x) else { return nil }
            return ExploreNewsItem(id: (x["id"] as? String) ?? url, title: title, summary: x["summary"] as? String ?? "",
                                   url: url, source: x["source"] as? String ?? "", publishedAt: x["published_at"] as? String ?? "",
                                   category: x["category"] as? String ?? "", image: (x["photo_hidden"] as? Bool ?? false) ? "" : (x["image"] as? String ?? ""),
                                   sourceCount: x["source_count"] as? Int ?? 1)
        }
    }

    @MainActor
    func load(force: Bool = false) async {
        if items.isEmpty, let cached = UserDefaults.standard.data(forKey: Self.cacheKey) {
            items = Self.parse(cached)
        }
        if !force, let at = loadedAt, Date().timeIntervalSince(at) < 600 { return }
        guard !loading, let url = URL(string: "\(Self.base)/api/news?cat=all&limit=40") else { return }
        loading = true
        failed = false
        defer { loading = false }
        var req = URLRequest(url: url, timeoutInterval: 12)
        if force { req.cachePolicy = .reloadIgnoringLocalCacheData }
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let fresh = Self.parse(data)
            items = fresh
            loadedAt = Date()
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        } catch {
            failed = true
        }
    }
}

/// "What's New" on the Explore home.
struct ExploreWhatsNew: View {
    private var store: ExploreNewsStore { .shared }
    @State private var filter = "all"
    @Environment(\.openURL) private var openURL

    private var counts: [String: Int] {
        var c: [String: Int] = [:]
        for i in store.items { c[i.category, default: 0] += 1 }
        return c
    }

    /// Featured + 4 rows of the chosen category (server order: kosher news leads).
    private var strip: [ExploreNewsItem] {
        Array((filter == "all" ? store.items : store.items.filter { $0.category == filter }).prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("What's New")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.navy)
                Text("Updated hourly")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !store.items.isEmpty {
                    NavigationLink(value: ExploreRoute.web(.news)) {
                        Text("See all").font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pagePadding)

            if !store.items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        StoryChip(title: "All", selected: filter == "all") { filter = "all" }
                        ForEach(ExploreNewsCategory.all.filter { (counts[$0.id] ?? 0) > 0 || $0.id == filter }) { c in
                            StoryChip(title: "\(c.label) \(counts[c.id] ?? 0)", selected: filter == c.id) { filter = c.id }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                .sensoryFeedback(.selection, trigger: filter)
            }

            Group {
                if store.loading && store.items.isEmpty {
                    VStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 16).fill(Color.surface).aspectRatio(16 / 9, contentMode: .fit)
                        ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 10).fill(Color.surface).frame(height: 64) }
                    }
                    .accessibilityLabel("Loading news")
                } else if store.failed && store.items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't load the latest news.").font(.subheadline.weight(.semibold))
                        Text("Check your connection and try again.").font(.footnote).foregroundStyle(Color.textSecondary)
                        Button { Task { await store.load(force: true) } } label: {
                            Label("Try again", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .background(Color.navy, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hairline(radius: 16)
                } else if strip.isEmpty {
                    Text("No \(filter == "all" ? "" : ExploreNewsCategory.label(filter).lowercased() + " ")news right now. New stories show up here automatically.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hairline(radius: 16)
                } else {
                    VStack(spacing: 0) {
                        featured(strip[0])
                        ForEach(Array(strip.dropFirst().enumerated()), id: \.element.id) { _, item in
                            Divider().overlay(Color.hairline)
                            row(item)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .task { await store.load() }
    }

    private func meta(_ item: ExploreNewsItem) -> String {
        var parts = [item.source]
        let when = TimeAgo.string(item.publishedMs)
        if !when.isEmpty { parts.append(when) }
        if filter == "all", !item.category.isEmpty { parts.append(ExploreNewsCategory.label(item.category)) }
        if item.sourceCount >= 2 { parts.append("\(item.sourceCount) sources") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private func thumb(_ item: ExploreNewsItem) -> some View {
        if item.imageURL.isEmpty {
            Rectangle().fill(Color.surface)
                .overlay {
                    Image(systemName: ExploreNewsCategory.icon(item.category))
                        .font(.title2.weight(.light))
                        .foregroundStyle(Color.navy.opacity(0.45))
                }
        } else {
            RemoteImage(url: item.imageURL, maxPixel: 900)
        }
    }

    private func featured(_ item: ExploreNewsItem) -> some View {
        Button { if let u = URL(string: item.url) { openURL(u) } } label: {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { thumb(item) }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(Color.navy)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                HStack(spacing: 6) {
                    Text(meta(item))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    shareButton(item)
                }
            }
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title). \(item.source). Opens the article.")
    }

    private func row(_ item: ExploreNewsItem) -> some View {
        Button { if let u = URL(string: item.url) { openURL(u) } } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    Text(meta(item))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                thumb(item)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let u = URL(string: item.url) {
                ShareLink(item: u, subject: Text(item.title), message: Text("\(item.title) (\(item.source)) via Kosher Travel")) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .accessibilityLabel("\(item.title). \(item.source). Opens the article.")
    }

    @ViewBuilder
    private func shareButton(_ item: ExploreNewsItem) -> some View {
        if let u = URL(string: item.url) {
            ShareLink(item: u, subject: Text(item.title), message: Text("\(item.title) (\(item.source)) via Kosher Travel")) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Share: \(item.title)")
        }
    }
}

/// "Your upcoming trips" on the Explore home (signed in, with trips that are not past).
struct ExploreUpcomingTrips: View {
    let uid: String

    struct Trip: Identifiable, Hashable {
        var id: String
        var title: String
        var city: String
        var days: Int
        var startDate: String
    }

    @State private var trips: [Trip] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !trips.isEmpty {
                HStack(alignment: .lastTextBaseline) {
                    Text("YOUR UPCOMING TRIPS")
                        .font(.caption.weight(.heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Button { ShellRouter.shared.open(tab: "mytravel") } label: {
                        HStack(spacing: 2) {
                            Text("My Travel")
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.navy)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                VStack(spacing: 8) {
                    ForEach(trips.prefix(3)) { t in
                        Button { ShellRouter.shared.open(tab: "mytravel") } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title.isEmpty ? t.city : t.title)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.primary)
                                        .lineLimit(1)
                                    Text(subtitle(t))
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.textTertiary)
                            }
                            .padding(12)
                            .hairline(radius: 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .task(id: uid) { await load() }
    }

    private func subtitle(_ t: Trip) -> String {
        var s = t.city
        if t.days > 0 { s += " · \(t.days) day\(t.days == 1 ? "" : "s")" }
        if !t.startDate.isEmpty { s += " · \(t.startDate)" }
        return s
    }

    @MainActor
    private func load() async {
        guard FirebaseBoot.isConfigured, !uid.isEmpty else { trips = []; return }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).collection("trips").getDocuments(source: .server)
            trips = snap.documents.compactMap { d in
                let x = d.data()
                if x["isPast"] as? Bool == true { return nil }
                let days = (x["days"] as? [Any])?.count ?? 0
                return Trip(id: (x["id"] as? String) ?? d.documentID, title: x["title"] as? String ?? "", city: x["city"] as? String ?? "",
                            days: days, startDate: x["startDate"] as? String ?? "")
            }
        } catch {
            print("[KT] trips not read: \(error)")
        }
    }
}
