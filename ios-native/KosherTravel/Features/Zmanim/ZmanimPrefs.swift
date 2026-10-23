// "My zmanim": the opinions a traveler holds and their own zmanim location, ported from the website's
// src/lib/zmanim/prefs.ts. Saved on this phone under the website's localStorage keys (UserDefaults, same JSON text)
// and, when signed in, in users/{uid}/userData/zmanimPrefs, exactly the fields the website writes (merge).
import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

@Observable
final class ZmanimPrefsStore {
    static let shared = ZmanimPrefsStore()

    static let prefsKey = "kt_zmanim_prefs_v1"
    static let placeKey = "kt_zmanim_place_v1"

    private(set) var opts: ZmanimOpts
    private(set) var place: ZmanimSavedPlace?
    @ObservationIgnored private var updatedAt: Double = 0
    @ObservationIgnored private var hasLocal = false
    @ObservationIgnored private var currentUid: String?
    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?

    private init() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: Self.prefsKey), let j = Self.json(raw) {
            opts = ZmanimOpts.clean(j)
            updatedAt = (j["updatedAt"] as? NSNumber)?.doubleValue ?? 0
            hasLocal = true
        } else {
            opts = .defaults
        }
        if let raw = d.string(forKey: Self.placeKey), let j = Self.json(raw) { place = Self.cleanPlace(j) } else { place = nil }
        listenForAuth()
    }

    private static func json(_ s: String) -> [String: Any]? {
        guard let data = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return o
    }
    private static func text(_ o: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static var nowMs: Double { (Date().timeIntervalSince1970 * 1000).rounded(.down) }

    // MARK: account sync

    private func listenForAuth() {
        guard FirebaseBoot.isConfigured else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            let uid = user?.uid
            if let uid, uid != self.currentUid {
                self.currentUid = uid
                Task { await self.syncForUser(uid) }
            }
            if uid == nil { self.currentUid = nil }
        }
    }

    private func doc(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid).collection("userData").document("zmanimPrefs")
    }

    @MainActor
    private func syncForUser(_ uid: String) async {
        guard let snap = try? await doc(uid).getDocument() else { return }
        let remote = snap.exists ? snap.data() : nil
        let remoteAt = (remote?["updatedAt"] as? NSNumber)?.doubleValue ?? 0
        if let remote, (!hasLocal || remoteAt > updatedAt) {
            opts = ZmanimOpts.clean(remote)
            updatedAt = remoteAt > 0 ? remoteAt : Self.nowMs
            hasLocal = true
            saveLocalPrefs()
        } else if hasLocal && updatedAt > 0 {
            pushRemote(uid)
        }
        if let rp = (remote?["place"] as? [String: Any]).flatMap(Self.cleanPlace), place == nil || rp.at > (place?.at ?? 0) {
            place = rp
            saveLocalPlace()
        } else if let p = place, p.at > 0 {
            pushPlace(uid, p)
        }
    }

    private func pushRemote(_ uid: String) {
        guard FirebaseBoot.isConfigured else { return }
        var data = opts.dictionary
        data["updatedAt"] = updatedAt
        doc(uid).setData(data, merge: true)
    }
    private func pushPlace(_ uid: String, _ p: ZmanimSavedPlace) {
        guard FirebaseBoot.isConfigured else { return }
        doc(uid).setData(["place": Self.placeDict(p)], merge: true)
    }

    // MARK: local

    private func saveLocalPrefs() {
        var o = opts.dictionary
        o["updatedAt"] = updatedAt
        if let s = Self.text(o) { UserDefaults.standard.set(s, forKey: Self.prefsKey) }
    }
    private func saveLocalPlace() {
        guard let p = place, let s = Self.text(Self.placeDict(p)) else { return }
        UserDefaults.standard.set(s, forKey: Self.placeKey)
    }

    private static func placeDict(_ p: ZmanimSavedPlace) -> [String: Any] {
        ["name": p.name, "lat": p.lat, "lng": p.lng, "tz": p.tz, "at": p.at, "gps": p.gps]
    }
    private static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
    /// cleanPlace: a valid place or nil (coordinates rounded to 4 decimals, name cut to 80 characters).
    static func cleanPlace(_ x: [String: Any]) -> ZmanimSavedPlace? {
        guard let lat = number(x["lat"]), let lng = number(x["lng"]), lat.isFinite, lng.isFinite, abs(lat) <= 90, abs(lng) <= 180,
              let tz = x["tz"] as? String, !tz.isEmpty else { return nil }
        let rawName = (x["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "My location"
        return ZmanimSavedPlace(name: String(rawName.prefix(80)),
                                lat: ZmanimDates.jsRound(lat * 1e4) / 1e4, lng: ZmanimDates.jsRound(lng * 1e4) / 1e4,
                                tz: tz, at: number(x["at"]) ?? 0, gps: (x["gps"] as? Bool) ?? false)
    }

    // MARK: public

    /// saveZmanimPrefs: saved at once (phone + account).
    func save(_ change: (inout ZmanimOpts) -> Void) {
        var next = opts
        change(&next)
        opts = ZmanimOpts.clean(next.dictionary)
        updatedAt = Self.nowMs
        hasLocal = true
        saveLocalPrefs()
        if let uid = currentUid { pushRemote(uid) }
    }

    /// saveZmanimPlace.
    func savePlace(_ p: ZmanimSavedPlace) {
        var d = Self.placeDict(p)
        d["at"] = Self.nowMs
        guard let c = Self.cleanPlace(d) else { return }
        place = c
        saveLocalPlace()
        if let uid = currentUid { pushPlace(uid, c) }
    }
}
