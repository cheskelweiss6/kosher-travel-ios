import SwiftUI
import UIKit
import SafariServices
import Network

// MARK: - Presenting from anywhere

/// Presents UIKit screens over whatever is on top (a tab, a sheet, a sheet on a sheet), so app-wide pieces
/// (map chooser, Safari, toasts) work from every screen without each screen wiring its own sheet.
@MainActor
enum TopPresenter {
    static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow && !($0 is PassThroughWindow) }
    }

    static var top: UIViewController? {
        var vc = keyWindow?.rootViewController
        while let next = vc?.presentedViewController, !next.isBeingDismissed { vc = next }
        return vc
    }

    static func present(_ vc: UIViewController) {
        top?.present(vc, animated: true)
    }

    static func safari(_ url: URL) {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Color.navy)
        vc.dismissButtonStyle = .close
        present(vc)
    }
}

// MARK: - Toasts above everything

/// A window above the app that shows the toast and lets every touch outside the toast through.
final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event) else { return nil }
        return hit == rootViewController?.view ? nil : hit
    }
}

@MainActor
enum ToastWindow {
    private static var window: PassThroughWindow?

    /// Called once from the root view; safe to call again.
    static func install() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = PassThroughWindow(windowScene: scene)
        let host = UIHostingController(rootView: ToastHost())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.windowLevel = .alert + 1
        w.backgroundColor = .clear
        w.isHidden = false
        window = w
    }
}

private struct ToastHost: View {
    @Bindable private var router = ShellRouter.shared
    var body: some View {
        VStack {
            if let toast = router.toast {
                ShellToastView(toast: toast)
                    .transition(Motion.slide(.top))
            }
            Spacer(minLength: 0)
            if let notice = router.notice {
                ShellNoticeView(notice: notice)
                    .padding(.bottom, 64)   // above the tab bar
                    .transition(Motion.slide(.bottom))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.expand, value: router.toast)
        .animation(Motion.expand, value: router.notice)
    }
}

// MARK: - Map app chooser (web: src/components/MapChooser.tsx)

enum MapApp: String, CaseIterable, Identifiable {
    case apple, google, waze
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple Maps"
        case .google: return "Google Maps"
        case .waze: return "Waze"
        }
    }
    /// Outline icons as on the web (lucide Map, MapPin, Navigation).
    var icon: String {
        switch self {
        case .apple: return "map"
        case .google: return "mappin"
        case .waze: return "location.north"
        }
    }

    private static let key = "kt-maps-app"
    /// The remembered app (Settings "Open maps in" and "Remember my choice" share it); nil = ask every time.
    static var preferred: MapApp? {
        get { UserDefaults.standard.string(forKey: key).flatMap(MapApp.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: key) }
    }
}

struct MapTarget: Equatable {
    var name: String?
    var query: String?
    var lat: Double?
    var lng: Double?
    var placeId: String?
    var title: String { (name ?? query ?? "").trimmingCharacters(in: .whitespaces) }
}

enum MapLinks {
    private static func coords(_ s: String?) -> (Double, Double)? {
        guard let s else { return nil }
        let parts = s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lng = Double(parts[1]),
              abs(lat) <= 90, abs(lng) <= 180,
              parts.allSatisfy({ $0.range(of: #"^-?\d{1,3}(\.\d+)?$"#, options: .regularExpression) != nil }) else { return nil }
        return (lat, lng)
    }

    private static func clean(_ s: String?) -> String {
        (s ?? "").replacingOccurrences(of: "+", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// What a Google Maps / Apple Maps link points at, or nil when it is not a map link we can read (web parseMapUrl).
    static func parse(_ url: URL) -> MapTarget? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = (url.host ?? "").lowercased()
        func q(_ k: String) -> String? { comps.queryItems?.first { $0.name == k }?.value }
        var t = MapTarget()
        @discardableResult func setCoords(_ s: String?) -> Bool {
            if let c = coords(s) { t.lat = c.0; t.lng = c.1; return true }
            return false
        }
        func setText(_ s: String?) {
            let v = clean(s)
            if v.isEmpty { return }
            if !setCoords(v) { t.query = v }
        }
        if host == "maps.apple.com" || host == "maps.apple" {
            if !setCoords(q("ll")) { if !setCoords(q("sll")) { setCoords(q("coordinate")) } }
            let text = clean(q("q") ?? q("name") ?? q("daddr") ?? q("destination") ?? q("address"))
            if !text.isEmpty {
                if coords(text) == nil { t.name = text } else { setCoords(text) }
            }
        } else if host.range(of: #"^(maps\.|www\.)?google\.[a-z.]+$"#, options: .regularExpression) != nil {
            let path = url.path
            let isMaps = host.hasPrefix("maps.") || path == "/maps" || path.hasPrefix("/maps/")
            if !isMaps || path.hasPrefix("/maps/embed") || path.hasPrefix("/maps/vt") || path.hasPrefix("/maps/api") { return nil }
            if let pid = q("query_place_id") ?? q("destination_place_id") { t.placeId = pid }
            setText(q("query") ?? q("destination") ?? q("q") ?? q("daddr"))
            if t.query == nil, let r = path.range(of: #"/maps/place/[^/]+"#, options: .regularExpression) {
                let seg = String(path[r].dropFirst("/maps/place/".count))
                setText(seg.removingPercentEncoding ?? seg)
            }
            if t.lat == nil, let r = path.range(of: #"@-?\d+(\.\d+)?,-?\d+(\.\d+)?"#, options: .regularExpression) {
                setCoords(String(path[r].dropFirst()))
            }
            if t.query == nil && t.lat == nil { setCoords(q("ll")) }
            if let query = t.query { t.name = query }
        } else {
            return nil
        }
        if t.name == nil && t.query == nil && t.lat == nil { return nil }
        return t
    }

    private static func fmt(_ d: Double) -> String {
        var s = String(format: "%.6f", d)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private static func enc(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?,#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// The link each app opens for a place: by name + location when both are known (web mapAppUrl).
    static func url(_ app: MapApp, _ t: MapTarget) -> URL? {
        let has = t.lat != nil && t.lng != nil
        let ll = has ? "\(fmt(t.lat!)),\(fmt(t.lng!))" : ""
        let text = t.title
        let s: String
        switch app {
        case .apple:
            let q = text.isEmpty ? (has ? "Location" : "") : text
            s = "https://maps.apple.com/?q=\(enc(q))" + (has ? "&ll=\(ll)" : "")
        case .google:
            if let pid = t.placeId {
                s = "https://www.google.com/maps/search/?api=1&query=\(enc(text.isEmpty ? (ll.isEmpty ? "place" : ll) : text))&query_place_id=\(enc(pid))"
            } else {
                s = "https://www.google.com/maps/search/?api=1&query=\(enc(has ? ll : text))"
            }
        case .waze:
            s = has ? "https://waze.com/ul?ll=\(enc(ll))&navigate=yes" : "https://waze.com/ul?q=\(enc(text))&navigate=yes"
        }
        return URL(string: s)
    }
}

@MainActor
enum MapOpener {
    private static var lastAsk = Date.distantPast

    /// Opens a map link the way the website does: the remembered app, else the "Open in" sheet.
    static func open(_ t: MapTarget) {
        guard Date().timeIntervalSince(lastAsk) > 0.6 else { return }
        lastAsk = Date()
        if let app = MapApp.preferred {
            launch(app, t)
            ShellRouter.shared.showToast("Opening in \(app.label)", seconds: 8, action: ShellToast.Action(label: "Change") {
                MapApp.preferred = nil
                ShellRouter.shared.toast = nil
                present(t)
            })
            return
        }
        present(t)
    }

    static func launch(_ app: MapApp, _ t: MapTarget) {
        guard let url = MapLinks.url(app, t) else { return }
        // Google Maps and Waze open their app when installed (universal links), else their website.
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok { TopPresenter.safari(url) }
        }
    }

    private static func present(_ t: MapTarget) {
        let host = UIHostingController(rootView: MapChooserSheet(target: t))
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.custom { _ in 330 }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 22
        }
        TopPresenter.present(host)
    }
}

struct MapChooserSheet: View {
    let target: MapTarget
    @Environment(\.dismiss) private var dismiss
    @State private var remember = MapApp.preferred != nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Open in").font(.headline).foregroundStyle(Color.navy)
                if !target.title.isEmpty {
                    Text(target.title).font(.subheadline).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(MapApp.allCases.enumerated()), id: \.element) { i, app in
                    if i > 0 { Divider() }
                    Button {
                        MapApp.preferred = remember ? app : nil
                        dismiss()
                        MapOpener.launch(app, target)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: app.icon)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(Color.navy)
                                .frame(width: 24)
                            Text(app.label).font(.body).foregroundStyle(Color.navy)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(minHeight: 56)
                        .padding(.horizontal, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
            Toggle("Remember my choice", isOn: $remember)
                .font(.subheadline)
                .foregroundStyle(Color.navy)
                .tint(Color.navy)
                .padding(.horizontal, 4)
            Button("Cancel") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.navy)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.white)
    }
}

// MARK: - One opener for every link the native screens open

extension LinkOpener {
    /// The app-wide openURL handler (RootTabView): maps through the chooser, phone / mail / WhatsApp to the system,
    /// web links to Safari inside the app with the affiliate rewrite.
    @MainActor
    static func handle(_ url: URL) -> OpenURLAction.Result {
        if let t = MapLinks.parse(url) { MapOpener.open(t); return .handled }
        switch target(for: url) {
        case .system(let u)?: openSystem(u)
        case .safari(let u)?: TopPresenter.safari(u)
        case .ownSite(let u)?: TopPresenter.safari(u)
        case .story(let id)?:
            let host = UIHostingController(rootView: NavigationStack { StoryDetailView(postId: id) })
            TopPresenter.present(host)
        case nil: return .systemAction
        }
        return .handled
    }
}

// MARK: - Sign in from anywhere (web: 'kt-need-signin' + the global AuthModal)

extension ShellRouter {
    /// Opens the native sign-in sheet over whatever is on screen (a tab, a sheet, a post), with an optional line
    /// saying why; when the person signs in, `then` finishes what they started (the like, the save, the follow).
    @MainActor
    func requireSignIn(_ message: String? = nil, mode: SignInSheet.Mode = .signIn, then: (@MainActor () -> Void)? = nil) {
        guard let auth else { signIn = mode; return }
        if auth.isSignedIn { then?(); return }
        if let message { showToast(message) }
        let host = UIHostingController(rootView: SignInHost(mode: mode, then: then).environment(auth))
        TopPresenter.present(host)
    }
}

private struct SignInHost: View {
    let mode: SignInSheet.Mode
    let then: (@MainActor () -> Void)?
    @Environment(AuthStore.self) private var auth
    var body: some View {
        SignInSheet(mode: mode)
            .tint(Color.navy)
            .onDisappear {
                if auth.isSignedIn, let then { Task { @MainActor in then() } }
            }
    }
}

// MARK: - Failure notice above the tab bar (web: components/NoticeBar.tsx, notify.ts)

struct ShellNotice: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var retry: (@MainActor () -> Void)?
    static func == (a: ShellNotice, b: ShellNotice) -> Bool { a.id == b.id }
}

extension ShellRouter {
    /// Every failed save, like or load: navy on white above the tab bar, optional Retry, closes after 5 s (9 s with Retry).
    @MainActor
    func notify(_ text: String, retry: (@MainActor () -> Void)? = nil) {
        let n = ShellNotice(text: text, retry: retry)
        notice = n
        let secs: UInt64 = retry == nil ? 5 : 9
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: secs * 1_000_000_000)
            if self.notice?.id == n.id { self.notice = nil }
        }
    }
}

struct ShellNoticeView: View {
    let notice: ShellNotice
    var body: some View {
        HStack(spacing: 10) {
            Text(notice.text)
                .font(.subheadline)
                .foregroundStyle(Color.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry = notice.retry {
                Button("Retry") {
                    ShellRouter.shared.notice = nil
                    retry()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.navy)
            }
            Button {
                ShellRouter.shared.notice = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.navy)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
        .shadow(color: Color.navy.opacity(0.08), radius: 10, y: 4)
        .padding(.horizontal, 16)
    }
}

// MARK: - Online / offline (web: App.tsx online/offline toasts)


@MainActor
enum NetworkWatch {
    private static var monitor: NWPathMonitor?
    private static var wasOnline = true

    static func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { @Sendable path in
            let online = path.status == .satisfied
            Task { @MainActor in changed(online) }
        }
        m.start(queue: DispatchQueue(label: "kt.network"))
        monitor = m
    }

    private static func changed(_ online: Bool) {
        guard online != wasOnline else { return }
        wasOnline = online
        ShellRouter.shared.showToast(online ? "You are back online! Synchronized." : "You are offline. Showing what was already loaded.", seconds: 3.5)
    }
}
