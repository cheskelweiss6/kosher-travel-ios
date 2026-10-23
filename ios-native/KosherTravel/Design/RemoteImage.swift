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

/// A photo that fills the frame its parent gives it. Quiet grey with an outline icon while loading or when there is no photo.
struct RemoteImage: View {
    let url: String
    var maxPixel: CGFloat = 900
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Rectangle()
            .fill(Color.surface)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if failed || url.isEmpty {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .clipped()
            .task(id: url) {
                if url.isEmpty { failed = true; return }
                if let hit = ImagePipeline.shared.cached(url, maxPixel: maxPixel) { image = hit; return }
                let loaded = await ImagePipeline.shared.load(url, maxPixel: maxPixel)
                withAnimation(.easeOut(duration: 0.2)) {
                    image = loaded
                    failed = loaded == nil
                }
            }
    }
}
