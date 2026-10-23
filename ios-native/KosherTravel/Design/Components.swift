import SwiftUI

struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.serifTitle())
                .foregroundStyle(Color.navy)
            Spacer()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small outlined label, e.g. GROCERY / CHABAD.
struct TagLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .foregroundStyle(Color.navy)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .hairline(radius: 6)
    }
}

/// An empty section stays honest: what is missing, and what would fill it.
struct EmptyNote: View {
    let title: String
    var detail: String? = nil
    var systemImage: String = "square.and.pencil"
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.navy)
                .frame(width: 36, height: 36)
                .hairline(radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                if let detail {
                    Text(detail).font(.footnote).foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

struct LoadingCards: View {
    var count = 3
    var minWidth: CGFloat = 220
    var aspect: CGFloat = 1.2   // width / height
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<count, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Color.surface)
                        .aspectRatio(aspect, contentMode: .fit)
                        .containerRelativeFrame(.horizontal) { len, _ in Layout.peekWidth(len, min: minWidth, spacing: 12) }
                }
            }
        }
        .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
        .scrollDisabled(true)
        .accessibilityLabel("Loading")
    }
}

/// Sizes that follow the screen instead of fixed widths (iPhone SE to Pro Max, iPad).
enum Layout {
    /// Width for cards in a sideways row: as many whole cards as fit at `min` width, plus a peek of the next one.
    static func peekWidth(_ length: CGFloat, min: CGFloat, spacing: CGFloat, margins: CGFloat = Theme.pagePadding * 2) -> CGFloat {
        let usable = Swift.max(length - margins, min)
        let n = Swift.max(1, (usable / min - 0.35).rounded(.down))
        return (usable - spacing * n) / (n + 0.35)
    }
    /// Width for `n` cards that fill the row exactly (n grows on wide screens).
    static func fillWidth(_ length: CGFloat, spacing: CGFloat, wideCount: Int = 3, compactCount: Int = 2,
                          margins: CGFloat = Theme.pagePadding * 2) -> CGFloat {
        let n = CGFloat(length > 600 ? wideCount : compactCount)
        return (length - margins - spacing * (n - 1)) / n
    }
}

/// Status line for the live part of a screen (shown only when something went wrong).
struct FeedStatusLine: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "wifi.exclamationmark")
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
    }
}

enum TimeAgo {
    static func string(_ ms: Double) -> String {
        guard ms > 0 else { return "" }
        let s = max(0, Date().timeIntervalSince1970 - ms / 1000)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        if s < 86400 * 30 { return "\(Int(s / 86400))d ago" }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}
