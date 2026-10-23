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
    case story(String, comments: Bool)
    case traveler(uid: String, name: String, photo: String)
    case title(String)
    case link(LinkTarget)
}

/// The WKWebView that shows one screen of the live app. Shared website data store (one sign-in for all embedded
/// screens), no web swipe-back (the native navigation stack owns the edge swipe), JavaScript alerts as native alerts.
struct ShellWebView: UIViewRepresentable {
    let route: WebRoute
    let authScript: String
    let reloadToken: Int
    var fullScreen = false
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
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var onEvent: (ShellEvent) -> Void
        weak var webView: WKWebView?
        var reloadToken = 0

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
            case "tab": onEvent(.tab(str("tab"), prompt: body["prompt"] as? String))
            case "title": if !str("title").isEmpty { onEvent(.title(str("title"))) }
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
