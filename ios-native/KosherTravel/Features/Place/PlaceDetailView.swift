import SwiftUI
import UIKit
import MapKit

/// The sheet for one listing, built to match the website's PlaceDetailsModal (src/components/PlaceDetailsModal.tsx) section
/// by section: the cover photo with the category label, name and city; Save / Share / Close; Photo Gallery; the kosher box;
/// Description; Contact & Links; Visit Specifications; Opening Hours & Schedule; Why It's Worth Visiting; What You Can Do
/// There; Exact Location & Map Preview; travelers' extras; Travel tips; Explore the Local Area; the disclaimer; and the
/// footer (Mark for Itinerary, Ask AI). Kept from the native sheet: the real map and everyone's reviews.
struct PlaceDetailView: View {
    let item: PlaceItem
    var onOpenStory: ((String) -> Void)? = nil
    var onReviewsChanged: ((String, [PlaceReview]) -> Void)? = nil
    /// A story author linking a venue (web onConfirmVisitedVenue); the box shows only when this is set.
    var onConfirmVisited: ((PlaceItem) -> Void)? = nil
    var isConfirmedVisited: Bool = false

    @Environment(AuthStore.self) private var auth
    @Environment(ExploreStore.self) private var explore
    @Environment(StoryFeed.self) private var feed
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var reviews: [PlaceReview] = []
    @State private var reviewsState: LoadState = .loading
    @State private var composing = false
    @State private var confirmDelete = false
    @State private var deleteError: String?

    @State private var photoIndex = 0
    @State private var isSaved = false
    @State private var addedToItinerary = false
    @State private var itineraryTimer: Task<Void, Never>?
    @State private var copied = false
    @State private var copyTimer: Task<Void, Never>?
    @State private var nearbyTab: PlaceSheetNearbyTab?

    enum LoadState { case loading, loaded, failed }

    private var v: Venue { item.venue }
    private var facts: PlaceSheetFacts { PlaceSheetFacts(item: item) }
    private var type: PlaceSheetType { item.sheetType }
    private var name: String { v.name.isEmpty ? "Unnamed Place" : v.name }
    private var city: String { item.sheetCity }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                cover
                VStack(alignment: .leading, spacing: 24) {
                    topSections
                    bottomSections
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .sensoryFeedback(.success, trigger: isSaved)
        .sensoryFeedback(.success, trigger: copied)
        .sensoryFeedback(.selection, trigger: photoIndex)
        .onAppear { isSaved = PlaceSheetFavorites.isSaved(name) }
        .task { await locate() }
        .task { await loadReviews() }
        .task { await feed.loadIfNeeded() }
        .sheet(isPresented: $composing) {
            PlaceReviewComposer(item: item, existing: myReview) { await loadReviews() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var topSections: some View {
        if onConfirmVisited != nil { visitedBox }
        if gallery.count > 1 { galleryStrip }
        if !v.kashrus.isEmpty || !facts.kosherFriendlyNotes.isEmpty { kosherBox }
        if !facts.description.isEmpty { descriptionBox }
        contactBox
        if facts.hasVisitSpecs { visitSpecs }
        if !facts.openingHours.isEmpty { hoursBox }
        if !facts.whyVisit.isEmpty { whyBox }
    }

    @ViewBuilder
    private var bottomSections: some View {
        if !facts.whatToDo.isEmpty { whatToDoSection }
        locationSection
        extras
        tipsBox
        exploreLocal
        if item.reviewPlaceId != nil { reviewsSection }
        disclaimer
    }

    // MARK: cover (web 416-524)

    /// web galleryPhotos: the listing's own photos, else the website's curated photos for that name, else the
    /// category default (Chabad / shul / grocery) or the navy "no verified photo yet" tile ("" = that fallback).
    private var gallery: [String] {
        let own = item.photos.filter { !PhotoFallback.isPlaceholder($0) }
        if !own.isEmpty { return own }
        if var list = PlaceSheetLocationPhotos.resolve(v.name) {
            if PhotoFallback.category(type.rawValue) != nil { list = list.filter { !PhotoFallback.isPlaceholder($0) } }
            if !list.isEmpty { return list }
        }
        return [""]
    }

    private var cover: some View {
        let photos = gallery
        return ZStack(alignment: .bottomLeading) {
            TabView(selection: $photoIndex) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, url in
                    RemoteImage(url: url, maxPixel: 1400, venue: true, category: type.rawValue)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.3), .clear], startPoint: .bottom, endPoint: .top)
                .allowsHitTesting(false)

            if photos.count > 1 {
                HStack {
                    coverArrow("chevron.left", label: "Previous photo") { step(-1) }
                    Spacer()
                    coverArrow("chevron.right", label: "Next photo") { step(1) }
                }
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(type.label.uppercased())
                } icon: {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(Color.navy)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.95), in: Capsule())
                .padding(.bottom, 4)
                Text(name)
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                if !city.isEmpty {
                    Label(city, systemImage: "mappin")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.trailing, 20)
            .allowsHitTesting(false)
        }
        .frame(height: 240)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .clipped()
        .overlay(alignment: .topTrailing) { coverButtons.padding(.top, 16).padding(.trailing, 16) }
    }

    private func step(_ d: Int) {
        let n = gallery.count
        guard n > 1 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { photoIndex = (photoIndex + d + n) % n }
    }

    private func coverArrow(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.4), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var shareText: String { "Check out \(name) in \(city)! - Shared via Kosher Travel Hub." }

    private var coverButtons: some View {
        HStack(spacing: 8) {
            Button { toggleSave() } label: {
                Image(systemName: isSaved ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSaved ? Color.white : Color.navy)
                    .frame(width: 38, height: 38)
                    .background(isSaved ? Color.navy : Color.white.opacity(0.95), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSaved ? "Saved to Favorites" : "Add to Favorites")

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.navy)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.95), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Share \(name)")

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.navy.opacity(0.85), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private func toggleSave() {
        isSaved = PlaceSheetFavorites.toggle(name: name, venue: v)
    }

    // MARK: visited (web 535-559)

    private var visitedBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.navy, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Visited during your trip?").font(.caption.weight(.heavy)).foregroundStyle(Color.navy).lineLimit(1)
                Text("Link this verified directory venue to your story.").font(.caption2).foregroundStyle(Color.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { onConfirmVisited?(item) } label: {
                Text(isConfirmedVisited ? "✓ Confirmed Visited" : "Yes, this is the place I visited")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
    }

    // MARK: photo gallery (web 561-586)

    private var galleryStrip: some View {
        let photos = gallery
        return VStack(alignment: .leading, spacing: 8) {
            PlaceSheetHeading(title: "Photo Gallery", icon: "eye", strong: false)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(photos.enumerated()), id: \.offset) { i, url in
                        Button { withAnimation(.easeInOut(duration: 0.25)) { photoIndex = i } } label: {
                            RemoteImage(url: url, maxPixel: 300, venue: true, category: type.rawValue)
                                .frame(width: 80, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(photoIndex == i ? Color.navy : Color.clear, lineWidth: 2)
                                )
                                .opacity(photoIndex == i ? 1 : 0.8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Preview \(i + 1)")
                    }
                }
                .padding(2)
            }
        }
    }

    // MARK: kosher box (web 588-605)

    private var kosherBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaceSheetHeading(title: "Kosher Program & Shabbat Accommodations", icon: "checkmark.shield", strong: true)
            if !v.kashrus.isEmpty {
                (Text("Supervision: ").font(.caption.weight(.bold)) + Text(v.kashrus).font(.caption.weight(.heavy)))
                    .foregroundStyle(Color.navy)
                    .accessibilityLabel("Supervision: \(v.kashrus)")
                PlaceSheetVerifyNote()
            }
            if !facts.kosherFriendlyNotes.isEmpty {
                Text(facts.kosherFriendlyNotes)
                    .font(.caption)
                    .foregroundStyle(Color.navy)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
    }

    // MARK: description (web 607-617)

    private var descriptionBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaceSheetHeading(title: "Description", icon: "book", strong: true)
            Text(facts.description)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
    }

    // MARK: contact & links (web 619-747)

    /// web address: address, else location / exactLocation, else the city.
    private var address: String { v.address.isEmpty ? city : v.address }

    /// web directionsUrl: the listing's own directions link, else a Google Maps search for name + address (the app's
    /// link opener sends it to the remembered map app or the "Open in" chooser, as the app does on the website).
    private var directionsURL: URL? {
        if let d = v.directions, !d.isEmpty, let u = URL(string: d) { return u }
        return PlaceSheetLinks.googleSearch(name + " " + address)
    }

    private func openDirections() {
        if let u = directionsURL { openURL(u) }
    }

    private var contactBox: some View {
        VStack(alignment: .leading, spacing: 14) {
            PlaceSheetHeading(title: "Contact & Links", icon: "location.north.line", strong: false)
            Divider().overlay(Color.hairline)

            HStack(alignment: .top, spacing: 10) {
                PlaceSheetRowIcon(name: "mappin.and.ellipse")
                VStack(alignment: .leading, spacing: 4) {
                    Text(address)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.navy)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    HStack(spacing: 14) {
                        Button { openDirections() } label: {
                            HStack(spacing: 3) {
                                Text("Get GPS Directions")
                                Image(systemName: "arrow.up.right.square").font(.system(size: 9, weight: .bold))
                            }
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Color.navy)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { copyAddress() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .bold))
                                Text(copied ? "Copied!" : "Copy GPS")
                            }
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(copied ? Color.navy : Color.textSecondary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, -10)
                }
            }

            HStack(spacing: 10) {
                PlaceSheetRowIcon(name: "globe")
                if let site = PlaceSheetLinks.website(v.website) {
                    PlaceSheetLinkButton(title: "Official Website", strong: true) { openURL(PlannerLinks.affiliate(site)) }
                } else if let search = PlaceSheetLinks.googleWebSearch(name + " " + city) {
                    PlaceSheetLinkButton(title: "Search the website", strong: false) { openURL(search) }
                }
                Spacer(minLength: 0)
            }

            if let booking = PlaceSheetLinks.website(facts.bookingLink) {
                HStack(spacing: 10) {
                    PlaceSheetRowIcon(name: "rosette")
                    PlaceSheetPillButton(title: "Booking Link") { openURL(PlannerLinks.affiliate(booking)) }
                    Spacer(minLength: 0)
                }
            } else if type == .attraction || type == .deep_experience, let find = PlaceSheetLinks.bookingSearch(name + " " + city) {
                HStack(spacing: 10) {
                    PlaceSheetRowIcon(name: "rosette")
                    PlaceSheetPillButton(title: "Find Bookings & Tickets") { openURL(find) }
                    Spacer(minLength: 0)
                }
            }

            if !v.phone.isEmpty {
                HStack(spacing: 10) {
                    PlaceSheetRowIcon(name: "phone")
                    if type == .grocery {
                        Text("Phone:").font(.caption.weight(.bold)).foregroundStyle(Color.textSecondary)
                    }
                    Button { if let tel = item.phoneURL { openURL(tel) } } label: {
                        Text(v.phone)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.navy)
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Call \(v.phone)")
                    Spacer(minLength: 0)
                }
            }

            ForEach(extraRows, id: \.title) { row in
                HStack(alignment: .top, spacing: 10) {
                    PlaceSheetRowIcon(name: row.icon)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).font(.caption2.weight(.semibold)).foregroundStyle(Color.textSecondary)
                        if let url = row.url {
                            Button { openURL(url) } label: {
                                Text(row.text).font(.caption.weight(.bold)).foregroundStyle(Color.navy).multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(row.text)
                                .font(.caption)
                                .foregroundStyle(Color.navy)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
    }

    private struct ExtraRow { let icon: String; let title: String; let text: String; let url: URL? }

    /// The listing's other facts the city cards show (rabbi, email, Shabbat meals, store type, features, distance, notes).
    private var extraRows: [ExtraRow] {
        var out: [ExtraRow] = []
        if let e = v.email, !e.isEmpty { out.append(.init(icon: "envelope", title: "Email", text: e, url: URL(string: "mailto:\(e)"))) }
        if let r = v.rabbi, !r.isEmpty { out.append(.init(icon: "person", title: "Rabbi", text: r, url: nil)) }
        if v.shabbatMeals == true { out.append(.init(icon: "fork.knife", title: "Shabbat meals", text: "Shabbat meals offered. Reserve ahead.", url: nil)) }
        if item.category == .grocery, let dedicated = v.isDedicated {
            out.append(.init(icon: "cart", title: "Store", text: dedicated ? "Kosher store" : "Kosher section in a general store", url: nil))
        }
        if let f = v.features, !f.isEmpty { out.append(.init(icon: "list.bullet", title: "Features", text: f, url: nil)) }
        if let d = v.distance, !d.isEmpty { out.append(.init(icon: "location", title: "Distance", text: d, url: nil)) }
        if let n = v.notes, !n.isEmpty { out.append(.init(icon: "note.text", title: "Notes", text: n, url: nil)) }
        return out
    }

    private func copyAddress() {
        UIPasteboard.general.string = address
        copyTimer?.cancel()
        copied = true
        copyTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { copied = false }
        }
    }

    // MARK: visit specifications (web 749-792)

    private var visitSpecs: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaceSheetHeading(title: "Visit Specifications", icon: "rosette", strong: false)
            Divider().overlay(Color.hairline)
            if !facts.estimatedVisitTime.isEmpty { specRow("clock", "Estimated Visit Time", facts.estimatedVisitTime) }
            if !facts.bestTimeToVisit.isEmpty { specRow("calendar", "Best Time to Visit", facts.bestTimeToVisit) }
            if !facts.admissionCost.isEmpty { specRow("dollarsign", "Admission Cost", facts.admissionCost) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
    }

    private func specRow(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            PlaceSheetRowIcon(name: icon)
            (Text("\(label): ").font(.caption.weight(.semibold)).foregroundColor(Color.textSecondary)
                + Text(value).font(.caption.weight(.bold)).foregroundColor(Color.navy))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: opening hours (web 794-802)

    private var hoursBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            PlaceSheetHeading(title: "Opening Hours & Schedule", icon: "clock", strong: false)
            Text(facts.openingHours)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.navy)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            PlaceSheetVerifyNote().padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
    }

    // MARK: why it's worth visiting (web 804-813) / what you can do there (815-832)

    private var whyBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlaceSheetHeading(title: "Why It\u{2019}s Worth Visiting & Highlights", icon: "star", strong: true)
            Text(facts.whyVisit)
                .font(.subheadline)
                .foregroundStyle(Color.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
    }

    private var whatToDoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaceSheetHeading(title: "What You Can Do There", icon: "backpack", strong: true)
            Divider().overlay(Color.hairline)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(facts.whatToDo.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.navy).padding(.top, 1)
                        Text(line).font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .hairline(radius: 16)
        }
    }

    // MARK: exact location & map preview (web 834-851; the real map is the native extra)

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaceSheetHeading(title: "Exact Location & Map Preview", icon: "map", strong: true)
            Divider().overlay(Color.hairline)
            if let c = coordinate {
                Map(position: $camera, interactionModes: []) {
                    Marker(name, systemImage: item.systemImage, coordinate: c)
                        .tint(Color.navy)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hairline(radius: 16)
                .onTapGesture { openDirections() }
                .accessibilityLabel("Map of \(name). Opens directions")
            }
            HStack(spacing: 12) {
                Image(systemName: "mappin")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.navy)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(Color.hairline, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy).lineLimit(1)
                    Text(address).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button { openDirections() } label: {
                    Label("Directions", systemImage: "location.north")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .hairline(radius: 16)
        }
    }

    private func locate() async {
        if let c = item.coordinate { setCoordinate(c); return }
        guard !v.address.isEmpty else { return }
        if let c = await PlaceGeocoder.shared.coordinate(for: v.address) { setCoordinate(c) }
    }

    private func setCoordinate(_ c: CLLocationCoordinate2D) {
        coordinate = c
        camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 900, longitudinalMeters: 900))
    }

    // MARK: travelers (web extraContent: TravelerPlaceExtra + PlaceInspiration)

    private func openStory(_ id: String) {
        guard let onOpenStory else { return }
        dismiss()
        onOpenStory(id)
    }

    @ViewBuilder
    private var extras: some View {
        if item.travelerCategory != nil { travelerNote }
        let handler: ((String) -> Void)? = onOpenStory == nil ? nil : { id in openStory(id) }
        TravelerPlaceExtra(item: item, onOpenStory: handler)
        let posts = inspiration
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Get Inspired: photos from travelers")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(Color.navy)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(posts) { p in
                            Button { openStory(p.id) } label: {
                                StoryInspirationTile(post: p, extra: nil, myUid: auth.uid)
                                    .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    /// web PlaceInspiration (PlaceStories.tsx:135-156): Inspiration posts whose place has this listing's name, in this city.
    private var inspiration: [StoryPost] {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c = city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !n.isEmpty else { return [] }
        return feed.inspiration.filter { s in
            s.placeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == n
                && (c.isEmpty || s.cityName.lowercased() == c)
        }
    }

    /// A place sent in by a traveler and approved (the 'places' collection).
    private var travelerNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Added by a traveler and approved by Kosher Travel", systemImage: "person.crop.circle.badge.checkmark")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
            if !item.travelerPostId.isEmpty, onOpenStory != nil {
                Button { openStory(item.travelerPostId) } label: {
                    Label("Read the traveler's story", systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .frame(minHeight: 44)
                }
            }
        }
    }

    // MARK: travel tips (web 855-865)

    private var tipsBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("TRAVEL TIPS").tracking(0.9)
            } icon: {
                Image(systemName: "sparkles").foregroundStyle(Color.navy)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textSecondary)
            Text(facts.travelTips(type))
                .font(.subheadline)
                .foregroundStyle(Color.navy.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .hairline(radius: 16)
    }

    // MARK: explore the local area (web 867-983; lists as App.tsx passes them)

    private var nearby: PlaceSheetNearby { PlaceSheetNearby(item: item, data: explore.data) }

    private var exploreLocal: some View {
        let near = nearby
        let tab = nearbyTab ?? near.defaultTab
        return VStack(alignment: .leading, spacing: 14) {
            Divider().overlay(Color.hairline)
            PlaceSheetHeading(title: "Explore the Local Area (\(city))", icon: "safari", strong: true)
            HStack(spacing: 2) {
                nearbyTabButton(.attractions, "Attractions (\(near.attractions.count))", current: tab)
                nearbyTabButton(.restaurants, "Restaurants (\(near.restaurants.count))", current: tab)
                nearbyTabButton(.hotels, "Hotels (\(near.hotels.count))", current: tab)
            }
            .padding(2)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .hairline(radius: 12)

            VStack(alignment: .leading, spacing: 8) {
                switch tab {
                case .attractions: attractionsList(near)
                case .restaurants: restaurantsList(near)
                case .hotels: hotelsList(near)
                }
            }
            .frame(minHeight: 120, alignment: .top)
        }
    }

    @ViewBuilder
    private func attractionsList(_ near: PlaceSheetNearby) -> some View {
                    if near.attractions.isEmpty {
                        nearbyEmpty("No other curated attractions listed nearby in \(city).")
                    } else {
                        ForEach(Array(near.attractions.prefix(4).enumerated()), id: \.offset) { _, a in
                            nearbyRow {
                                RemoteImage(url: a.photo, maxPixel: 200, venue: true)
                                    .frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } title: { Text(a.name).font(.caption.weight(.heavy)).foregroundStyle(Color.navy).lineLimit(1) } line: {
                                Label((a.cityName ?? "").isEmpty ? city : (a.cityName ?? ""), systemImage: "mappin")
                                    .font(.caption2.weight(.semibold)).foregroundStyle(Color.textTertiary).lineLimit(1)
                            }
                        }
                    }
                    }

    @ViewBuilder
    private func restaurantsList(_ near: PlaceSheetNearby) -> some View {
                    if near.restaurants.isEmpty {
                        nearbyEmpty("No kosher restaurants recorded directly in the \(city) area.")
                    } else {
                        ForEach(Array(near.restaurants.prefix(4).enumerated()), id: \.offset) { _, r in
                            nearbyRow { PlaceSheetIconBox(name: "fork.knife") } title: { Text(r.name).font(.caption.weight(.heavy)).foregroundStyle(Color.navy).lineLimit(1) } line: {
                                Label(r.kashrus.isEmpty ? (r.kind.isEmpty ? "Kosher" : r.kind) : r.kashrus, systemImage: "fork.knife")
                                    .font(.caption2.weight(.heavy)).foregroundStyle(Color.navy).lineLimit(1)
                            }
                        }
                    }
                    }

    @ViewBuilder
    private func hotelsList(_ near: PlaceSheetNearby) -> some View {
                    if near.hotels.isEmpty {
                        VStack(spacing: 2) {
                            Text("Hotel Advisory & walking-distance options").font(.caption.weight(.heavy)).foregroundStyle(Color.navy)
                            Text("We advise checking with local Jewish agencies regarding Shabbat-safe key-locks and kosher breakfast alternatives in the \(city) area.")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 16)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .hairline(radius: 12)
                    } else {
                        ForEach(Array(near.hotels.prefix(4).enumerated()), id: \.offset) { _, h in
                            nearbyRow { PlaceSheetIconBox(name: "bed.double") } title: {
                                HStack(spacing: 4) {
                                    Text(h.name).font(.caption.weight(.heavy)).foregroundStyle(Color.navy).lineLimit(1)
                                    Spacer(minLength: 2)
                                    if let p = h.price, !p.isEmpty {
                                        Text(p).font(.caption2.weight(.heavy)).foregroundStyle(Color.navy)
                                    }
                                }
                            } line: {
                                Text(h.description).font(.caption2.weight(.semibold)).foregroundStyle(Color.textSecondary).lineLimit(1)
                            }
                        }
                    }
    }

    private func nearbyTabButton(_ t: PlaceSheetNearbyTab, _ title: String, current: PlaceSheetNearbyTab) -> some View {
        Button { nearbyTab = t } label: {
            Text(title)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(current == t ? Color.navy : Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(current == t ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: current == t ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(current == t ? .isSelected : [])
    }

    private func nearbyEmpty(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .italic()
            .foregroundStyle(Color.textTertiary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 12)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private func nearbyRow<A: View, T: View, L: View>(@ViewBuilder leading: () -> A, @ViewBuilder title: () -> T,
                                                      @ViewBuilder line: () -> L) -> some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                title()
                line()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hairline(radius: 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: disclaimer (web 985-991)

    private var disclaimer: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 14)).foregroundStyle(Color.textTertiary)
            Text("Travel specifications, opening hours, kashrus credentials, and minyan schedules can change unexpectedly. We strongly advise confirming with local authorities or Chabad emissaries before making final plans.")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hairline(radius: 12)
    }

    // MARK: footer (web 995-1043; "Kosher Travel Guide" and Close show on wide screens only, as on the website)

    private var askAIPrompt: String {
        "Tell me more details, tips, and minyan or kosher dining hours for \"\(name)\" in \(city)."
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.hairline)
            HStack(spacing: 10) {
                if sizeClass == .regular {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("KOSHER TRAVEL GUIDE").font(.caption2.weight(.heavy)).tracking(1).foregroundStyle(Color.textTertiary)
                        Text("Verified details, directions, and Jewish travel resources.").font(.caption.weight(.bold)).foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Label("Close", systemImage: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.navy)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .hairline(radius: 12)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer(minLength: 0)
                }
                Button { markForItinerary() } label: {
                    Label(addedToItinerary ? "Added to trip" : "Mark for Itinerary",
                          systemImage: addedToItinerary ? "checkmark" : "bookmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(addedToItinerary ? Color.white : Color.navy)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(addedToItinerary ? Color.navy : Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .hairline(radius: 12)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: addedToItinerary) { _, new in new }
                Button { askAI() } label: {
                    Label("Ask AI", systemImage: "message")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 44)
                        .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.white)
    }

    private func markForItinerary() {
        itineraryTimer?.cancel()
        withAnimation(.easeInOut(duration: 0.35)) { addedToItinerary = true }
        itineraryTimer = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.35)) { addedToItinerary = false } }
        }
    }

    private func askAI() {
        let prompt = askAIPrompt
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            ShellRouter.shared.open(tab: "planner", prompt: prompt)
        }
    }

    // MARK: reviews (native: the same Firestore reviews the website's cards show)

    private var myReview: PlaceReview? {
        guard let uid = auth.uid else { return nil }
        return reviews.first { $0.userId == uid }
    }

    private var reviewsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Reviews", count: reviews.count)
            switch reviewsState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading reviews").font(.footnote).foregroundStyle(Color.textSecondary)
                }
            case .failed:
                HStack {
                    FeedStatusLine(message: "Reviews could not load.")
                    Spacer()
                    Button("Retry") { Task { await loadReviews() } }
                        .font(.footnote.weight(.semibold))
                }
            case .loaded:
                if reviews.isEmpty {
                    Text("No reviews yet.").font(.subheadline).foregroundStyle(Color.textSecondary)
                } else {
                    PlaceReviewSummaryCard(reviews: reviews)
                    ForEach(reviews) { r in
                        PlaceReviewRow(review: r, isMine: r.userId == auth.uid)
                        if r.id != reviews.last?.id { Divider().overlay(Color.hairline) }
                    }
                }
            }
            writeButton
        }
        .confirmationDialog("Delete your review?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete review", role: .destructive) { Task { await deleteMine() } }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Could not delete", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(deleteError ?? "") }
    }

    @ViewBuilder
    private var writeButton: some View {
        if auth.isSignedIn {
            HStack(spacing: 10) {
                Button { composing = true } label: {
                    Label(myReview == nil ? "Write a review" : "Edit your review", systemImage: "square.and.pencil")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.navy, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                if myReview != nil {
                    Button { confirmDelete = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color.alert)
                            .frame(width: 46, height: 46)
                            .hairline(radius: 14)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete your review")
                }
            }
        } else {
            Button { ShellRouter.shared.requireSignIn("Sign in to write a review.") } label: {
                Label("Sign in to write a review", systemImage: "person.crop.circle")
            }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.navy)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hairline(radius: 14)
        }
    }

    private func loadReviews() async {
        guard let pid = item.reviewPlaceId else { return }
        if reviews.isEmpty { reviewsState = .loading }
        do {
            let list = try await PlaceReviewService.reviews(placeId: pid)
            reviews = list
            reviewsState = .loaded
            onReviewsChanged?(PlaceKey.key(pid), list)
        } catch {
            reviewsState = reviews.isEmpty ? .failed : .loaded
        }
    }

    private func deleteMine() async {
        guard let mine = myReview else { return }
        do {
            try await PlaceReviewService.delete(reviewId: mine.id)
            await loadReviews()
        } catch {
            deleteError = "Your review could not be deleted. Check your connection and try again."
        }
    }
}

// MARK: - pieces

private struct PlaceActionLabel: View {
    let title: String
    let systemImage: String
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 17, weight: .regular))
            Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.navy)
        .frame(maxWidth: .infinity, minHeight: 56)
        .hairline(radius: 14)
        .contentShape(Rectangle())
    }
}

private struct PlaceActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { PlaceActionLabel(title: title, systemImage: systemImage) }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
    }
}

private struct PlaceDetailRow: View {
    struct Model { let icon: String; let title: String; let text: String; let action: URL? }
    let row: Model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let content = HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(Color.navy)
                .frame(width: 26, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.caption).foregroundStyle(Color.textSecondary)
                Text(row.text)
                    .font(.subheadline)
                    .foregroundStyle(row.action == nil ? Color.primary : Color.navy)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if row.action != nil {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Color.textTertiary)
                    .padding(.top, 10)
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        if let url = row.action {
            Button { openURL(url) } label: { content }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { UIPasteboard.general.string = row.text } label: { Label("Copy", systemImage: "doc.on.doc") }
                }
        } else {
            content.textSelection(.enabled)
        }
    }
}

/// Five stars and a count, e.g. "4.5 · 3 reviews".
struct PlaceStarLine: View {
    let avg: Double
    let count: Int
    var body: some View {
        HStack(spacing: 5) {
            PlaceStars(value: avg, size: 12)
            Text(String(format: "%.1f", avg)).font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
            Text("·").foregroundStyle(Color.textSecondary)
            Text("\(count) review\(count == 1 ? "" : "s")").font(.footnote).foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(format: "%.1f", avg)) stars, \(count) review\(count == 1 ? "" : "s")")
    }
}

struct PlaceStars: View {
    let value: Double
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= value + 0.25 ? "star.fill" : (Double(i) - 0.5 <= value + 0.25 ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size, weight: .regular))
                    .foregroundStyle(Color.navy)
            }
        }
    }
}

private struct PlaceReviewSummaryCard: View {
    let reviews: [PlaceReview]
    var body: some View {
        let s = PlaceReviewSummary(reviews)
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 2) {
                Text(String(format: "%.1f", s.avg)).font(.system(.largeTitle, design: .serif).weight(.bold)).foregroundStyle(Color.navy)
                PlaceStars(value: s.avg, size: 11)
                Text("\(s.count) review\(s.count == 1 ? "" : "s")").font(.caption).foregroundStyle(Color.textSecondary)
            }
            VStack(spacing: 3) {
                ForEach((1...5).reversed(), id: \.self) { star in
                    let n = reviews.filter { $0.rating == star }.count
                    HStack(spacing: 6) {
                        Text("\(star)").font(.caption2.monospacedDigit()).foregroundStyle(Color.textSecondary).frame(width: 10)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.surface)
                                Capsule().fill(Color.navy)
                                    .frame(width: s.count == 0 ? 0 : g.size.width * CGFloat(n) / CGFloat(s.count))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
        .padding(14)
        .hairline(radius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: "Average %.1f stars from %d reviews", s.avg, s.count))
    }
}

private struct PlaceReviewRow: View {
    let review: PlaceReview
    let isMine: Bool
    @ScaledMetric(relativeTo: .subheadline) private var face: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Group {
                    if review.userPhoto.hasPrefix("https://") {
                        RemoteImage(url: review.userPhoto, maxPixel: 120)
                    } else {
                        Text(String(review.userName.prefix(1)).uppercased())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.navy)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.surface)
                    }
                }
                .frame(width: face, height: face)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isMine ? "\(review.userName) (you)" : review.userName)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                    HStack(spacing: 6) {
                        PlaceStars(value: Double(review.rating), size: 10)
                        Text(TimeAgo.string(review.updatedAtMs)).font(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if !review.text.isEmpty {
                Text(review.text).font(.subheadline).foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !review.photoUrls.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(review.photoUrls, id: \.self) { u in
                            RemoteImage(url: u, maxPixel: 500)
                                .frame(width: 96, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Write or edit your review: 1-5 stars and up to 1000 characters (photos stay as they were; adding photos is on the website).
struct PlaceReviewComposer: View {
    let item: PlaceItem
    let existing: PlaceReview?
    let onSaved: () async -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var rating = 0
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?
    @State private var saved = 0
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { i in
                            Button {
                                rating = i
                            } label: {
                                Image(systemName: i <= rating ? "star.fill" : "star")
                                    .font(.system(size: 28, weight: .regular))
                                    .foregroundStyle(Color.navy)
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                            .accessibilityAddTraits(i == rating ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .sensoryFeedback(.selection, trigger: rating)
                } header: {
                    Text(item.venue.name)
                }
                Section {
                    TextField("What should other travelers know?", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                        .focused($focused)
                        .onChange(of: text) { _, new in
                            if new.count > PlaceReviewService.textMax { text = String(new.prefix(PlaceReviewService.textMax)) }
                        }
                } footer: {
                    HStack {
                        if let error { Text(error).foregroundStyle(Color.alert) }
                        Spacer()
                        Text("\(text.count)/\(PlaceReviewService.textMax)")
                    }
                }
            }
            .navigationTitle(existing == nil ? "Write a review" : "Edit your review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else {
                        Button(existing == nil ? "Post" : "Save") { Task { await save() } }
                            .disabled(rating < 1)
                            .fontWeight(.semibold)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saved)
        }
        .onAppear {
            if let e = existing { rating = e.rating; text = e.text }
        }
        .interactiveDismissDisabled(saving)
    }

    private func save() async {
        guard let uid = auth.uid else { error = "Sign in on the Profile tab to write a review."; return }
        guard rating >= 1 else { error = "Choose 1 to 5 stars."; return }
        saving = true
        error = nil
        defer { saving = false }
        let name = auth.displayName.isEmpty ? (auth.email.split(separator: "@").first.map(String.init) ?? "Traveler") : auth.displayName
        do {
            try await PlaceReviewService.save(item: item, uid: uid, name: name, photo: auth.photoURL, rating: rating, text: text)
            saved += 1
            await onSaved()
            dismiss()
        } catch {
            self.error = "Your review could not be saved. Check your connection and try again."
        }
    }
}
