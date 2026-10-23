import SwiftUI

// MARK: - Pieces both park sheets share (web StateParkDetailModal / NationalParkDetailModal)

enum ParkSheetTab: String, CaseIterable, Identifiable, Hashable {
    case overview, activities, visitorInfo, reviews
    var id: String { rawValue }

    /// The website's tab words: Overview, Activities, Visitor Info, "Reviews (N)" once there are any.
    func label(reviewCount: Int?) -> String {
        switch self {
        case .overview: return "Overview"
        case .activities: return "Activities"
        case .visitorInfo: return "Visitor Info"
        case .reviews:
            if let n = reviewCount, n > 0 { return "Reviews (\(n))" }
            return "Reviews"
        }
    }
}

struct ParkSheetTabBar: View {
    @Binding var tab: ParkSheetTab
    let reviewCount: Int?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(ParkSheetTab.allCases) { t in
                        let on = tab == t
                        Button {
                            tab = t
                        } label: {
                            VStack(spacing: 8) {
                                Text(t.label(reviewCount: reviewCount))
                                    .font(.subheadline.weight(on ? .bold : .semibold))
                                    .foregroundStyle(on ? Color.navy : Color.textSecondary)
                                    .lineLimit(1)
                                Rectangle()
                                    .fill(on ? Color.navy : Color.clear)
                                    .frame(height: 2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, Theme.pagePadding - 12)
            }
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
        .sensoryFeedback(.selection, trigger: tab)
    }
}

/// The banner photos (web PlacePhotosGallery): swipe between them, a counter, "Back to Parks" and a close button.
struct ParkSheetHero: View {
    let name: String
    let photos: [String]
    let onClose: () -> Void
    @State private var page = 0
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 260

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if photos.isEmpty {
                    NoPhotoTile()
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { i, url in
                            RemoteImage(url: ParkImage.sized(url, width: 960), maxPixel: 1400, venue: true)
                                .clipped()
                                .tag(i)
                                .accessibilityLabel("\(name) photo \(i + 1) of \(photos.count)")
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: min(height, 360))
            .clipped()

            HStack {
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.footnote.weight(.semibold))
                        Text("Back to Parks").font(.footnote.weight(.bold))
                    }
                    .foregroundStyle(Color.navy)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 36)
                    .background(.regularMaterial, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.navy)
                        .frame(width: 36, height: 36)
                        .background(.regularMaterial, in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if photos.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(page + 1) / \(photos.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }
                }
                .padding(12)
                .allowsHitTesting(false)
            }
        }
        .frame(height: min(height, 360))
    }
}

/// A section heading inside a park sheet.
struct ParkSheetTitle: View {
    var systemImage: String? = nil
    let text: String
    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage).font(.subheadline.weight(.semibold))
            }
            Text(text)
        }
        .font(.headline)
        .foregroundStyle(Color.navy)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The grey box the website uses for quick facts and paragraphs.
struct ParkInfoBox<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .hairline(radius: Theme.cardRadius)
    }
}

/// A small caps label over a value (web "Best Time to Visit" / "Entrance Fees" boxes).
struct ParkFact: View {
    let label: String
    var systemImage: String? = nil
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let systemImage { Image(systemName: systemImage).font(.footnote).foregroundStyle(Color.navy) }
                Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A rounded chip with an optional icon (wildlife, activities).
struct ParkChip: View {
    var systemImage: String? = nil
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption) }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Color.navy)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Color.white, in: Capsule())
        .overlay { Capsule().strokeBorder(Color.hairline, lineWidth: 1) }
    }
}

/// Wrapping row of chips.
struct ParkFlow: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0 && x + s.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = Swift.max(rowHeight, s.height)
            widest = Swift.max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: Swift.min(s.width, bounds.width), height: s.height))
            x += s.width + spacing
            rowHeight = Swift.max(rowHeight, s.height)
        }
    }
}

/// Chips that wrap onto new lines.
struct ParkChipFlow: View {
    let items: [String]
    var systemImage: String? = nil
    var body: some View {
        ParkFlow(spacing: 8).callAsFunction {
            ForEach(Array(items.enumerated()), id: \.offset) { _, t in ParkChip(systemImage: systemImage, text: t) }
        }
    }
}

/// A trail's difficulty: an outlined tag for Easy / Moderate, filled navy for anything harder (the website's
/// green / amber / navy, in the app's navy-only palette).
struct ParkDifficultyTag: View {
    let difficulty: String
    var body: some View {
        let d = difficulty.lowercased()
        let filled = !(d == "easy" || d == "moderate")
        Text(difficulty.uppercased())
            .font(.caption2.weight(.heavy))
            .tracking(0.4)
            .foregroundStyle(filled ? Color.white : Color.navy)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(filled ? Color.navy : Color.white, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1)
                }
            }
    }
}

/// A big full-width link button (Official Website / Google Maps Directions / Directions on Maps).
struct ParkLinkButton: View {
    let title: String
    let systemImage: String
    var filled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(filled ? Color.white : Color.navy)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(filled ? Color.navy : Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if !filled { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1) }
                }
        }
        .buttonStyle(.plain)
    }
}

/// "Close Park Details" at the bottom of both sheets.
struct ParkCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Close Park Details", systemImage: "xmark")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.navy, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// One trail card (both sheets).
struct ParkTrailRow: View {
    let trail: ParkTrail
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(trail.name).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
                    .fixedSize(horizontal: false, vertical: true)
                if !trail.difficulty.isEmpty { ParkDifficultyTag(difficulty: trail.difficulty) }
                Spacer(minLength: 0)
            }
            if !trail.length.isEmpty {
                Text(trail.length).font(.caption.weight(.semibold).monospaced()).foregroundStyle(Color.textSecondary)
            }
            if !trail.description.isEmpty {
                Text(trail.description).font(.footnote).foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .hairline(radius: 14)
    }
}

/// A bullet line with an icon in front (tips, drives, ranger programs, nearby places).
struct ParkIconLine: View {
    let systemImage: String
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.footnote)
                .foregroundStyle(Color.navy)
                .frame(width: 18)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

struct ParkPhotoID: Identifiable, Hashable {
    let url: String
    var id: String { url }
}

/// Full-size photo, tap or X to close (web lightbox).
struct ParkLightbox: View {
    let url: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            RemoteImage(url: ParkImage.sized(url, width: 1280), maxPixel: 2000)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onTapGesture { dismiss() }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel("Close")
        }
    }
}
