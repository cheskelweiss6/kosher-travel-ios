import SwiftUI

/// The website's reviews pieces on a city listing card (src/components/reviews/PlaceRating.tsx): the rating line under
/// the name, the "Reviews (N)" chip label, and the Reviews sheet both open (setReviewsTarget → PlaceReviewsSheet).
enum CityCardReviews {
    /// Web reviewsLabel: "Reviews" with none (or while loading), else "Reviews (N)".
    static func label(_ s: PlaceReviewSummary?) -> String {
        guard let s, s.count > 0 else { return "Reviews" }
        return "Reviews (\(s.count))"
    }
}

/// Web PlaceRating: "★ 4.5 · 3 reviews", or "☆ No reviews yet · Write one"; an empty line of the same height while
/// the city's reviews load, so the card doesn't jump. A tap opens the Reviews sheet.
struct CityCardRating: View {
    let summary: PlaceReviewSummary?
    let onOpen: () -> Void

    var body: some View {
        if let s = summary {
            Button(action: onOpen) {
                HStack(spacing: 4) {
                    if s.count > 0 {
                        Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(Color.navy)
                        Text(String(format: "%.1f", s.avg)).fontWeight(.semibold).foregroundStyle(Color.navy)
                        Text("·")
                        Text("\(s.count) review\(s.count == 1 ? "" : "s")")
                    } else {
                        Image(systemName: "star").font(.system(size: 11)).foregroundStyle(Color.textTertiary)
                        Text("No reviews yet ·")
                        Text("Write one").fontWeight(.semibold).foregroundStyle(Color.navy)
                    }
                }
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(s.count > 0
                ? "\(String(format: "%.1f", s.avg)) stars, \(s.count) review\(s.count == 1 ? "" : "s"). Open reviews"
                : "No reviews yet. Write one")
        } else {
            Color.clear.frame(height: 28).accessibilityHidden(true)
        }
    }
}

/// Web PlaceReviewsSheet: "Reviews" over the place's name, an X, and the same ReviewSection the parks use
/// (ParkReviewsSection: summary, write / edit with stars, words and photos, everyone's reviews, delete your own),
/// saved with the place's own id, kind and destination, as the website saves it.
/// `CityReviewsSheet(placeId:name:kind:destId:)` for any place (a tour guide: "guide-<id>", kind "guide");
/// `CityReviewsSheet(item:)` for a city listing.
struct CityReviewsSheet: View {
    let placeId: String
    let name: String
    let kind: String
    var destId: String = ""
    @Environment(\.dismiss) private var dismiss

    init(placeId: String, name: String, kind: String, destId: String = "") {
        self.placeId = placeId
        self.name = name
        self.kind = kind
        self.destId = destId
    }

    init(item: PlaceItem) {
        self.init(placeId: item.reviewPlaceId ?? "", name: item.venue.name,
                  kind: item.category.reviewKind, destId: item.destId)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reviews").font(.body.weight(.semibold)).foregroundStyle(Color.navy)
                    Text(name).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.navy)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.leading, 16).padding(.trailing, 4).padding(.top, 10).padding(.bottom, 6)
            Divider().overlay(Color.hairline)
            ScrollView {
                if !placeId.isEmpty {
                    ParkReviewsSection(placeId: placeId, placeName: name, placeKind: kind, destId: destId)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                }
            }
        }
        .background(Color.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

extension View {
    /// The Reviews sheet for the card in `target`; when it closes, the place's reviews are read again and handed to
    /// `onChanged` (placeKey, reviews) so the card's rating and count catch up, as the website's onSummary does.
    func cityCardReviewsSheet(_ target: Binding<PlaceItem?>,
                              onChanged: ((String, [PlaceReview]) -> Void)? = nil) -> some View {
        modifier(CityCardReviewsSheetModifier(target: target, onChanged: onChanged))
    }
}

private struct CityCardReviewsSheetModifier: ViewModifier {
    @Binding var target: PlaceItem?
    let onChanged: ((String, [PlaceReview]) -> Void)?
    @State private var last: PlaceItem?

    func body(content: Content) -> some View {
        content
            .sheet(item: $target, onDismiss: refresh) { item in
                CityReviewsSheet(item: item)
                    .onAppear { last = item }
            }
    }

    private func refresh() {
        guard let onChanged, let pid = last?.reviewPlaceId else { return }
        Task {
            if let list = try? await PlaceReviewService.reviews(placeId: pid) { onChanged(PlaceKey.key(pid), list) }
        }
    }
}
