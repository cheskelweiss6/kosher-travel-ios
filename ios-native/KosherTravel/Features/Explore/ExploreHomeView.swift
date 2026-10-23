import SwiftUI

struct ExploreHomeView: View {
    @Environment(StoryFeed.self) private var feed

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                regions
                inspiration
                articles
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.white)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await feed.refresh() }
        .task { await feed.loadIfNeeded() }
    }

    // MARK: Browse Regions

    private var regions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Browse Regions")
                .padding(.horizontal, Theme.pagePadding)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NavigationLink(value: ExploreRoute.unitedStates) {
                        RegionCard(title: "United States", tag: "North America", asset: "RegionUSA")
                    }
                    NavigationLink(value: ExploreRoute.caribbean) {
                        RegionCard(title: "Caribbean", tag: "Tropical", asset: "RegionCaribbean")
                    }
                }
                .buttonStyle(.plain)
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
        }
    }

    // MARK: Get Inspired

    @ViewBuilder
    private var inspiration: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Get Inspired")
                .padding(.horizontal, Theme.pagePadding)
            Text("Beautiful places from travelers")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 8)
            if !feed.loadedOnce && feed.posts.isEmpty {
                LoadingCards(count: 4, minWidth: 130, aspect: 0.62)
            } else if feed.inspiration.isEmpty {
                Group {
                    if let msg = feed.errorMessage { FeedStatusLine(message: msg) }
                    else { EmptyNote(title: "No photos from travelers yet", systemImage: "camera") }
                }
                .padding(.horizontal, Theme.pagePadding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(feed.inspiration.prefix(20)) { post in
                            NavigationLink(value: ExploreRoute.story(post.id)) {
                                InspirationTile(post: post)
                            }
                            .buttonStyle(.plain)
                            .containerRelativeFrame(.horizontal) { len, _ in Layout.peekWidth(len, min: 130, spacing: 10) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }

    // MARK: Stories & Articles

    @ViewBuilder
    private var articles: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Stories & Articles", count: feed.articles.count)
            Text("Trips written by travelers on Kosher Travel")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .padding(.bottom, 8)
            if !feed.loadedOnce && feed.posts.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 14).fill(Color.surface).frame(height: 84)
                }
            } else if feed.articles.isEmpty {
                if let msg = feed.errorMessage { FeedStatusLine(message: msg) }
                else { EmptyNote(title: "No articles yet", detail: "Be the first: write up your trip day by day") }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(feed.articles.prefix(8).enumerated()), id: \.element.id) { i, post in
                        NavigationLink(value: ExploreRoute.story(post.id)) {
                            ArticleRow(post: post)
                        }
                        .buttonStyle(.plain)
                        if i < min(feed.articles.count, 8) - 1 { Divider().overlay(Color.hairline) }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
    }
}

struct RegionCard: View {
    let title: String
    let tag: String
    let asset: String

    var body: some View {
        Color.clear
            .aspectRatio(1.15, contentMode: .fit)
            .overlay {
                Image(asset)
                    .resizable()
                    .scaledToFill()
            }
            // flat scrim for legibility (no gradients in the brand)
            .overlay { Color.black.opacity(0.28) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                    Text(title)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .containerRelativeFrame(.horizontal) { len, _ in Layout.fillWidth(len, spacing: 12) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isButton)
    }
}
