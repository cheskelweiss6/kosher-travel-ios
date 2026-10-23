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

    var body: some View {
        let list = feed.articles(kind: kind, name: placeName)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Articles from travelers", count: list.count)
                .padding(.horizontal, Theme.pagePadding)
            if !feed.loadedOnce && feed.posts.isEmpty {
                LoadingCards(count: 2, minWidth: 220, aspect: 1.2)
            } else if list.isEmpty {
                Group {
                    if let msg = feed.errorMessage { FeedStatusLine(message: msg) }
                    else { EmptyNote(title: "No articles for \(placeName) yet", detail: "Be the first: write up your trip day by day") }
                }
                .padding(.horizontal, Theme.pagePadding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(list) { post in
                            NavigationLink(value: ExploreRoute.story(post.id)) { ArticleCard(post: post) }
                                .buttonStyle(.plain)
                                .containerRelativeFrame(.horizontal) { len, _ in Layout.peekWidth(len, min: 220, spacing: 12) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}
