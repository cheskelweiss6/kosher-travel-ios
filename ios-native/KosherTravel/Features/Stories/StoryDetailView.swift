import SwiftUI

/// A traveler's post, native: paged photos and videos (or the article's cover), author with Follow, like / comment /
/// save / share, the caption or intro, the trip day by day with tagged places, links and products.
/// Opened from the Stories feed, a traveler page, or Explore (`StoryDetailView(postId:)`).
struct StoryDetailView: View {
    let postId: String
    @Environment(StoryFeed.self) private var feed
    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL
    private var store: StoriesStore { .shared }

    @State private var page = 0
    @State private var viewer: ViewerStart?
    @State private var showComments = false
    @State private var commentCount: Int?
    @State private var likeBusy = false
    @State private var saveBusy = false
    @State private var followBusy = false
    @State private var signInPrompt: String?
    @State private var note: String?
    @State private var askReport = false
    @State private var confirmBlock = false
    @State private var loading = true
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var editRoute: WebRoute?
    @Environment(\.dismiss) private var dismiss

    struct ViewerStart: Identifiable {
        let id = UUID()
        let index: Int
    }

    init(postId: String) {
        self.postId = postId
    }

    private var post: StoryPost? { store.post(postId) ?? feed.post(postId) }
    private var extra: StoryExtra? { store.extra(postId) }

    /// The post's media with the poster's settings (falls back to the basic list while the full document loads).
    private func mediaList(_ p: StoryPost) -> [StoryMediaInfo] {
        if let ex = extra, !ex.media.isEmpty { return ex.media }
        return p.media.map {
            StoryMediaInfo(type: $0.type, url: $0.url, thumb: $0.thumb, w: 0, h: 0, muted: false, trimStart: nil, trimEnd: nil,
                      placeName: "", placeLink: "", placeUrl: "")
        }
    }

    var body: some View {
        Group {
            if let p = post {
                // Inspiration posts open in the full-screen Get Inspired feed (Reels style), like the web/Capacitor app;
                // articles keep this page.
                if p.isGuide || !(extra?.stops.isEmpty ?? true) {
                    content(p)
                } else {
                    InspireFeedView(startId: p.id)
                }
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Post not available", systemImage: "photo.on.rectangle",
                                       description: Text("It may have been removed."))
            }
        }
        .background(Color.white)
        .task {
            await store.ensure(postId)
            loading = false
            if commentCount == nil { commentCount = await CommentsService.count(postId) }
            if let r = LaunchRoute.current, r.hasSuffix("post:\(postId)/comments"), post != nil { showComments = true }
        }
        .task(id: auth.uid) {
            await store.syncAccount(uid: auth.uid)
            guard let p = post else { return }
            if await StoryActions.recordView(post: p, extra: extra, uid: auth.uid) { store.applyView(postId: p.id) }
        }
        .fullScreenCover(item: $viewer) { start in
            if let p = post { StoryMediaViewer(media: mediaList(p), index: start.index) }
        }
        .sheet(isPresented: $showComments) {
            if let p = post {
                CommentsSheet(post: p, ownerUid: extra?.userId ?? "", thumb: extra?.media.first?.thumb ?? "") { n in
                    commentCount = n
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .alert("Sign in", isPresented: Binding(get: { signInPrompt != nil }, set: { if !$0 { signInPrompt = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInPrompt ?? "")
        }
        // the web's report sheet (reasons, note, Block) and block confirmation (src/components/safety)
        .sheet(isPresented: $askReport) {
            if let p = post {
                StoryReportSheet(post: p, ownerUid: extra?.userId ?? "", thumb: extra?.media.first?.thumb ?? "")
            }
        }
        .storyBlockConfirm(isPresented: $confirmBlock, name: (post?.authorName ?? "").isEmpty ? "this traveler" : (post?.authorName ?? "")) {
            await blockOwner()
        }
        .storyDeleteConfirm(isPresented: $confirmDelete, article: post?.isGuide ?? true) { deletePost() }
        // Edit: the post editor every post is written in, opened on this post; its X or Save closes it
        .fullScreenCover(item: $editRoute, onDismiss: {
            let id = postId
            Task { await store.reload(id) }
        }) { r in
            NavigationStack { WebScreen(route: r, fullScreen: true) }
        }
        .onDisappear { StoryVideoCenter.shared.stopAll() }
        .overlay(alignment: .bottom) {
            if let note {
                Text(note)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.navy, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: note)
        .task(id: note) {
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            note = nil
        }
    }

    // MARK: layout

    private func content(_ p: StoryPost) -> some View {
        let media = mediaList(p)
        let article = p.isGuide || !(extra?.stops.isEmpty ?? true)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if article { cover(p, media) } else { gallery(media) }
                header(p, article: article)
                authorRow(p)
                actionBar(p)
                if article { askAIButton(p) }
                if !p.intro.isEmpty { StoryReadText(text: p.intro) }
                if !p.caption.isEmpty && p.caption != p.intro { StoryReadText(text: p.caption) }
                if let linked = extra?.linkedArticleId, !linked.isEmpty, linked != p.id { fullArticleLink(linked) }
                if article { dayByDay(p, media) }
                linksSection(article ? (extra?.tripLinks ?? []) : (extra?.links ?? []), title: article ? "Trip links" : "Links")
                productsSection(extra?.products ?? [])
                tagsRow(extra?.tags ?? [])
            }
            .padding(.bottom, 40)
        }
        // the web's place line (state or country, never "Wy, Wyoming"); one Share only, the iOS share symbol in the action row
        .navigationTitle(navTitle(p))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func gallery(_ media: [StoryMediaInfo]) -> some View {
        if !media.isEmpty {
            TabView(selection: $page) {
                ForEach(Array(media.enumerated()), id: \.offset) { i, m in
                    Group {
                        if m.isVideo {
                            // only the slide on screen may play; swiping on stops it at once
                            StoryVideoView(media: m, active: i == page)
                        } else {
                            RemoteImage(url: m.still, maxPixel: 1600)
                                .onTapGesture { viewer = ViewerStart(index: i) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel(m.placeName.isEmpty ? "Photo \(i + 1)" : m.placeName)
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(4 / 5, contentMode: .fit)
            .overlay(alignment: .topTrailing) {
                if media.count > 1 {
                    Text("\(page + 1)/\(media.count)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if media.indices.contains(page), !media[page].placeName.isEmpty {
                    Label(media[page].placeName, systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .labelStyle(StoryTightLabelStyle())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(12)
                        .padding(.leading, media[page].muted ? 40 : 0)
                        .allowsHitTesting(false)
                }
            }
            if media.count > 1 { pageDots(media.count) }
        }
    }

    private func pageDots(_ n: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<min(n, 12), id: \.self) { i in
                Circle()
                    .fill(i == min(page, 11) ? Color.navy : Color.hairline)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, -8)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cover(_ p: StoryPost, _ media: [StoryMediaInfo]) -> some View {
        let idx = media.firstIndex { !$0.small.isEmpty } ?? 0
        if media.indices.contains(idx) {
            RemoteImage(url: media[idx].isVideo ? media[idx].thumb : media[idx].still, maxPixel: 1600)
                .aspectRatio(16 / 11, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if media.count > 1 {
                        Label("\(media.count)", systemImage: "photo.on.rectangle")
                            .font(.caption.weight(.semibold))
                            .labelStyle(StoryTightLabelStyle())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(12)
                    }
                }
                .onTapGesture { viewer = ViewerStart(index: idx) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Open photos")
        }
    }

    private func header(_ p: StoryPost, article: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TagLabel(text: article ? "Article" : "Inspiration")
            Text(p.title.isEmpty ? p.cityName : p.title)
                .font(.serifTitle(.title2))
                .foregroundStyle(Color.navy)
                .fixedSize(horizontal: false, vertical: true)
            if !p.regionLine.isEmpty {
                Label(p.regionLine, systemImage: "mappin.and.ellipse")
                    .labelStyle(StoryTightLabelStyle())
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            if article, let ex = extra {
                let n = ex.days.count
                let line = [n > 0 ? "\(n) \(n == 1 ? "day" : "days")" : "", ex.dateRange].filter { !$0.isEmpty }.joined(separator: " · ")
                if !line.isEmpty {
                    Label(line, systemImage: "calendar")
                        .labelStyle(StoryTightLabelStyle())
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private func authorRow(_ p: StoryPost) -> some View {
        let uid = extra?.userId ?? ""
        let mine = !uid.isEmpty && uid == auth.uid
        return HStack(spacing: 10) {
            if uid.isEmpty {
                authorLabel(p, uid: uid)
            } else {
                NavigationLink {
                    TravelerView(uid: uid, name: p.authorName, photo: p.authorPhoto)
                } label: {
                    authorLabel(p, uid: uid)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 8)
            if !uid.isEmpty && !mine {
                StoryFollowPill(following: store.following.contains(uid), busy: followBusy) {
                    toggleFollow(uid: uid, name: p.authorName, photo: p.authorPhoto)
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    private func authorLabel(_ p: StoryPost, uid: String) -> some View {
        HStack(spacing: 10) {
            TravelerAvatar(uid: uid, stored: p.authorPhoto, name: p.authorName, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(p.authorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(1)
                let ago = TimeAgo.string(p.createdAtMs)
                if !ago.isEmpty {
                    Text(ago).font(.caption).foregroundStyle(Color.textSecondary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func actionBar(_ p: StoryPost) -> some View {
        let liked = auth.uid.map { extra?.likedUserIds.contains($0) ?? false } ?? false
        let likes = extra?.likesCount ?? p.likesCount
        let saved = store.saved.contains(p.id)
        let uid = extra?.userId ?? ""
        return HStack(spacing: 22) {
            Button { toggleLike(p) } label: {
                HStack(spacing: 6) {
                    LikeHeartIcon(liked: liked, font: .title2)
                    Text("\(likes)").font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: liked)
            .accessibilityLabel(liked ? "Unlike, \(likes) likes" : "Like, \(likes) likes")

            Button { showComments = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right").font(.title2)
                    if let c = commentCount, c > 0 {
                        Text("\(c)").font(.subheadline.weight(.semibold))
                    }
                }
                .foregroundStyle(Color.navy)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comments")

            ShareLink(item: StoryActions.shareURL(p.id), subject: Text(p.title.isEmpty ? p.cityName : p.title)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundStyle(Color.navy)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Share")

            Spacer(minLength: 0)

            let views = extra?.viewsCount ?? p.viewsCount
            if views > 0 {
                Label("\(views)", systemImage: "eye")
                    .labelStyle(StoryTightLabelStyle())
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityLabel("\(views) views")
            }

            Button { toggleSave(p) } label: {
                Image(systemName: saved ? "bookmark.fill" : "bookmark")
                    .font(.title2)
                    .foregroundStyle(Color.navy)
                    .frame(minWidth: 32, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(saveBusy)
            .sensoryFeedback(.selection, trigger: saved)
            .accessibilityLabel(saved ? "Saved" : "Save")

            let canManage = StoryOwnerTools.canManage(ownerUid: uid, auth: auth)
            if (auth.isSignedIn && uid != auth.uid) || canManage {
                Menu {
                    if canManage {
                        StoryOwnerMenuItems(article: p.isGuide) {
                            StoryVideoCenter.shared.stopAll()
                            editRoute = StoryOwnerTools.editRoute(p.id, article: p.isGuide)
                        } onDelete: {
                            confirmDelete = true
                        }
                    }
                    if uid != auth.uid {
                    Button { askReport = true } label: { Label("Report this \(post?.isGuide == true ? "article" : "post")", systemImage: "flag") }
                    if !uid.isEmpty {
                        Button { confirmBlock = true } label: {
                            Label("Block \((post?.authorName ?? "").isEmpty ? "this traveler" : (post?.authorName ?? ""))", systemImage: "person.crop.circle.badge.xmark")
                        }
                    }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundStyle(Color.navy)
                        .frame(minWidth: 28, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }

    /// The bar's name: the post's state or country; a trip whose place is a country itself shows that country
    /// ("Costa Rica"), never a bare "Article" (Cheskel, Oct 23 2026: "change the name, whichever name belongs there").
    private func navTitle(_ p: StoryPost) -> String {
        if !p.regionLine.isEmpty { return p.regionLine }
        let c = p.cityName.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty && StoryRegion.norm(c) != StoryRegion.norm(p.title) { return c }
        return p.isGuide ? "Articles" : "Get Inspired"
    }

    /// "Ask AI to plan this trip": the AI planner opens with this trip (the web article's same button, plan()).
    private func askAIButton(_ p: StoryPost) -> some View {
        Button {
            StoryVideoCenter.shared.stopAll()
            ShellRouter.shared.open(tab: "planner", prompt: planPrompt(p))
        } label: {
            Label("Ask AI to plan this trip", systemImage: "sparkles")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
        .accessibilityLabel("Ask AI to plan this trip")
    }

    /// The web's plan(): a trip through several cities asks for the same route; otherwise the city (and its place).
    private func planPrompt(_ p: StoryPost) -> String {
        let cities = (extra?.stops ?? []).map(\.cityName).filter { !$0.isEmpty }
        if p.isGuide && cities.count > 1 {
            return "Plan a kosher trip like this one: " + cities.joined(separator: " → ")
        }
        let place = p.placeName.trimmingCharacters(in: .whitespaces)
        return "Plan a kosher trip to \(p.cityName)" + (place.isEmpty ? "" : " (I want to see \(place))")
    }

    @MainActor
    private func deletePost() {
        guard !deleting, let p = post else { return }
        deleting = true
        StoryVideoCenter.shared.stopAll()
        let id = p.id
        let ex = extra
        let wasArticle = p.isGuide
        Task {
            let ok = await StoryOwnerTools.delete(postId: id, extra: ex)
            deleting = false
            if ok {
                store.remove(id)
                ShellRouter.shared.showToast(wasArticle ? "Article deleted" : "Post deleted")
                dismiss()
            } else {
                ShellRouter.shared.showToast("Couldn't delete it. Check your connection and try again.")
            }
        }
    }

    private func fullArticleLink(_ id: String) -> some View {
        NavigationLink {
            StoryDetailView(postId: id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "book")
                    .font(.body)
                    .foregroundStyle(Color.navy)
                    .frame(width: 36, height: 36)
                    .hairline(radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Read the full article").font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                    if let t = store.post(id)?.title, !t.isEmpty {
                        Text(t).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary)
            }
            .padding(14)
            .hairline(radius: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.pagePadding)
        .task { await store.ensure(id) }
    }

    // MARK: day by day

    @ViewBuilder
    private func dayByDay(_ p: StoryPost, _ media: [StoryMediaInfo]) -> some View {
        if let ex = extra, !ex.days.isEmpty {
            VStack(alignment: .leading, spacing: 26) {
                SectionHeader(title: "Day by day", count: ex.days.count)
                ForEach(Array(ex.days.enumerated()), id: \.offset) { i, day in
                    dayView(i, day, ex, media)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        } else if let ex = extra, !ex.stops.isEmpty {
            VStack(alignment: .leading, spacing: 26) {
                SectionHeader(title: "The trip", count: ex.stops.count)
                ForEach(Array(ex.stops.enumerated()), id: \.offset) { _, stop in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(stop.cityName).font(.serifTitle(.headline)).foregroundStyle(Color.navy)
                        if !stop.dates.isEmpty {
                            Text(stop.dates).font(.subheadline).foregroundStyle(Color.textSecondary)
                        }
                        if !stop.text.isEmpty { StoryReadText(text: stop.text, padded: false) }
                        placeRows(stop.places)
                        mediaStrip(stop.mediaIdx, media)
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
    }

    private func dayView(_ i: Int, _ day: StoryDayInfo, _ ex: StoryExtra, _ media: [StoryMediaInfo]) -> some View {
        let stopNames = day.stopIdxs.compactMap { ex.stops.indices.contains($0) ? ex.stops[$0].cityName : nil }
        let where_ = stopNames.isEmpty ? day.cityName : stopNames.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Day \(i + 1)")
                    .font(.serifTitle(.headline))
                    .foregroundStyle(Color.navy)
                let label = StoryExtra.dayLabel(day.date)
                if !label.isEmpty {
                    Text(label).font(.subheadline).foregroundStyle(Color.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if !where_.isEmpty {
                Label(where_, systemImage: "mappin.and.ellipse")
                    .labelStyle(StoryTightLabelStyle())
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.navy)
            }
            if !day.place.isEmpty { StoryReadText(text: day.place, padded: false) }
            placeRows(day.places)
            let dayLinks = ex.links(on: day.date)
            if !dayLinks.isEmpty {
                VStack(spacing: 8) { ForEach(dayLinks, id: \.self) { linkRow($0) } }
            }
            mediaStrip(day.mediaIdx, media)
        }
    }

    @ViewBuilder
    private func placeRows(_ places: [TaggedPlaceInfo]) -> some View {
        if !places.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(places.enumerated()), id: \.offset) { i, pl in
                    Button {
                        if let u = pl.openURL { openURL(u) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: pl.symbol)
                                .font(.body)
                                .foregroundStyle(Color.navy)
                                .frame(width: 32, height: 32)
                                .hairline(radius: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(pl.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.navy)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text([pl.categoryLabel, pl.area.isEmpty ? pl.address : pl.area].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if pl.openURL != nil {
                                Image(systemName: StoryExtra.httpsURL(pl.link) != nil ? "link" : "arrow.up.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(pl.openURL == nil)
                    if i < places.count - 1 { Divider().overlay(Color.hairline) }
                }
            }
        }
    }

    @ViewBuilder
    private func mediaStrip(_ idx: [Int], _ media: [StoryMediaInfo]) -> some View {
        let items = idx.filter { media.indices.contains($0) }
        if !items.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.self) { k in
                        let m = media[k]
                        Button { viewer = ViewerStart(index: k) } label: {
                            RemoteImage(url: m.small, maxPixel: 500)
                                .frame(width: 132, height: 168)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    if m.isVideo { StoryVideoBadge().padding(6) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(m.isVideo ? "Video" : (m.placeName.isEmpty ? "Photo" : m.placeName))
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
            }
            .padding(.horizontal, -Theme.pagePadding)
        }
    }

    // MARK: links, products, tags

    @ViewBuilder
    private func linksSection(_ links: [StoryLinkInfo], title: String) -> some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: title, count: links.count)
                Text("Some links may earn us a commission.").font(.caption).foregroundStyle(Color.textSecondary)
                ForEach(links, id: \.self) { linkRow($0) }
            }
            .padding(.horizontal, Theme.pagePadding)
        }
    }

    private func linkRow(_ l: StoryLinkInfo) -> some View {
        Button {
            if let u = StoryExtra.httpsURL(l.url) { openURL(u) }
        } label: {
            HStack(spacing: 12) {
                if l.thumb.isEmpty {
                    Image(systemName: "link")
                        .font(.body)
                        .foregroundStyle(Color.navy)
                        .frame(width: 40, height: 40)
                        .hairline(radius: 10)
                } else {
                    RemoteImage(url: l.thumb, maxPixel: 200)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.label.isEmpty ? l.host : l.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(l.host).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary)
            }
            .padding(10)
            .hairline(radius: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func productsSection(_ products: [StoryProductInfo]) -> some View {
        if !products.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Shop", count: products.count)
                    .padding(.horizontal, Theme.pagePadding)
                Text("Some links may earn us a commission.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, Theme.pagePadding)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(products, id: \.self) { pr in
                            Button {
                                if let u = StoryExtra.httpsURL(pr.url) { openURL(u) }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Color.white
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay { StoryProductImage(url: pr.img) }
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                        .hairline(radius: 12)
                                    Text(pr.name)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Color.navy)
                                        .lineLimit(2, reservesSpace: true)
                                        .multilineTextAlignment(.leading)
                                    if !pr.price.isEmpty {
                                        Text(pr.price).font(.caption).foregroundStyle(Color.textSecondary)
                                    }
                                }
                                .frame(width: 140)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                }
            }
        }
    }

    @ViewBuilder
    private func tagsRow(_ tags: [String]) -> some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { ForEach(tags, id: \.self) { TagLabel(text: $0) } }
                    .padding(.horizontal, Theme.pagePadding)
            }
        }
    }

    // MARK: actions

    private func toggleLike(_ p: StoryPost) {
        guard let actor = StoryActor.from(auth) else { ShellRouter.shared.requireSignIn("Sign in to like posts.") { toggleLike(p) }; return }
        guard !likeBusy else { return }
        let ex = extra
        let was = ex?.likedUserIds.contains(actor.uid) ?? false
        let count = ex?.likesCount ?? p.likesCount
        store.applyLike(postId: p.id, uid: actor.uid, on: !was, count: count + (was ? -1 : 1))
        likeBusy = true
        Task {
            let r = await StoryActions.setLike(post: p, extra: ex, actor: actor, on: !was)
            likeBusy = false
            if let r {
                store.applyLike(postId: p.id, uid: actor.uid, on: r.on, count: r.count)
            } else {
                store.applyLike(postId: p.id, uid: actor.uid, on: was, count: count)
                note = "Your like wasn't saved. Try again."
            }
        }
    }

    private func toggleSave(_ p: StoryPost) {
        guard let uid = auth.uid else { ShellRouter.shared.requireSignIn("Sign in to save posts.") { toggleSave(p) }; return }
        let was = store.saved.contains(p.id)
        store.setSaved(p.id, !was)
        saveBusy = true
        Task {
            let ok = await StoryActions.setSaved(post: p, extra: extra, uid: uid, on: !was)
            saveBusy = false
            if ok {
                note = was ? "Removed from saved" : "Saved to your profile"
            } else {
                store.setSaved(p.id, was)
                note = "Couldn't change it. Try again."
            }
        }
    }

    private func toggleFollow(uid: String, name: String, photo: String) {
        guard let actor = StoryActor.from(auth) else { ShellRouter.shared.requireSignIn("Sign in to follow travelers.") { toggleFollow(uid: uid, name: name, photo: photo) }; return }
        let was = store.following.contains(uid)
        store.setFollowing(uid, !was)
        followBusy = true
        Task {
            let ok = await StoryActions.setFollow(actor: actor, target: uid, targetName: name,
                                                  targetPhoto: store.photo(uid: uid, stored: photo), on: !was)
            followBusy = false
            if !ok {
                store.setFollowing(uid, was)
                note = "Couldn't change it. Try again."
            }
        }
    }

    @MainActor
    private func blockOwner() async {
        guard let p = post, let owner = extra?.userId, !owner.isEmpty, let actor = StoryActor.from(auth) else { return }
        if await StorySafety.shared.block(me: actor, uid: owner, name: p.authorName, photo: p.authorPhoto) {
            note = "\(p.authorName.isEmpty ? "This traveler" : p.authorName) is blocked."
        } else {
            note = "Couldn't block. Try again."
        }
    }

}

/// Body text that keeps the poster's paragraphs.
struct StoryReadText: View {
    let text: String
    var padded = true
    var body: some View {
        let paras = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(paras.enumerated()), id: \.offset) { _, para in
                if !para.isEmpty {
                    Text(para)
                        .font(.body)
                        .foregroundStyle(Color.navy.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, padded ? Theme.pagePadding : 0)
    }
}

/// Product photos are usually on white: show them whole, not cropped.
struct StoryProductImage: View {
    let url: String
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().padding(8)
            } else {
                Image(systemName: "bag").font(.title2).foregroundStyle(Color.textTertiary)
            }
        }
        .task(id: url) {
            guard !url.isEmpty else { return }
            if let hit = ImagePipeline.shared.cached(url, maxPixel: 500) { image = hit; return }
            image = await ImagePipeline.shared.load(url, maxPixel: 500)
        }
    }
}
