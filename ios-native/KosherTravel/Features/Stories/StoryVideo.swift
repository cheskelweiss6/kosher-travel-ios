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
struct StoryVideoView: View {
    let media: StoryMediaInfo
    var autoplay = false
    var active = true
    var fill = true
    var onRatio: ((Double) -> Void)? = nil

    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?
    @State private var statusObserver: NSKeyValueObservation?
    @State private var ready = false
    @State private var wanted = false
    /// at least half of the video is on the screen (Cheskel, Oct 23 2026: "inspiration video, even I scroll to the next post")
    @State private var onScreen = true
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
         onRatio: ((Double) -> Void)? = nil) {
        self.media = media
        self.autoplay = autoplay
        self.active = active
        self.fill = fill
        self.onRatio = onRatio
    }

    var body: some View {
        ZStack {
            if !media.thumb.isEmpty {
                if fill {
                    RemoteImage(url: media.thumb, maxPixel: 1400)
                } else {
                    StoryFitImage(url: media.thumb, maxPixel: 1400)
                }
            } else {
                Color.navy
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
        StoryVideoCenter.shared.claim(p)
        if begin.seconds > 0 {
            p.seek(to: begin, toleranceBefore: .zero, toleranceAfter: .zero) { _ in p.play() }
        } else {
            p.play()
        }
        player = p
    }

    private func stop() {
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
    var onRatio: ((Double) -> Void)? = nil
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.navy
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: fill ? 0 : 22)
                    .opacity(fill ? 0 : 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .accessibilityHidden(true)
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
            StoryVideoView(media: m, autoplay: true, active: active, fill: false)
                .aspectRatio(CGFloat(m.w > 0 && m.h > 0 ? m.w / m.h : 9.0 / 16.0), contentMode: .fit)
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
