import SwiftUI

/// A traveler's public page: photo, name, followers, Follow, and all their live posts (articles, then photos/videos).
struct TravelerView: View {
    let uid: String
    let name: String
    let photo: String

    @Environment(AuthStore.self) private var auth
    private var store: StoriesStore { .shared }
    @State private var followers: Int?
    @State private var loading = true
    @State private var failed = false
    @State private var busy = false
    @State private var signInPrompt: String?

    init(uid: String, name: String, photo: String) {
        self.uid = uid
        self.name = name
        self.photo = photo
    }

    private var posts: [StoryPost] { store.posts(by: uid) }
    private var displayName: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        return posts.first?.authorName ?? "Traveler"
    }
    private var storedPhoto: String { photo.isEmpty ? (posts.first?.authorPhoto ?? "") : photo }

    var body: some View {
        let list = posts
        let articles = list.filter { store.isArticle($0) }
        let quick = list.filter { !store.isArticle($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(articles: articles.count, quick: quick.count)
                if loading && list.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 20)
                } else if list.isEmpty {
                    EmptyNote(title: failed ? "Posts could not load" : "No posts yet",
                              detail: failed ? "Pull down to try again." : nil,
                              systemImage: "photo.on.rectangle")
                        .padding(.horizontal, Theme.pagePadding)
                }
                if !articles.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Articles", count: articles.count)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 20, alignment: .top)], alignment: .leading, spacing: 24) {
                            ForEach(articles) { p in
                                NavigationLink { StoryDetailView(postId: p.id) } label: {
                                    StoryArticleCard(post: p, extra: store.extra(p.id), myUid: auth.uid)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
                if !quick.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Photos and videos", count: quick.count)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)], alignment: .leading, spacing: 20) {
                            ForEach(quick) { p in
                                NavigationLink { StoryDetailView(postId: p.id) } label: {
                                    StoryInspirationTile(post: p, extra: store.extra(p.id), myUid: auth.uid)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.white)
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: travelerURL) { Image(systemName: "square.and.arrow.up") }
                    .accessibilityLabel("Share")
            }
        }
        .refreshable { await reload() }
        .task { await reload() }
        .task(id: auth.uid) { await store.syncAccount(uid: auth.uid) }
        .alert("Sign in", isPresented: Binding(get: { signInPrompt != nil }, set: { if !$0 { signInPrompt = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInPrompt ?? "")
        }
    }

    /// The web's shared traveler link (?map=<uid>).
    private var travelerURL: URL {
        var c = URLComponents(string: "https://www.yourkoshertravel.com/")!
        c.queryItems = [URLQueryItem(name: "map", value: uid)]
        return c.url!
    }

    private func header(articles: Int, quick: Int) -> some View {
        VStack(spacing: 12) {
            TravelerAvatar(uid: uid, stored: storedPhoto, name: displayName, size: 92)
            Text(displayName)
                .font(.serifTitle(.title2))
                .foregroundStyle(Color.navy)
                .multilineTextAlignment(.center)
            HStack(spacing: 28) {
                stat(followers.map { "\($0)" } ?? "–", followers == 1 ? "Follower" : "Followers")
                stat("\(articles)", articles == 1 ? "Article" : "Articles")
                stat("\(quick)", quick == 1 ? "Post" : "Posts")
            }
            if uid != auth.uid {
                StoryFollowPill(following: store.following.contains(uid), busy: busy, action: toggleFollow)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Theme.pagePadding)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(Color.navy)
            Text(label).font(.caption).foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func reload() async {
        async let ok = store.loadAuthor(uid)
        async let n = StoryActions.followerCount(uid)
        let (loaded, count) = await (ok, n)
        failed = !loaded
        if let count { followers = count }
        loading = false
        store.requestPhoto(uid)
    }

    private func toggleFollow() {
        guard let actor = StoryActor.from(auth) else { signInPrompt = "Sign in on the Profile tab to follow travelers."; return }
        let was = store.following.contains(uid)
        store.setFollowing(uid, !was)
        if let f = followers { followers = max(0, f + (was ? -1 : 1)) }
        busy = true
        Task {
            let ok = await StoryActions.setFollow(actor: actor, target: uid, targetName: displayName,
                                                  targetPhoto: store.photo(uid: uid, stored: storedPhoto), on: !was)
            busy = false
            if !ok {
                store.setFollowing(uid, was)
                if let f = followers { followers = max(0, f + (was ? 1 : -1)) }
            }
        }
    }
}
