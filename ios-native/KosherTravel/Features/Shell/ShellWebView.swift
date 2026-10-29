import SwiftUI
import WebKit

/// What an embedded page asks of the native app (sent by the website's src/ktShell.ts through
/// `window.webkit.messageHandlers.ktShell`), plus the web view's own load events.
enum ShellEvent {
    case ready                       // the page has opened the requested screen
    case loaded                      // the page finished loading
    case failed(String)              // the page could not load (offline, server error)
    case close                       // leave this embedded screen (its own Back / X / Close)
    case signIn(SignInSheet.Mode)    // the page needs a signed-in user: show the native sign-in sheet
    case tab(String, prompt: String?) // go to a native tab (AI Planner, Profile…), optionally with a planner question
    /// The warm My Travel page (website from Oct 29 2026, params planner=1) moved itself between its AI Planner and
    /// My Travel screens (a "Plan a trip" or "View trip" tap): show the native tab that holds it now.
    case inPageTab(String)
    case story(String, comments: Bool)
    case traveler(uid: String, name: String, photo: String)
    case title(String)
    case link(LinkTarget)
    case webBack(Bool)               // the page has (true) / has no (false) level of its own to step back to
}

/// Back inside an embedded page. The live website opens its inner levels (Europe → Poland → Kraków, a city's
/// Restaurants…) inside one page, each with its own Back pill, and keeps no browser history for them. So native Back
/// and the left-edge swipe step the page back one level first (by pressing the page's own Back), and only on the
/// level the screen opened on do they leave the screen. The page side is `WebSession.backScript` (our own user
/// script; the website itself is unchanged).
@MainActor
final class ShellWebNav {
    weak var webView: WKWebView?
    /// True while the page shows a Back of its own (it has a level to step back to).
    var canGoBack = false

    /// Steps the page back one level; `otherwise` runs when it has none (leave the screen).
    func back(otherwise: @escaping () -> Void) {
        guard canGoBack, let wv = webView else { otherwise(); return }
        wv.evaluateJavaScript("!!(window.__ktNav && window.__ktNav.back())") { result, _ in
            if (result as? Bool) != true { otherwise() }
        }
    }
}

/// The WKWebView that shows one screen of the live app. Shared website data store (one sign-in for all embedded
/// screens), no web swipe-back (the native navigation stack owns the edge swipe), JavaScript alerts as native alerts.
struct ShellWebView: UIViewRepresentable {
    let route: WebRoute
    let authScript: String
    let reloadToken: Int
    var fullScreen = false
    /// Back inside the page (native Back and the edge swipe step the page back one level first).
    var nav: ShellWebNav? = nil
    let onEvent: (ShellEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.applicationNameForUserAgent = "KosherTravelApp/2"
        let ucc = WKUserContentController()
        install(scripts: ucc)
        ucc.add(WeakScriptHandler(context.coordinator), name: "ktShell")
        config.userContentController = ucc

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsLinkPreview = false
        wv.isOpaque = false
        wv.backgroundColor = .white
        wv.scrollView.backgroundColor = .white
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        if #available(iOS 16.4, *) { wv.isInspectable = true }
        #endif
        context.coordinator.webView = wv
        context.coordinator.reloadToken = reloadToken
        context.coordinator.nav = nav
        nav?.webView = wv
        context.coordinator.installEdgeBack(on: wv)
        wv.load(URLRequest(url: route.url))
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
        guard context.coordinator.reloadToken != reloadToken else { return }
        context.coordinator.reloadToken = reloadToken
        // The sign-in (or the retry) changed: re-install the start scripts and load the screen again.
        let ucc = wv.configuration.userContentController
        ucc.removeAllUserScripts()
        install(scripts: ucc)
        wv.load(URLRequest(url: route.url))
    }

    static func dismantleUIView(_ wv: WKWebView, coordinator: Coordinator) {
        wv.stopLoading()
        wv.configuration.userContentController.removeScriptMessageHandler(forName: "ktShell")
    }

    private func install(scripts ucc: WKUserContentController) {
        ucc.addUserScript(WKUserScript(source: authScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addUserScript(WKUserScript(source: WebSession.shellScript(route, fullScreen: fullScreen),
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        if nav != nil {
            ucc.addUserScript(WKUserScript(source: WebSession.backScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIGestureRecognizerDelegate {
        var onEvent: (ShellEvent) -> Void
        weak var webView: WKWebView?
        var reloadToken = 0
        var nav: ShellWebNav?
        private var tip: UIView?

        init(onEvent: @escaping (ShellEvent) -> Void) { self.onEvent = onEvent }

        // Messages from the page (our own origin only).
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  WebSession.hosts.contains(message.frameInfo.securityOrigin.host.lowercased()),
                  let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            func str(_ k: String) -> String { (body[k] as? String) ?? "" }
            switch type {
            case "ready": onEvent(.ready)
            case "close": onEvent(.close)
            case "signin": onEvent(.signIn(str("mode") == "signup" ? .signUp : .signIn))
            case "tab":
                if (body["inPage"] as? Bool) == true { onEvent(.inPageTab(str("tab"))) }
                else {
                    // V2-FULL-1029: a Stories request (Share from a city page, a post) rides along to the Stories tab
                    if str("tab") == "stories", let intent = body["intent"] as? [String: Any],
                       JSONSerialization.isValidJSONObject(intent),
                       let data = try? JSONSerialization.data(withJSONObject: intent),
                       let json = String(data: data, encoding: .utf8) {
                        ShellRouter.shared.storiesRequest = json
                    }
                    onEvent(.tab(str("tab"), prompt: body["prompt"] as? String))
                }
            case "title": if !str("title").isEmpty { onEvent(.title(str("title"))) }
            case "navback":
                let has = (body["back"] as? Bool) ?? false
                guard let nav, nav.canGoBack != has else { return }
                nav.canGoBack = has
                onEvent(.webBack(has))
            case "open":
                switch str("route") {
                case "story": if !str("id").isEmpty { onEvent(.story(str("id"), comments: (body["comments"] as? Bool) ?? false)) }
                case "traveler": if !str("uid").isEmpty { onEvent(.traveler(uid: str("uid"), name: str("name"), photo: str("photo"))) }
                default: break
                }
            case "link":
                if let u = URL(string: str("url")), let t = LinkOpener.target(for: u) { route(t) }
            default: break
            }
        }

        private func route(_ t: LinkTarget) {
            switch t {
            case .system(let u): LinkOpener.openSystem(u)
            case .story(let id): onEvent(.story(id, comments: false))
            default: onEvent(.link(t))
            }
        }

        // MARK: Edge swipe: one level back inside the page

        func installEdgeBack(on wv: WKWebView) {
            let pan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanned(_:)))
            pan.edges = .left
            pan.delegate = self
            wv.addGestureRecognizer(pan)
        }

        /// Only while the page has a level to step back to. On the level the screen opened on this swipe never starts,
        /// so the system swipe-back (which follows the finger and leaves the screen) works exactly as on every screen.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g is UIScreenEdgePanGestureRecognizer else { return true }
            return nav?.canGoBack == true
        }

        /// While the page has a level to step back to, the system swipe-back (it would leave the whole screen) and the
        /// page's scrolling wait for this swipe; a touch away from the edge ends it at once, so nothing else waits.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            guard g is UIScreenEdgePanGestureRecognizer, nav?.canGoBack == true, let wv = webView else { return false }
            if other === wv.scrollView.panGestureRecognizer { return true }
            return other === navigationController(of: wv)?.interactivePopGestureRecognizer
        }

        private func navigationController(of view: UIView) -> UINavigationController? {
            var r: UIResponder? = view
            while let x = r {
                if let vc = x as? UIViewController, let n = vc.navigationController { return n }
                r = x.next
            }
            return nil
        }

        @objc private func edgePanned(_ g: UIScreenEdgePanGestureRecognizer) {
            guard let wv = webView else { return }
            let dx = max(0, g.translation(in: wv).x)
            switch g.state {
            case .began, .changed:
                follow(wv, dx: dx, y: g.location(in: wv).y)
            case .ended:
                let go = dx >= Motion.EdgeBack.commit
                    || (dx >= Motion.EdgeBack.flickDistance && g.velocity(in: wv).x >= Motion.EdgeBack.flickSpeed)
                settle(wv)
                if go { nav?.back(otherwise: { [weak self] in self?.onEvent(.close) }) }
            default:
                settle(wv)
            }
        }

        /// The back arrow comes in from the edge with the finger (filled navy once letting go will go back) and the
        /// page follows a little.
        private func follow(_ wv: WKWebView, dx: CGFloat, y: CGFloat) {
            let t = tip ?? makeTip(in: wv)
            let size = Motion.EdgeBack.tipSize
            let travel = min(dx, Motion.EdgeBack.maxTravel)
            let progress = min(1, dx / Motion.EdgeBack.commit)
            let ready = dx >= Motion.EdgeBack.commit
            wv.bringSubviewToFront(t)
            t.center = CGPoint(x: -size / 2 + travel * 0.75, y: min(max(y, size), wv.bounds.height - size))
            t.alpha = progress
            t.transform = CGAffineTransform(scaleX: 0.7 + 0.3 * progress, y: 0.7 + 0.3 * progress)
            if ready != (t.tag == 1) {
                t.tag = ready ? 1 : 0
                UIView.animate(withDuration: Motion.quick) {
                    t.backgroundColor = ready ? Theme.navyUI : .white
                    t.tintColor = ready ? .white : Theme.navyUI
                }
            }
            wv.scrollView.transform = Motion.reduceMotion ? .identity
                : CGAffineTransform(translationX: travel * Motion.EdgeBack.pageFollow, y: 0)
        }

        private func settle(_ wv: WKWebView) {
            let t = tip
            Motion.uiSettle {
                t?.alpha = 0
                t?.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                wv.scrollView.transform = .identity
            }
            t?.tag = 0
            t?.backgroundColor = .white
            t?.tintColor = Theme.navyUI
        }

        private func makeTip(in wv: WKWebView) -> UIView {
            let size = Motion.EdgeBack.tipSize
            let t = UIView(frame: CGRect(x: -size, y: 0, width: size, height: size))
            t.isUserInteractionEnabled = false
            t.isAccessibilityElement = false
            t.backgroundColor = .white
            t.tintColor = Theme.navyUI
            t.layer.cornerRadius = size / 2
            t.layer.shadowColor = UIColor.black.cgColor
            t.layer.shadowOpacity = 0.18
            t.layer.shadowRadius = 6
            t.layer.shadowOffset = CGSize(width: 0, height: 2)
            let img = UIImageView(image: UIImage(systemName: "chevron.backward",
                                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)))
            img.translatesAutoresizingMaskIntoConstraints = false
            t.addSubview(img)
            NSLayoutConstraint.activate([img.centerXAnchor.constraint(equalTo: t.centerXAnchor, constant: -1),
                                         img.centerYAnchor.constraint(equalTo: t.centerYAnchor)])
            t.alpha = 0
            wv.addSubview(t)
            tip = t
            return t
        }

        // Navigation: our own pages stay here; every other link leaves through the link opener.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            let scheme = url.scheme?.lowercased() ?? ""
            if ["about", "blob", "data", "javascript"].contains(scheme) { return .allow }
            let mainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if !mainFrame && (scheme == "http" || scheme == "https") { return .allow }   // embeds (video, maps)
            if WebSession.isOwn(url) {
                if navigationAction.navigationType == .linkActivated, let id = PlannerLinks.storyId(url) {
                    onEvent(.story(id, comments: false))
                    return .cancel
                }
                return .allow
            }
            if let t = LinkOpener.target(for: url) { route(t) }
            return .cancel
        }

        // window.open / target=_blank
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url, let t = LinkOpener.target(for: url) {
                if case .ownSite(let u) = t { route(.safari(u)) } else { route(t) }
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { onEvent(.loaded) }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { report(error) }

        private func report(_ error: Error) {
            let ns = error as NSError
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return }   // frame load interrupted by our own policy
            onEvent(.failed(ns.localizedDescription))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

        // JavaScript alert / confirm / prompt as native alerts (without these, confirm() silently answers "no").
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo) async {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "OK", style: .default) { _ in done.resume() })
                if !present(a, from: webView) { done.resume() }
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo) async -> Bool {
            await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
                let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done.resume(returning: false) })
                a.addAction(UIAlertAction(title: "OK", style: .default) { _ in done.resume(returning: true) })
                if !present(a, from: webView) { done.resume(returning: false) }
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo) async -> String? {
            await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
                let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
                a.addTextField { $0.text = defaultText }
                a.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done.resume(returning: nil) })
                a.addAction(UIAlertAction(title: "OK", style: .default) { [weak a] _ in done.resume(returning: a?.textFields?.first?.text) })
                if !present(a, from: webView) { done.resume(returning: nil) }
            }
        }

        private func present(_ vc: UIViewController, from view: UIView) -> Bool {
            guard var top = view.window?.rootViewController else { return false }
            while let p = top.presentedViewController { top = p }
            top.present(vc, animated: true)
            return true
        }
    }
}

/// Breaks the retain cycle WKUserContentController -> handler.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: message)
    }
}
