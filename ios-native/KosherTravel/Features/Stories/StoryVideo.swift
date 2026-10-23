import SwiftUI
import AVKit

/// One video of a post: its poster (thumb) until tapped, then it plays in place.
/// Keeps the poster's settings: sound off when they muted it, and only the trimmed part plays (looping).
struct StoryVideoView: View {
    let media: StoryMediaInfo
    var autoplay = false
    @State private var player: AVPlayer?
    @State private var endObserver: NSObjectProtocol?

    init(media: StoryMediaInfo, autoplay: Bool = false) {
        self.media = media
        self.autoplay = autoplay
    }

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
            } else {
                RemoteImage(url: media.thumb, maxPixel: 1400)
                .overlay {
                    Button(action: start) {
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
        }
        .overlay(alignment: .bottomLeading) {
            if media.muted {
                Image(systemName: "speaker.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(7)
                    .background(.black.opacity(0.45), in: Circle())
                    .padding(10)
                    .accessibilityLabel("Sound off")
                    .allowsHitTesting(false)
            }
        }
        .onAppear { if autoplay { start() } }
        .onDisappear { stop() }
    }

    private var startTime: CMTime {
        CMTime(seconds: max(0, media.trimStart ?? 0), preferredTimescale: 600)
    }

    private func start() {
        guard player == nil, let url = URL(string: media.url), !media.url.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        let item = AVPlayerItem(url: url)
        if let end = media.trimEnd, end > (media.trimStart ?? 0) {
            item.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600)
        }
        let p = AVPlayer(playerItem: item)
        p.isMuted = media.muted
        p.actionAtItemEnd = .pause
        let begin = startTime
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { _ in
            p.seek(to: begin, toleranceBefore: .zero, toleranceAfter: .zero)
            p.play()
        }
        if begin.seconds > 0 {
            p.seek(to: begin, toleranceBefore: .zero, toleranceAfter: .zero) { _ in p.play() }
        } else {
            p.play()
        }
        player = p
    }

    private func stop() {
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
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
                    page(m)
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
    }

    @ViewBuilder
    private func page(_ m: StoryMediaInfo) -> some View {
        if m.isVideo {
            StoryVideoView(media: m)
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
                        withAnimation(.easeOut(duration: 0.2)) { scale = scale > 1 ? 1 : 2.5 }
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
