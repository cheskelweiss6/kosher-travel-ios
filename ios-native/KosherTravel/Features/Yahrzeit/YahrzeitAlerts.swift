import Foundation
import Observation
import UserNotifications
import FirebaseFirestore

/// Yahrzeit alerts on the phone (Oct 25 2026, Cheskel: "add option in the setting to turn on alerts for yahrzeit").
///
/// No server and no push keys: the app books the notifications on the phone itself (local notifications) and books
/// them again every time it opens, so new kevarim, a changed setting or a new heart are picked up.
/// - The switch, which kevarim and how many days before are the website's own setting (yahrzeitPrefs.ts):
///   users/{uid}/userData/yahrzeitPrefs { on, yahrzeitAlerts, scope "saved"|"all", daysBefore 1|3|7, tz, updatedAt },
///   and for a guest on this phone only. The saved kevarim are the hearts: users/{uid}/userData/preferences bookmarkedKevarim.
/// - The dates are worked out by the website's tested Hebrew-calendar code (src/lib/yahrzeit/core.ts) and written to
///   yahrzeit-dates.json: a copy ships inside the app, and a newer one is read from www.yourkoshertravel.com when there is one.
/// - Each yahrzeit gets a notification at 9 AM (phone time) N days before and on the day. iOS keeps at most 64 waiting
///   notifications per app, so the nearest 60 are booked; the rest are booked on a later app open.
struct YahrzeitPrefs: Equatable {
    var on = false
    var scope = "saved"      // "saved" | "all"
    var daysBefore = 3       // 1 | 3 | 7

    static let dayChoices = [1, 3, 7]

    init() {}
    init(_ d: [String: Any]) {
        on = (d["on"] as? Bool) == true
        scope = (d["scope"] as? String) == "all" ? "all" : "saved"
        let n = (d["daysBefore"] as? NSNumber)?.intValue ?? 3
        daysBefore = Self.dayChoices.contains(n) ? n : 3
    }
    var dict: [String: Any] { ["on": on, "scope": scope, "daysBefore": daysBefore] }
}

struct YahrzeitDatesFile: Decodable {
    struct Kever: Decodable {
        let id: String
        let name: String
        let yahrzeit: String?
        let hebrewYahrzeit: String?
        let city: String?
        let country: String?
        let dates: [String]
    }
    let v: Int
    let from: String
    let to: String
    let kevarim: [Kever]
}

/// One notification the app would book (also what the "next alert" line shows).
struct YahrzeitAlertPlan: Equatable {
    let id: String
    let keverId: String
    let fire: Date
    let title: String
    let body: String
}

@MainActor
@Observable
final class YahrzeitAlerts {
    static let shared = YahrzeitAlerts()
    nonisolated static let remoteURL = URL(string: "https://www.yourkoshertravel.com/yahrzeit-dates.json")!
    nonisolated static let idPrefix = "yz-"
    nonisolated static let maxBooked = 60
    nonisolated static let alertHour = 9

    private(set) var prefs = YahrzeitPrefs()
    private(set) var permission: UNAuthorizationStatus = .notDetermined
    private(set) var booked = 0
    private(set) var next: YahrzeitAlertPlan?
    private(set) var savedCount = 0
    private(set) var uid: String?

    @ObservationIgnored private var file: YahrzeitDatesFile?
    @ObservationIgnored private var remoteTried = false
    private let delegate = YahrzeitNotificationDelegate()

    private init() {}

    private static func key(_ uid: String?) -> String { "kt_yahrzeit_prefs_v1_" + (uid ?? "guest") }

    // MARK: - setting

    /// Read the setting (this phone first, then the account), and book the notifications again.
    func refresh(uid: String?) async {
        self.uid = uid
        if UNUserNotificationCenter.current().delegate == nil { UNUserNotificationCenter.current().delegate = delegate }
        if let d = UserDefaults.standard.dictionary(forKey: Self.key(uid)) { prefs = YahrzeitPrefs(d) } else { prefs = YahrzeitPrefs() }
        if let uid, FirebaseBoot.isConfigured,
           let snap = try? await Firestore.firestore().collection("users").document(uid)
               .collection("userData").document("yahrzeitPrefs").getDocument(),
           let d = snap.data() {
            prefs = YahrzeitPrefs(d)
            UserDefaults.standard.set(prefs.dict, forKey: Self.key(uid))
        }
        await reschedule()
    }

    /// Save a change: this phone at once, the account in the background (same document the website writes).
    func save(_ next: YahrzeitPrefs) async {
        prefs = next
        UserDefaults.standard.set(next.dict, forKey: Self.key(uid))
        if next.on && permission == .notDetermined { _ = await requestPermission() }
        if let uid, FirebaseBoot.isConfigured {
            var d = next.dict
            d["yahrzeitAlerts"] = next.on
            d["tz"] = TimeZone.current.identifier
            d["updatedAt"] = Int(Date().timeIntervalSince1970 * 1000)
            try? await Firestore.firestore().collection("users").document(uid)
                .collection("userData").document("yahrzeitPrefs").setData(d, merge: true)
        }
        await reschedule()
    }

    @discardableResult
    func requestPermission() async -> Bool {
        let ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return ok
    }

    /// A notification in 5 seconds, on this phone only, so the person can see what an alert looks like.
    func sendTest() async {
        if permission == .notDetermined { _ = await requestPermission() }
        guard permission == .authorized || permission == .provisional || permission == .ephemeral else { return }
        let c = UNMutableNotificationContent()
        c.title = "Yahrzeit alerts are on"
        c.body = next.map { "Next: \($0.body)" } ?? "You'll get a note on the day and before each yahrzeit."
        c.sound = .default
        c.threadIdentifier = "yahrzeit"
        let r = UNNotificationRequest(identifier: Self.idPrefix + "test",
                                      content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false))
        try? await UNUserNotificationCenter.current().add(r)
    }

    // MARK: - booking

    func reschedule() async {
        let center = UNUserNotificationCenter.current()
        permission = await center.notificationSettings().authorizationStatus
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) && $0 != Self.idPrefix + "test" }
        center.removePendingNotificationRequests(withIdentifiers: old)
        booked = 0
        next = nil
        guard prefs.on else { return }
        var ids: Set<String>? = nil
        if prefs.scope == "saved" && uid != nil {   // a guest has no saved list here: all kevarim
            let s = await savedIds()
            savedCount = s.count
            if s.isEmpty { return }
            ids = s
        }
        guard let f = await datesFile() else { return }
        let plans = Self.plan(f, ids: ids, daysBefore: prefs.daysBefore, now: Date())
        next = plans.first
        guard permission == .authorized || permission == .provisional || permission == .ephemeral else { return }
        for p in plans {
            let c = UNMutableNotificationContent()
            c.title = p.title
            c.body = p.body
            c.sound = .default
            c.threadIdentifier = "yahrzeit"
            c.userInfo = ["keverId": p.keverId, "kind": "yahrzeit"]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.fire)
            let r = UNNotificationRequest(identifier: p.id, content: c,
                                          trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
            if (try? await center.add(r)) != nil { booked += 1 }
        }
        print("[KT] yahrzeit booked=\(booked) next=\(next?.body ?? "none")")
    }

    /// The nearest notifications for these kevarim (nil = all), soonest first, at most `maxBooked`.
    nonisolated static func plan(_ f: YahrzeitDatesFile, ids: Set<String>?, daysBefore: Int, now: Date,
                                 calendar: Calendar = .current) -> [YahrzeitAlertPlan] {
        var out: [YahrzeitAlertPlan] = []
        let ymd = DateFormatter()
        ymd.calendar = Calendar(identifier: .gregorian)
        ymd.locale = Locale(identifier: "en_US_POSIX")
        ymd.timeZone = calendar.timeZone
        ymd.dateFormat = "yyyy-MM-dd"
        let nice = DateFormatter()
        nice.locale = Locale(identifier: "en_US")
        nice.timeZone = calendar.timeZone
        nice.dateFormat = "EEE, MMM d"
        let horizon = now.addingTimeInterval(400 * 86400)
        for k in f.kevarim {
            if let ids, !ids.contains(k.id) { continue }
            let when = Self.dateWords(k)
            for s in k.dates {
                guard let day = ymd.date(from: s), day < horizon else { continue }
                for d in Set([daysBefore, 0]) {
                    guard let alertDay = calendar.date(byAdding: .day, value: -d, to: day),
                          let fire = calendar.date(bySettingHour: alertHour, minute: 0, second: 0, of: alertDay),
                          fire > now else { continue }
                    let title = d == 0 ? "Yahrzeit today" : (d == 1 ? "Yahrzeit tomorrow" : "Yahrzeit in \(d) days")
                    var parts = [k.name]
                    if !when.isEmpty { parts.append(when) }
                    if d != 0 { parts.append(nice.string(from: day)) }
                    out.append(YahrzeitAlertPlan(id: "\(idPrefix)\(k.id)-\(s)-\(d)", keverId: k.id, fire: fire,
                                                 title: title, body: parts.joined(separator: " \u{00B7} ")))
                }
            }
        }
        out.sort { $0.fire == $1.fire ? $0.id < $1.id : $0.fire < $1.fire }
        return Array(out.prefix(maxBooked))
    }

    /// "21 Adar", else the Hebrew in its own right-to-left island so it never scrambles the English line.
    nonisolated static func dateWords(_ k: YahrzeitDatesFile.Kever) -> String {
        let en = (k.yahrzeit ?? "").trimmingCharacters(in: .whitespaces)
        if !en.isEmpty, en.range(of: "\\p{Hebrew}", options: .regularExpression) == nil { return en }
        let he = (k.hebrewYahrzeit ?? en).trimmingCharacters(in: .whitespaces)
        return he.isEmpty ? "" : "\u{2068}\(he)\u{2069}"
    }

    // MARK: - data

    private func savedIds() async -> Set<String> {
        guard let uid, FirebaseBoot.isConfigured,
              let snap = try? await Firestore.firestore().collection("users").document(uid)
                  .collection("userData").document("preferences").getDocument(),
              let list = snap.data()?["bookmarkedKevarim"] as? [Any] else { return [] }
        return Set(list.map { "\($0)" })
    }

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("yahrzeit-dates.json")
    }

    private func datesFile() async -> YahrzeitDatesFile? {
        if file == nil {
            var best: YahrzeitDatesFile?
            if let u = Bundle.main.url(forResource: "yahrzeit-dates", withExtension: "json"),
               let d = try? Data(contentsOf: u) { best = try? JSONDecoder().decode(YahrzeitDatesFile.self, from: d) }
            if let u = Self.cacheURL, let d = try? Data(contentsOf: u),
               let c = try? JSONDecoder().decode(YahrzeitDatesFile.self, from: d), c.to >= (best?.to ?? "") { best = c }
            file = best
        }
        if !remoteTried {
            remoteTried = true
            var req = URLRequest(url: Self.remoteURL)
            req.timeoutInterval = 15
            req.cachePolicy = .reloadIgnoringLocalCacheData
            if let got = try? await URLSession.shared.data(for: req),
               (got.1 as? HTTPURLResponse)?.statusCode == 200,
               let r = try? JSONDecoder().decode(YahrzeitDatesFile.self, from: got.0), r.v == 1, !r.kevarim.isEmpty {
                file = r
                if let u = Self.cacheURL { try? got.0.write(to: u, options: .atomic) }
            }
        }
        return file
    }
}

/// Shows a yahrzeit alert as a banner even while the app is open.
final class YahrzeitNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
