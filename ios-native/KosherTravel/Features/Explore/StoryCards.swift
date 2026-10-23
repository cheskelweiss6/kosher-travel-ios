import SwiftUI

/// Get Inspired tile: a tall photo with the place under it.
struct InspirationTile: View {
    let post: StoryPost
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: post.cover?.cardImage ?? "", maxPixel: 600)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if post.hasVideo {
                        Image(systemName: "play.circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 2)
                            .padding(8)
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(post.cityName.isEmpty ? post.title : post.cityName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(1)
                Text(post.placeLine)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One article in a list: cover, title, places and author.
struct ArticleRow: View {
    let post: StoryPost
    @ScaledMetric(relativeTo: .subheadline) private var thumb: CGFloat = 72
    var body: some View {
        HStack(spacing: 12) {
            RemoteImage(url: post.cover?.cardImage ?? "", maxPixel: 300)
                .frame(width: thumb, height: thumb)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .hairline(radius: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(post.title.isEmpty ? post.cityName : post.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text([post.placeLine, post.authorName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// A wide article card for horizontal rows on region / state pages.
struct ArticleCard: View {
    let post: StoryPost
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemoteImage(url: post.cover?.cardImage ?? "", maxPixel: 700)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title.isEmpty ? post.cityName : post.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text(post.placeLine)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}

/// "Articles from travelers" block used on region, state and country pages.
struct TravelerArticlesSection: View {
    @Environment(StoryFeed.self) private var feed
    let kind: StoryPost.PlaceKind
    let placeName: String
    var region: String? = nil
    @State private var compose: WebRoute?

    var body: some View {
        let list = feed.articles(kind: kind, name: placeName)
        let insp = kind == .city ? feed.inspiration.filter { $0.matches(kind: .city, name: placeName) } : []
        VStack(alignment: .leading, spacing: 8) {
            // Web PlaceStories (Oct 21 2026): small 72pt rows, photo left and title beside it, a "Share yours" tile last.
            HStack {
                Label("Articles from travelers", systemImage: "photo.on.rectangle")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Color.navy)
                Spacer()
                if !list.isEmpty { Text("\(list.count)").font(.caption.weight(.bold)).foregroundStyle(Color.textSecondary) }
            }
            .padding(.horizontal, Theme.pagePadding)
            if !feed.loadedOnce && feed.posts.isEmpty {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.surface).frame(height: 72)
                    .padding(.horizontal, Theme.pagePadding)
            } else if list.isEmpty {
                if let msg = feed.errorMessage {
                    FeedStatusLine(message: msg).padding(.horizontal, Theme.pagePadding)
                } else {
                    Button { compose = shareRoute } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "camera").font(.system(size: 18)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(Color.navy, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No articles for \(placeName) yet").font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
                                Text("Be the first: write up your trip day by day").font(.footnote).foregroundStyle(Color.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").foregroundStyle(Color.textTertiary)
                        }
                        .padding(14)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Theme.pagePadding)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(list) { post in
                            NavigationLink(value: ExploreRoute.story(post.id)) { CompactArticleCard(post: post) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(post.title). Opens the article.")
                        }
                        Button { compose = shareRoute } label: {
                            VStack(spacing: 4) {
                                Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                                Text("Share yours").font(.caption.weight(.bold))
                            }
                            .foregroundStyle(Color.navy)
                            .frame(width: 84, height: 72)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .hairline(radius: 12)
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
            }
            if !insp.isEmpty {
                Text("Get Inspired in \(placeName)").font(.footnote.weight(.heavy)).foregroundStyle(Color.navy)
                    .padding(.horizontal, Theme.pagePadding).padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(insp) { post in
                            NavigationLink(value: ExploreRoute.story(post.id)) { InspirationTile(post: post).frame(width: 120) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
            }
        }
        .fullScreenCover(item: $compose) { r in
            NavigationStack { WebScreen(route: r, fullScreen: true) }
        }
    }

    private var shareRoute: WebRoute { kind == .city ? .compose(city: placeName, region: region) : .compose() }
}

/// Web place-article-card: 214 x 72, photo on the left, two-line title and the place beside it.
struct CompactArticleCard: View {
    let post: StoryPost
    var body: some View {
        HStack(spacing: 0) {
            RemoteImage(url: post.cover?.cardImage ?? "", maxPixel: 240)
                .frame(width: 72, height: 72)
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(post.title.isEmpty ? post.cityName : post.title)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !post.placeLine.isEmpty {
                    Label(post.placeLine, systemImage: "mappin").font(.caption2).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 214, height: 72)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hairline(radius: 12)
    }
}
