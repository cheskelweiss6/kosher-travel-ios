import SwiftUI
import WebKit
import Observation

/// My Travel is still the live website's screen (parity checklist phase 7). Loading that page only when the tab was
/// tapped meant a spinner every time (the whole site boots in the web view first: about a second on Wi-Fi, longer on
/// cellular), and the embedded screen re-checked the sign-in token on every return to the tab and reloaded the page
/// when Firebase had refreshed it (about once an hour).
///
/// WarmWebPage keeps one web view for the tab alive for the life of the app: RootTabView starts it in the background
/// right after launch (and again after a sign-in or sign-out), parked behind the app's own screen so WebKit keeps it
/// running, and the tab simply moves the already-loaded view on screen. The page refreshes its own data from there
/// (the website's Firebase SDK keeps the session fresh with the refresh token), so it is never reloaded because of a
/// token change, only when the signed-in account changes or after an error's Retry.
@MainActor
@Observable
final class WarmWebPage {
    static let myTravel = WarmWebPage(route: .myTravel)

    let route: WebRoute
    /// The page has opened its screen (the site posts "ready"); before that the tab shows a placeholder.
    private(set) var ready = false
    /// The main page could not load (offline, server error): the tab shows the error screen with Retry.
    private(set) var failed: String?
    /// The page's own title, when it sends one.
    private(set) var title: String?
    /// Bumped whenever a new web view exists, so the on-screen host re-attaches it.
    private(set) var loads = 0

    @ObservationIgnored private(set) var webView: WKWebView?
    @ObservationIgnored private var coordinator: ShellWebView.Coordinator?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var loadedUid = ""
    @ObservationIgnored private var generation = 0
    /// The on-screen tab's handler for what the page asks (push a post, open a link, sign in…).
    @ObservationIgnored var handler: ((ShellEvent) -> Void)?
    @ObservationIgnored var visible = false {
        didSet { if visible, let mode = pendingSignIn { pendingSignIn = nil; handler?(.signIn(mode)) } }
    }
    /// A sign-in request the page sent while it was not on screen; shown when the tab appears.
    @ObservationIgnored private var pendingSignIn: SignInSheet.Mode?

    init(route: WebRoute) { self.route = route }

    /// Load the page in the background, or load it again when the signed-in account changed. Cheap to call often:
    /// a page already loaded for this account is left as it is.
    func warm(uid: String?) async {
        let now = uid ?? ""
        if started && now == loadedUid && failed == nil { return }
        generation += 1
        let gen = generation
        await WebSession.prepareStore(uid: uid)
        let script = await WebSession.authScript()
        guard gen == generation else { return }   // a newer call (account switched meanwhile) takes over
        if started && now == loadedUid && failed == nil { return }
        load(authScript: script, uid: now)
    }

    /// Retry after an error, with the current sign-in.
    func retry(uid: String?) {
        failed = nil
        started = false
        Task { await warm(uid: uid) }
    }

    private func load(authScript: String, uid: String) {
        let wv = webView ?? makeWebView()
        let ucc = wv.configuration.userContentController
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(source: authScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: WebSession.shellScript(route), injectionTime: .atDocumentStart,
                                       forMainFrameOnly: true))
        started = true
        loadedUid = uid
        ready = false
        failed = nil
        wv.load(URLRequest(url: route.url))
        if wv.superview == nil { park(wv) }
    }

    private func makeWebView() -> WKWebView {
        let coord = ShellWebView.Coordinator(onEvent: { _ in })
        coord.onEvent = { [weak self] e in self?.receive(e) }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "KosherTravelApp/2"
        let ucc = WKUserContentController()
        ucc.add(WeakScriptHandler(coord), name: "ktShell")
        config.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = coord
        wv.uiDelegate = coord
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsLinkPreview = false
        wv.isOpaque = false
        wv.backgroundColor = .white
        wv.scrollView.backgroundColor = .white
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        #endif
        coord.webView = wv
        coordinator = coord
        webView = wv
        loads += 1
        return wv
    }

    private func receive(_ e: ShellEvent) {
        switch e {
        case .ready:
            ready = true
        case .loaded:
            // An older website build that never says "ready" is still shown after a moment.
            let gen = generation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, gen == self.generation else { return }
                self.ready = true
            }
        case .failed(let msg):
            failed = msg
        case .title(let t):
            title = t
        case .signIn(let mode):
            if visible, let handler { handler(e) } else { pendingSignIn = mode }
        default:
            // Pushes, links and tab switches only come from a tap, so only while the tab is on screen.
            if visible { handler?(e) }
        }
    }

    // MARK: on screen / parked

    /// Put the web view into the tab's container (on screen).
    func attach(to container: UIView) {
        guard let wv = webView, wv.superview !== container else { return }
        wv.removeFromSuperview()
        wv.frame = container.bounds
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.isUserInteractionEnabled = true
        wv.accessibilityElementsHidden = false
        container.addSubview(wv)
    }

    /// The tab's container went away: keep the page running behind the app's screen.
    func detach(from container: UIView) {
        guard let wv = webView, wv.superview === container else { return }
        wv.removeFromSuperview()
        park(wv)
    }

    /// Behind the app's own (opaque) root view, in the window, so WebKit keeps loading and rendering it at full speed.
    /// Invisible and untouchable there; VoiceOver skips it.
    private func park(_ wv: WKWebView) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .filter { $0.windowLevel == .normal && !$0.isHidden && $0.rootViewController != nil }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return }
        wv.frame = window.bounds
        wv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        wv.isUserInteractionEnabled = false
        wv.accessibilityElementsHidden = true
        window.insertSubview(wv, at: 0)
    }
}

/// The on-screen spot for a warm page's web view.
struct WarmWebHost: UIViewRepresentable {
    let page: WarmWebPage
    /// page.loads, read here so a new web view is re-attached.
    let loads: Int

    func makeCoordinator() -> Holder { Holder(page: page) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .white
        v.clipsToBounds = true
        page.attach(to: v)
        return v
    }

    func updateUIView(_ v: UIView, context: Context) { page.attach(to: v) }

    static func dismantleUIView(_ v: UIView, coordinator: Holder) {
        coordinator.page.detach(from: v)
    }

    final class Holder {
        let page: WarmWebPage
        init(page: WarmWebPage) { self.page = page }
    }
}

/// An embedded tab that stays loaded (My Travel): shows the warm page at once; a quiet placeholder only while the
/// very first load after launch is still running; the error screen with Retry when it failed.
struct WarmWebScreen: View {
    let page: WarmWebPage

    @Environment(AuthStore.self) private var auth
    @State private var safari: IdentifiedURL?
    @State private var push: ShellPush?
    @State private var signIn: SignInSheet.Mode?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            WarmWebHost(page: page, loads: page.loads)
                .opacity(page.failed == nil ? 1 : 0)
                .accessibilityHidden(page.failed != nil)
            if page.failed != nil {
                ShellErrorView(retry: { page.retry(uid: auth.uid) })
            } else if !page.ready {
                WarmPagePlaceholder()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: page.ready)
        .navigationTitle(page.title ?? page.route.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $safari) { item in
            SafariSheet(url: item.url).ignoresSafeArea()
        }
        .sheet(item: $signIn) { mode in
            SignInSheet(mode: mode)
        }
        .navigationDestination(item: $push) { p in
            switch p {
            case .story(let id, _): StoryDetailView(postId: id)
            case .traveler(let uid, let name, let photo): TravelerView(uid: uid, name: name, photo: photo)
            case .web(let r): WebScreen(route: r)
            }
        }
        .onAppear {
            page.handler = handle
            page.visible = true
        }
        .onDisappear { page.visible = false }
        // Normally already loaded by RootTabView; this covers a tap before that finished, and account changes.
        .task(id: auth.ready ? (auth.uid ?? "-") : "?") {
            guard auth.ready else { return }
            await page.warm(uid: auth.uid)
        }
    }

    private func handle(_ e: ShellEvent) {
        switch e {
        case .signIn(let mode): signIn = mode
        case .tab(let name, let prompt): ShellRouter.shared.open(tab: name, prompt: prompt)
        case .story(let id, let comments): push = .story(id, comments: comments)
        case .traveler(let uid, let name, let photo): push = .traveler(uid: uid, name: name, photo: photo)
        case .link(let t):
            switch t {
            case .safari(let u), .ownSite(let u): safari = IdentifiedURL(url: u)
            case .system(let u): LinkOpener.openSystem(u)
            case .story(let id): push = .story(id, comments: false)
            }
        case .ready, .loaded, .failed, .title, .close:
            break   // state kept by the page object; a tab root has nothing to close
        }
    }
}

/// Shown only while the first load after launch is still running: the shape of My Travel's section bar and two
/// cards, no spinner.
struct WarmPagePlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.surface)
                        .frame(height: 36)
                }
            }
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.surface)
                .frame(width: 180, height: 18)
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Color.surface)
                    .aspectRatio(16 / 9, contentMode: .fit)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
