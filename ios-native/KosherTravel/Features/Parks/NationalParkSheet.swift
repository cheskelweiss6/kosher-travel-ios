import SwiftUI

/// The website's NationalParkDetailModal, phone layout: banner photos, "National Park Service Site", name, place and
/// "Open Year-Round", the four tabs, then the Park Logistics card, travel tips, nearby attractions and
/// "Close Park Details" (the website shows that column under every tab on a phone). Also used for tribal & scenic parks.
struct NationalParkSheet: View {
    let park: NationalPark
    @Environment(\.dismiss) private var dismiss
    @State private var tab: ParkSheetTab = .overview
    @State private var reviewCount: Int?

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
                    logistics
                    if !park.travelTips.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ParkSheetTitle(systemImage: "lightbulb", text: "Essential Travel Tips")
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(park.travelTips, id: \.self) { ParkIconLine(systemImage: "circle.fill", text: $0).imageScale(.small) }
                            }
                        }
                    }
                    if !park.nearbyAttractions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ParkSheetTitle(text: "Nearby Attractions")
                            VStack(spacing: 0) {
                                ForEach(park.nearbyAttractions, id: \.self) { a in
                                    HStack {
                                        Text(a).font(.subheadline).foregroundStyle(Color.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.textTertiary)
                                    }
                                    .padding(.vertical, 10)
                                    if a != park.nearbyAttractions.last { Rectangle().fill(Color.hairline).frame(height: 1) }
                                }
                            }
                        }
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
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ParkBadge(text: "National Park Service Site", systemImage: "mountain.2")
            Text(park.name)
                .font(.serifTitle(.title2))
                .foregroundStyle(Color.navy)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 14) {
                let place = ParkText.lastTwoParts(park.address)
                if !place.isEmpty {
                    Label(place, systemImage: "mappin.and.ellipse")
                }
                Label("Open Year-Round", systemImage: "clock")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    // MARK: Overview (web 279-318)

    @ViewBuilder
    private var overview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ParkSheetTitle(text: "About \(park.name)")
            Text(park.fullDescription).font(.body).fixedSize(horizontal: false, vertical: true)
        }
        if !park.wildlife.isEmpty {
            ParkInfoBox {
                ParkSheetTitle(systemImage: "pawprint", text: "Wildlife Spotting")
                Text("Keep your camera ready! The park offers a habitat for unique wildlife species:")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ParkChipFlow(items: park.wildlife)
            }
        }
        if !park.bestViewpoints.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(text: "Best Viewpoints")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(park.bestViewpoints.enumerated()), id: \.offset) { i, vp in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.navy, in: Circle())
                            Text(vp).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: Activities (web 319-388)

    @ViewBuilder
    private var activities: some View {
        if !park.thingsToDo.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(systemImage: "sparkles", text: "Popular Activities")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(park.thingsToDo, id: \.self) { ParkIconLine(systemImage: "checkmark", text: $0) }
                }
            }
        }
        if !park.hikingTrails.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ParkSheetTitle(systemImage: "figure.hiking", text: "Recommended Hiking Trails")
                ForEach(Array(park.hikingTrails.enumerated()), id: \.offset) { _, t in ParkTrailRow(trail: t) }
            }
        }
        if !park.scenicDrives.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(systemImage: "car", text: "Scenic Drives & Byways")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(park.scenicDrives.enumerated()), id: \.offset) { _, d in ParkIconLine(systemImage: "car", text: d.line) }
                }
            }
        }
    }

    // MARK: Visitor Info (web 389-446)

    @ViewBuilder
    private var visitorInfo: some View {
        ParkInfoBox {
            ParkSheetTitle(systemImage: "rosette", text: "Official Visitor Center")
            if !park.visitorCenter.name.isEmpty {
                Text(park.visitorCenter.name).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
            }
            if !park.visitorCenter.info.isEmpty {
                Text(park.visitorCenter.info).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            if !park.visitorCenter.hours.isEmpty {
                Label(park.visitorCenter.hours, systemImage: "clock").font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
            }
            if !park.visitorCenter.phone.isEmpty {
                Button { ParkLinks.call(park.visitorCenter.phone) } label: {
                    Label(park.visitorCenter.phone, systemImage: "phone").font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        if !park.rangerPrograms.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ParkSheetTitle(text: "Ranger Programs & Camps")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(park.rangerPrograms, id: \.self) { ParkIconLine(systemImage: "rosette", text: $0) }
                }
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            ParkSheetTitle(systemImage: "tent", text: "Camping & Overnight Information")
            Text(park.campingInfo).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: 10) {
            ParkSheetTitle(systemImage: "figure.roll", text: "Accessibility Information")
            Text(park.accessibilityInfo).font(.subheadline).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Park Logistics (web 453-549)

    private var logistics: some View {
        ParkInfoBox {
            Text("PARK LOGISTICS").font(.caption.weight(.heavy)).tracking(0.8).foregroundStyle(Color.navy)
            logisticsRow("dollarsign.circle", "Entrance Fees",
                         park.entranceFees.isEmpty ? "Check the park website for current fees" : park.entranceFees)
            logisticsRow("clock", "Hours of Operation", park.hours)
            logisticsRow("calendar", "Best Time to Visit", park.bestTimeToVisit)
            logisticsRow("mappin.and.ellipse", "Address / Location", park.address)
            VStack(spacing: 10) {
                if !park.googleMapsLocation.isEmpty {
                    ParkLinkButton(title: "Get Directions on Maps", systemImage: "location", filled: true) { ParkLinks.open(park.googleMapsLocation) }
                }
                if !park.officialWebsite.isEmpty {
                    ParkLinkButton(title: "Official NPS Website", systemImage: "globe") { ParkLinks.open(park.officialWebsite) }
                }
            }
            .padding(.top, 4)
        }
    }

    private func logisticsRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.navy)
                .frame(width: 34, height: 34)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .hairline(radius: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(.caption2.weight(.heavy)).tracking(0.5).foregroundStyle(Color.textSecondary)
                Text(value).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
