import SwiftUI
import UIKit
import ImageIO

/// Loads, downsamples and caches remote photos (memory + disk). WebP decodes natively.
final class ImagePipeline: @unchecked Sendable {
    static let shared = ImagePipeline()
    private let memory = NSCache<NSString, UIImage>()
    private let session: URLSession

    private init() {
        memory.totalCostLimit = 80 * 1024 * 1024
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache.shared
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.timeoutIntervalForRequest = 20
        session = URLSession(configuration: cfg)
    }

    static func configureCache() {
        URLCache.shared = URLCache(memoryCapacity: 40 * 1024 * 1024, diskCapacity: 400 * 1024 * 1024)
    }

    func cached(_ key: String, maxPixel: CGFloat) -> UIImage? {
        memory.object(forKey: "\(Int(maxPixel))|\(key)" as NSString)
    }

    func load(_ source: String, maxPixel: CGFloat) async -> UIImage? {
        let key = "\(Int(maxPixel))|\(source)" as NSString
        if let hit = memory.object(forKey: key) { return hit }
        var data: Data?
        if source.hasPrefix("data:") {
            if let comma = source.firstIndex(of: ",") {
                data = Data(base64Encoded: String(source[source.index(after: comma)...]), options: .ignoreUnknownCharacters)
            }
        } else if let url = URL(string: source) {
            var req = URLRequest(url: url)
            req.setValue("KosherTravel-iOS/2.0", forHTTPHeaderField: "User-Agent")
            if let result = try? await session.data(for: req),
               let http = result.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                data = result.0
            }
        }
        guard let data, let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        memory.setObject(image, forKey: key, cost: cost)
        return image
    }

    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        let opts = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts) else { return UIImage(data: data) }
        return UIImage(cgImage: cg)
    }
}

/// The website's photo rules (src/categoryDefaults.ts, src/photoPlaceholder.ts): a real photo of the place always wins;
/// a Chabad / shul / grocery venue without one (or whose photo fails) shows the owner's default artwork for that category;
/// anything else shows the neutral navy "no verified photo yet" tile. Never a stock photo of somewhere else.
enum PhotoFallback {
    static let defaultsBase = "https://www.yourkoshertravel.com/defaults/"

    /// "chabad", "synagogue" or "grocery" for a venue category / type word, else nil (web: defaultPhotoCategory).
    static func category(_ word: String?) -> String? {
        let c = (word ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        if c.isEmpty { return nil }
        if c.contains("chabad") { return "chabad" }
        if c.contains("synagogue") || c.contains("shul") { return "shul" }
        if c.contains("grocer") || c.contains("supermarket") { return "grocery" }
        return nil
    }

    /// True for an empty value or one of the website's built-in placeholders (inline SVG): web isPlaceholderPhoto.
    static func isPlaceholder(_ url: String) -> Bool {
        let u = url.trimmingCharacters(in: .whitespaces)
        return u.isEmpty || u.hasPrefix("data:image/svg")
    }

    /// The sources to try, in order.
    static func chain(_ url: String, category word: String?) -> [String] {
        var out: [String] = []
        if !isPlaceholder(url) { out.append(url) }
        if let c = category(word) { out.append(defaultsBase + c + ".webp") }
        return out
    }
}

/// The neutral "no verified photo yet" tile: navy with a faint outline map pin (the website's placeholder; solid navy
/// because the native brand has no gradients).
struct NoPhotoTile: View {
    var body: some View {
        Rectangle()
            .fill(Color.navy)
            .overlay {
                Image(systemName: "mappin")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.28))
            }
            .accessibilityHidden(true)
    }
}

/// A photo that fills the frame its parent gives it. Quiet grey with an outline icon while loading or when there is no photo.
/// `venue: true` (listing cards and place sheets) follows the website's venue photo rules instead: the category default
/// (Chabad / shul / grocery) when the place has no photo or it fails, else the navy no-photo tile.
struct RemoteImage: View {
    let url: String
    var maxPixel: CGFloat = 900
    var venue = false
    var category: String? = nil
    @State private var image: UIImage?
    @State private var failed = false

    private var sources: [String] {
        venue ? PhotoFallback.chain(url, category: category) : (url.isEmpty ? [] : [url])
    }

    var body: some View {
        Rectangle()
            .fill(Color.surface)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if failed || sources.isEmpty {
                    if venue {
                        NoPhotoTile()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .clipped()
            .task(id: url + "|" + (category ?? "") + (venue ? "|v" : "")) {
                image = nil
                failed = false
                let list = sources
                if list.isEmpty { failed = true; return }
                for source in list {
                    if let hit = ImagePipeline.shared.cached(source, maxPixel: maxPixel) { image = hit; return }
                    if let loaded = await ImagePipeline.shared.load(source, maxPixel: maxPixel) {
                        withAnimation(Motion.fade) { image = loaded }
                        return
                    }
                }
                withAnimation(Motion.fade) { failed = true }
            }
    }
}
