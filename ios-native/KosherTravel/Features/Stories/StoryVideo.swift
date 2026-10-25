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
}

struct StoryPlayerLayer: UIViewRepresentable {
    let player: AVPlayer
    var fill: Bool

    func makeUIView(context: Context) -> StoryPlayerUIView {
        let v = StoryPlayerUIView()
        v.backgroundColor = .clear
        v.playerLayer.player = player
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        return v
    }

    func updateUIView(_ v: StoryPlayerUIView, context: Context) {
        if v.playerLayer.player !== player { v.playerLayer.player = player }
        v.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
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
            if !media.thumb.isEmpty {
                if fill {
                    RemoteImage(url: media.thumb, maxPixel: 1400)
                } else {
                    StoryFitImage(url: media.thumb, maxPixel: 1400, backdrop: backdrop)
                }
            } else {
                backdrop ? Color.navy : Color.black
            }
            if let player {
                StoryPlayerLayer(player: player, fill: fill)
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
            }
        }
        .clipped()
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
        guard !userPaused else { return false }
        if player == nil { return autoplay && live && !media.url.isEmpty }
        return !ready || buffering
    }

    private var controlsOverlay: some View {
        ZStack {
            if waiting {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(width: 72, height: 72)
                    .background(.black.opacity(0.4), in: Circle())
                    .accessibilityLabel("Loading video")
                    .transition(.opacity)
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
        guard player == nil, live, let url = URL(string: media.url), !media.url.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        if let end = media.trimEnd, end > (media.trimStart ?? 0) {
            item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        }
        let p = AVPlayer(playerItem: item)
        p.isMuted = media.muted || !sound.on
        p.actionAtItemEnd = .pause
        let begin = startTime
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            p.seek(to: begin, toleranceBefore: .zero, toleranceAfter: .zero)
            p.play()
        }
        let report = onRatio
        statusObserver = item.observe(\.status, options: [.initial, .new]) { it, _ in
            guard it.status == .readyToPlay else { return }
            let size = it.presentationSize
            DispatchQueue.main.async {
                withAnimation(Motion.content) { ready = true }
                if size.width > 0, size.height > 0 { report?(Double(size.width / size.height)) }
            }
        }
        if controls {
            controlObserver = p.observe(\.timeControlStatus, options: [.initial, .new]) { pl, _ in
                let isWaiting = pl.timeControlStatus == .waitingToPlayAtSpecifiedRate
                DispatchQueue.main.async { buffering = isWaiting }
            }
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
        if begin.seconds > 0 {
            p.seek(to: begin, toleranceBefore: .zero, toleranceAfter: .zero) { _ in p.play() }
        } else {
            p.play()
        }
        player = p
    }

    private func stop() {
        if let p = player, let o = timeObserver { p.removeTimeObserver(o) }
        timeObserver = nil
        controlObserver?.invalidate()
        controlObserver = nil
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
                if backdrop {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: fill ? 0 : 22)
                        .opacity(fill ? 0 : 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .accessibilityHidden(true)
                }
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fill ? .fill : .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// A photo that fits the screen and zooms with a pinch or a double tap.
struct ZoomableRemoteImage: View {
    let url: String
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { v in scale = min(4, max(1, lastScale * v)) }
                            .onEnded { _ in lastScale = scale }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(Motion.move) { scale = scale > 1 ? 1 : 2.5 }
                        lastScale = scale
                    }
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            if let hit = ImagePipeline.shared.cached(url, maxPixel: 2200) { image = hit; return }
            image = await ImagePipeline.shared.load(url, maxPixel: 2200)
        }
    }
}
