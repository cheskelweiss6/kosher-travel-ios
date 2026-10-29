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

    /// Back inside the page (ShellWebNav): finds the page's own Back for the level it shows (the same rule as the
    /// website's swipe-back in src/lib/nativeFeel.ts: a Back pill / chevron near the top left that is not covered by
    /// another screen; also one scrolled away at the top of a long city page), tells the app whether there is one
    /// ("navback"), and presses it when the app asks (`window.__ktNav.back()`). Our own origin only; changes nothing on
    /// the page by itself.
    static let backScript = """
        (function(){try{
          var h=location.hostname; if(h!=='www.yourkoshertravel.com'&&h!=='yourkoshertravel.com')return;
          if(window.__ktNav)return;
          var SEL='[data-kt-back], button[aria-label="Back"], button[aria-label^="Back "], button[aria-label^="Back to"]';
          function scroller(e){
            for(var p=e.parentElement;p&&p!==document.body&&p!==document.documentElement;p=p.parentElement){
              var o=getComputedStyle(p).overflowY; if((o==='auto'||o==='scroll')&&p.scrollHeight>p.clientHeight+1)return p;
            }
            return null;
          }
          function overlayAt(x,y){
            var hit=document.elementFromPoint(x,y);
            for(var e=hit;e&&e!==document.body;e=e.parentElement){
              var cs=getComputedStyle(e);
              if(cs.position==='fixed'&&(parseInt(cs.zIndex,10)||0)>=20&&e.getBoundingClientRect().width>=window.innerWidth*0.8)return e;
            }
            return null;
          }
          function find(){
            var c=[];
            document.querySelectorAll(SEL).forEach(function(b){c.push(b);});
            document.querySelectorAll('button svg.lucide-chevron-left, button svg.lucide-arrow-left').forEach(function(s){
              var b=s.closest('button');
              if(b&&!b.closest('[data-testid=inspire-post], .snap-x')&&!/previous|prev|earlier|month|week/i.test(b.getAttribute('aria-label')||''))c.push(b);
            });
            var best=null,top=1e9,cx=window.innerWidth/2,cy=window.innerHeight/2;
            c.forEach(function(b){
              if(b.disabled||/top/i.test(b.getAttribute('aria-label')||''))return;
              var r=b.getBoundingClientRect();
              if(!r.width||!r.height||r.left>160||r.top>190)return;
              if(r.bottom>0){
                var hit=document.elementFromPoint(r.left+r.width/2,Math.max(1,r.top+r.height/2));
                if(!hit||!(hit===b||b.contains(hit)))return;
              }else{
                var s=scroller(b);
                var y=s?r.top-s.getBoundingClientRect().top+s.scrollTop:r.top+window.scrollY;
                if(y>400)return;
                var mid=document.elementFromPoint(cx,cy);
                if(!mid||!(s?s.contains(mid):!overlayAt(cx,cy)))return;
              }
              var key=r.bottom>0?r.top:1e6+r.top;
              if(key<top){best=b;top=key;}
            });
            return best;
          }
          var last=null,timer=0;
          function post(v){try{window.webkit.messageHandlers.ktShell.postMessage({type:'navback',back:v});}catch(e){}}
          function check(){timer=0;var v=!!find();if(v!==last){last=v;post(v);}}
          function soon(){if(!timer)timer=setTimeout(check,150);}
          window.__ktNav={back:function(){var b=find();if(!b){soon();return false;}b.click();soon();return true;},has:function(){return !!find();}};
          function start(){
            try{new MutationObserver(soon).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['style','hidden','aria-hidden']});}catch(e){}
            window.addEventListener('scroll',soon,{passive:true,capture:true});
            window.addEventListener('resize',soon,{passive:true});
            window.addEventListener('popstate',soon);
            soon();
          }
          if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
        }catch(e){}})();
        """

    /// What's New (root QA, Oct 29 2026: the screen showed the Explore home instead of the news). The website's news
    /// list is its own full screen over the Explore page ("See all" under What's New); this opens it, and hides that
    /// screen's own top bar because the app's bar already says "What's New" with its Back (no double header). A story
    /// opens the publisher's article, as on the website (window.open -> in-app Safari). `open: first` (QA screenshots
    /// only) opens the first story. Our own origin only.
    static let newsScript = """
        (function(){try{
        var h=location.hostname; if(h!=='www.yourkoshertravel.com'&&h!=='yourkoshertravel.com')return;
        if(window.__ktNewsList)return; window.__ktNewsList=1;
        var openFirst=!!(window.__KT_SHELL__&&window.__KT_SHELL__.open==='first');
        var css='html.kt-shell [role=dialog][aria-label="What\\u2019s New"] > [data-kt-bar], html.kt-shell [role=dialog][aria-label="What\\'s New"] > [data-kt-bar]{display:none!important}';
        function addCss(){var s=document.createElement('style');s.textContent=css;(document.head||document.documentElement).appendChild(s);}
        function dlg(){return document.querySelector('[role=dialog][aria-label="What\\'s New"], [role=dialog][aria-label="What\\u2019s New"]');}
        var n=0;
        function go(){
        var d=dlg();
        if(d){ if(openFirst){ setTimeout(function(){var b=d.querySelector('[data-testid=news-featured] > button, [data-testid=news-row] > button'); if(b)b.click();},1500);} return; }
        var b=document.querySelector('[data-testid=news-seeall]');
        if(b){b.click();}
        if(++n<120)setTimeout(go,250);
        }
        function start(){addCss();go();}
        if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',start,{once:true});else start();
        }catch(e){}})();
        """

    /// The user script that tells the page it is inside the app and which screen to open.
    static func shellScript(_ route: WebRoute, fullScreen: Bool = false) -> String {
        let base = baseShellScript(route, fullScreen: fullScreen)
        // The composer's native-app look (Features/Compose/ComposeSkin.swift), only on the compose screen.
        return route.screen == "compose" ? base + "\n" + ComposeSkin.script : base
    }

    private static func baseShellScript(_ route: WebRoute, fullScreen: Bool) -> String {
        """
        (function(){try{
          window.__KT_SHELL__=\(route.shellJSON);
          window.__KT_SHELL__.layout=\(fullScreen ? "'full'" : "'bar'");
          var c=document.documentElement&&document.documentElement.classList; if(!c)return;
          c.add('kt-shell'); c.add('native-app'); c.add('native-ios'); c.add(\(fullScreen ? "'kt-shell-full'" : "'kt-shell-bar'"));
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
