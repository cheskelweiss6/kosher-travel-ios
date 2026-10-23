import SwiftUI

/// Get Inspired, native: Inspiration posts as a full-screen vertical swipe feed (Reels style), the same as the
/// web/Capacitor app's InspireFeed. Photos and videos fill the screen and swipe sideways; words and icons sit on the
/// photo: the place, the title, the caption, the poster with Follow and views, "Read the full article"; the right rail
/// has Like, Comment, Share, Links, Shop, Ask AI and More (Report; never on your own post).
/// Opened by StoryDetailView for any post that is not an article (Cheskel, Oct 23 2026: "instagram style like it was before").
struct InspireFeedView: View {
    let startId: String
    @Environment(StoryFeed.self) private var feed
    @Environment(AuthStore.self) private var auth
    private var store: StoriesStore { .shared }

    @State private var ids: [String] = []
    @State private var activeId: String?
    /// posts deleted from this feed by their poster or the admin
    @State private var gone: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    init(startId: String) {
        self.startId = startId
        _activeId = State(initialValue: startId)
    }

    private func postFor(_ id: String) -> StoryPost? { store.post(id) ?? feed.post(id) }

    /// Every Inspiration post, newest first as the feed has them, with the opened one always in the list.
    private func buildIds() -> [String] {
        let safety = StorySafety.shared
        var list = store.inspiration.filter { !safety.isBlocked(store.extra($0.id)?.userId ?? "") }.map(\.id)
        if list.isEmpty { list = feed.inspiration.map(\.id) }
        if !list.contains(startId) { list.insert(startId, at: 0) }
        return list
    }

    /// A deleted post leaves the feed; the next one shows, or the feed closes when it was the last.
    private func removePage(_ id: String) {
        let left = ids.filter { !gone.contains($0) && $0 != id }
        if activeId == id {
            let i = ids.firstIndex(of: id) ?? 0
            activeId = ids[(i + 1)...].first { left.contains($0) } ?? left.last
        }
        gone.insert(id)
        if left.isEmpty { dismiss() }
    }

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            let pages = ids.filter { !gone.contains($0) }.compactMap { postFor($0) }
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(pages) { p in
                        InspirePostPage(post: p, active: activeId == p.id, topInset: top, bottomInset: bottom) { id in
                            removePage(id)
                        }
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
        // only the post on screen may sound; nothing keeps playing once the feed closes
        .onDisappear { StoryVideoCenter.shared.stopAll() }
        .task(id: auth.uid ?? "") { await StorySafety.shared.load(uid: auth.uid) }
        .onChange(of: StorySafety.shared.blocked.count) { _, _ in
            // a blocked traveler's posts leave the feed at once (web blockUser)
            let fresh = buildIds()
            ids = fresh
            if let a = activeId, !fresh.contains(a) { activeId = fresh.first }
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
    /// Called once the post was deleted (the feed drops its page).
    var onDeleted: (String) -> Void = { _ in }

    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL
    private var store: StoriesStore { .shared }

    @State private var page = 0
    @State private var commentCount: Int?
    @State private var showComments = false
    @State private var showLinks = false
    @State private var showShop = false
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var editRoute: WebRoute?
    /// Every photo / video opens whole (fit) over a blurred copy; the Fit button fills the screen (web InspireFeed).
    @State private var fill = false
    @State private var ratios: [Int: Double] = [:]
    @State private var likeBusy = false
    @State private var followBusy = false
    @State private var viewed = false

    private var extra: StoryExtra? { store.extra(post.id) }
    private var ownerUid: String { extra?.userId ?? "" }
    private var mine: Bool { !ownerUid.isEmpty && ownerUid == auth.uid }
    /// the poster or the admin: Edit and Delete in the ••• menu (web canEdit / canDelete)
    private var canManage: Bool { StoryOwnerTools.canManage(ownerUid: ownerUid, auth: auth) }
    /// The post's article ("Read the full article"), when it has one: its links and places show here too.
    private var articleId: String {
        let a = extra?.linkedArticleId ?? ""
        return a == post.id ? "" : a
    }
    private var article: StoryExtra? { articleId.isEmpty ? nil : store.extra(articleId) }
    private var linkGroups: [StoryLinkGroup] { StoryLinkGroup.groups(post: extra, article: article) }
    private var placeRows: [StoryPlaceRow] { StoryPlaceRow.rows(post: post, extra: extra) }

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

    /// How far up the right rail sits (Cheskel, Oct 23 2026: "everything on the right side should be more up"):
    /// a fixed spot clear of the words, like Reels, not riding on the caption's height.
    private var railLift: CGFloat { bottomInset + 150 }

    var body: some View {
        ZStack {
            Color.navy
            mediaPager
            // words: bottom left, narrower than the screen so they never run under the rail
            words
                .padding(.leading, 16)
                .padding(.trailing, 76)
                .padding(.bottom, bottomInset + 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            // rail: right side, below the top bar and above the words; compact rather than ever reaching the top bar
            ViewThatFits(in: .vertical) {
                rail(compact: false)
                rail(compact: true)
                ScrollView { rail(compact: true) }.scrollIndicators(.hidden)
            }
            .padding(.top, topInset + 104)
            .padding(.bottom, railLift)
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .clipped()
        .onChange(of: active) { _, _ in fill = false }
        .onChange(of: page) { _, _ in fill = false }
        .task { await store.ensure(post.id) }
        .task(id: articleId) { if !articleId.isEmpty { await store.ensure(articleId) } }
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
            InspireLinksSheet(groups: linkGroups, places: placeRows)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShop) {
            InspireShopSheet(products: extra?.products ?? [])
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReport) {
            StoryReportSheet(post: post, ownerUid: ownerUid, thumb: extra?.media.first?.thumb ?? "")
        }
        .storyBlockConfirm(isPresented: $confirmBlock, name: post.authorName.isEmpty ? "this traveler" : post.authorName) {
            await blockOwner()
        }
        .storyDeleteConfirm(isPresented: $confirmDelete, article: false) { deletePost() }
        // Edit: the post editor every post is written in, opened on this post; its X or Save closes it
        .fullScreenCover(item: $editRoute, onDismiss: {
            let id = post.id
            Task { await store.reload(id) }
        }) { r in
            NavigationStack { WebScreen(route: r, fullScreen: true) }
        }
    }

    // MARK: media

    private var screenRatio: Double {
        let s = UIScreen.main.bounds.size
        return s.height > 0 ? Double(s.width / s.height) : 9.0 / 19.5
    }

    /// Fit and fill look different only when the media's shape is more than ~10% off the screen's (web differs()).
    private func differs(_ i: Int) -> Bool {
        guard let r = ratios[i], r > 0 else { return false }
        return abs(log(r / screenRatio)) > log(1.1)
    }

    /// A known shape close to the screen's just fills; otherwise the whole photo shows until Fit is tapped.
    private func fillsScreen(_ i: Int) -> Bool {
        guard ratios[i] != nil else { return false }
        return !differs(i) || fill
    }

    /// The web's samePlace(): a photo's place that only repeats the post's own place or city adds nothing.
    private func samePlace(_ name: String) -> Bool {
        let n = (name.split(separator: ",").first.map(String.init) ?? name).trimmingCharacters(in: .whitespaces).lowercased()
        return n == placeTitle.trimmingCharacters(in: .whitespaces).lowercased()
            || n == post.cityName.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func knownRatio(_ m: StoryMediaInfo) -> Double? {
        m.w > 0 && m.h > 0 ? m.w / m.h : nil
    }

    private var mediaPager: some View {
        let list = media
        let cur = list.indices.contains(page) ? list[page] : nil
        return TabView(selection: $page) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, m in
                ZStack {
                    if m.isVideo {
                        StoryVideoView(media: m, autoplay: true, active: active && i == page, fill: fillsScreen(i)) { r in
                            if ratios[i] == nil { ratios[i] = r }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggleSound(m) }
                        .accessibilityLabel("Video \(i + 1)")
                    } else {
                        StoryFitImage(url: m.still, maxPixel: 1600, fill: fillsScreen(i)) { r in
                            if ratios[i] == nil { ratios[i] = r }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if differs(i) { withAnimation(.easeOut(duration: 0.2)) { fill.toggle() } } }
                        .accessibilityLabel(m.placeName.isEmpty ? "Photo \(i + 1)" : m.placeName)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .tag(i)
                .onAppear { if ratios[i] == nil, let r = knownRatio(m) { ratios[i] = r } }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .overlay(alignment: .topLeading) {
            // where this photo was taken, when it says more than the post's own place (web PhotoPlacePill)
            if let cur, !cur.placeName.isEmpty, !samePlace(cur.placeName) {
                Label(cur.placeName, systemImage: "mappin.and.ellipse")
                    .font(.caption.weight(.semibold))
                    .labelStyle(StoryTightLabelStyle())
                    .lineLimit(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(.leading, 12)
                    .padding(.trailing, 112)
                    .padding(.top, topInset + 72)
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
                .padding(.top, topInset + 52)
                .shadow(color: .black.opacity(0.4), radius: 2)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            // sound and fit / fill, under the top bar across from Back, away from the rail
            HStack(spacing: 8) {
                if let cur, cur.isVideo, !cur.url.isEmpty, !cur.muted {
                    glassIcon(StoryVideoSound.shared.on ? "speaker.wave.2" : "speaker.slash",
                              a11y: StoryVideoSound.shared.on ? "Sound off" : "Sound on") { toggleSound(cur) }
                }
                if differs(page) {
                    glassIcon(fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                              a11y: fill ? "Show the whole \(cur?.isVideo == true ? "video" : "photo")" : "Fill the screen") {
                        withAnimation(.easeOut(duration: 0.2)) { fill.toggle() }
                    }
                }
            }
            .padding(.trailing, 10)
            .padding(.top, topInset + 48)
        }
    }

    private func glassIcon(_ symbol: String, a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .glassRounded(20)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        .accessibilityLabel(a11y)
    }

    /// Tap on a video (or the speaker): sound on / off for every video, like the web; a video the poster muted stays silent.
    private func toggleSound(_ m: StoryMediaInfo) {
        guard !m.muted else { return }
        StoryVideoSound.shared.on.toggle()
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
        // white words straight on the photo, readable on bright sand or snow too (web SHADOW: two soft shadows)
        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        .shadow(color: .black.opacity(0.35), radius: 12)
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

    private func rail(compact: Bool) -> some View {
        let liked = auth.uid.map { extra?.likedUserIds.contains($0) ?? false } ?? false
        let likes = extra?.likesCount ?? post.likesCount
        let linkCount = linkGroups.reduce(0) { $0 + $1.links.count } + placeRows.count
        let products = extra?.products ?? []
        return VStack(spacing: compact ? 2 : 8) {
            railButton(label: likes > 0 ? "\(likes)" : "Like", a11y: liked ? "Unlike" : "Like", compact: compact) {
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

            railButton(label: (commentCount ?? 0) > 0 ? "\(commentCount ?? 0)" : "Comment", a11y: "Comments", compact: compact) {
                showComments = true
            } icon: {
                Image(systemName: "bubble.right").foregroundStyle(.white)
            }

            ShareLink(item: StoryActions.shareURL(post.id), subject: Text(placeTitle)) {
                railFace(label: "Share", compact: compact) { Image(systemName: "square.and.arrow.up").foregroundStyle(.white) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Share")

            if linkCount > 0 {
                railButton(label: "Links", a11y: "Links: \(linkCount) \(linkCount == 1 ? "link or place" : "links and places") in this post", compact: compact) {
                    showLinks = true
                } icon: {
                    Image(systemName: "link").foregroundStyle(.white)
                }
            }
            if !products.isEmpty {
                railButton(label: "Shop", a11y: "Shop \(products.count) \(products.count == 1 ? "product" : "products")", compact: compact) {
                    showShop = true
                } icon: {
                    Image(systemName: "bag").foregroundStyle(.white)
                }
            }
            railButton(label: "Ask AI", a11y: "Ask AI about this place", compact: compact) {
                StoryVideoCenter.shared.stopAll()
                ShellRouter.shared.open(tab: "planner", prompt: askPrompt)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(.white)
            }
            moreMenu
        }
        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
    }

    /// ••• : a menu right at the button (not a sheet at the top of the screen). The poster and the admin get Edit and
    /// Delete (red, asks first); anyone else's post gets Report and Block (web InspireFeed "more" sheet + SafetyUI).
    @ViewBuilder
    private var moreMenu: some View {
        if !mine || canManage {
            Menu {
                if canManage {
                    StoryOwnerMenuItems(article: false) {
                        StoryVideoCenter.shared.stopAll()
                        editRoute = StoryOwnerTools.editRoute(post.id, article: false)
                    } onDelete: {
                        confirmDelete = true
                    }
                }
                if !mine {
                Button {
                    if auth.isSignedIn { showReport = true } else {
                        ShellRouter.shared.requireSignIn("Sign in to report a post.") { showReport = true }
                    }
                } label: {
                    Label("Report this post", systemImage: "flag")
                }
                if !ownerUid.isEmpty {
                    Button {
                        if auth.isSignedIn { confirmBlock = true } else {
                            ShellRouter.shared.requireSignIn("Sign in to block a traveler.") { confirmBlock = true }
                        }
                    } label: {
                        Label("Block \(post.authorName.isEmpty ? "this traveler" : post.authorName)", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .accessibilityLabel("More")
        }
    }

    private func railFace<I: View>(label: String, compact: Bool, @ViewBuilder icon: () -> I) -> some View {
        VStack(spacing: compact ? 1 : 3) {
            icon()
                .font(.system(size: compact ? 23 : 26, weight: .regular))
                .frame(width: 44, height: compact ? 34 : 40)
            Text(label)
                .font(.system(size: compact ? 10.5 : 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .frame(minWidth: 52, minHeight: 44)
        .contentShape(Rectangle())
    }

    private func railButton<I: View>(label: String, a11y: String, compact: Bool, action: @escaping () -> Void, @ViewBuilder icon: () -> I) -> some View {
        let face = railFace(label: label, compact: compact, icon: icon)
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
    private func deletePost() {
        guard !deleting else { return }
        deleting = true
        StoryVideoCenter.shared.stopAll()
        let id = post.id
        let ex = extra
        Task {
            let ok = await StoryOwnerTools.delete(postId: id, extra: ex)
            deleting = false
            if ok {
                store.remove(id)
                onDeleted(id)
                ShellRouter.shared.showToast("Post deleted")
            } else {
                ShellRouter.shared.showToast("Couldn't delete it. Check your connection and try again.")
            }
        }
    }

    @MainActor
    private func blockOwner() async {
        guard let actor = StoryActor.from(auth) else { return }
        let name = post.authorName.isEmpty ? "this traveler" : post.authorName
        if await StorySafety.shared.block(me: actor, uid: ownerUid, name: post.authorName, photo: post.authorPhoto) {
            ShellRouter.shared.showToast("\(name) is blocked.")
        } else {
            ShellRouter.shared.showToast("Couldn't block. Try again.")
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
