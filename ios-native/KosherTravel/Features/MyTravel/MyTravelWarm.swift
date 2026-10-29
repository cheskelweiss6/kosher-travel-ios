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
    static let myTravel = WarmWebPage(route: .myTravelWarm)
    /// The Explore tab (V2-FULL-1029): the website's Explore home, regions, countries, states, cities and listings.
    static let explore = WarmWebPage(route: .exploreTab)
    /// The Stories tab (V2-FULL-1029): the website's Stories (Get Inspired, Articles, posts, travelers, Share, admin tools).
    static let stories = WarmWebPage(route: .storiesTab)

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
    /// The tabs showing this page (My Travel, and the AI Planner when the website has the in-page planner), each with
    /// its handler for what the page asks (push a post, open a link, sign in…). Pushes, links and tab switches only come
    /// from a tap, so they go to the tab on screen.
    @ObservationIgnored private var handlers: [AppTab: (ShellEvent) -> Void] = [:]
    @ObservationIgnored private var visibleTabs: Set<AppTab> = []
    /// The native tab whose container holds the web view now (observed: each tab's host attaches it when it is theirs).
    private(set) var shownTab: AppTab?
    /// The page is on screen in some tab.
    var visible: Bool { !visibleTabs.isEmpty }
    private var handler: ((ShellEvent) -> Void)? { shownTab.flatMap { handlers[$0] } }
    /// A sign-in request the page sent while it was not on screen; shown when the tab appears.
    @ObservationIgnored private var pendingSignIn: SignInSheet.Mode?

    /// Whether the loaded website has the in-page AI Planner (window.__ktShellTab, website from Oct 29 2026): nil until
    /// the page has opened once. False keeps the native planner chat in the AI Planner tab.
    private(set) var inPagePlanner: Bool?
    /// True for a moment while the page changes screen for a tab switch (the tab covers the old screen meanwhile).
    private(set) var switching = false
    /// The page's own screen, as last set or reported: "mytravel" or "planner".
    @ObservationIgnored private var pageTab = "mytravel"
    /// A question (and/or a city to plan) for the page's planner, sent once the page can take it.
    @ObservationIgnored private var pendingAsk: (prompt: String?, city: String?)?
    /// Scripts for the page that wait until it has opened (V2-FULL-1029: a Stories request from another tab).
    @ObservationIgnored private var pendingJS: [String] = []

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
        pageTab = "mytravel"
        switching = false
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
            detectPlanner()
            flushJS()
        case .loaded:
            // An older website build that never says "ready" is still shown after a moment.
            let gen = generation
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, gen == self.generation, !self.ready else { return }
                self.ready = true
                self.detectPlanner()
                self.flushJS()
            }
        case .failed(let msg):
            failed = msg
        case .title(let t):
            title = t
        case .signIn(let mode):
            if visible, let handler { handler(e) } else { pendingSignIn = mode }
        case .inPageTab(let name):
            // the page moved itself (Plan a trip / View trip); the tab that shows it follows
            pageTab = name == "planner" ? "planner" : "mytravel"
            if visible { handler?(e) }
        default:
            // Pushes, links and tab switches only come from a tap, so only while the tab is on screen.
            if visible { handler?(e) }
        }
    }

    // MARK: the two tabs (My Travel, AI Planner)

    /// A tab showing this page appeared: the web view moves into its container and the page shows that tab's screen.
    func appear(tab: AppTab, handler: @escaping (ShellEvent) -> Void) {
        handlers[tab] = handler
        visibleTabs.insert(tab)
        shownTab = tab
        if let mode = pendingSignIn { pendingSignIn = nil; handler(.signIn(mode)) }
        syncTab()
    }

    func disappear(tab: AppTab) {
        visibleTabs.remove(tab)
        if shownTab == tab, let other = visibleTabs.first { shownTab = other }
    }

    /// Ask the page's planner (Explore's "Ask AI", a city's Plan Trip). Sent when the page is ready and in the planner tab.
    func ask(prompt: String?, city: String?) {
        pendingAsk = (prompt, city)
        syncTab()
    }

    /// Run a script in the page once it has opened (now, when it already has).
    func run(js: String) {
        pendingJS.append(js)
        flushJS()
    }

    private func flushJS() {
        guard ready, let wv = webView, !pendingJS.isEmpty else { return }
        let all = pendingJS
        pendingJS = []
        for js in all { wv.evaluateJavaScript(js) { _, _ in } }
    }

    private func detectPlanner() {
        guard let wv = webView else { return }
        let gen = generation
        wv.evaluateJavaScript("typeof window.__ktShellTab === 'function'") { [weak self] result, _ in
            let has = (result as? Bool) ?? false
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }
                self.inPagePlanner = has
                self.syncTab()
            }
        }
    }

    /// Make the page show the screen of the tab it is in (and send a waiting question to its planner).
    private func syncTab() {
        guard ready, inPagePlanner == true, let tab = shownTab, let wv = webView else { return }
        let want = tab == .planner ? "planner" : "mytravel"
        let ask = want == "planner" ? pendingAsk : nil
        guard want != pageTab || ask != nil else { return }
        if ask != nil { pendingAsk = nil }
        let changing = want != pageTab
        pageTab = want
        if changing {
            title = nil
            switching = true
        }
        var promptJS = "null", cityJS = "null"
        if let q = ask?.prompt, !q.isEmpty { promptJS = WebSession.jsString(q) }
        if let c = ask?.city, !c.isEmpty { cityJS = WebSession.jsString(c) }
        let tabJS = WebSession.jsString(want)
        let js = "(function(){try{return !!(window.__ktShellTab && window.__ktShellTab(" + tabJS + "," + promptJS + "," + cityJS
            + "));}catch(e){return false;}})()"
        let gen = generation
        wv.evaluateJavaScript(js) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                // one frame for the page to draw the new screen before the cover lifts
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard let self, gen == self.generation else { return }
                self.switching = false
            }
        }
        if changing {
            // never leave the cover up (a page that did not answer)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard let self, gen == self.generation else { return }
                self.switching = false
            }
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

/// The on-screen spot for a warm page's web view. Two tabs can show the same page (My Travel and the AI Planner); only
/// the host of the tab on screen holds the web view.
struct WarmWebHost: UIViewRepresentable {
    let page: WarmWebPage
    /// page.loads, read here so a new web view is re-attached.
    let loads: Int
    /// This host's tab is the one showing the page now.
    let active: Bool

    func makeCoordinator() -> Holder { Holder(page: page) }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .white
        v.clipsToBounds = true
        if active { page.attach(to: v) }
        return v
    }

    func updateUIView(_ v: UIView, context: Context) { if active { page.attach(to: v) } }

    static func dismantleUIView(_ v: UIView, coordinator: Holder) {
        coordinator.page.detach(from: v)
    }

    final class Holder {
        let page: WarmWebPage
        init(page: WarmWebPage) { self.page = page }
    }
}

/// An embedded tab that stays loaded (My Travel, and the AI Planner on the same page): shows the warm page at once; a
/// quiet placeholder only while the very first load after launch is still running; the error screen with Retry when it
/// failed.
struct WarmWebScreen: View {
    let page: WarmWebPage
    var tab: AppTab = .myTravel
    /// A bar title that does not follow the page (Stories: "" — the page shows its own heading).
    var fixedTitle: String? = nil

    @Environment(AuthStore.self) private var auth
    @State private var safari: IdentifiedURL?
    @State private var push: ShellPush?
    @State private var signIn: SignInSheet.Mode?

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            WarmWebHost(page: page, loads: page.loads, active: page.shownTab == tab)
                .opacity(page.failed == nil ? 1 : 0)
                .accessibilityHidden(page.failed != nil)
            if page.switching && page.shownTab == tab {
                Color.white.allowsHitTesting(false)
            }
            if page.failed != nil {
                ShellErrorView(retry: { page.retry(uid: auth.uid) })
            } else if !page.ready {
                WarmPagePlaceholder()
                    .transition(.opacity)
            }
        }
        .animation(Motion.content, value: page.ready)
        .navigationTitle(fixedTitle ?? page.title ?? page.route.title)
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
            page.appear(tab: tab, handler: handle)
            takeAsk()
        }
        .onDisappear { page.disappear(tab: tab) }
        // Explore's "Ask AI" and a city's Plan Trip hand the planner a question (ShellRouter): the page's planner asks it.
        .onChange(of: ShellRouter.shared.plannerPrompt) { _, _ in takeAsk() }
        .onChange(of: ShellRouter.shared.plannerTripCity) { _, _ in takeAsk() }
        .onChange(of: page.inPagePlanner) { _, _ in takeAsk() }
        // Normally already loaded by RootTabView; this covers a tap before that finished, and account changes.
        .task(id: auth.ready ? (auth.uid ?? "-") : "?") {
            guard auth.ready else { return }
            await page.warm(uid: auth.uid)
        }
    }

    private func takeAsk() {
        guard tab == .planner, page.inPagePlanner == true else { return }
        let r = ShellRouter.shared
        let q = r.plannerPrompt, c = r.plannerTripCity
        guard (q?.isEmpty == false) || (c?.isEmpty == false) else { return }
        r.plannerPrompt = nil
        r.plannerTripCity = nil
        page.ask(prompt: q, city: c)
    }

    private func handle(_ e: ShellEvent) {
        switch e {
        case .signIn(let mode): signIn = mode
        case .tab(let name, let prompt): ShellRouter.shared.open(tab: name, prompt: prompt)
        case .inPageTab(let name): ShellRouter.shared.open(tab: name)
        case .story(let id, let comments): push = .story(id, comments: comments)
        case .traveler(let uid, let name, let photo): push = .traveler(uid: uid, name: name, photo: photo)
        case .link(let t):
            switch t {
            case .safari(let u), .ownSite(let u): safari = IdentifiedURL(url: u)
            case .system(let u): LinkOpener.openSystem(u)
            case .story(let id): push = .story(id, comments: false)
            }
        case .ready, .loaded, .failed, .title, .close, .webBack:
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
