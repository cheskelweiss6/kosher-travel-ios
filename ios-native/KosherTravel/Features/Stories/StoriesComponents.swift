import SwiftUI

/// Navigation inside the Stories tab.
enum StoriesRoute: Hashable {
    case post(String)
    case traveler(uid: String, name: String, photo: String)
    case web(WebRoute)   // a live-app screen inside the native shell (Get Inspired)
}

/// A traveler's round photo: their current profile photo when they set one, else the stored one, else their initial.
struct TravelerAvatar: View {
    let uid: String
    let stored: String
    let name: String
    var size: CGFloat = 32
    private var store: StoriesStore { .shared }

    var body: some View {
        let photo = store.photo(uid: uid, stored: stored)
        ZStack {
            if photo.isEmpty {
                Circle().fill(Color.navy)
                Text(String((name.isEmpty ? "T" : name).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                RemoteImage(url: photo, maxPixel: max(96, size * 3))
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .overlay { Circle().strokeBorder(Color.hairline, lineWidth: 0.5) }
        .accessibilityHidden(true)
        .onAppear { store.requestPhoto(uid) }
    }
}

/// The like heart: outline, or filled #ED4956 once liked (with a small bounce).
struct LikeHeartIcon: View {
    let liked: Bool
    var font: Font = .title3
    var body: some View {
        Group {
            if liked {
                Image(systemName: "heart.fill")
                    .symbolVariant(.fill)
                    .foregroundStyle(Color.alert)
            } else {
                Image(systemName: "heart")
                    .foregroundStyle(Color.navy)
            }
        }
        .font(font)
        .symbolEffect(.bounce, value: liked)
    }
}

/// Small likes / views line for cards.
struct StoryCounts: View {
    let likes: Int
    let views: Int
    let liked: Bool
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                LikeHeartIcon(liked: liked, font: .footnote)
                Text("\(likes)")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(likes) likes")
            if views > 0 {
                Label("\(views)", systemImage: "eye")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(views) views")
            }
        }
        .font(.footnote)
        .foregroundStyle(Color.textSecondary)
        .labelStyle(StoryTightLabelStyle())
    }
}

struct StoryTightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

/// Article card for the Stories feed: cover, title, places, author with photo, likes and views.
struct StoryArticleCard: View {
    let post: StoryPost
    let extra: StoryExtra?
    let myUid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteImage(url: post.cover?.cardImage ?? "", maxPixel: 1000)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if post.hasVideo { StoryVideoBadge().padding(10) }
                }
                .overlay(alignment: .bottomLeading) {
                    if let range = extra?.dateRange, !range.isEmpty {
                        Text(range)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.navy)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.92), in: Capsule())
                            .padding(10)
                    }
                }
            Text(post.title.isEmpty ? post.cityName : post.title)
                .font(.serifTitle(.title3))
                .foregroundStyle(Color.navy)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if !post.regionLine.isEmpty {
                Label(post.regionLine, systemImage: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .labelStyle(StoryTightLabelStyle())
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                TravelerAvatar(uid: extra?.userId ?? "", stored: post.authorPhoto, name: post.authorName, size: 26)
                Text(post.authorName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StoryCounts(likes: extra?.likesCount ?? post.likesCount,
                            views: extra?.viewsCount ?? post.viewsCount,
                            liked: myUid.map { extra?.likedUserIds.contains($0) ?? false } ?? false)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Inspiration tile (photo / video post): tall cover, place and author.
struct StoryInspirationTile: View {
    let post: StoryPost
    let extra: StoryExtra?
    let myUid: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(url: post.cover?.cardImage ?? "", maxPixel: 700)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if post.hasVideo { StoryVideoBadge().padding(8) }
                }
            Text(post.title.isEmpty ? post.cityName : post.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.navy)
                .lineLimit(1)
            HStack(spacing: 6) {
                TravelerAvatar(uid: extra?.userId ?? "", stored: post.authorPhoto, name: post.authorName, size: 20)
                Text(post.regionLine.isEmpty ? post.authorName : post.regionLine)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 3) {
                    LikeHeartIcon(liked: myUid.map { extra?.likedUserIds.contains($0) ?? false } ?? false, font: .caption)
                    Text("\(extra?.likesCount ?? post.likesCount)")
                }
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct StoryVideoBadge: View {
    var body: some View {
        Image(systemName: "play")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(.black.opacity(0.45), in: Circle())
            .accessibilityLabel("Video")
    }
}

/// Follow / Following pill (navy outline; filled navy once following).
struct StoryFollowPill: View {
    let following: Bool
    let busy: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if busy { ProgressView().controlSize(.mini) }
                Text(following ? "Following" : "Follow")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(following ? Color.navy : .white)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(following ? Color.white : Color.navy, in: Capsule())
            .overlay { Capsule().strokeBorder(following ? Color.hairline : Color.navy, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .sensoryFeedback(.selection, trigger: following)
    }
}

/// Filter chip (All / Following / tags).
struct StoryChip: View {
    let title: String
    var systemImage: String? = nil
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? .white : Color.navy)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(selected ? Color.navy : Color.white, in: Capsule())
            .overlay { Capsule().strokeBorder(selected ? Color.navy : Color.hairline, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
