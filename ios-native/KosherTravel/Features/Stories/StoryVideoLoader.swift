import Foundation
import AVFoundation
import Network

/// Fast start for story videos (Cheskel, Oct 25 2026, build 268 on 5G: "I have good service and footage still loading
/// slow, have to fix that bug").
/// - Each video gets a short start buffer (about 2 s) and starts as soon as it can, instead of AVPlayer's default of
///   waiting until it predicts the whole clip can play without a pause (slow on the phone's 15-25 Mbit originals).
/// - The next video (next slide, next post in Get Inspired) is loaded ahead, so a swipe lands on a video that is
///   already buffering.
/// - On cellular or Low Data Mode the small 720p copy (<name>_720.mp4 next to the original in Storage, or a media
///   item's lowUrl) plays when one exists; on Wi-Fi the original plays. Originals are never changed or removed.
@MainActor
final class StoryVideoLoader {
    static let shared = StoryVideoLoader()

    /// cellular or Low Data Mode: the small copy plays when it exists
    private(set) var cellular = false
    private let monitor = NWPathMonitor()
    /// original url -> small copy url ("" = none)
    private var small: [String: String] = [:]
    private var probing: [String: Task<String, Never>] = [:]
    /// players made ahead of time, by the original url, newest last
    private var ahead: [String: AVPlayer] = [:]
    private var order: [String] = []
    private var audioReady = false

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let slow = path.isExpensive || path.isConstrained
            Task { @MainActor in self?.cellular = slow }
        }
        monitor.start(queue: DispatchQueue(label: "kt.story.video.path"))
    }

    /// The audio session is set once, not on every video start (it can block the main thread for a moment).
    func prepareAudio() {
        guard !audioReady else { return }
        audioReady = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Storage's small copy for an original: same folder, "<name>_720.mp4" (made Oct 25 2026 for 19 post videos).
    nonisolated static func smallCandidate(_ url: String) -> URL? {
        guard var c = URLComponents(string: url), c.host == "firebasestorage.googleapis.com" else { return nil }
        let path = c.percentEncodedPath
        guard let r = path.range(of: "/o/") else { return nil }
        let obj = String(path[r.upperBound...])
        guard !obj.isEmpty, !obj.contains("_720."), let dot = obj.lastIndex(of: ".") else { return nil }
        let ext = obj[obj.index(after: dot)...]
        guard !ext.isEmpty, ext.count <= 4, !ext.contains("%") else { return nil }
        c.percentEncodedPath = String(path[..<r.upperBound]) + String(obj[..<dot]) + "_720.mp4"
        c.percentEncodedQuery = "alt=media"
        return c.url
    }

    /// The copy is there: its Storage metadata answers 200 (a missing one answers 404 in about 0.1 s).
    nonisolated static func exists(_ media: URL) async -> Bool {
        guard var c = URLComponents(url: media, resolvingAgainstBaseURL: false) else { return false }
        c.percentEncodedQuery = nil
        guard let meta = c.url else { return false }
        let req = URLRequest(url: meta, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        guard let (_, resp) = try? await URLSession.shared.data(for: req), let h = resp as? HTTPURLResponse else { return false }
        return h.statusCode == 200
    }

    /// The small copy of a video, when there is one (checked once per file, then remembered).
    func smallURL(for m: StoryMediaInfo) async -> URL? {
        if !m.lowUrl.isEmpty, let u = URL(string: m.lowUrl) { return u }
        let key = m.url
        if let s = small[key] { return s.isEmpty ? nil : URL(string: s) }
        let task: Task<String, Never>
        if let t = probing[key] {
            task = t
        } else {
            guard let cand = Self.smallCandidate(key) else {
                small[key] = ""
                return nil
            }
            task = Task { await StoryVideoLoader.exists(cand) ? cand.absoluteString : "" }
            probing[key] = task
        }
        let s = await task.value
        small[key] = s
        probing[key] = nil
        return s.isEmpty ? nil : URL(string: s)
    }

    /// The file to play: the small copy on cellular when it exists, else the original.
    func source(for m: StoryMediaInfo) async -> URL? {
        guard !m.url.isEmpty, let original = URL(string: m.url) else { return nil }
        if cellular, let s = await smallURL(for: m) { return s }
        return original
    }

    /// A player item tuned for a quick start: about 2 s of video buffered before it plays.
    static func makeItem(_ src: URL, _ m: StoryMediaInfo) -> AVPlayerItem {
        let item = AVPlayerItem(asset: AVURLAsset(url: src))
        item.preferredForwardBufferDuration = 2
        if let end = m.trimEnd, end > (m.trimStart ?? 0) {
            item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        }
        return item
    }

    static func makePlayer(_ src: URL, _ m: StoryMediaInfo) -> AVPlayer {
        let p = AVPlayer(playerItem: makeItem(src, m))
        p.automaticallyWaitsToMinimizeStalling = false
        p.actionAtItemEnd = .pause
        return p
    }

    /// Start loading a video that is likely to be shown next (muted, paused). At most 3 are kept.
    func preload(_ m: StoryMediaInfo) {
        guard m.isVideo, !m.url.isEmpty, ahead[m.url] == nil else { return }
        let key = m.url
        Task { @MainActor in
            guard let src = await self.source(for: m), self.ahead[key] == nil else { return }
            let p = StoryVideoLoader.makePlayer(src, m)
            p.isMuted = true
            let start = max(0, m.trimStart ?? 0)
            if start > 0 {
                // the completion-handler form: inside this async Task the plain call is the async overload and needs await
                p.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
            }
            self.ahead[key] = p
            self.order.append(key)
            while self.order.count > 3 {
                let old = self.order.removeFirst()
                self.ahead[old]?.replaceCurrentItem(with: nil)
                self.ahead[old] = nil
            }
        }
    }

    /// The player made ahead for this video, if any (it is handed over, not kept).
    func take(_ url: String) -> AVPlayer? {
        guard let p = ahead.removeValue(forKey: url) else { return nil }
        order.removeAll { $0 == url }
        if p.currentItem?.status == .failed { return nil }
        return p
    }

    /// The feed closed: drop everything loaded ahead.
    func clear() {
        for p in ahead.values { p.replaceCurrentItem(with: nil) }
        ahead = [:]
        order = []
    }
}
