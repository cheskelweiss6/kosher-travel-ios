import SwiftUI

// MARK: - The card (web: the state page's park / activity cards)

/// Photo with a navy badge, name, two lines of description, then the town and a "View Details →" line.
struct ParkCardView: View {
    let image: String
    let badge: String
    var badgeIcon: String? = nil
    let name: String
    let summary: String
    let location: String
    var trailing: String? = "View Details →"
    var trailingIsLink = true
    var nameLineLimit: Int? = 1
    var photoHeight: CGFloat = 160

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Group {
                    if image.isEmpty {
                        NoPhotoTile()
                    } else {
                        RemoteImage(url: ParkImage.sized(image, width: 400), maxPixel: 800, venue: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: photoHeight * min(scale, 1.4))
                .clipped()

                ParkBadge(text: badge, systemImage: badgeIcon)
                    .padding(8)
            }
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.navy)
                        .lineLimit(nameLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Rectangle().fill(Color.hairline).frame(height: 1)
                HStack(spacing: 8) {
                    Label {
                        Text(location).lineLimit(1)
                    } icon: {
                        Image(systemName: "mappin").font(.caption2)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 4)
                    if let trailing, !trailing.isEmpty {
                        Text(trailing)
                            .font(trailingIsLink ? Font.caption.weight(.bold) : Font.caption.weight(.bold).monospaced())
                            .foregroundStyle(trailingIsLink ? Color.navy : Color.primary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .hairline(radius: Theme.cardRadius)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

/// The navy uppercase badge on a park photo.
struct ParkBadge: View {
    let text: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text.uppercased())
        }
        .font(.caption2.weight(.heavy))
        .tracking(0.6)
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.navy.opacity(0.92), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .lineLimit(1)
    }
}

enum ParkCardStyle: Hashable {
    /// Cities & Areas tab sections (web App.tsx 7288-7410).
    case section
    /// State Parks / National Parks tabs (web App.tsx 7984-8180).
    case tab
    /// Tribal & Scenic tab (web App.tsx 8212-8256).
    case tribal
}

struct StateParkCard: View {
    let park: StatePark
    let stateName: String
    var style: ParkCardStyle = .section
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ParkCardView(
                image: park.image,
                badge: "State Park",
                badgeIcon: "leaf",
                name: park.name,
                summary: park.shortDescription,
                location: style == .section ? ParkText.secondOrFirstPart(park.address, state: stateName)
                                            : ParkText.secondPart(park.address, state: stateName),
                nameLineLimit: style == .section ? 1 : nil
            )
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens the park details")
    }
}

struct NationalParkCard: View {
    let park: NationalPark
    let stateName: String
    var style: ParkCardStyle = .section
    let action: () -> Void

    private var badge: String {
        switch style {
        case .section: return ParkText.sectionBadge(park.designation)
        case .tab: return park.designation.isEmpty ? "NPS Site" : park.designation
        case .tribal: return park.designation.isEmpty ? "Tribal / Scenic Landmark" : park.designation
        }
    }

    var body: some View {
        Button(action: action) {
            ParkCardView(
                image: park.image,
                badge: badge,
                name: park.name,
                summary: park.shortDescription,
                location: style == .section ? ParkText.secondOrFirstPart(park.address, state: stateName)
                                            : ParkText.lastTwoParts(park.address, state: stateName),
                trailing: style == .tribal ? "Explore Guide →" : "View Details →",
                nameLineLimit: style == .tab ? nil : 1,
                photoHeight: style == .tribal ? 176 : 160
            )
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens the park details")
    }
}

/// Not tappable, like the website's activity cards.
struct ParkActivityCard: View {
    let activity: ParkActivity
    var body: some View {
        ParkCardView(
            image: activity.image,
            badge: activity.badge,
            name: activity.name,
            summary: activity.description,
            location: activity.parkName,
            trailing: activity.duration.isEmpty ? nil : activity.duration,
            trailingIsLink: false,
            nameLineLimit: nil,
            photoHeight: 144
        )
        .accessibilityElement(children: .combine)
    }
}

/// One column on a phone, two or three on wider screens (web grid-cols-1 sm:grid-cols-2 lg:grid-cols-3).
enum ParkGrid {
    static let columns = [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)]
}

// MARK: - Cities & Areas tab sections (web App.tsx 7288-7465)

struct ParkSectionHeader: View {
    let systemImage: String
    let title: String
    let subtitle: String
    var viewAllCount: Int? = nil
    var onViewAll: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage).font(.body)
                }
                .font(.serifTitle())
                .foregroundStyle(Color.navy)
                .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let viewAllCount, let onViewAll {
                Button(action: onViewAll) {
                    HStack(spacing: 2) {
                        Text("View all (\(viewAllCount))")
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A section's top rule and spacing (web "mt-8 pt-6 border-t").
private struct ParkSectionFrame<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle().fill(Color.hairline).frame(height: 1)
            content
        }
        .padding(.top, 16)
    }
}

/// "State Parks in {state}": six cards, "View all (N)" when there are more (switches to the State Parks tab).
struct StateParksSection: View {
    let stateName: String
    var onViewAll: (() -> Void)? = nil
    private var store: ParkStore { ParkStore.shared }
    @State private var open: StatePark?

    init(stateName: String, onViewAll: (() -> Void)? = nil) {
        self.stateName = stateName
        self.onViewAll = onViewAll
    }

    var body: some View {
        let parks = store.isLoaded ? store.stateParks(in: stateName) : []
        Group {
            if !parks.isEmpty {
                ParkSectionFrame {
                    ParkSectionHeader(systemImage: "leaf", title: "State Parks in \(stateName)",
                                      subtitle: "Notable state parks, scenic reservations, and nature trails in \(stateName).",
                                      viewAllCount: parks.count > 6 ? parks.count : nil, onViewAll: onViewAll)
                    LazyVGrid(columns: ParkGrid.columns, spacing: 16) {
                        ForEach(parks.prefix(6)) { p in
                            StateParkCard(park: p, stateName: stateName, style: .section) { open = p }
                        }
                    }
                }
            }
        }
        .task { await store.load() }
        .sheet(item: $open) { StateParkSheet(park: $0) }
    }
}

/// "National Parks & Monuments in {state}": six cards, "View all (N)" when there are more.
struct NationalParksSection: View {
    let stateName: String
    var onViewAll: (() -> Void)? = nil
    private var store: ParkStore { ParkStore.shared }
    @State private var open: NationalPark?

    init(stateName: String, onViewAll: (() -> Void)? = nil) {
        self.stateName = stateName
        self.onViewAll = onViewAll
    }

    var body: some View {
        let parks = store.isLoaded ? store.nationalParks(in: stateName) : []
        Group {
            if !parks.isEmpty {
                ParkSectionFrame {
                    ParkSectionHeader(systemImage: "mountain.2", title: "National Parks & Monuments in \(stateName)",
                                      subtitle: "Federal national parks, monuments, and historic reserves in \(stateName).",
                                      viewAllCount: parks.count > 6 ? parks.count : nil, onViewAll: onViewAll)
                    LazyVGrid(columns: ParkGrid.columns, spacing: 16) {
                        ForEach(parks.prefix(6)) { p in
                            NationalParkCard(park: p, stateName: stateName, style: .section) { open = p }
                        }
                    }
                }
            }
        }
        .task { await store.load() }
        .sheet(item: $open) { NationalParkSheet(park: $0) }
    }
}

/// "Park Activities & Outdoor Adventures in {state}": six activity cards (not tappable).
struct ParkActivitiesSection: View {
    let stateName: String
    private var store: ParkStore { ParkStore.shared }

    init(stateName: String) { self.stateName = stateName }

    var body: some View {
        let list = store.isLoaded ? store.activities(in: stateName) : []
        Group {
            if !list.isEmpty {
                ParkSectionFrame {
                    ParkSectionHeader(systemImage: "scope", title: "Park Activities & Outdoor Adventures in \(stateName)",
                                      subtitle: "Family-friendly recreation, scenic trails, wildlife viewing, and water activities in and near \(stateName)'s parks.")
                    LazyVGrid(columns: ParkGrid.columns, spacing: 16) {
                        ForEach(list.prefix(6)) { a in ParkActivityCard(activity: a) }
                    }
                }
            }
        }
        .task { await store.load() }
    }
}
