import SwiftUI
import AVKit
import AVFoundation
import Observation

/// Only one story video plays at a time anywhere in the app (Cheskel, Oct 23 2026: the previous video's sound kept
/// playing after swiping on). A player that starts pauses the one before it.
@MainActor
final class StoryVideoCenter {
    static let shared = StoryVideoCenter()
    private weak var current: AVPlayer?

    func claim(_ p: AVPlayer) {
        if let c = current, c !== p { c.pause() }
        current = p
    }

    func release(_ p: AVPlayer) {
        if current === p { current = nil }
    }

    /// Stops whatever is playing (a feed or a page closing).
    func stopAll() {
        current?.pause()
        current = nil
    }
}

/// Sound for story videos, one switch for the whole app like the web's VideoSound: on when a feed is opened by a tap
/// (the phone allows sound then); a video the poster muted always stays silent.
@Observable
final class StoryVideoSound {
    static let shared = StoryVideoSound()
    var on = true
}

/// The video surface: an AVPlayerLayer with no system controls (no frosted loading box, no play glyph over the video).
final class StoryPlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    /// Called once a real video frame is ready on the layer (never a black layer).
    var onFrame: (() -> Void)?
    private var frameObserver: NSKeyValueObservation?

    func watchFrames() {
        guard frameObserver == nil else { return }
        frameObserver = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] l, _ in
            guard l.isReadyForDisplay else { return }
            DispatchQueue.main.async { self?.onFrame?() }
        }
    }
}

struct StoryPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    var fill: Bool
    var onFrame: (() -> Void)? = nil

    func makeUIView(context: Context) -> StoryPlayerUIView {
        let v = StoryPlayerUIView()
        v.backgroundColor = .clear
        v.onFrame = onFrame
        v.playerLayer.player = player
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        v.watchFrames()
        return v
    }

    func updateUIView(_ v: StoryPlayerUIView, context: Context) {
        v.onFrame = onFrame
        if v.playerLayer.player !== player { v.playerLayer.player = player }
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        if v.playerLayer.isReadyForDisplay, let f = onFrame { DispatchQueue.main.async { f() } }
    }
}

/// One video of a post. Its still shows until the first frame is ready, then it plays in place, looping the poster's
/// trimmed part, with the poster's sound setting. `active` false pauses and tears the player down at once (another
/// page or slide is on screen), so a video never keeps sounding off screen.
/// `controls` (the full-screen viewer, Cheskel Oct 25 2026: "if it's loading it should come up that it's loading ...
/// I couldn't know if it's a photo or a video"): a spinner while it loads or buffers, tap to pause/play, and a bar with
/// play/pause, progress and the time left. `backdrop` false shows the still whole on black (no blurred copy behind).
struct StoryVideoView: View {
    let media: StoryMediaInfo
    var autoplay = false
    var active = true
    var fill = true
    var controls = false
    var backdrop = true
    var onRatio: ((Double) -> Void)? = nil

    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var ready = false
    @State private var wanted = false
    /// at least half of the video is on the screen (Cheskel, Oct 23 2026: "inspiration video, even I scroll to the next post")
    @State private var onScreen = true
    @State private var buffering = false
    @State private var userPaused = false
    @State private var progress: Double = 0
    @State private var remaining: Double = 0
    @State private var timeObserver: Any?
    @State private var controlObserver: NSKeyValueObservation?
    /// the video failed to load (bad network, missing file): "Couldn't load video, tap to retry"
    @State private var failed = false
    @State private var failObserver: NSObjectProtocol?
    @State private var stallObserver: NSObjectProtocol?
    /// a start is under way (the small-copy check on cellular); a newer start or a stop makes an older one void
    @State private var starting = false
    @State private var startGen = 0
    /// a frame made from the video itself, when the post's cover picture is missing or all black (Oct 25 2026: a cover
    /// grabbed before the video had painted was saved pure black, and the story showed a black screen)
    @State private var poster: UIImage?
    @Environment(\.scenePhase) private var scenePhase
    private var sound: StoryVideoSound { .shared }

    /// Only the video that is on screen, on the current page or slide, with the app in front, may play.
    private var live: Bool { active && onScreen && scenePhase == .active }

    /// More than half of `frame` lies inside the screen.
    nonisolated static func halfVisible(_ frame: CGRect, in screen: CGRect) -> Bool {
        guard frame.width > 1, frame.height > 1 else { return false }
        let cut = frame.intersection(screen)
        guard !cut.isNull else { return false }
        return cut.width * cut.height >= 0.5 * frame.width * frame.height
    }

    init(media: StoryMediaInfo, autoplay: Bool = false, active: Bool = true, fill: Bool = true,
         controls: Bool = false, backdrop: Bool = true, onRatio: ((Double) -> Void)? = nil) {
        self.media = media
        self.autoplay = autoplay
        self.active = active
        self.fill = fill
        self.controls = controls
        self.backdrop = backdrop
        self.onRatio = onRatio
    }

    var body: some View {
        ZStack {
            if let poster {
                ZStack {
                    backdrop ? Color.navy : Color.black
                    Image(uiImage: poster)
                        .resizable()
                        .aspectRatio(contentMode: fill ? .fill : .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            } else if !media.thumb.isEmpty {
                if fill {
                    RemoteImage(url: media.thumb, maxPixel: 1400)
                } else {
                    StoryFitImage(url: media.thumb, maxPixel: 1400, backdrop: backdrop)
                }
            } else {
                backdrop ? Color.navy : Color.black
            }
            if let player {
                StoryPlayerLayer(player: player, fill: fill, onFrame: { frameShown(player) })
                    .opacity(ready ? 1 : 0)
                    .allowsHitTesting(false)
            }
            if player == nil && !autoplay {
                Button(action: { wanted = true; start() }) {
                    Image(systemName: "play.circle")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play video")
            }
            if controls {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { togglePlay() }
                controlsOverlay
            } else if waiting {
                spinner
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            if failed {
                Button { retry() } label: {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 26, weight: .semibold))
                        Text("Couldn't load video, tap to retry")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Couldn't load video. Tap to retry")
            }
        }
        .clipped()
        .task(id: "\(media.url)|\(media.thumb)") {
            await checkPoster()
            // the post was read again (e.g. after Edit post): a video on screen with no player starts now
            if autoplay, live, player == nil { start() }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            StoryVideoView.halfVisible(proxy.frame(in: .global), in: CGRect(origin: .zero, size: UIScreen.main.bounds.size))
        } action: { visible in
            onScreen = visible
        }
        .onAppear { if autoplay && live { start() } }
        .onDisappear { stop() }
        .onChange(of: live) { _, now in
            if now {
                if autoplay || wanted { start() }
            } else {
                stop()
            }
        }
        .onChange(of: sound.on) { _, on in
            player?.isMuted = media.muted || !on
        }
    }

    /// Loading: the player is being made, the first frame is not ready, or playback is waiting for more data.
    private var waiting: Bool {
        guard !userPaused, !failed else { return false }
        if player == nil { return (autoplay || wanted) && live && !media.url.isEmpty }
        return !ready || buffering
    }

    private var spinner: some View {
        ProgressView()
            .controlSize(.large)
            .tint(.white)
            .frame(width: 72, height: 72)
            .background(.black.opacity(0.4), in: Circle())
            .accessibilityLabel("Loading video")
            .transition(.opacity)
    }

    private func retry() {
        stop()
        failed = false
        wanted = true
        start()
    }

    /// The post's cover picture is missing or all black: make one from the video itself.
    private func checkPoster() async {
        if !media.thumb.isEmpty, let img = await ImagePipeline.shared.load(media.thumb, maxPixel: 64), !StoryVideoView.isBlank(img) {
            // Oct 25 2026: a cover picked in Edit post replaces a frame made earlier from the video
            if poster != nil { withAnimation(Motion.fade) { poster = nil } }
            return
        }
        guard let u = await StoryVideoLoader.shared.source(for: media) else { return }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: u))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 900, height: 900)
        let at = CMTime(seconds: max(0.1, media.coverTime ?? media.trimStart ?? 0.1), preferredTimescale: 600)
        if let r = try? await gen.image(at: at) {
            let img = UIImage(cgImage: r.image)
            withAnimation(Motion.fade) { poster = img }
        }
    }

    /// Every pixel (on a 16 x 16 copy) is black or nearly.
    nonisolated static func isBlank(_ img: UIImage) -> Bool {
        guard let cg = img.cgImage else { return false }
        var px = [UInt8](repeating: 0, count: 4 * 16 * 16)
        let drawn: Bool = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return true
        }
        guard drawn else { return false }
        var top: UInt8 = 0
        for i in stride(from: 0, to: px.count, by: 4) { top = max(top, px[i], px[i + 1], px[i + 2]) }
        return top < 6
    }

    private var controlsOverlay: some View {
        ZStack {
            if waiting {
                spinner
            } else if userPaused {
                Image(systemName: "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(.black.opacity(0.45), in: Circle())
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(Motion.fade, value: waiting)
        .overlay(alignment: .bottom) { controlBar }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button { togglePlay() } label: {
                Image(systemName: userPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(userPaused ? "Play video" : "Pause video")
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.3))
                    Capsule().fill(Color.white)
                        .frame(width: CGFloat(max(0, min(1, progress))) * g.size.width)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 44)
            .accessibilityHidden(true)
            Text(remaining > 0 ? StoryVideoView.clock(remaining) : " ")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 36, alignment: .trailing)
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .background(Color.black.opacity(0.45), in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 104)
    }

    nonisolated static func clock(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "" }
        let t = Int(s.rounded(.up))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    private func togglePlay() {
        if let p = player {
            if userPaused {
                userPaused = false
                StoryVideoCenter.shared.claim(p)
                p.play()
            } else {
                userPaused = true
                p.pause()
            }
        } else {
            userPaused = false
            wanted = true
            start()
        }
    }

    private var startTime: CMTime {
        CMTime(seconds: max(0, media.trimStart ?? 0), preferredTimescale: 600)
    }

    private func start() {
        guard player == nil, !starting, live, !media.url.isEmpty else { return }
        StoryVideoLoader.shared.prepareAudio()
        // Oct 25 2026 (slow start on 5G): a video loaded ahead (the next slide / next post) is handed over as is
        if let p = StoryVideoLoader.shared.take(media.url) {
            attach(p)
            return
        }
        starting = true
        let gen = startGen
        let m = media
        Task { @MainActor in
            let src = await StoryVideoLoader.shared.source(for: m)
            guard gen == startGen else { return }
            starting = false
            guard player == nil, live, let src else { return }
            attach(StoryVideoLoader.makePlayer(src, m))
        }
    }

    /// Wires a player to this view and plays it at once: a short start buffer, no waiting for the whole clip.
    private func attach(_ p: AVPlayer) {
        guard let item = p.currentItem else { return }
        p.isMuted = media.muted || !sound.on
        p.actionAtItemEnd = .pause
        p.automaticallyWaitsToMinimizeStalling = false
        item.preferredForwardBufferDuration = 2
        if let end = media.trimEnd, end > (media.trimStart ?? 0) {
            item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        }
        let begin = startTime
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            let tol = CMTime(seconds: 0.1, preferredTimescale: 600)
            p.seek(to: begin, toleranceBefore: tol, toleranceAfter: tol)
            p.play()
        }
        let report = onRatio
        statusObserver = item.observe(\.status, options: [.initial, .new]) { it, _ in
            if it.status == .failed {
                DispatchQueue.main.async { failed = true; buffering = false }
                return
            }
            guard it.status == .readyToPlay else { return }
            let size = it.presentationSize
            DispatchQueue.main.async {
                if size.width > 0, size.height > 0 { report?(Double(size.width / size.height)) }
            }
        }
        failObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { _ in
            failed = true
            buffering = false
        }
        // ran out of data during the quick start: from here on the player waits (spinner) and resumes by itself
        stallObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled, object: item, queue: .main) { _ in
            StoryVideoView.settle(p)
            p.play()
        }
        // the video shows once a real frame is on the layer (frameShown), not at "ready to play" when the layer can
        // still be black; until then the still and a spinner show
        controlObserver = p.observe(\.timeControlStatus, options: [.initial, .new]) { pl, _ in
            let st = pl.timeControlStatus
            DispatchQueue.main.async {
                buffering = st == .waitingToPlayAtSpecifiedRate
                guard st == .playing else { return }
                Task { @MainActor in
                    // backup in case the layer never reported its frame
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if player === pl, !ready, pl.timeControlStatus == .playing, pl.currentTime().seconds > begin.seconds + 0.2 {
                        withAnimation(Motion.content) { ready = true }
                    }
                    // a second and a half into playback: back to the system's normal buffering
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    if player === pl { StoryVideoView.settle(pl) }
                }
            }
        }
        if controls {
            let lo = max(0, media.trimStart ?? 0)
            let hi = media.trimEnd
            timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { t in
                let full = p.currentItem?.duration.seconds ?? 0
                let total = (hi ?? 0) > lo ? (hi ?? 0) : full
                let now = t.seconds
                guard total.isFinite, now.isFinite, total > lo else { return }
                let frac = (now - lo) / (total - lo)
                let left = max(0, total - now)
                DispatchQueue.main.async {
                    progress = frac
                    remaining = left
                }
            }
        }
        StoryVideoCenter.shared.claim(p)
        player = p
        if begin.seconds > 0.05, abs(p.currentTime().seconds - begin.seconds) > 0.25 {
            playFromTrim(p, begin)
        } else {
            p.play()
        }
        watchStart(p, begin)
    }

    /// Oct 25 2026 (Cheskel, Pompeii after a cover edit: "only shows a photo of the cover but no video playing"; the
    /// only trimmed video in the app): a trimmed video seeks to its start only once the file is ready, with a small
    /// tolerance (an exact-frame seek on a big remote .mov can hang), and plays when the seek ends either way.
    private func playFromTrim(_ p: AVPlayer, _ begin: CMTime) {
        Task { @MainActor in
            var waited = 0
            while player === p, p.currentItem?.status == .unknown, waited < 50 {
                try? await Task.sleep(nanoseconds: 100_000_000)
                waited += 1
            }
            guard player === p else { return }
            let tol = CMTime(seconds: 0.1, preferredTimescale: 600)
            p.seek(to: begin, toleranceBefore: tol, toleranceAfter: tol) { _ in
                DispatchQueue.main.async { if player === p { p.play() } }
            }
        }
    }

    /// A start that never gets going (no frames after a few seconds) is nudged: play from the start of the kept part
    /// with any tolerance, and if that also stalls, from the beginning of the file. Never leaves a still on screen.
    private func watchStart(_ p: AVPlayer, _ begin: CMTime) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard player === p, !userPaused, !failed, live else { return }
            if p.timeControlStatus != .playing {
                p.seek(to: begin, toleranceBefore: .positiveInfinity, toleranceAfter: .positiveInfinity) { _ in
                    DispatchQueue.main.async { if player === p { p.play() } }
                }
                p.play()
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard player === p, !userPaused, !failed, live else { return }
            if p.timeControlStatus != .playing {
                p.seek(to: .zero) { _ in
                    DispatchQueue.main.async { if player === p { p.play() } }
                }
            }
        }
    }

    /// A real frame is on screen: show the video over the still.
    private func frameShown(_ p: AVPlayer) {
        guard player === p, !ready else { return }
        withAnimation(Motion.content) { ready = true }
    }

    /// After the quick start: the system's own buffering again, so a weak signal pauses with the spinner instead of
    /// stuttering, and the buffer is no longer capped at 2 s.
    nonisolated static func settle(_ p: AVPlayer) {
        p.automaticallyWaitsToMinimizeStalling = true
        p.currentItem?.preferredForwardBufferDuration = 0
    }

    private func stop() {
        startGen += 1
        starting = false
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = nil
        if let p = player, let o = timeObserver { p.removeTimeObserver(o) }
        timeObserver = nil
        controlObserver?.invalidate()
        controlObserver = nil
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        failObserver = nil
        failed = false
        buffering = false
        userPaused = false
        progress = 0
        remaining = 0
        if let p = player {
            p.pause()
            p.isMuted = true
            StoryVideoCenter.shared.release(p)
            p.replaceCurrentItem(with: nil)
        }
        statusObserver?.invalidate()
        statusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
        ready = false
    }
}

/// A photo shown whole (fit) over a blurred copy of itself, so nothing is cropped and the screen is never empty
/// (the web's InspireFeed "fit" look). Reports the photo's shape once it has loaded.
struct StoryFitImage: View {
    let url: String
    var maxPixel: CGFloat = 1600
    var fill = false
    /// false: the photo alone on black (the full-screen viewer), no blurred copy behind it
    var backdrop = true
    var onRatio: ((Double) -> Void)? = nil
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            backdrop ? Color.navy : Color.black
            if let image {
                // Oct 25 2026: each picture is laid out inside a screen-sized box (Color.clear + overlay), so a filled
                // picture can never grow the slide past the screen (a bare scaledToFill + maxWidth frame takes the
                // picture's oversized size and pushed the slide off-center / zoomed in).
                if backdrop {
                    Color.clear
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .blur(radius: fill ? 0 : 22)
                        }
                        .opacity(fill ? 0 : 1)
                        .clipped()
                        .accessibilityHidden(true)
                }
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: fill ? .fill : .fit)
                    }
                    .clipped()
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: url) {
            guard !url.isEmpty else { return }
            var img = ImagePipeline.shared.cached(url, maxPixel: maxPixel)
            if img == nil { img = await ImagePipeline.shared.load(url, maxPixel: maxPixel) }
            guard let img else { return }
            withAnimation(Motion.fade) { image = img }
            if img.size.width > 0, img.size.height > 0 { onRatio?(Double(img.size.width / img.size.height)) }
        }
    }
}

/// Full-screen viewer for a post's photos and videos (swipe between them), from any thumbnail.
struct StoryMediaViewer: View {
    let media: [StoryMediaInfo]
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(media: [StoryMediaInfo], index: Int) {
        self.media = media
        _index = State(initialValue: index)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(media.enumerated()), id: \.offset) { i, m in
                    page(m, active: i == index)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: media.count > 1 ? .automatic : .never))
            .ignoresSafeArea(edges: .bottom)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .padding(.trailing, 16)
            .padding(.top, 8)
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .bottom) {
            if media.indices.contains(index) {
                caption(media[index])
            }
        }
        .statusBarHidden()
        .onDisappear { StoryVideoCenter.shared.stopAll() }
    }

    @ViewBuilder
    private func page(_ m: StoryMediaInfo, active: Bool) -> some View {
        if m.isVideo {
            // Oct 25 2026: the whole screen is the video's frame and the video itself is fitted inside it (black bars),
            // so it keeps its real shape. Posts carry no width/height for most videos, and the old 9:16 guess squeezed
            // every landscape video into a tall box.
            StoryVideoView(media: m, autoplay: true, active: active, fill: false, controls: true, backdrop: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZoomableRemoteImage(url: m.url.isEmpty ? m.thumb : m.url)
        }
    }

    @ViewBuilder
    private func caption(_ m: StoryMediaInfo) -> some View {
        if !m.placeName.isEmpty {
            let target = StoryExtra.httpsURL(m.placeLink) ?? StoryExtra.httpsURL(m.placeUrl)
            Button {
                if let target { openURL(target) }
            } label: {
                Label(m.placeName, systemImage: "mappin.and.ellipse")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.5), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(target == nil)
            .padding(.bottom, 44)
        }
    }
}

/// A photo that opens whole (fitted, on black) and zooms with a pinch or a double tap; once zoomed it pans with a drag,
/// and a swipe moves to the next photo only when it is back at its whole size.
/// Oct 25 2026 (Cheskel: "The photos are also opening zoomed in"): the photo is laid out in an exact screen-sized box,
/// every new photo starts at 1x, and zoom snaps back to whole when pinched below 1x.
struct ZoomableRemoteImage: View {
    let url: String
    var maxPixel: CGFloat = 2200
    @State private var image: UIImage?
    @State private var failed = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let box = geo.size
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: box.width, height: box.height)
                        .scaleEffect(scale)
                        .offset(offset)
                        .contentShape(Rectangle())
                        .gesture(
                            MagnificationGesture()
                                .onChanged { v in scale = min(4, max(1, lastScale * v)) }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale <= 1.01 { reset() } else { clamp(box) }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { v in
                                    offset = CGSize(width: lastOffset.width + v.translation.width,
                                                    height: lastOffset.height + v.translation.height)
                                }
                                .onEnded { _ in clamp(box) },
                            including: scale > 1.01 ? .all : .subviews
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(Motion.move) {
                                if scale > 1.01 {
                                    scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                                } else {
                                    scale = 2.5; lastScale = 2.5
                                }
                            }
                        }
                        .accessibilityLabel("Photo")
                        .accessibilityHint("Double tap to zoom")
                } else if failed {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: box.width, height: box.height)
            .clipped()
        }
        .task(id: url) {
            reset()
            failed = false
            if let hit = ImagePipeline.shared.cached(url, maxPixel: maxPixel) { image = hit; return }
            image = await ImagePipeline.shared.load(url, maxPixel: maxPixel)
            failed = image == nil
        }
    }

    private func reset() {
        withAnimation(Motion.move) {
            scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
        }
    }

    /// The photo's size when it fits the box (the 1x size).
    private func fitted(_ box: CGSize) -> CGSize {
        guard let image, image.size.width > 0, image.size.height > 0, box.width > 0, box.height > 0 else { return box }
        let r = min(box.width / image.size.width, box.height / image.size.height)
        return CGSize(width: image.size.width * r, height: image.size.height * r)
    }

    /// Keep a zoomed photo's edges from being dragged into the middle of the screen.
    private func clamp(_ box: CGSize) {
        let f = fitted(box)
        let mx = max(0, (f.width * scale - box.width) / 2)
        let my = max(0, (f.height * scale - box.height) / 2)
        withAnimation(Motion.move) {
            offset = CGSize(width: min(mx, max(-mx, offset.width)), height: min(my, max(-my, offset.height)))
        }
        lastOffset = offset
    }
}


/// A post's card picture (Get Inspired tiles, Explore article tiles, Stories cards, lists).
/// Oct 25 2026 (Cheskel's Pompeii story: its saved cover JPEG is pure black, so the tile in Get Inspired was a black
/// square): when the post has a video and its cover is missing, fails to load, or is all black, the card shows a frame
/// from the video itself (about 1 s in), made once per video and cached for the session.
struct StoryCoverImage: View {
    let post: StoryPost
    var maxPixel: CGFloat = 600
    @State private var frame: UIImage?

    /// Oct 25 2026 (Cheskel's Pompeii post: the cover picked in Edit post did not show on Explore): the check runs again
    /// whenever the saved cover changes, and a frame made from the video is shown only while that cover is missing or black.
    private var coverKey: String { "\(post.id)|\(post.cover?.cardImage ?? "")" }

    var body: some View {
        RemoteImage(url: post.cover?.cardImage ?? "", maxPixel: maxPixel)
            .overlay {
                if let frame {
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: coverKey) { await check() }
    }

    private func check() async {
        guard let video = post.media.first(where: { $0.isVideo }), !video.url.isEmpty else { frame = nil; return }
        let cover = post.cover?.cardImage ?? ""
        if !cover.isEmpty, let img = await ImagePipeline.shared.load(cover, maxPixel: 64), !StoryVideoView.isBlank(img) {
            // the saved cover is a real picture: it wins over any frame made earlier
            frame = nil
            return
        }
        let at = video.frameTime
        if let hit = StoryFrameCache.shared.cached(video.url, at: at) { frame = hit; return }
        if let img = await StoryFrameCache.shared.frame(video.url, at: at) {
            withAnimation(Motion.fade) { frame = img }
        }
    }
}

/// Frames made from story videos for their cards: one per video URL, kept for the session.
@MainActor
final class StoryFrameCache {
    static let shared = StoryFrameCache()
    private var done: [String: UIImage] = [:]
    private var running: [String: Task<UIImage?, Never>] = [:]

    /// One frame per video URL and time (Oct 25 2026: keyed by the time too, so a newly picked cover frame is made again).
    private func key(_ url: String, _ at: Double?) -> String { at.map { "\(url)#\(Int(($0 * 100).rounded()))" } ?? url }

    func cached(_ url: String, at: Double? = nil) -> UIImage? { done[key(url, at)] }

    func frame(_ url: String, at: Double? = nil) async -> UIImage? {
        let k = key(url, at)
        if let hit = done[k] { return hit }
        if let t = running[k] { return await t.value }
        // the poster's picked frame (or the start of what plays) first, then the old guesses
        let times: [Double] = at.map { [max(0.1, $0), 1.0, 0.2] } ?? [1.0, 0.2, 2.5]
        let t = Task<UIImage?, Never> {
            guard let u = URL(string: url) else { return nil }
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: u))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 700, height: 700)
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
            var fallback: UIImage?
            for s in times {
                if let r = try? await gen.image(at: CMTime(seconds: s, preferredTimescale: 600)) {
                    let img = UIImage(cgImage: r.image)
                    if !StoryVideoView.isBlank(img) { return img }
                    if fallback == nil { fallback = img }
                }
            }
            return fallback
        }
        running[k] = t
        let img = await t.value
        running[k] = nil
        if let img { done[k] = img }
        return img
    }
}
