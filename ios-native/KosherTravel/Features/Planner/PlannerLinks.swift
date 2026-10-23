import SwiftUI
import SafariServices

/// Links in answers: the app's own story links open the post here, web links open in Safari inside the app,
/// Expedia / Hotels.com links go through Cheskel's tracked links (web: src/lib/affiliate.ts affiliateUrl).
enum PlannerLinks {
    static let expedia = (camref: "1100l6w7pu", creativeref: "1100l68075")
    static let hotels = (camref: "1100l6w7pt", creativeref: "1011l66481")

    /// The story id in https://www.yourkoshertravel.com/?story=<id>
    static func storyId(_ url: URL) -> String? {
        guard let host = url.host?.lowercased(), host == "yourkoshertravel.com" || host.hasSuffix(".yourkoshertravel.com"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let id = items.first(where: { $0.name == "story" })?.value, !id.isEmpty else { return nil }
        return id
    }

    private static let foreignParam = try? NSRegularExpression(pattern:
        "^(camref|creativeref|adref|pubref|clickref|affcid|afflid|affdtl|my_ad|ref_id|rffrid|semcid|semdtl|mdpcid|mdpdtl|emlcid|emldtl|olacid|oladtl|brandcid|partnerref|irclickid|irgwc|irpid|sharedid|subid|utm_[a-z_]+|gclid|gclsrc|dclid|fbclid|msclkid|ttclid|wbraid|gbraid|aff|affid|aff_id|affiliate_?id|siteid)$",
        options: [.caseInsensitive])

    private static func isHost(_ host: String, _ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func cleanLanding(_ u: URL) -> String {
        guard var c = URLComponents(url: u, resolvingAgainstBaseURL: false) else { return u.absoluteString }
        c.scheme = "https"
        if let q = c.percentEncodedQuery {
            let kept = q.split(separator: "&").map(String.init).filter { pair in
                guard !pair.isEmpty else { return false }
                let rawKey = String(pair.split(separator: "=", maxSplits: 1).first ?? "")
                let key = rawKey.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? rawKey
                let ns = key as NSString
                return foreignParam?.firstMatch(in: key, range: NSRange(location: 0, length: ns.length)) == nil
            }
            c.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        }
        return c.string ?? u.absoluteString
    }

    private static func innerLanding(_ u: URL) -> URL? {
        let host = u.host?.lowercased() ?? ""
        if isHost(host, "expedia.com") || isHost(host, "hotels.com") {
            let lp = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "landingPage" })?.value
            return lp.flatMap(URL.init(string:))
        }
        if isHost(host, "prf.hn"), let r = u.path.range(of: #"/destination:([^/]+)"#, options: .regularExpression) {
            let raw = String(u.path[r]).replacingOccurrences(of: "/destination:", with: "")
            return URL(string: raw.removingPercentEncoding ?? raw)
        }
        return nil
    }

    static func affiliate(_ u: URL, depth: Int = 0) -> URL {
        guard depth < 3, let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return u }
        let host = u.host?.lowercased() ?? ""
        let isExp = isHost(host, "expedia.com"), isHot = isHost(host, "hotels.com")
        if isExp || isHot {
            let path = u.path
            if path.lowercased().hasPrefix("/affiliate/") && path.count > "/affiliate/".count { return u }   // his short link
            if path.lowercased() == "/affiliate" || path.lowercased() == "/affiliate/" {
                let mine = isExp ? expedia.camref : hotels.camref
                let camref = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "camref" })?.value
                if camref == mine { return u }
                guard let inner = innerLanding(u) else { return u }
                return affiliate(inner, depth: depth + 1)
            }
            let landing = encode(cleanLanding(u))
            let s = isExp
                ? "https://expedia.com/affiliate?siteid=1&landingPage=\(landing)&camref=\(expedia.camref)&creativeref=\(expedia.creativeref)"
                : "https://www.hotels.com/affiliate?landingPage=\(landing)&camref=\(hotels.camref)&creativeref=\(hotels.creativeref)"
            return URL(string: s) ?? u
        }
        if isHost(host, "prf.hn"), let inner = innerLanding(u) {
            let ih = inner.host?.lowercased() ?? ""
            if isHost(ih, "expedia.com") || isHost(ih, "hotels.com") { return affiliate(inner, depth: depth + 1) }
        }
        return u
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = Theme.navyUI
        vc.dismissButtonStyle = .done
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
