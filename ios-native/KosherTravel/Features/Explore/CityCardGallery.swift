import SwiftUI
import UIKit
import PhotosUI

// MARK: - Photos (the website's PlacePhotosGallery rules)

/// Which photos a city listing card swipes through, by the website's PlacePhotosGallery rules
/// (src/components/PlacePhotosGallery.tsx): the place's own photos; with none, the owner's default artwork for
/// Chabad / shul / grocery venues; else the navy "no verified photo yet" tile (""). The few cards where the website's
/// fuller rule (curated attraction photos, curated location photos) gives something else are precomputed from the
/// website's own code into `CityCardPhotoData` (ios-native/scripts/export-cardphotos.sh), so nothing can drift.
enum CityCardPhotos {
    /// The website's `category` prop for a listing section ("restaurant", "grocery", "chabad", "synagogue", "hotel").
    static func webCategory(_ c: PlaceCategory) -> String {
        switch c {
        case .restaurant, .takeout: return "restaurant"
        case .grocery: return "grocery"
        case .chabad: return "chabad"
        case .shul, .mikvah: return "synagogue"
        case .hotel, .rental: return "hotel"
        default: return ""
        }
    }

    /// The gallery for a listing card on a city sub-page (`city` = the city page's name, as the website passes it).
    static func forItem(_ item: PlaceItem, city: String) -> [String] {
        resolve(name: item.venue.name, city: city, category: webCategory(item.category), photos: item.photos)
    }

    /// The gallery for any card: the place's name, the city page's name, the website's category word, and its photos
    /// (main photo first). "" in the result is the navy no-photo tile.
    static func resolve(name: String, city: String, category: String, photos: [String]) -> [String] {
        let key = "\(category.lowercased())|\(city.lowercased())|\(name.lowercased())"
        if let web = CityCardPhotoData.overrides[key] { return web }
        return simple(name: name, category: category, photos: photos)
    }

    /// The app's own rule (kept identical to `appGallery` in export-cardphotos.ts).
    static func simple(name: String, category: String, photos: [String]) -> [String] {
        var own: [String] = []
        for p in photos {
            let t = p.trimmingCharacters(in: .whitespaces)
            let ok = t.count >= 12 && (t.hasPrefix("https://") || t.hasPrefix("http://"))
            if ok && !own.contains(p) { own.append(p) }
        }
        if !own.isEmpty { return own }
        if let d = defaultCategory(name: name, category: category) { return [PhotoFallback.defaultsBase + d + ".webp"] }
        return [""]
    }

    /// The default-artwork word ("chabad", "shul", "grocery") for a card, or nil (web: categoryDefault in PlacePhotosGallery).
    static func defaultCategory(name: String, category: String) -> String? {
        if let d = PhotoFallback.category(category) { return d }
        let c = category.lowercased()
        let hotelOrRestaurant = c.contains("hotel") || c.contains("lodging") || c.contains("restaurant")
        return name.lowercased().contains("chabad") && !hotelOrRestaurant ? "chabad" : nil
    }
}

// MARK: - Photos a traveler contributed on this phone (web: localStorage contributed_photos_<name>)

/// The website keeps a photo you contribute on a card in the browser only (localStorage, keyed by the place's name),
/// first in the gallery, with Delete for it. The app keeps it on the phone the same way (Application Support).
final class CityCardContributions: ObservableObject {
    static let shared = CityCardContributions()
    @Published private(set) var version = 0

    private let fm = FileManager.default
    private var root: URL? {
        try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("contributed_photos", isDirectory: true)
    }

    private func folder(_ name: String) -> URL? {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let root else { return nil }
        // A stable file-safe folder name for the place's name (FNV-1a).
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return root.appendingPathComponent(String(h, radix: 16), isDirectory: true)
    }

    /// Newest first, as the website adds them ([new, ...old]).
    func photos(for name: String) -> [URL] {
        _ = version
        guard let dir = folder(name),
              let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "jpg" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Resized to at most 1200 px on the long side, JPEG 0.85 (the website's compressAndStoreImage).
    func add(_ data: Data, for name: String) -> Bool {
        guard let dir = folder(name), let image = UIImage(data: data) else { return false }
        let maxSide: CGFloat = 1200
        let w = image.size.width, h = image.size.height
        let scale = max(w, h) > maxSide ? maxSide / max(w, h) : 1
        let size = CGSize(width: max(1, (w * scale).rounded()), height: max(1, (h * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpg = resized.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let stamp = String(format: "%015.0f", Date().timeIntervalSince1970 * 1000)
            try jpg.write(to: dir.appendingPathComponent(stamp + ".jpg"), options: .atomic)
            version += 1
            return true
        } catch {
            return false
        }
    }

    func remove(_ url: URL) {
        try? fm.removeItem(at: url)
        version += 1
    }
}

// MARK: - The swipeable card gallery

/// The website's PlacePhotosGallery as a listing card shows it (h-32, rounded, no lightbox): swipe through the
/// photos, dots under them, the Contribute (camera) button at the top right, Delete on a photo you contributed,
/// and a tap on a photo runs `onTap` (the city pages open the place sheet, as the website's onImageClick does).
///
/// Use: `CityCardGallery(name: v.name, photos: CityCardPhotos.forItem(item, city: page.name),
///                       defaultCategory: "chabad", onTap: { ... })`. `photos` comes from `CityCardPhotos`
/// ("" = the navy no-photo tile); `defaultCategory` ("chabad" / "shul" / "grocery" or nil) is the artwork a photo
/// that fails to load falls back to.
struct CityCardGallery: View {
    let name: String
    let photos: [String]
    var defaultCategory: String? = nil
    var height: CGFloat = 128
    var cornerRadius: CGFloat = 12
    var contribute = true
    var onTap: (() -> Void)? = nil

    @ObservedObject private var contributed = CityCardContributions.shared
    @State private var index = 0
    @State private var pick: PhotosPickerItem?
    @State private var uploading = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var confirmDelete = false

    private enum Slide: Hashable { case local(URL), remote(String) }

    private var slides: [Slide] {
        contributed.photos(for: name).map(Slide.local) + (photos.isEmpty ? [""] : photos).map(Slide.remote)
    }

    var body: some View {
        let list = slides
        let current = min(index, max(0, list.count - 1))
        ZStack {
            TabView(selection: $index) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, s in
                    slide(s)
                        .contentShape(Rectangle())
                        .onTapGesture { onTap?() }
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            if list.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<list.count, id: \.self) { i in
                        Capsule()
                            .fill(i == current ? Color.white : Color.white.opacity(0.5))
                            .frame(width: i == current ? 20 : 6, height: 6)
                    }
                }
                .padding(.bottom, 14)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            if contribute {
                PhotosPicker(selection: $pick, matching: .images) {
                    Group {
                        if uploading {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: "camera").font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundStyle(Color.white)
                    .frame(width: 30, height: 26)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                }
                .disabled(uploading)
                .accessibilityLabel("Contribute a Photo")
                .padding(.top, 2).padding(.trailing, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if Self.isLocal(list[cityCardSafe: current]) {
                Button { confirmDelete = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.alert)
                        .frame(width: 30, height: 26)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove My Contribution")
                .padding(.top, 2).padding(.leading, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if let toast {
                Text(toast.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.6)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.navy.opacity(0.95), in: Capsule())
                    .padding(.top, 50)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) photos")
        .onChange(of: photos) { _, _ in index = 0 }
        .onChange(of: name) { _, _ in index = 0 }
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task { await add(item) }
        }
        .sensoryFeedback(Motion.Haptic.selection, trigger: index)
        .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) { removeCurrent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from this place's photos on this phone.")
        }
    }

    private static func isLocal(_ s: Slide?) -> Bool {
        if case .some(.local) = s { return true }
        return false
    }

    @ViewBuilder private func slide(_ s: Slide) -> some View {
        switch s {
        case .local(let url):
            CityCardLocalPhoto(url: url)
        case .remote(let url):
            RemoteImage(url: url, maxPixel: 900, venue: true, category: defaultCategory)
        }
    }

    private func add(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false; pick = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), contributed.add(data, for: name) else {
            show("Failed to process photo.")
            return
        }
        index = 0
        show("Photo contributed successfully!")
    }

    private func removeCurrent() {
        let list = slides
        guard case .some(.local(let url)) = list[cityCardSafe: min(index, max(0, list.count - 1))] else { return }
        contributed.remove(url)
        let left = contributed.photos(for: name).count
        if index >= left { index = max(0, left) }
        show("Photo removed successfully.")
    }

    private func show(_ text: String) {
        toastTask?.cancel()
        withAnimation(Motion.fade) { toast = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { withAnimation(Motion.fade) { toast = nil } }
        }
    }
}

/// A photo kept on the phone, filling the frame.
private struct CityCardLocalPhoto: View {
    let url: URL
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
            .task(id: url) { image = UIImage(contentsOfFile: url.path) }
    }
}

private extension Array {
    subscript(cityCardSafe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
