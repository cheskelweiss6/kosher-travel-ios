import Foundation

/// A screen of the live app (www.yourkoshertravel.com) shown inside the native shell until it is rebuilt natively.
/// `screen` and `params` reach the page as `window.__KT_SHELL__` before it loads (never in the URL, so nothing is
/// logged); the page opens that screen with its own header and tab bar hidden (src/ktShell.ts on the website).
struct WebRoute: Hashable, Identifiable {
    var screen: String
    var params: [String: String] = [:]
    var title: String

    var id: String {
        screen + "|" + params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }.joined(separator: "&")
    }

    /// The JSON object handed to the page.
    var shellJSON: String {
        var obj: [String: String] = params
        obj["screen"] = screen
        obj["v"] = "1"
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{\"screen\":\"explore\",\"v\":\"1\"}" }
        return s
    }

    // MARK: Explore
    static func state(_ name: String, tab: String? = nil) -> WebRoute {
        var p = ["name": name]
        if let tab { p["tab"] = tab }
        return WebRoute(screen: "state", params: p, title: name)
    }
    static func country(_ name: String) -> WebRoute { WebRoute(screen: "country", params: ["name": name], title: name) }
    /// A city page. `sub` is "<State>, United States" or "<Country>" (the web's areaDest match).
    static func city(_ name: String, sub: String, section: String? = nil) -> WebRoute {
        var p = ["name": name, "sub": sub]
        if let section { p["section"] = section }
        return WebRoute(screen: "city", params: p, title: name)
    }
    static let exploreSearch = WebRoute(screen: "search", title: "Search")
    static let kivrei = WebRoute(screen: "kivrei", title: "Kivrei Tzadikim")
    static let europe = WebRoute(screen: "europe", title: "Europe")
    static let news = WebRoute(screen: "news", title: "What's New")

    // MARK: My Travel
    static let myTravel = WebRoute(screen: "mytravel", title: "My Travel")
    static let travelMap = WebRoute(screen: "travelmap", title: "Travel Map")

    // MARK: Stories
    static let inspire = WebRoute(screen: "inspire", title: "Get Inspired")
    static func compose(as kind: String? = nil, city: String? = nil, region: String? = nil) -> WebRoute {
        var p: [String: String] = [:]
        if let kind { p["as"] = kind }
        if let city { p["city"] = city }
        if let region { p["region"] = region }
        return WebRoute(screen: "compose", params: p, title: kind == "guide" ? "New article" : "Share your trip")
    }

    // MARK: Profile and admin
    static let profileWeb = WebRoute(screen: "profile", title: "My posts and reviews")
    static let adminReview = WebRoute(screen: "admin", params: ["tool": "review"], title: "Review posts")
    static let adminInbox = WebRoute(screen: "admin", params: ["tool": "inbox"], title: "Inbox")
}
