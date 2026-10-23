import SwiftUI

/// The website's StateParkDetailModal, phone layout: banner photos, "Official State Park", name, address, then
/// Overview / Activities / Visitor Info / Reviews (N), and "Close Park Details".
struct StateParkSheet: View {
    let park: StatePark
    @Environment(\.dismiss) private var dismiss
    @State private var tab: ParkSheetTab = .overview
    @State private var reviewCount: Int?
    @State private var lightbox: ParkPhotoID?
    @State private var trailMap = false

    init(park: StatePark) { self.park = park }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ParkSheetHero(name: park.name, photos: park.photos) { dismiss() }
                header
                ParkSheetTabBar(tab: $tab, reviewCount: reviewCount)
                VStack(alignment: .leading, spacing: 28) {
                    switch tab {
                    case .overview: overview
                    case .activities: activities
                    case .visitorInfo: visitorInfo
                    case .reviews:
                        ParkReviewsSection(placeId: park.reviewPlaceId, placeName: park.name) { reviewCount = $0 }
                    }
                    ParkCloseButton { dismiss() }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color.white)
        .task(id: park.id) {
            if let list = try? await PlaceReviewService.reviews(placeId: park.reviewPlaceId) { reviewCount = list.count }
        }
        .fullScreenCover(item: $lightbox) { ParkLightbox(url: $0.url) }
        .fullScreenCover(isPresented: $trailMap) { ParkTrailMapView(park: park) }
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ParkBadge(text: "Official State Park", systemImage: "leaf")
            Text(park.name)
                .font(.serifTitle(.title2))
                .foregroundStyle(Color.navy)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !park.address.isEmpty {
                Label(park.address, systemImage: "mappin.and.ellipse")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: Overview (web 285-375)

    @ViewBuilder
    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ParkSheetTitle(systemImage: "leaf", text: "About the Park")
            Text(park.fullDescription).font(.body).foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        ParkInfoBox {
            ParkFact(label: "Best Time to Visit", systemImage: "calendar", value: park.bestTimeToVisit)
            Rectangle().fill(Color.hairline).frame(height: 1)
            ParkFact(label: "Entrance Fees", systemImage: "dollarsign.circle", value: park.entranceFees)
        }
        if !park.photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(text: "Photo Gallery")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                    ForEach(Array(park.photos.enumerated()), id: \.offset) { i, url in
                        Button { lightbox = ParkPhotoID(url: url) } label: {
                            Color.surface
                                .aspectRatio(4 / 3, contentMode: .fit)
                                .overlay { RemoteImage(url: ParkImage.sized(url, width: 500), maxPixel: 700, venue: true) }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(park.name) view \(i + 1)")
                    }
                }
            }
        }
        if !park.wildlife.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(systemImage: "bird", text: "Wildlife & Ecosystem")
                ParkChipFlow(items: park.wildlife, systemImage: "pawprint")
            }
        }
        if !park.tips.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(systemImage: "info.circle", text: "Tips for a Perfect Trip")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(park.tips, id: \.self) { ParkIconLine(systemImage: "lightbulb", text: $0) }
                }
            }
        }
    }

    // MARK: Activities (web 376-462)

    @ViewBuilder
    private var activities: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ParkSheetTitle(systemImage: "figure.hiking", text: "Scenic Trails & Hiking")
                Spacer(minLength: 8)
                Button { trailMap = true } label: {
                    Label("Trail Map", systemImage: "map")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(Color.navy, in: Capsule())
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(park.hikingTrails.enumerated()), id: \.offset) { _, t in ParkTrailRow(trail: t) }
        }
        VStack(alignment: .leading, spacing: 10) {
            ParkSheetTitle(systemImage: "tent", text: "Camping & Lodging Information")
            ParkInfoBox {
                Text(park.campingInfo).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
        if !park.fishingBoating.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(systemImage: "sailboat", text: "Water Activities & Boating")
                ParkInfoBox {
                    Text(park.fishingBoating).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !park.thingsToDo.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(systemImage: "safari", text: "Other Popular Activities")
                ParkChipFlow(items: park.thingsToDo, systemImage: "sparkles")
            }
        }
    }

    // MARK: Visitor Info (web 463-532)

    @ViewBuilder
    private var visitorInfo: some View {
        ParkInfoBox {
            ParkSheetTitle(systemImage: "building.2", text: "Visitor Center Info")
            if !park.visitorCenter.name.isEmpty {
                Text(park.visitorCenter.name).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
            }
            if !park.visitorCenter.hours.isEmpty {
                Text(park.visitorCenter.hours).font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
            }
            if !park.visitorCenter.info.isEmpty {
                Text(park.visitorCenter.info).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
        ParkInfoBox {
            ParkSheetTitle(systemImage: "clock", text: "Park Operating Hours")
            Text("Gates & Grounds").font(.caption.weight(.heavy)).foregroundStyle(Color.textSecondary)
            Text(park.hours).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        VStack(spacing: 10) {
            if !park.officialWebsite.isEmpty {
                ParkLinkButton(title: "Official Website", systemImage: "globe", filled: true) { ParkLinks.open(park.officialWebsite) }
            }
            if !park.googleMapsLocation.isEmpty {
                ParkLinkButton(title: "Google Maps Directions", systemImage: "location") { ParkLinks.open(park.googleMapsLocation) }
            }
        }
        if !park.nearbyAttractions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(systemImage: "sparkles", text: "Recommended Nearby Places")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(park.nearbyAttractions, id: \.self) { ParkIconLine(systemImage: "mappin", text: $0) }
                }
            }
        }
    }
}
