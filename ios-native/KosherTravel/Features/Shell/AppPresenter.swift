import SwiftUI
import UIKit
import SafariServices

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
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy, value: router.toast)
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
