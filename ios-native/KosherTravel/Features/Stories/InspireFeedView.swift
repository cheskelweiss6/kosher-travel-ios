import SwiftUI

/// Get Inspired, native: Inspiration posts as a full-screen vertical swipe feed (Reels style), the same as the
/// web/Capacitor app's InspireFeed. Photos and videos fill the screen and swipe sideways; words and icons sit on the
/// photo: the place, the title, the caption, the poster with Follow and views, "Read the full article"; the right rail
/// has Like, Comment, Share, Links, Shop, Ask AI and More (Report; never on your own post).
/// Opened by StoryDetailView for any post that is not an article (Cheskel, Oct 23 2026: "instagram style like it was before").
struct InspireFeedView: View {
    let startId: String
    @Environment(StoryFeed.self) private var feed
    private var store: StoriesStore { .shared }

    @State private var ids: [String] = []
    @State private var activeId: String?

    init(startId: String) {
        self.startId = startId
        _activeId = State(initialValue: startId)
    }

    private func postFor(_ id: String) -> StoryPost? { store.post(id) ?? feed.post(id) }

    /// Every Inspiration post, newest first as the feed has them, with the opened one always in the list.
    private func buildIds() -> [String] {
        var list = store.inspiration.map(\.id)
        if list.isEmpty { list = feed.inspiration.map(\.id) }
        if !list.contains(startId) { list.insert(startId, at: 0) }
        return list
    }

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            let pages = ids.compactMap { postFor($0) }
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(pages) { p in
                        InspirePostPage(post: p, active: activeId == p.id, topInset: top, bottomInset: bottom)
                            .containerRelativeFrame([.horizontal, .vertical])
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $activeId)
            .scrollIndicators(.hidden)
            .ignoresSafeArea()
        }
        .background(Color.navy.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Get Inspired")
                    .font(.serifTitle(.headline))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            }
        }
        .onAppear {
            if ids.isEmpty { ids = buildIds() }
            if activeId == nil { activeId = startId }
        }
        .task {
            await store.loadIfNeeded()
            let fresh = buildIds()
            if fresh != ids {
                ids = fresh
                activeId = activeId ?? startId
            }
        }
    }
}

/// One post of the feed (one full screen).
struct InspirePostPage: View {
    let post: StoryPost
    let active: Bool
    let topInset: CGFloat
    let bottomInset: CGFloat

    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL
    private var store: StoriesStore { .shared }

    @State private var page = 0
    @State private var commentCount: Int?
    @State private var showComments = false
    @State private var showLinks = false
    @State private var showShop = false
    @State private var showMore = false
    @State private var askReport = false
    @State private var likeBusy = false
    @State private var followBusy = false
    @State private var viewed = false

    private var extra: StoryExtra? { store.extra(post.id) }
    private var ownerUid: String { extra?.userId ?? "" }
    private var mine: Bool { !ownerUid.isEmpty && ownerUid == auth.uid }

    private var media: [StoryMediaInfo] {
        if let ex = extra, !ex.media.isEmpty { return ex.media }
        return post.media.map {
            StoryMediaInfo(type: $0.type, url: $0.url, thumb: $0.thumb, w: 0, h: 0, muted: false, trimStart: nil, trimEnd: nil,
                           placeName: "", placeLink: "", placeUrl: "")
        }
    }

    /// The web's inspirePlace(): the tagged place, else the title, else the city.
    private var placeTitle: String {
        let n = post.placeName.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { return n }
        return post.title.isEmpty ? post.cityName : post.title
    }

    /// The web's cityLine(): "Glenwood Springs, Colorado".
    private var cityLine: String {
        let sub = post.citySub.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return [post.cityName, sub].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var body: some View {
        ZStack {
            Color.navy
            mediaPager
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 8) {
                    words
                    rail
                }
                .padding(.leading, 16)
                .padding(.trailing, 6)
                .padding(.bottom, bottomInset + 20)
            }
        }
        .clipped()
        .task { await store.ensure(post.id) }
        .task(id: active) {
            guard active else { return }
            if commentCount == nil { commentCount = await CommentsService.count(post.id) }
            if !viewed, let ex = extra ?? store.extra(post.id) {
                viewed = true
                if await StoryActions.recordView(post: post, extra: ex, uid: auth.uid) { store.applyView(postId: post.id) }
            }
        }
        .sheet(isPresented: $showComments) {
            CommentsSheet(post: post, ownerUid: ownerUid, thumb: extra?.media.first?.thumb ?? "") { n in
                commentCount = n
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLinks) {
            InspireLinksSheet(links: extra?.links ?? [])
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShop) {
            InspireShopSheet(products: extra?.products ?? [])
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("", isPresented: $showMore, titleVisibility: .hidden) {
            if !mine {
                Button("Report this post") {
                    if auth.isSignedIn { askReport = true } else {
                        ShellRouter.shared.requireSignIn("Sign in to report a post.") { askReport = true }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Report this post?", isPresented: $askReport, titleVisibility: .visible) {
            ForEach(["Inappropriate photo", "Not kosher / wrong info", "Spam or ads", "Something else"], id: \.self) { reason in
                Button(reason) { report(reason) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The team checks every report.")
        }
    }

    // MARK: media

    private var mediaPager: some View {
        let list = media
        return TabView(selection: $page) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, m in
                ZStack {
                    if m.isVideo {
                        StoryVideoView(media: m, autoplay: active && i == page)
                    } else {
                        RemoteImage(url: m.still, maxPixel: 1600)
                            .accessibilityLabel(m.placeName.isEmpty ? "Photo \(i + 1)" : m.placeName)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay(alignment: .topTrailing) {
            // every photo says where it is (its own place), under the top bar
            if list.indices.contains(page), !list[page].placeName.isEmpty {
                Label(list[page].placeName, systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .labelStyle(StoryTightLabelStyle())
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.trailing, 12)
                    .padding(.top, topInset + 10)
                    .padding(.leading, 80)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if list.count > 1 {
                HStack(spacing: 5) {
                    ForEach(0..<min(list.count, 12), id: \.self) { i in
                        Capsule()
                            .fill(i == min(page, 11) ? Color.white : Color.white.opacity(0.55))
                            .frame(width: i == min(page, 11) ? 18 : 6, height: 6)
                    }
                }
                .padding(.top, topInset + 46)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: words (bottom left)

    private var words: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !cityLine.isEmpty {
                Label(cityLine, systemImage: "mappin")
                    .labelStyle(StoryTightLabelStyle())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            Text(placeTitle)
                .font(.system(size: 23, weight: .bold, design: .serif))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(2)
            }
            authorLine.padding(.top, 4)
            if let linked = extra?.linkedArticleId, !linked.isEmpty, linked != post.id {
                NavigationLink {
                    StoryDetailView(postId: linked)
                } label: {
                    HStack(spacing: 4) {
                        Text("Read the full article").lineLimit(1)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .padding(.leading, 14)
                    .padding(.trailing, 10)
                    .frame(height: 36)
                    .background(Color.white, in: Capsule())
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .accessibilityLabel("Read the full article")
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var authorLine: some View {
        HStack(spacing: 8) {
            if ownerUid.isEmpty {
                authorLabel
            } else {
                NavigationLink {
                    TravelerView(uid: ownerUid, name: post.authorName, photo: post.authorPhoto)
                } label: {
                    authorLabel
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(post.authorName)'s profile")
            }
            let views = extra?.viewsCount ?? post.viewsCount
            Label("\(views)", systemImage: "eye")
                .labelStyle(StoryTightLabelStyle())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize()
                .accessibilityLabel("\(views) views")
            if !ownerUid.isEmpty && !mine {
                StoryFollowPill(following: store.following.contains(ownerUid), busy: followBusy) {
                    toggleFollow()
                }
                .fixedSize()
            }
        }
    }

    private var authorLabel: some View {
        HStack(spacing: 8) {
            TravelerAvatar(uid: ownerUid, stored: post.authorPhoto, name: post.authorName, size: 28)
            Text(post.authorName)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            let ago = TimeAgo.string(post.createdAtMs)
            if !ago.isEmpty {
                Text("· \(ago)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize()
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: rail (right)

    private var rail: some View {
        let liked = auth.uid.map { extra?.likedUserIds.contains($0) ?? false } ?? false
        let likes = extra?.likesCount ?? post.likesCount
        let links = extra?.links ?? []
        let products = extra?.products ?? []
        return VStack(spacing: 8) {
            railButton(label: likes > 0 ? "\(likes)" : "Like", a11y: liked ? "Unlike" : "Like") {
                toggleLike()
            } icon: {
                Group {
                    if liked {
                        Image(systemName: "heart.fill").foregroundStyle(Color.alert)
                    } else {
                        Image(systemName: "heart").foregroundStyle(.white)
                    }
                }
                .symbolEffect(.bounce, value: liked)
            }
            .sensoryFeedback(.impact(weight: .light), trigger: liked)

            railButton(label: (commentCount ?? 0) > 0 ? "\(commentCount ?? 0)" : "Comment", a11y: "Comments") {
                showComments = true
            } icon: {
                Image(systemName: "bubble.right").foregroundStyle(.white)
            }

            ShareLink(item: StoryActions.shareURL(post.id), subject: Text(placeTitle)) {
                railFace(label: "Share") { Image(systemName: "square.and.arrow.up").foregroundStyle(.white) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")

            if !links.isEmpty {
                railButton(label: "Links", a11y: "Links: \(links.count) \(links.count == 1 ? "link" : "links") in this post") {
                    showLinks = true
                } icon: {
                    Image(systemName: "link").foregroundStyle(.white)
                }
            }
            if !products.isEmpty {
                railButton(label: "Shop", a11y: "Shop \(products.count) \(products.count == 1 ? "product" : "products")") {
                    showShop = true
                } icon: {
                    Image(systemName: "bag").foregroundStyle(.white)
                }
            }
            railButton(label: "Ask AI", a11y: "Ask AI about this place") {
                ShellRouter.shared.open(tab: "planner", prompt: askPrompt)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(.white)
            }
            Button { showMore = true } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
    }

    private func railFace<I: View>(label: String, @ViewBuilder icon: () -> I) -> some View {
        VStack(spacing: 3) {
            icon()
                .font(.system(size: 26, weight: .regular))
                .frame(width: 44, height: 40)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(minWidth: 52)
        .contentShape(Rectangle())
    }

    private func railButton<I: View>(label: String, a11y: String, action: @escaping () -> Void, @ViewBuilder icon: () -> I) -> some View {
        let face = railFace(label: label, icon: icon)
        return Button(action: action) {
            face
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
    }

    /// The web's askAiPrompt(place, city).
    private var askPrompt: String {
        var seen: [String] = []
        for x in [placeTitle, post.cityName] {
            let t = x.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && !seen.contains(where: { $0.lowercased() == t.lowercased() }) { seen.append(t) }
        }
        return "Tell me about \(seen.joined(separator: ", ")) — kosher food, shuls nearby, tips"
    }

    // MARK: actions (same as the post page)

    @MainActor
    private func toggleLike() {
        guard let actor = StoryActor.from(auth) else { ShellRouter.shared.requireSignIn("Sign in to like posts.") { toggleLike() }; return }
        guard !likeBusy else { return }
        let ex = extra
        let was = ex?.likedUserIds.contains(actor.uid) ?? false
        let count = ex?.likesCount ?? post.likesCount
        store.applyLike(postId: post.id, uid: actor.uid, on: !was, count: count + (was ? -1 : 1))
        likeBusy = true
        let p = post
        Task {
            let r = await StoryActions.setLike(post: p, extra: ex, actor: actor, on: !was)
            likeBusy = false
            if let r {
                store.applyLike(postId: p.id, uid: actor.uid, on: r.on, count: r.count)
            } else {
                store.applyLike(postId: p.id, uid: actor.uid, on: was, count: count)
                ShellRouter.shared.showToast("Your like wasn't saved. Try again.")
            }
        }
    }

    @MainActor
    private func toggleFollow() {
        let uid = ownerUid
        guard !uid.isEmpty else { return }
        guard let actor = StoryActor.from(auth) else { ShellRouter.shared.requireSignIn("Sign in to follow travelers.") { toggleFollow() }; return }
        let was = store.following.contains(uid)
        store.setFollowing(uid, !was)
        followBusy = true
        let name = post.authorName
        let photo = store.photo(uid: uid, stored: post.authorPhoto)
        Task {
            let ok = await StoryActions.setFollow(actor: actor, target: uid, targetName: name, targetPhoto: photo, on: !was)
            followBusy = false
            if !ok {
                store.setFollowing(uid, was)
                ShellRouter.shared.showToast("Couldn't change it. Try again.")
            }
        }
    }

    @MainActor
    private func report(_ reason: String) {
        guard let uid = auth.uid else { ShellRouter.shared.requireSignIn("Sign in to report a post.") { report(reason) }; return }
        let id = post.id
        Task {
            switch await StoryActions.reportPost(id, reason: reason, uid: uid) {
            case .ok: ShellRouter.shared.showToast("Thanks. The team will check it.")
            case .already: ShellRouter.shared.showToast("You already reported this post.")
            case .failed: ShellRouter.shared.showToast("The report wasn't sent. Try again.")
            }
        }
    }
}

/// The post's links (rail "Links").
struct InspireLinksSheet: View {
    let links: [StoryLinkInfo]
    @Environment(\.openURL) private var openURL
    var body: some View {
        NavigationStack {
            List(Array(links.enumerated()), id: \.offset) { _, l in
                Button {
                    if let u = URL(string: l.url) { openURL(u) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "link")
                            .foregroundStyle(Color.navy)
                            .frame(width: 32, height: 32)
                            .hairline(radius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(l.label.isEmpty ? l.host : l.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.navy)
                                .lineLimit(2)
                            if !l.host.isEmpty {
                                Text(l.host).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Links")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The post's products (rail "Shop").
struct InspireShopSheet: View {
    let products: [StoryProductInfo]
    @Environment(\.openURL) private var openURL
    var body: some View {
        NavigationStack {
            List(Array(products.enumerated()), id: \.offset) { _, pr in
                Button {
                    if let u = URL(string: pr.url) { openURL(u) }
                } label: {
                    HStack(spacing: 12) {
                        RemoteImage(url: pr.img, maxPixel: 200)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.navy)
                                .lineLimit(2)
                            if !pr.price.isEmpty {
                                Text(pr.price).font(.footnote).foregroundStyle(Color.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Shop")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
