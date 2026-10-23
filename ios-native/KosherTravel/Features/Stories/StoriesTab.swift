import SwiftUI

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
                    Button { webCover = .compose() } label: {
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
            .task(id: auth.uid) { await store.syncAccount(uid: auth.uid) }
        }
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
                if auth.isSignedIn {
                    StoryChip(title: "Following", systemImage: "person.badge.plus", selected: followingOnly) {
                        followingOnly.toggle()
                    }
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
