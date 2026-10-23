import SwiftUI
import FirebaseFirestore

/// Stories tab: the live traveler feed (Articles / Inspiration, All / Following, tags), like the web's Stories tab.
struct StoriesTab: View {
    @Environment(AuthStore.self) private var auth
    private var store: StoriesStore { .shared }
    @State private var path: [StoriesRoute] = []
    @State private var showArticles = false   // web: "Get Inspired" is the first, selected segment
    @State private var followingOnly = false
    @State private var tag = "All"
    @State private var appliedRoute = false
    /// The composer is still the live screen, full screen with its own X (Get Inspired is pushed: StoriesRoute.web).
    @State private var webCover: WebRoute?
    @State private var composing = false   // the native chooser + composer (NATIVE-COMPOSER)

    private static let tags = ["Shabbos", "Food", "Shul", "Family", "Nature", "Beach", "Hotels", "Yom Tov", "Cruise", "Tips"]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Show", selection: $showArticles) {
                        Text("Get Inspired").tag(false)
                        Text("Articles").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.pagePadding)
                    .sensoryFeedback(.selection, trigger: showArticles)

                    // Cheskel (Oct 23 2026): "instead of a Following button should be like Instagram, the profiles of
                    // who I am following": round faces, a navy ring when they posted since you last looked
                    if auth.isSignedIn, let me = auth.uid {
                        StoryFollowingFaces(myUid: me) { person in
                            path.append(.traveler(uid: person.uid, name: person.name, photo: person.photo))
                        }
                    }
                    chips
                    content
                }
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
            .background(Color.white)
            .navigationTitle("Stories")
            .toolbar {
                // Cheskel (Oct 23 2026): "the top left button should be to add posts" (the web's Share: new story composer)
                ToolbarItem(placement: .topBarLeading) {
                    Button { composing = true } label: {
                        Label("Share", systemImage: "plus")
                    }
                    .accessibilityLabel("Share your story")
                    .accessibilityIdentifier("stories-share")
                }
                ToolbarItem(placement: .topBarTrailing) { AccountToolbarButtons() }
            }
            .navigationDestination(for: StoriesRoute.self) { route in
                switch route {
                case .post(let id): StoryDetailView(postId: id)
                case .traveler(let uid, let name, let photo): TravelerView(uid: uid, name: name, photo: photo)
                case .web(let r): WebScreen(route: r)
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.loadIfNeeded() }
            .task(id: auth.uid) {
                await store.syncAccount(uid: auth.uid)
                await StorySafety.shared.load(uid: auth.uid)
            }
        }
        .composeFlow(isPresented: $composing)
        .fullScreenCover(item: $webCover) { r in
            NavigationStack { WebScreen(route: r, fullScreen: true) }
        }
        .onAppear(perform: applyLaunchRoute)
        .onChange(of: auth.isSignedIn) { _, signedIn in if !signedIn { followingOnly = false } }
    }

    // MARK: filters

    private var usedTags: [String] {
        let present = Set(store.posts.flatMap { store.extra($0.id)?.tags ?? [] })
        return Self.tags.filter { present.contains($0) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StoryChip(title: "All", selected: !followingOnly && tag == "All") {
                    followingOnly = false
                    tag = "All"
                }
                if followingOnly {
                    // only reachable from the QA route tab:stories/following now; the faces row replaced the chip
                    StoryChip(title: "Following", systemImage: "person.badge.plus", selected: true) { followingOnly = false }
                }
                if !usedTags.isEmpty {
                    Rectangle().fill(Color.hairline).frame(width: 1, height: 22)
                    ForEach(usedTags, id: \.self) { t in
                        StoryChip(title: t, selected: tag == t) { tag = (tag == t) ? "All" : t }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
        .sensoryFeedback(.selection, trigger: followingOnly)
    }

    private var list: [StoryPost] {
        let base = showArticles ? store.articles : store.inspiration
        return base.filter { p in
            let ex = store.extra(p.id)
            // a blocked traveler's posts stay hidden (web blockUser)
            if StorySafety.shared.isBlocked(ex?.userId ?? "") { return false }
            if tag != "All" && !(ex?.tags.contains(tag) ?? false) { return false }
            if followingOnly {
                guard let author = ex?.userId, !author.isEmpty else { return false }
                return store.following.contains(author)
            }
            return true
        }
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        let items = list
        if !store.loadedOnce && items.isEmpty {
            VStack(spacing: 16) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Color.surface)
                        .aspectRatio(16 / 10, contentMode: .fit)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .accessibilityLabel("Loading")
        } else if let msg = store.errorMessage, items.isEmpty {
            FeedStatusLine(message: msg)
                .padding(.horizontal, Theme.pagePadding)
        } else if items.isEmpty {
            emptyNote
                .padding(.horizontal, Theme.pagePadding)
        } else if showArticles {
            // one column on iPhone, more on iPad (cards keep a readable width)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 20, alignment: .top)], alignment: .leading, spacing: 28) {
                ForEach(items) { post in
                    NavigationLink(value: StoriesRoute.post(post.id)) {
                        StoryArticleCard(post: post, extra: store.extra(post.id), myUid: auth.uid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)], alignment: .leading, spacing: 20) {
                ForEach(items) { post in
                    NavigationLink(value: StoriesRoute.post(post.id)) {
                        StoryInspirationTile(post: post, extra: store.extra(post.id), myUid: auth.uid)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
    }

    @ViewBuilder
    private var emptyNote: some View {
        if followingOnly {
            EmptyNote(title: "Nothing from people you follow yet",
                      detail: "Tap Follow on a traveler's post or page to see their stories here.",
                      systemImage: "person.badge.plus")
        } else if tag != "All" {
            EmptyNote(title: "No \(showArticles ? "articles" : "posts") tagged \(tag) yet", systemImage: "tag")
        } else {
            EmptyNote(title: showArticles ? "No articles yet" : "No photos from travelers yet",
                      detail: "Travelers' trips show here as soon as they are posted.",
                      systemImage: "photo.on.rectangle")
        }
    }

    // MARK: QA deep links: tab:stories[/inspiration|/articles|/following|/post:<id>[/comments]|/traveler:<uid>]

    private func applyLaunchRoute() {
        guard !appliedRoute else { return }
        appliedRoute = true
        guard let r = LaunchRoute.current, r.hasPrefix("tab:stories/") else { return }
        let rest = String(r.dropFirst("tab:stories/".count))
        if rest == "inspiration" { showArticles = false }
        else if rest == "articles" { showArticles = true }
        else if rest == "following" { followingOnly = true }
        else if rest.hasPrefix("post:") {
            let id = rest.dropFirst(5).split(separator: "/").first.map(String.init) ?? ""
            if !id.isEmpty { path = [.post(id)] }
        } else if rest.hasPrefix("traveler:") {
            let uid = String(rest.dropFirst(9))
            if !uid.isEmpty { path = [.traveler(uid: uid, name: "", photo: "")] }
        }
    }
}

/// Instagram-style row of the travelers you follow: round photos with names, scrolling sideways. A navy ring when
/// they posted since you last opened them, a thin grey ring when seen. Hidden when you follow nobody.
/// Data: users/{me}/following/{uid} { name, photo, createdAt } (the same documents the Follow button writes), with
/// each traveler's current photo and newest post from the live feed.
struct StoryFollowingFaces: View {
    let myUid: String
    var open: (Person) -> Void
    private var store: StoriesStore { .shared }

    struct Person: Identifiable, Hashable {
        var uid: String
        var name: String
        var photo: String
        var followedAtMs: Double
        var id: String { uid }
    }

    @State private var people: [Person] = []
    @State private var seen: [String: Double] = [:]

    private static func seenKey(_ me: String) -> String { "kt.following.seen.\(me)" }

    private func newestPostMs(_ uid: String) -> Double {
        store.posts(by: uid).map(\.createdAtMs).max() ?? 0
    }

    private func hasNew(_ p: Person) -> Bool {
        let newest = newestPostMs(p.uid)
        guard newest > 0 else { return false }
        return newest > (seen[p.uid] ?? p.followedAtMs)
    }

    /// Only people you still follow (the store's live list), new posts first, then the most recent poster.
    private var ordered: [Person] {
        let live = store.following
        let list = people.filter { live.contains($0.uid) && !StorySafety.shared.isBlocked($0.uid) }
        return list.sorted { a, b in
            let na = hasNew(a), nb = hasNew(b)
            if na != nb { return na }
            return newestPostMs(a.uid) > newestPostMs(b.uid)
        }
    }

    var body: some View {
        let list = ordered
        // a VStack, not a Group, so the load still runs while the row is empty
        VStack(spacing: 0) {
            if !list.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(list) { p in
                            Button {
                                markSeen(p.uid)
                                open(p)
                            } label: {
                                face(p, fresh: hasNew(p))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(p.name)\(hasNew(p) ? ", new posts" : "")")
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.vertical, 2)
                }
                .accessibilityLabel("People you follow")
            }
        }
        .task(id: myUid + "|\(store.following.count)") { await load() }
    }

    private func face(_ p: Person, fresh: Bool) -> some View {
        VStack(spacing: 6) {
            TravelerAvatar(uid: p.uid, stored: p.photo, name: p.name, size: 58)
                .padding(3)
                .overlay(Circle().strokeBorder(fresh ? Color.navy : Color.hairline, lineWidth: fresh ? 2.5 : 1))
            Text(p.name)
                .font(.caption)
                .foregroundStyle(fresh ? Color.navy : Color.textSecondary)
                .fontWeight(fresh ? .semibold : .regular)
                .lineLimit(1)
                .frame(width: 70)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
    }

    private func markSeen(_ uid: String) {
        let now = Date().timeIntervalSince1970 * 1000
        seen[uid] = max(now, newestPostMs(uid))
        UserDefaults.standard.set(seen, forKey: Self.seenKey(myUid))
    }

    @MainActor
    private func load() async {
        seen = (UserDefaults.standard.dictionary(forKey: Self.seenKey(myUid)) as? [String: Double]) ?? [:]
        guard FirebaseBoot.isConfigured else { return }
        do {
            let snap = try await Firestore.firestore().collection("users").document(myUid).collection("following")
                .limit(to: 300).getDocuments()
            people = snap.documents.map { d in
                let x = d.data()
                let fromPosts = store.posts(by: d.documentID).first
                var name = (x["name"] as? String) ?? ""
                if name.isEmpty { name = fromPosts?.authorName ?? "Traveler" }
                let photo = (x["photo"] as? String) ?? fromPosts?.authorPhoto ?? ""
                let at = (x["createdAt"] as? Timestamp)?.dateValue().timeIntervalSince1970 ?? 0
                return Person(uid: d.documentID, name: name, photo: photo, followedAtMs: at * 1000)
            }
        } catch {
            print("[KT] following list not read: \(error)")
        }
    }
}
