import Foundation
import WebKit
import FirebaseAuth

/// One web session for every embedded screen (the app's own website data store, separate from Safari), and the
/// native sign-in handed to the page.
///
/// Sign-in handoff: the page uses the Firebase web SDK, which keeps the signed-in user under
/// `firebase:authUser:<web api key>:[DEFAULT]` and, at start, takes a user it finds in local storage (and moves it to
/// IndexedDB). Before the page's own scripts run, a user script writes the natively signed-in user there (uid, email,
/// and the user's own Firebase refresh/ID tokens). The tokens never go in a URL, a log or a server: they move from the
/// app's Keychain-backed Firebase session into the website's storage on this phone, for our own origin only. The page
/// then checks them with Firebase as usual (an invalid token signs the page out). When the native account changes,
/// the website's stored sign-in is wiped first so a previous account can never linger in an embedded screen.
enum WebSession {
    static let home = URL(string: "https://www.yourkoshertravel.com/")!
    static let hosts: Set<String> = ["www.yourkoshertravel.com", "yourkoshertravel.com"]
    /// The website's Firebase web API key (public by design; the same key ships in the website).
    static let webApiKey = "AIzaSyAqIbbxAIfqwuTaE31czStjZXDKJMynkEs"
    private static let lastUidKey = "kt.shell.webUid"

    static func isOwn(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return hosts.contains(host)
    }

    /// Wipes the website's saved sign-in (and its other local storage) when the native account differs from the one
    /// last handed to the page.
    @MainActor
    static func prepareStore(uid: String?) async {
        let now = uid ?? ""
        let last = UserDefaults.standard.string(forKey: lastUidKey) ?? ""
        guard now != last else { return }
        let store = WKWebsiteDataStore.default()
        let types: Set<String> = [WKWebsiteDataTypeIndexedDBDatabases, WKWebsiteDataTypeLocalStorage,
                                  WKWebsiteDataTypeSessionStorage]
        let records = await store.dataRecords(ofTypes: types)
        let ours = records.filter { $0.displayName.lowercased().contains("yourkoshertravel.com") }
        if !ours.isEmpty { await store.removeData(ofTypes: types, for: ours) }
        UserDefaults.standard.set(now, forKey: lastUidKey)
    }

    /// The user script that hands the native sign-in to the page (or removes a stale one when signed out).
    @MainActor
    static func authScript() async -> String {
        let key = "firebase:authUser:\(webApiKey):[DEFAULT]"
        var userJSON = "null"
        if FirebaseBoot.isConfigured, let user = Auth.auth().currentUser, let refresh = user.refreshToken, !refresh.isEmpty,
           let result = try? await user.getIDTokenResult() {
            var u: [String: Any] = [
                "uid": user.uid,
                "emailVerified": user.isEmailVerified,
                "isAnonymous": user.isAnonymous,
                "apiKey": webApiKey,
                "appName": "[DEFAULT]",
                "stsTokenManager": [
                    "refreshToken": refresh,
                    "accessToken": result.token,
                    "expirationTime": Int64(result.expirationDate.timeIntervalSince1970 * 1000),
                ],
                "providerData": user.providerData.map { p -> [String: Any] in
                    var d: [String: Any] = ["providerId": p.providerID, "uid": p.uid]
                    if let v = p.displayName { d["displayName"] = v }
                    if let v = p.email { d["email"] = v }
                    if let v = p.photoURL?.absoluteString { d["photoURL"] = v }
                    if let v = p.phoneNumber { d["phoneNumber"] = v }
                    return d
                },
            ]
            if let v = user.email { u["email"] = v }
            if let v = user.displayName { u["displayName"] = v }
            if let v = user.photoURL?.absoluteString { u["photoURL"] = v }
            if let v = user.phoneNumber { u["phoneNumber"] = v }
            if let d = user.metadata.creationDate { u["createdAt"] = String(Int64(d.timeIntervalSince1970 * 1000)) }
            if let d = user.metadata.lastSignInDate { u["lastLoginAt"] = String(Int64(d.timeIntervalSince1970 * 1000)) }
            if let data = try? JSONSerialization.data(withJSONObject: u), let s = String(data: data, encoding: .utf8) {
                userJSON = s
            }
        }
        return """
        (function(){try{
          var h=location.hostname; if(h!=='www.yourkoshertravel.com'&&h!=='yourkoshertravel.com')return;
          var k=\(jsString(key)); var u=\(userJSON);
          if(u){localStorage.setItem(k, JSON.stringify(u));}else{localStorage.removeItem(k);}
        }catch(e){}})();
        """
    }

    /// The user script that tells the page it is inside the app and which screen to open.
    static func shellScript(_ route: WebRoute, fullScreen: Bool = false) -> String {
        """
        (function(){try{
          window.__KT_SHELL__=\(route.shellJSON);
          window.__KT_SHELL__.layout=\(fullScreen ? "'full'" : "'bar'");
          var c=document.documentElement.classList; c.add('kt-shell'); c.add(\(fullScreen ? "'kt-shell-full'" : "'kt-shell-bar'"));
        }catch(e){}})();
        """
    }

    static func jsString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]), var out = String(data: data, encoding: .utf8)
        else { return "''" }
        out.removeFirst(); out.removeLast()   // ["..."] -> "..."
        return out
    }
}
