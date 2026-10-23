import SwiftUI
import UIKit
import PhotosUI
import FirebaseFirestore
import FirebaseStorage

/// Reviews for a park, written to the same Firestore documents the website's ReviewSection writes
/// (placeReviews/{placeKey}__{uid}, placeKind "park", no destId; state parks "sp-{id}", national "np-{id}").
/// Reading and deleting reuse PlaceReviewService; saving mirrors its save with the park's own place id.
enum ParkReviewService {
    static let photosMax = 3

    static func save(placeId: String, placeName: String, uid: String, name: String, photo: String,
                     rating: Int, text: String, photoUrls: [String]) async throws -> Bool {
        guard FirebaseBoot.isConfigured else { throw URLError(.cannotConnectToHost) }
        let id = PlaceReviewService.reviewId(placeId: placeId, uid: uid)
        let ref = Firestore.firestore().collection(PlaceReviewService.collection).document(id)
        let before = try? await ref.getDocument()
        let isNew = !(before?.exists ?? false)
        let old = before?.data() ?? [:]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let createdAt: Any = isNew ? FieldValue.serverTimestamp() : (old["createdAt"] ?? FieldValue.serverTimestamp())
        let who = String((name.isEmpty ? "Traveler" : name).prefix(80))
        let place = String((placeName.isEmpty ? "this place" : placeName).prefix(120))
        let stars = max(1, min(5, rating))
        let data: [String: Any] = [
            "placeKey": PlaceKey.key(placeId),
            "placeId": String(placeId.prefix(200)),
            "placeName": place,
            "placeKind": "park",
            "destId": "",
            "userId": uid,
            "userName": who,
            "userPhoto": String(photo.prefix(2000)),
            "rating": stars,
            "text": String(trimmed.prefix(PlaceReviewService.textMax)),
            "photoUrls": Array(photoUrls.prefix(photosMax)),
            "createdAt": createdAt,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        try await ref.setData(data)
        if isNew {
            for owner in PlaceReviewService.notifyUids where owner != uid {
                let note: [String: Any] = [
                    "kind": "review", "actorUid": uid, "actorName": who, "actorPhoto": String(photo.prefix(2000)),
                    "reviewId": id, "placeId": String(placeId.prefix(200)), "placeName": place, "placeKind": "park",
                    "destId": "", "rating": stars, "text": String(trimmed.prefix(140)),
                    "createdAt": FieldValue.serverTimestamp(), "read": false,
                ]
                Firestore.firestore().collection("users").document(owner).collection("notifications")
                    .document("r_" + id).setData(note) { err in
                        if let err { print("[KT] park review note not written: \(err)") }
                    }
            }
        }
        return isNew
    }

    /// web uploadReviewPhoto: storyMedia/{uid}/reviews/r-{time}-{rand}.jpg, shrunk to a JPEG.
    static func upload(_ image: UIImage, uid: String) async throws -> String {
        let side: CGFloat = 1600
        let scale = min(1, side / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = small.jpegData(compressionQuality: 0.82) else { throw URLError(.cannotDecodeContentData) }
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let rand = String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(5))
        let ref = Storage.storage().reference(withPath: "storyMedia/\(uid)/reviews/r-\(stamp)-\(rand).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        meta.cacheControl = "public,max-age=31536000"
        _ = try await ref.putDataAsync(jpeg, metadata: meta)
        return try await ref.downloadURL().absoluteString
    }

    /// web ago(): just now, 5m ago, 3h ago, 2d ago, else "Oct 2026".
    static func ago(_ ms: Double) -> String {
        let s = max(0, Date().timeIntervalSince1970 - ms / 1000)
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        if s < 86400 * 30 { return "\(Int(s / 86400))d ago" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.dateFormat = "MMM yyyy"
        return f.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}

private struct ParkPickedPhoto: Identifiable {
    let id = UUID()
    var url: String = ""          // already uploaded (editing)
    var image: UIImage? = nil     // new, uploaded on Post
}

/// The website's ReviewSection for a park: summary, Write / Edit review, the form (stars, words, up to 3 photos),
/// and everyone's reviews with Delete for your own (and for the admin).
struct ParkReviewsSection: View {
    let placeId: String
    let placeName: String
    var onCount: ((Int) -> Void)? = nil

    @Environment(AuthStore.self) private var auth
    @State private var list: [PlaceReview]?
    @State private var ok = true
    @State private var writing = false
    @State private var rating = 0
    @State private var text = ""
    @State private var photos: [ParkPickedPhoto] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var err: String?
    @State private var note: String?
    @State private var askedSignIn = false
    @State private var confirmDelete: PlaceReview?
    @State private var lightbox: ParkPhotoID?
    @FocusState private var focused: Bool

    init(placeId: String, placeName: String, onCount: ((Int) -> Void)? = nil) {
        self.placeId = placeId
        self.placeName = placeName
        self.onCount = onCount
    }

    private var mine: PlaceReview? {
        guard let uid = auth.uid, let list else { return nil }
        return list.first { $0.userId == uid }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryRow
            if let note {
                Text(note).font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
            }
            if writing { form }
            if let list, !list.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(list) { r in
                        row(r)
                        if r.id != list.last?.id { Rectangle().fill(Color.hairline).frame(height: 1) }
                    }
                }
            }
        }
        .task(id: placeId) { await load() }
        .onChange(of: auth.uid) { _, uid in
            guard uid != nil, askedSignIn else { return }
            askedSignIn = false
            writing = true
            note = rating > 0 ? "You’re signed in. Tap Post to share your review." : "You’re signed in. Tap the stars to rate."
        }
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            let chosen = items
            picks = []
            Task {
                for item in chosen where photos.count < ParkReviewService.photosMax {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        photos.append(ParkPickedPhoto(image: img))
                    }
                }
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let r = confirmDelete { Task { await remove(r) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(item: $lightbox) { ParkLightbox(url: $0.url) }
    }

    private var confirmTitle: String {
        guard let r = confirmDelete else { return "" }
        return r.userId == auth.uid ? "Delete your review?" : "Delete \(r.userName)'s review?"
    }

    // MARK: summary + the one button

    private var summaryRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Group {
                if list == nil {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading reviews…")
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                } else if let list, !list.isEmpty {
                    let avg = Double(list.reduce(0) { $0 + $1.rating }) / Double(list.count)
                    HStack(spacing: 6) {
                        Text(String(format: "%.1f", avg)).font(.title3.weight(.heavy)).foregroundStyle(Color.navy)
                        ParkStars(value: avg, size: 13)
                        Text("\(list.count) review\(list.count == 1 ? "" : "s")").font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text(ok ? "No reviews yet. Be the first." : "Couldn’t load reviews.")
                        .font(.footnote).foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
            if !writing && (ok || list == nil) {
                Button { startEdit() } label: {
                    Label(mine != nil ? "Edit review" : "Write a review", systemImage: mine != nil ? "pencil" : "star")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.navy)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .hairline(radius: 12)
                }
                .buttonStyle(.plain)
            }
            if !ok && list != nil {
                Button("Retry") { Task { await load(force: true) } }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.navy)
                    .frame(minHeight: 44)
            }
        }
    }

    // MARK: the form

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mine != nil ? "Edit your review" : "Rate \(placeName)")
                .font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { i in
                    Button {
                        rating = i
                        err = nil
                    } label: {
                        Image(systemName: i <= rating ? "star.fill" : "star")
                            .font(.system(size: 26))
                            .foregroundStyle(i <= rating ? Color.navy : Color.textTertiary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")")
                    .accessibilityAddTraits(rating == i ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: rating)
            TextField("What was it like? (optional)", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .font(.body)
                .focused($focused)
                .padding(12)
                .background(Color.white)
                .hairline(radius: 12)
                .onChange(of: text) { _, t in
                    if t.count > PlaceReviewService.textMax { text = String(t.prefix(PlaceReviewService.textMax)) }
                }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(photos) { p in
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if let img = p.image {
                                    Image(uiImage: img).resizable().scaledToFill()
                                } else {
                                    RemoteImage(url: p.url, maxPixel: 300)
                                }
                            }
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Button {
                                photos.removeAll { $0.id == p.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Color.navy, in: Circle())
                                    .frame(width: 44, height: 44, alignment: .topTrailing)
                            }
                            .buttonStyle(.plain)
                            .offset(x: 10, y: -10)
                            .accessibilityLabel("Remove photo")
                        }
                    }
                    if photos.count < ParkReviewService.photosMax {
                        PhotosPicker(selection: $picks, maxSelectionCount: ParkReviewService.photosMax - photos.count, matching: .images) {
                            Label("Add photos", systemImage: "camera")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Color.navy)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .hairline(radius: 12)
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            if let err {
                Text(err).font(.footnote.weight(.semibold)).foregroundStyle(Color.alert)
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { cancel() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(minHeight: 44)
                Button { Task { await post() } } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().controlSize(.small).tint(.white) }
                        Text(auth.isSignedIn ? (mine != nil ? "Save" : "Post") : "Sign in to post")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }
        }
        .padding(14)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .hairline(radius: Theme.cardRadius)
    }

    // MARK: one review

    private func row(_ r: PlaceReview) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if r.userPhoto.hasPrefix("https://") {
                    RemoteImage(url: r.userPhoto, maxPixel: 120)
                } else {
                    Text(String((r.userName.isEmpty ? "T" : r.userName).prefix(1)).uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.surface)
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(r.userName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy).lineLimit(1)
                    ParkStars(value: Double(r.rating), size: 11)
                    Text(ParkReviewService.ago(r.updatedAtMs)).font(.caption).foregroundStyle(Color.textSecondary)
                }
                if !r.text.isEmpty {
                    Text(r.text).font(.subheadline).foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if !r.photoUrls.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(r.photoUrls, id: \.self) { u in
                            Button { lightbox = ParkPhotoID(url: u) } label: {
                                RemoteImage(url: u, maxPixel: 400)
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if let uid = auth.uid, r.userId == uid || auth.isAdmin {
                    Button { confirmDelete = r } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.alert)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    // MARK: actions (web ReviewSection)

    private func load(force: Bool = false) async {
        if force { list = nil }
        ok = true
        do {
            let rows = try await PlaceReviewService.reviews(placeId: placeId)
            list = rows
            ok = true
            onCount?(rows.count)
        } catch {
            if list == nil { list = [] }
            ok = false
        }
    }

    private func startEdit() {
        if let mine {
            rating = mine.rating
            text = mine.text
            photos = mine.photoUrls.map { ParkPickedPhoto(url: $0) }
        }
        writing = true
        err = nil
        note = nil
        focused = true
    }

    private func cancel() {
        writing = false
        err = nil
        note = nil
        rating = 0
        text = ""
        photos = []
        focused = false
    }

    private func post() async {
        if busy { return }
        if rating == 0 { err = "Tap the stars to rate it."; return }
        guard let uid = auth.uid else {
            askedSignIn = true
            ShellRouter.shared.requireSignIn("Sign in to post your review")
            return
        }
        busy = true
        err = nil
        note = nil
        defer { busy = false }
        do {
            var urls: [String] = []
            for p in photos {
                if let img = p.image {
                    let u = try await ParkReviewService.upload(img, uid: uid)
                    urls.append(u)
                } else if !p.url.isEmpty {
                    urls.append(p.url)
                }
            }
            let name = !auth.displayName.isEmpty ? auth.displayName
                : (auth.email.split(separator: "@").first.map(String.init) ?? "Traveler")
            let isNew = try await ParkReviewService.save(placeId: placeId, placeName: placeName, uid: uid, name: name,
                                                         photo: auth.photoURL, rating: rating, text: text, photoUrls: urls)
            writing = false
            rating = 0
            text = ""
            photos = []
            focused = false
            note = isNew ? "Thanks, your review is posted." : "Your review is updated."
            await load()
        } catch {
            print("[KT] park review not posted: \(error)")
            err = "Your review wasn’t posted. Check your connection and tap Post again."
        }
    }

    private func remove(_ r: PlaceReview) async {
        do {
            try await PlaceReviewService.delete(reviewId: r.id)
            list = (list ?? []).filter { $0.id != r.id }
            onCount?(list?.count ?? 0)
            note = nil
        } catch {
            err = "Couldn’t delete it. Try again."
        }
    }
}

/// Five navy stars (web Stars: filled up to the rounded rating).
struct ParkStars: View {
    let value: Double
    var size: CGFloat = 13
    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= value.rounded() ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(Double(i) <= value.rounded() ? Color.navy : Color.textTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(value.rounded())) out of 5 stars")
    }
}
