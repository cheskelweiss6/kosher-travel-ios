import SwiftUI

// The website's traveler place cards (src/components/stories/travelerPlaces.tsx), in SwiftUI, with the same words:
// "From travelers · In N stories", Map, Book / Open (the poster's own link) with "Some links may earn us a commission."
// above it, and the same card shapes as the region's own Things to Do tiles, State Parks cards, Hotels cards,
// shul / Chabad rows and Cities & Areas cards. Tapping a story opens the newest post that tags the place.
// Links go through the app's openURL handler: maps open the "Open in" chooser, the poster's link opens in Safari inside
// the app with the Expedia / Hotels.com rewrite (web affiliateUrl).

enum TPStyle {
    /// slate-900, the cards' names
    static let ink = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
    /// slate-600
    static let slate600 = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
    /// slate-700
    static let slate700 = Color(red: 51 / 255, green: 65 / 255, blue: 85 / 255)
    /// slate-100, the line above Map / Book and the city chip
    static let slate100 = Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255)
    /// slate-300, the grey words on a photo
    static let slate300 = Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255)
    /// slate-950
    static let slate950 = Color(red: 2 / 255, green: 6 / 255, blue: 23 / 255)
}

/// Opens a story: through the caller when it handles it, else as a pushed post page (ExploreRoute.story).
struct TPStoryButton<Label: View>: View {
    let postId: String
    var onOpenStory: ((String) -> Void)?
    @ViewBuilder let label: () -> Label

    var body: some View {
        if let onOpenStory {
            Button { onOpenStory(postId) } label: { label() }
                .buttonStyle(.pressable)
        } else {
            NavigationLink(value: ExploreRoute.story(postId)) { label() }
                .buttonStyle(.pressable)
        }
    }
}

/// "From travelers · In 1 story": the story part opens the newest post that tags it (web FromTravelers).
struct FromTravelersLink: View {
    let posts: [String]
    var onOpenStory: ((String) -> Void)? = nil
    /// On a photo (the Cities & Areas card): light grey words, white link.
    var onPhoto = false
    /// Web (Oct 23 2026): a place the app doesn't list reads "Added by a traveler"; an app listing travelers tagged or
    /// named, and a town card, read "From travelers".
    var lead = "Added by a traveler"

    init(sight: SharedSight, label: String = "Added by a traveler", onOpenStory: ((String) -> Void)? = nil) {
        posts = sight.posts
        lead = label
        self.onOpenStory = onOpenStory
    }
    init(town: TravelerTown, onPhoto: Bool = false, onOpenStory: ((String) -> Void)? = nil) {
        posts = town.posts
        lead = "From travelers"
        self.onPhoto = onPhoto
        self.onOpenStory = onOpenStory
    }
    /// An app listing that live posts tag or name (the AI server's index `listings`).
    init(posts: [String], label: String = "From travelers", onOpenStory: ((String) -> Void)? = nil) {
        self.posts = posts
        lead = label
        self.onOpenStory = onOpenStory
    }

    private var label: String { posts.count == 1 ? "In 1 story" : "In \(posts.count) stories" }

    var body: some View {
        HStack(spacing: 4) {
            Text(lead)
                .lineLimit(1)
            if let first = posts.first {
                Text("·").accessibilityHidden(true)
                TPStoryButton(postId: first, onOpenStory: onOpenStory) {
                    HStack(spacing: 4) {
                        Image(systemName: "book")
                            .font(.system(size: 12, weight: .semibold))
                        Text(label)
                            .fontWeight(.bold)
                            .lineLimit(1)
                    }
                    .foregroundStyle(onPhoto ? Color.white : Color.navy)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .padding(.vertical, -12)
                .accessibilityLabel("\(label), from travelers")
            }
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(onPhoto ? TPStyle.slate300 : Color.textSecondary)
    }
}

/// "Some links may earn us a commission." (web TravelerCommissionNote)
struct TravelerCommissionNote: View {
    var body: some View {
        Text(TravelerRules.commissionNote)
            .font(.system(size: 12))
            .foregroundStyle(Color.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The white "Map" button (web MapButton).
struct TravelerMapButton: View {
    let name: String
    let url: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "map").font(.system(size: 15, weight: .regular))
                Text("Map").font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.navy)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .hairline(radius: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Open \(name) in Maps")
    }
}

/// The navy "Book" / "Open" button: the poster's own link (web BookButton).
struct TravelerBookButton: View {
    let sight: SharedSight
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let u = sight.linkURL { openURL(u) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square").font(.system(size: 15, weight: .regular))
                Text(sight.linkVerb).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(sight.linkVerb) \(sight.name)")
    }
}

/// Map, and Book (a place to stay) or Open when the poster added his own link; the commission line sits above them
/// (web TravelerActions).
struct TravelerActionsRow: View {
    let sight: SharedSight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sight.link != nil { TravelerCommissionNote() }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if sight.link != nil { TravelerBookButton(sight: sight) }
                TravelerMapButton(name: sight.name, url: sight.mapURL)
            }
        }
    }
}

/// The line above Map / Book on a card (web `border-t border-slate-100 pt-3`).
private struct TPTopRule: ViewModifier {
    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(TPStyle.slate100).frame(height: 1)
            content.padding(.top, 12)
        }
    }
}

/// The traveler's photo, or a white tile with an outline icon when there is none or it fails (web Photo).
struct TravelerPhoto: View {
    let url: String?
    let systemImage: String
    var iconSize: CGFloat = 24
    var maxPixel: CGFloat = 600
    @State private var failed = false

    var body: some View {
        if let u = url, !u.isEmpty, !failed {
            TPPhotoLoader(url: u, maxPixel: maxPixel, failed: $failed)
        } else {
            Rectangle()
                .fill(Color.white)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .regular))
                        .foregroundStyle(Color.navy)
                }
        }
    }
}

/// Loads a photo through the app's image pipeline and reports a failure so the icon tile shows instead.
private struct TPPhotoLoader: View {
    let url: String
    let maxPixel: CGFloat
    @Binding var failed: Bool
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color.surface)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: url) {
                if let hit = ImagePipeline.shared.cached(url, maxPixel: maxPixel) { image = hit; return }
                if let loaded = await ImagePipeline.shared.load(url, maxPixel: maxPixel) {
                    withAnimation(Motion.fade) { image = loaded }
                } else {
                    failed = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// A State Things to Do tile, the same as the app's own (photo, name): the traveler's photo of it (web TravelerTile).
struct TravelerTile: View {
    let sight: SharedSight
    var onOpen: (() -> Void)? = nil
    var onOpenStory: ((String) -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var side: CGFloat { sizeClass == .regular ? 80 : 64 }

    var body: some View {
        HStack(spacing: 12) {
            TravelerPhoto(url: sight.photo, systemImage: "mappin", iconSize: 24, maxPixel: 300)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if (sight.photo ?? "").isEmpty { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1) }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(sight.name)
                    .font(.system(size: sizeClass == .regular ? 14 : 12, weight: .heavy))
                    .tracking(-0.2)
                    .foregroundStyle(TPStyle.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                FromTravelersLink(sight: sight, onOpenStory: onOpenStory)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(onOpen != nil ? .isButton : [])
    }
}

/// A State Parks card, the same as the app's own (photo, name, line), with Map / Book (web TravelerParkCard).
struct TravelerParkCard: View {
    let sight: SharedSight
    var onOpen: (() -> Void)? = nil
    var onOpenStory: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TravelerPhoto(url: sight.photo, systemImage: "tree", iconSize: 40, maxPixel: 900)
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(sight.name)
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(TPStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !sight.kind.isEmpty || !sight.area.isEmpty {
                        Text(sight.kindLine)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                            .lineSpacing(2)
                    }
                    FromTravelersLink(sight: sight, onOpenStory: onOpenStory)
                        .padding(.top, 6)
                }
                TravelerActionsRow(sight: sight)
                    .modifier(TPTopRule())
            }
            .padding(16)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .contain)
    }
}

/// A Hotels card, the same as the app's own (name, kind, city, photo, address), with Book (his link) and Map
/// (web TravelerStayCard). `label` defaults to the website's stayLabel ("Campground", "Cabins"… else "Hotel").
struct TravelerStayCard: View {
    let sight: SharedSight
    var label: String? = nil
    var onOpen: (() -> Void)? = nil
    var onOpenStory: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    HStack(alignment: .center, spacing: 10) {
                        TPIconBox(systemImage: "bed.double", size: 32, icon: 15)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sight.name)
                                .font(.system(size: 13, weight: .heavy))
                                .tracking(-0.2)
                                .foregroundStyle(TPStyle.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text((label ?? sight.stayLabel).uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1)
                                .foregroundStyle(Color.navy)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !sight.cityName.isEmpty {
                        Text(sight.cityName)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(TPStyle.slate700)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(TPStyle.slate100, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .hairline(radius: 6)
                            .layoutPriority(-1)
                    }
                }
                if let p = sight.photo, !p.isEmpty {
                    TravelerPhoto(url: p, systemImage: "bed.double", iconSize: 32, maxPixel: 900)
                        .frame(height: 128)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !sight.area.isEmpty {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.top, 1)
                        Text(sight.area)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TPStyle.slate600)
                            .lineLimit(2)
                    }
                }
                FromTravelersLink(sight: sight, onOpenStory: onOpenStory)
            }
            TravelerActionsRow(sight: sight)
                .modifier(TPTopRule())
                .padding(.top, 12)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .contain)
    }
}

/// A Synagogues / Chabad row (a map-tagged shul or Chabad house), same white card (web TravelerPlaceRow).
struct TravelerPlaceRow: View {
    let sight: SharedSight
    /// "Shul" / "Chabad", as the page names its section.
    let label: String
    var onOpenStory: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                TPIconBox(systemImage: "building.columns", size: 32, icon: 15)
                VStack(alignment: .leading, spacing: 0) {
                    Text(sight.name)
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(-0.2)
                        .foregroundStyle(TPStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([label, sight.area].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    FromTravelersLink(sight: sight, onOpenStory: onOpenStory)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TravelerActionsRow(sight: sight)
                .modifier(TPTopRule())
                .padding(.top, 12)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
    }
}

/// A small white square with a navy outline icon.
struct TPIconBox: View {
    let systemImage: String
    var size: CGFloat = 32
    var icon: CGFloat = 15

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: icon, weight: .regular))
            .foregroundStyle(Color.navy)
            .frame(width: size, height: size)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .hairline(radius: 12)
            .accessibilityHidden(true)
    }
}

/// A Cities & Areas card for a town travelers tagged: the same tall card as the app's cities (photo, name, state), with
/// "From travelers · In N stories" and Map. No photo: a white card with an outline icon (web TravelerTownCard).
struct TravelerTownCard: View {
    let town: TravelerTown
    let stateName: String
    var onOpen: (() -> Void)? = nil
    var onOpenStory: ((String) -> Void)? = nil
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var failed = false

    private var hasPhoto: Bool { !(town.photo ?? "").isEmpty && !failed }

    var body: some View {
        Group {
            if hasPhoto {
                ZStack {
                    TPPhotoLoader(url: town.photo ?? "", maxPixel: 1000, failed: $failed)
                    LinearGradient(stops: [
                        .init(color: TPStyle.slate950.opacity(0.45), location: 0),
                        .init(color: TPStyle.slate950.opacity(0.2), location: 0.5),
                        .init(color: TPStyle.slate950.opacity(0.9), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    content(onPhoto: true)
                        .padding(20)
                }
                .frame(height: sizeClass == .regular ? 288 : 256)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.05), radius: 1, y: 1)
            } else {
                content(onPhoto: false)
                    .padding(20)
                    .frame(maxWidth: .infinity, minHeight: sizeClass == .regular ? 288 : nil)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .hairline(radius: 24)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func content(onPhoto: Bool) -> some View {
        VStack(alignment: .leading, spacing: onPhoto ? 0 : 24) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(town.name)
                        .font(.system(size: sizeClass == .regular ? 20 : 18, weight: .bold, design: .serif))
                        .tracking(0.4)
                        .foregroundStyle(onPhoto ? Color.white : Color.navy)
                        .shadow(color: onPhoto ? Color.black.opacity(0.35) : .clear, radius: 3, y: 2)
                    Text("\(stateName), USA")
                        .font(.system(size: sizeClass == .regular ? 12 : 10, weight: .semibold))
                        .foregroundStyle(onPhoto ? TPStyle.slate300 : Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !onPhoto { TPIconBox(systemImage: "mappin", size: 40, icon: 18) }
            }
            if onPhoto { Spacer(minLength: 0) }
            HStack(alignment: .bottom, spacing: 12) {
                FromTravelersLink(town: town, onPhoto: onPhoto, onOpenStory: onOpenStory)
                Spacer(minLength: 0)
                TravelerMapButton(name: town.name, url: town.mapURL)
            }
        }
    }
}

/// In a place's details sheet: "From travelers · In N stories", and his Book / Open link (with the commission line) when
/// he added one. Works for a traveler's place and for an app place travelers tagged by the same name
/// (web TravelerPlaceExtra). Shows nothing otherwise.
struct TravelerPlaceExtra: View {
    let item: PlaceItem
    var onOpenStory: ((String) -> Void)? = nil
    private var store: SharedSights { SharedSights.shared }
    private var index: TravelerTipsStore { TravelerTipsStore.shared }

    var body: some View {
        // Web (Oct 23 2026): a traveler's own place reads "Added by a traveler"; an app listing travelers tagged or
        // named reads "From travelers" (also from the AI server's index), plus up to 3 tips about this place.
        let given = item.id.hasPrefix(SharedSight.placeIdPrefix)
        let s = store.sight(for: item)
        let sightShown = s.map { !$0.posts.isEmpty || $0.link != nil } ?? false
        let _ = index.kick()
        let posts = given ? [] : index.listingPosts(item.venue.name)
        let listingShown = !sightShown && !posts.isEmpty
        let tips = Array(index.tips(for: TipScope(kind: .place, name: item.venue.name)).prefix(3))
        if sightShown || listingShown || !tips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if sightShown, let s {
                    FromTravelersLink(sight: s, label: given ? "Added by a traveler" : "From travelers", onOpenStory: onOpenStory)
                }
                if listingShown {
                    FromTravelersLink(posts: posts, label: "From travelers", onOpenStory: onOpenStory)
                }
                if !tips.isEmpty {
                    if sightShown || listingShown { Divider().overlay(Color.hairline).padding(.vertical, 4) }
                    Label { Text("Tips from travelers").foregroundStyle(Color.primary) } icon: {
                        Image(systemName: "lightbulb").foregroundStyle(Color.navy)
                    }
                    .font(.footnote.weight(.black))
                    ForEach(tips) { t in
                        Button { if !t.postId.isEmpty { onOpenStory?(t.postId) } } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\u{201C}\(t.text)\u{201D}")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text((t.author.isEmpty ? "A traveler" : t.author) + (t.when.isEmpty ? "" : ", visited \(t.when)"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .hairline(radius: 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(onOpenStory == nil)
                    }
                    Text("Travelers\u{2019} own words, not checked by the app.")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
                if sightShown, let s, s.link != nil {
                    TravelerCommissionNote()
                    HStack {
                        Spacer(minLength: 0)
                        TravelerBookButton(sight: s)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .hairline(radius: 16)
            .padding(.top, 16)
        }
    }
}
