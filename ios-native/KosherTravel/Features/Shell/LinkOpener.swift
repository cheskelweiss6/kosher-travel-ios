import SwiftUI
import UIKit

/// Where a tapped link goes. One rule set for the whole app (parity checklist phase 1, "one link opener"):
/// our own post links open the native post, maps / phone / mail / WhatsApp open the system app, and every other
/// web link opens in Safari inside the app, with Expedia / Hotels.com links switched to Cheskel's tracked link
/// (the same rewrite as the website's src/lib/affiliate.ts).
enum LinkTarget: Equatable {
    case story(String)
    case ownSite(URL)
    case safari(URL)
    case system(URL)
}

enum LinkOpener {
    private static let systemSchemes: Set<String> = ["tel", "telprompt", "mailto", "sms", "maps", "facetime", "facetime-audio",
                                                     "itms-apps", "itms-appss", "whatsapp", "comgooglemaps", "waze"]

    static func target(for url: URL) -> LinkTarget? {
        let scheme = url.scheme?.lowercased() ?? ""
        if systemSchemes.contains(scheme) { return .system(url) }
        guard scheme == "http" || scheme == "https" else { return nil }
        if let id = PlannerLinks.storyId(url) { return .story(id) }
        if WebSession.isOwn(url) { return .ownSite(url) }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let opensApp =
            host == "maps.apple.com" || host == "maps.google.com" || host == "maps.app.goo.gl" ||
            ((host == "www.google.com" || host == "google.com") && path.hasPrefix("/maps")) ||
            host == "waze.com" || host.hasSuffix(".waze.com") ||
            host == "wa.me" || host == "api.whatsapp.com" || host == "chat.whatsapp.com" ||
            host == "apps.apple.com" || host == "itunes.apple.com"
        if opensApp { return .system(url) }
        return .safari(PlannerLinks.affiliate(url))
    }

    /// Opens a system link (Maps, phone, mail…). Returns false when nothing on the phone can open it.
    @MainActor
    static func openSystem(_ url: URL) {
        UIApplication.shared.open(url, options: [:]) { ok in
            if !ok { ShellRouter.shared.showToast("This link can't be opened on this iPhone") }
        }
    }
}
