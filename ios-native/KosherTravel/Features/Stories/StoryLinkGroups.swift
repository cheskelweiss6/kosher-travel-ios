import SwiftUI

/// The links a post shows (web LinksButton linkGroups): the post's own links, then — for a photo/video post that has
/// an article ("Read the full article") — the article's links under "Day N · Fri, Jan 31" for the day they are dated,
/// the rest under "Trip". One row per address. Read-time only: nothing is copied or written.
struct StoryLinkGroup: Identifiable, Hashable {
    var id: String
    var title: String
    var links: [StoryLinkInfo]

    static func groups(post: StoryExtra?, article: StoryExtra?) -> [StoryLinkGroup] {
        var seen = Set<String>()
        var order: [String] = []
        var byKey: [String: StoryLinkGroup] = [:]
        func put(_ key: String, _ title: String, _ l: StoryLinkInfo) {
            let k = sameURL(l.url)
            guard StoryExtra.httpsURL(l.url) != nil, !seen.contains(k) else { return }
            seen.insert(k)
            if byKey[key] == nil { byKey[key] = StoryLinkGroup(id: key, title: title, links: []); order.append(key) }
            byKey[key]?.links.append(l)
        }
        func byDay(_ src: StoryExtra, _ l: StoryLinkInfo) {
            if !l.date.isEmpty, let i = src.days.firstIndex(where: { $0.date == l.date }) {
                let dd = shortDay(src.days[i].date)
                put("d\(i)", "Day \(i + 1)" + (dd.isEmpty ? "" : " · \(dd)"), l)
            } else {
                put("trip", "Trip", l)
            }
        }
        if let post {
            if post.isFullArticle {
                for l in post.links { byDay(post, l) }
            } else {
                for l in post.links { put("post", "This post", l) }
            }
        }
        if let article { for l in article.links { byDay(article, l) } }
        func rank(_ k: String) -> Int {
            if k == "post" { return 0 }
            if k.hasPrefix("d") { return 1 + (Int(k.dropFirst()) ?? 0) }
            return 1000
        }
        return order.sorted { rank($0) < rank($1) }.compactMap { byKey[$0] }
    }

    /// host + path + query, lowercased (web sameUrl)
    static func sameURL(_ u: String) -> String {
        var t = u.trimmingCharacters(in: .whitespaces)
        if let h = t.firstIndex(of: "#") { t = String(t[..<h]) }
        guard let c = URLComponents(string: t), let host = c.host else { return t.lowercased() }
        var path = c.path
        while path.hasSuffix("/") { path.removeLast() }
        return (host + path + (c.query.map { "?" + $0 } ?? "")).lowercased()
    }

    /// "Fri, Jan 31"
    static func shortDay(_ s: String) -> String {
        guard let d = StoryExtra.ymd(s) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "EEE, MMM d"
        return f.string(from: d)
    }
}

/// A place in a post (web postPlaces): each photo/video's tagged place, then the post's own place; one row per name.
/// Map opens its Google page when it was picked from Google, else a map search of its name and town; the poster's
/// own link (booking / the place's site) shows as Book or Open.
struct StoryPlaceRow: Identifiable, Hashable {
    var id: String { name.lowercased() }
    var name: String
    var map: URL?
    var link: URL?
    var verb: String
    var photo: String

    static func rows(post: StoryPost, extra: StoryExtra?, hideLinks: Set<String> = []) -> [StoryPlaceRow] {
        var out: [StoryPlaceRow] = []
        let city = post.cityName.trimmingCharacters(in: .whitespaces).lowercased()
        let sub = post.citySub.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        let area = [post.cityName, sub].filter { !$0.isEmpty }.joined(separator: ", ")
        func add(_ raw: String, placeUrl: String, link: String, photo: String) {
            let n = raw.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { return }
            let key = n.lowercased()
            let own = StoryExtra.httpsURL(link).flatMap { hideLinks.contains(StoryLinkGroup.sameURL($0.absoluteString)) ? nil : $0 }
            if let i = out.firstIndex(where: { $0.id == key }) {
                if out[i].link == nil, let own { out[i].link = own; out[i].verb = verbFor(n) }
                if out[i].photo.isEmpty { out[i].photo = photo }
                return
            }
            if key == city && own == nil { return } // a bare city name is not a place to open
            var map = StoryExtra.httpsURL(placeUrl)
            if map == nil {
                let town = area.split(separator: ",").first.map { String($0).lowercased() } ?? ""
                let q = !area.isEmpty && !key.contains(town) ? "\(n), \(area)" : n
                var c = URLComponents(string: "https://maps.apple.com/")
                c?.queryItems = [URLQueryItem(name: "q", value: q)]
                map = c?.url
            }
            out.append(StoryPlaceRow(name: n, map: map, link: own, verb: verbFor(n), photo: photo))
        }
        for m in extra?.media ?? [] {
            add(m.placeName, placeUrl: m.placeUrl, link: m.placeLink, photo: m.small.hasPrefix("https://") ? m.small : "")
        }
        add(post.placeName, placeUrl: "", link: "", photo: "")
        return Array(out.prefix(40))
    }

    private static func verbFor(_ name: String) -> String {
        let hotelish = ["hotel", "resort", "inn", "lodge", "motel", "suites", "hostel", "cabin", "villa", "airbnb", "vrbo", "stay"]
        let words = name.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        return words.contains(where: { hotelish.contains($0) }) ? "Book" : "Open"
    }
}

/// The Links sheet (rail "Links"): the links from this post and its trip, then the places in this post.
struct InspireLinksSheet: View {
    let groups: [StoryLinkGroup]
    let places: [StoryPlaceRow]
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private var labelled: Bool { groups.count > 1 || groups.contains { $0.id.hasPrefix("d") } }

    var body: some View {
        NavigationStack {
            List {
                if !groups.isEmpty {
                    Text("Some links may earn us a commission.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(groups) { g in
                    Section {
                        ForEach(Array(g.links.enumerated()), id: \.offset) { _, l in linkRow(l) }
                    } header: {
                        if labelled && !g.title.isEmpty {
                            Text(g.title).font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary).textCase(nil)
                        } else if g.id == groups.first?.id {
                            Text(labelled ? "Links from this trip" : "Used in this post")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary).textCase(nil)
                        }
                    }
                }
                if !places.isEmpty {
                    Section {
                        ForEach(places) { placeRow($0) }
                    } header: {
                        Text("Places in this post").font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary).textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.body.weight(.semibold)).foregroundStyle(Color.navy)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private func linkRow(_ l: StoryLinkInfo) -> some View {
        Button {
            if let u = StoryExtra.httpsURL(l.url) { openURL(u) }
        } label: {
            HStack(spacing: 12) {
                if l.thumb.hasPrefix("https://") {
                    RemoteImage(url: l.thumb, maxPixel: 200)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    Image(systemName: "link")
                        .foregroundStyle(Color.navy)
                        .frame(width: 44, height: 44)
                        .hairline(radius: 9)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.label.isEmpty ? l.host : l.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !l.host.isEmpty {
                        Text(l.host).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l.label.isEmpty ? l.host : "\(l.label), \(l.host)")
    }

    private func placeRow(_ p: StoryPlaceRow) -> some View {
        HStack(spacing: 10) {
            if p.photo.hasPrefix("https://") {
                RemoteImage(url: p.photo, maxPixel: 200)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                Image(systemName: "mappin")
                    .foregroundStyle(Color.navy)
                    .frame(width: 44, height: 44)
                    .hairline(radius: 9)
            }
            Text(p.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.navy)
                .lineLimit(2)
            Spacer(minLength: 4)
            if let link = p.link {
                Button { openURL(link) } label: {
                    Text(p.verb)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Color.navy, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.verb) \(p.name)")
            }
            if let map = p.map {
                Button { openURL(map) } label: {
                    Text("Map")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .hairline(radius: 18)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.name) on the map")
            }
        }
        .frame(minHeight: 52)
    }
}
