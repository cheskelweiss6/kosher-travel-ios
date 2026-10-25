import SwiftUI

struct ExploreHomeView: View {
    @Environment(StoryFeed.self) private var feed
    @Environment(AuthStore.self) private var auth
    @State private var webCover: WebRoute?
    @State private var composing = false   // the native chooser + composer (NATIVE-COMPOSER)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                searchField
                regions
                inspiration
                articles
                // web App.tsx: What's New under Stories & Articles, then the person's upcoming trips
                ExploreWhatsNew()
                if let uid = auth.uid { ExploreUpcomingTrips(uid: uid) }
                moreRows
            }
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(Color.white)
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Web: "Share" (share your story) sits top-left on the Explore home only.
            ToolbarItem(placement: .topBarLeading) {
                Button { composing = true } label: {
                    Label("Share", systemImage: "photo.badge.plus").labelStyle(.titleAndIcon)
                }
                .accessibilityLabel("Share your story")
                .accessibilityIdentifier("explore-share")
            }
            ToolbarItem(placement: .topBarTrailing) { AccountToolbarButtons() }
        }
        .refreshable {
            await feed.refresh()
            await ExploreNewsStore.shared.load(force: true)
        }
        .task { await feed.loadIfNeeded() }
        .composeFlow(isPresented: $composing)
        .fullScreenCover(item: $webCover) { r in
            NavigationStack { WebScreen(route: r, fullScreen: true) }
        }
    }

    // MARK: Search (web: the home search field "Search a country, state or city" at the top of Explore)

    private var searchField: some View {
        NavigationLink(value: ExploreRoute.web(.exploreSearch)) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.navy)
                Text("Search a country, state or city")
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .hairline(radius: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, Theme.pagePadding)
        .accessibilityLabel("Search a country, state or city")
        .accessibilityIdentifier("explore-search")
    }

    // MARK: More (live screens inside the shell until they are native)

    private var moreRows: some View {
        VStack(spacing: 0) {
            moreRow("building.columns", "Kivrei Tzadikim", .kivrei)
            // Europe is public since Oct 24 2026 (website src/europeLaunch.ts EUROPE_PUBLIC = true, Cheskel's "Go")
            Divider().overlay(Color.hairline)
            moreRow("globe.europe.africa", "Europe", .europe)
        }
        .padding(.horizontal, 14)
        .hairline(radius: 14)
        .padding(.horizontal, Theme.pagePadding)
    }

    private func moreRow(_ icon: String, _ title: String, _ route: WebRoute) -> some View {
        NavigationLink(value: ExploreRoute.web(route)) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Color.navy).frame(width: 24)
                Text(title).foregroundStyle(Color.navy)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.textTertiary)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Browse Regions

    private var regions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Browse Regions")
                .padding(.horizontal, Theme.pagePadding)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    NavigationLink(value: ExploreRoute.unitedStates) {
                        RegionCard(title: "United States", tag: "50 States", asset: "RegionUSA")
                    }
                    NavigationLink(value: ExploreRoute.caribbean) {
                        RegionCard(title: "Caribbean", tag: "Tropical", asset: "RegionCaribbean")
                    }
                    NavigationLink(value: ExploreRoute.mexicoCentralAmerica) {
                        RegionCard(title: "Mexico & Central America", tag: "8 Countries", asset: "RegionCentralAmerica")
                    }
                    // web: the fourth region card (public since Oct 24 2026); the Europe page is the live site's for now
                    NavigationLink(value: ExploreRoute.web(.europe)) {
                        RegionCard(title: "Europe", tag: "Kivrei Tzadikim", asset: "RegionEurope")
                    }
                }
                .buttonStyle(.pressable)
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
                            .buttonStyle(.pressable)
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
    // Cheskel Oct 23: the long list piled up; now a sideways row of cards (like Browse Regions / Get Inspired)
    // with "See all" opening the full list.

    @ViewBuilder
    private var articles: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionHeader(title: "Stories & Articles")
                if !feed.articles.isEmpty {
                    NavigationLink {
                        AllArticlesView()
                    } label: {
                        Text("See all").font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("articles-see-all")
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            Text("Trips written by travelers on Kosher Travel")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 8)
            if !feed.loadedOnce && feed.posts.isEmpty {
                LoadingCards(count: 3, minWidth: 150, aspect: 0.75)
            } else if feed.articles.isEmpty {
                Group {
                    if let msg = feed.errorMessage { FeedStatusLine(message: msg) }
                    else { EmptyNote(title: "No articles yet", detail: "Be the first: write up your trip day by day") }
                }
                .padding(.horizontal, Theme.pagePadding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(feed.articles.prefix(12)) { post in
                            NavigationLink(value: ExploreRoute.story(post.id)) {
                                ExploreArticleTile(post: post)
                            }
                            .buttonStyle(.pressable)
                            .containerRelativeFrame(.horizontal) { len, _ in Layout.peekWidth(len, min: 150, spacing: 12) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .accessibilityIdentifier("articles-row")
            }
        }
    }
}

/// One card in Explore's sideways Stories & Articles row; the same tile the website shows there
/// (TravelArticles.tsx: tall cover photo, two-line title, "place · author").
struct ExploreArticleTile: View {
    let post: StoryPost
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StoryCoverImage(post: post, maxPixel: 600)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .hairline(radius: 14)
            Text(post.title.isEmpty ? post.cityName : post.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.navy)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
            Text([post.regionLine, post.authorName].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Explore → Stories & Articles → See all: every article, newest first, as the rows the home used to show.
struct AllArticlesView: View {
    @Environment(StoryFeed.self) private var feed

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if feed.articles.isEmpty {
                    EmptyNote(title: "No articles yet", detail: "Be the first: write up your trip day by day")
                        .padding(.top, 24)
                } else {
                    ForEach(Array(feed.articles.enumerated()), id: \.element.id) { i, post in
                        NavigationLink(value: ExploreRoute.story(post.id)) {
                            ArticleRow(post: post)
                        }
                        .buttonStyle(.plain)
                        if i < feed.articles.count - 1 { Divider().overlay(Color.hairline) }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 32)
        }
        .background(Color.white)
        .navigationTitle("Stories & Articles")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await feed.refresh() }
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
                        .lineLimit(2)
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
