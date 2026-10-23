import SwiftUI
import UIKit
import MapKit

/// The sheet for one listing: photos, name, hechsher, actions (call, directions, website, share), details, a map pin
/// and the reviews everyone wrote (written only when signed in, same Firestore documents as the website).
struct PlaceDetailView: View {
    let item: PlaceItem
    var onOpenStory: ((String) -> Void)? = nil
    var onReviewsChanged: ((String, [PlaceReview]) -> Void)? = nil

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var reviews: [PlaceReview] = []
    @State private var reviewsState: LoadState = .loading
    @State private var composing = false
    @State private var confirmDelete = false
    @State private var deleteError: String?

    enum LoadState { case loading, loaded, failed }

    private var v: Venue { item.venue }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    photos
                    header
                    actions
                    if !detailRows.isEmpty { details }
                    if !v.address.isEmpty || coordinate != nil { mapCard }
                    if item.travelerCategory != nil { travelerNote }
                    if item.reviewPlaceId != nil { reviewsSection }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Color.white)
            .navigationTitle(v.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.navy)
                            .frame(width: 30, height: 30)
                            .hairline(radius: 15)
                    }
                    .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if let url = item.appleMapsURL {
                        ShareLink(item: url, subject: Text(v.name), message: Text(item.shareText)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color.navy)
                        }
                        .accessibilityLabel("Share \(v.name)")
                    }
                }
            }
        }
        .task { await locate() }
        .task { await loadReviews() }
        .sheet(isPresented: $composing) {
            PlaceReviewComposer(item: item, existing: myReview) { await loadReviews() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: photos

    @ViewBuilder
    private var photos: some View {
        let list = item.photos
        if list.count > 1 {
            TabView {
                ForEach(list, id: \.self) { url in
                    RemoteImage(url: url, maxPixel: 1400)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .aspectRatio(16 / 10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if let one = list.first {
            RemoteImage(url: one, maxPixel: 1400)
                .aspectRatio(16 / 10, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(v.name)
                .font(.serifTitle(.title2))
                .foregroundStyle(Color.navy)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TagLabel(text: (item.travelerCategory ?? item.category).label)
                if let t = v.tags, !t.isEmpty {
                    ForEach(t.prefix(2), id: \.self) { TagLabel(text: $0) }
                }
            }
            if !v.kashrus.isEmpty {
                Label {
                    Text(v.kashrus).font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                } icon: {
                    Image(systemName: "checkmark.seal").foregroundStyle(Color.navy)
                }
                .accessibilityLabel("Hechsher: \(v.kashrus)")
            }
            if item.reviewPlaceId != nil, reviewsState == .loaded, !reviews.isEmpty {
                let s = PlaceReviewSummary(reviews)
                PlaceStarLine(avg: s.avg, count: s.count)
            }
        }
    }

    // MARK: actions (Apple Maps style)

    private var actions: some View {
        HStack(spacing: 10) {
            if let tel = item.phoneURL {
                PlaceActionButton(title: "Call", systemImage: "phone") { openURL(tel) }
            }
            if !v.address.isEmpty || coordinate != nil {
                PlaceActionButton(title: "Directions", systemImage: "arrow.triangle.turn.up.right.diamond") { openDirections() }
            }
            if let web = item.websiteURL {
                PlaceActionButton(title: "Website", systemImage: "safari") { openURL(web) }
            }
            if let url = item.appleMapsURL {
                ShareLink(item: url, subject: Text(v.name), message: Text(item.shareText)) {
                    PlaceActionLabel(title: "Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func openDirections() {
        if let c = coordinate {
            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: c))
            mapItem.name = v.name
            if item.phoneURL != nil { mapItem.phoneNumber = v.phone }
            mapItem.url = item.websiteURL
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        } else if let url = item.directionsURL {
            openURL(url)
        }
    }

    // MARK: details

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            let rows = detailRows
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                PlaceDetailRow(row: row)
                if i < rows.count - 1 { Divider().overlay(Color.hairline).padding(.leading, 40) }
            }
        }
        .padding(.horizontal, 14)
        .hairline(radius: 16)
    }

    private var detailRows: [PlaceDetailRow.Model] {
        var out: [PlaceDetailRow.Model] = []
        if !v.address.isEmpty {
            out.append(.init(icon: "mappin.and.ellipse", title: "Address", text: v.address, action: item.directionsURL))
        }
        if !v.phone.isEmpty { out.append(.init(icon: "phone", title: "Phone", text: v.phone, action: item.phoneURL)) }
        if item.websiteURL != nil { out.append(.init(icon: "globe", title: "Website", text: item.websiteHost, action: item.websiteURL)) }
        if let e = v.email, !e.isEmpty { out.append(.init(icon: "envelope", title: "Email", text: e, action: URL(string: "mailto:\(e)"))) }
        if let h = v.hours, !h.isEmpty { out.append(.init(icon: "clock", title: "Hours", text: h, action: nil)) }
        if let r = v.rabbi, !r.isEmpty { out.append(.init(icon: "person", title: "Rabbi", text: r, action: nil)) }
        if v.shabbatMeals == true { out.append(.init(icon: "fork.knife", title: "Shabbat meals", text: "Shabbat meals offered. Reserve ahead.", action: nil)) }
        if let p = v.price, !p.isEmpty { out.append(.init(icon: "tag", title: "Price", text: p, action: nil)) }
        if let f = v.features, !f.isEmpty { out.append(.init(icon: "list.bullet", title: "Features", text: f, action: nil)) }
        if let d = v.distance, !d.isEmpty { out.append(.init(icon: "location", title: "Distance", text: d, action: nil)) }
        if !v.description.isEmpty { out.append(.init(icon: "text.alignleft", title: "About", text: v.description, action: nil)) }
        if let n = v.notes, !n.isEmpty { out.append(.init(icon: "note.text", title: "Notes", text: n, action: nil)) }
        if let k = v.kosherNotes, !k.isEmpty { out.append(.init(icon: "checkmark.seal", title: "Kosher notes", text: k, action: nil)) }
        if item.category == .grocery, let dedicated = v.isDedicated {
            out.append(.init(icon: "cart", title: "Store", text: dedicated ? "Kosher store" : "Kosher section in a general store", action: nil))
        }
        return out
    }

    // MARK: map

    private var mapCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let c = coordinate {
                Map(position: $camera, interactionModes: []) {
                    Marker(v.name, systemImage: item.systemImage, coordinate: c)
                        .tint(Color.navy)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hairline(radius: 16)
                .onTapGesture { openDirections() }
                .accessibilityLabel("Map of \(v.name). Opens directions")
            } else {
                Button { openDirections() } label: {
                    Label("Open in Maps", systemImage: "map")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .hairline(radius: 14)
                }
                .buttonStyle(.plain)
            }
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

    // MARK: traveler

    private var travelerNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Added by a traveler and approved by Kosher Travel", systemImage: "person.crop.circle.badge.checkmark")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
            if !item.travelerPostId.isEmpty, let onOpenStory {
                Button {
                    let id = item.travelerPostId
                    dismiss()
                    onOpenStory(id)
                } label: {
                    Label("Read the traveler's story", systemImage: "book")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                }
            }
        }
    }

    // MARK: reviews

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
            Label("Sign in on the Profile tab to write a review", systemImage: "person.crop.circle")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
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
