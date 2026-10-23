import Foundation
import FirebaseFirestore

/// The website's username rules and claim, line for line (src/components/onboarding/onboardState.ts:
/// usernameProblem, usernameKey, usernameAvailability, claimUsername). The username is the name on posts and
/// reviews: users/{uid}/userData/preferences `username` + `profileDNA.username` (App.tsx handleUpdateProfileField),
/// and since Oct 23 2026 every new name is also claimed in usernames/{key} so two travelers never share one.
enum UsernameRules {
    static let minLength = 3
    static let maxLength = 30
    static let reserved = ["admin", "administrator", "owner", "kosher travel", "koshertravel", "support", "help",
                           "moderator", "staff", "official", "team"]

    enum Availability: Equatable { case free, taken, unknown }
    enum Claim: Equatable { case ok, taken, error }

    // the website's words
    static let hint = "3 to 30 letters or numbers."
    static let takenLine = "Already used by another traveler. Try another."
    static let unknownLine = "Couldn't check right now. Continue will check again."
    static let takenOnSave = "That username is already used by another traveler."
    static let justTaken = "That username was just taken. Try another."
    static func claimFailed(canSkip: Bool) -> String {
        canSkip ? "Couldn't save your username right now. Check your connection and try again, or tap Skip."
                : "Couldn't save your username right now. Check your connection and try again."
    }
    static let saveFailed = "Couldn't save right now. Check your connection and try again."

    private static let allowed = try? NSRegularExpression(pattern: "^[\\p{L}\\p{N} ._'-]+$")
    private static let dunder = try? NSRegularExpression(pattern: "^__.*__$")

    private static func matches(_ re: NSRegularExpression?, _ s: String) -> Bool {
        guard let re else { return true }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// usernameProblem: nil when the name is fine. Lengths count like the website's (UTF-16 units).
    static func problem(_ value: String, canSkip: Bool = true) -> String? {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return canSkip ? "Choose a username, or tap Skip." : "Choose a username." }
        if s.utf16.count < minLength { return "Use at least 3 characters." }
        if s.utf16.count > maxLength { return "Use 30 characters or fewer." }
        if !matches(allowed, s) { return "Use letters, numbers, spaces, dots, dashes or underscores." }
        if matches(dunder, s) { return "Use letters, numbers, spaces, dots, dashes or underscores." }
        if reserved.contains(key(s)) { return "That name is reserved. Try another." }
        return nil
    }

    /// usernameKey: one usernames/{key} doc per name, case and spacing folded ("Moshe  K" and "moshe k" are the same name).
    static func key(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// The name as saved: trimmed, runs of spaces folded to one (the claim doc's `name`).
    static func clean(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// The website's spellings to look for among live posts: as typed, lower, upper, Title Case.
    static func variants(_ s: String) -> [String] {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        var title = ""
        var atWordStart = true
        for ch in t.lowercased() {
            if atWordStart && ch.isLetter { title += ch.uppercased() } else { title.append(ch) }
            atWordStart = ch.isWhitespace
        }
        var out: [String] = []
        for v in [t, t.lowercased(), t.uppercased(), title] where !out.contains(v) { out.append(v) }
        return Array(out.prefix(10))
    }

    /// usernameAvailability: taken when another account holds usernames/{key}, or another traveler already posts
    /// under the name (older accounts never claimed theirs; nobody is renamed).
    static func availability(_ name: String, uid: String) async -> Availability {
        guard FirebaseBoot.isConfigured else { return .unknown }
        let db = Firestore.firestore()
        do {
            async let claim = db.collection("usernames").document(key(name)).getDocument()
            async let posts = db.collection("storyPosts")
                .whereField("status", isEqualTo: "live")
                .whereField("authorName", in: variants(name))
                .limit(to: 5)
                .getDocuments()
            let (c, p) = try await (claim, posts)
            if c.exists, (c.data()?["uid"] as? String) != uid { return .taken }
            return p.documents.contains { ($0.data()["userId"] as? String) != uid } ? .taken : .free
        } catch {
            print("[KT] username check: \(error.localizedDescription)")
            return .unknown
        }
    }

    /// claimUsername: the claim doc is created only if nobody holds it (the rules allow create by the owner and no
    /// update, so two people can never both get it); this account's earlier claims are released afterwards.
    static func claim(_ name: String, uid: String) async -> Claim {
        guard FirebaseBoot.isConfigured else { return .error }
        let db = Firestore.firestore()
        let k = key(name)
        let ref = db.collection("usernames").document(k)
        let cleaned = clean(name)
        if await availability(name, uid: uid) == .taken { return .taken }
        do {
            let result = try await db.runTransaction { tx, errorPointer -> Any? in
                let cur: DocumentSnapshot
                do {
                    cur = try tx.getDocument(ref)
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                if cur.exists {
                    return (cur.data()?["uid"] as? String) == uid ? "ok" : "taken"
                }
                tx.setData(["uid": uid, "name": cleaned, "createdAt": FieldValue.serverTimestamp()], forDocument: ref)
                return "ok"
            }
            let res = (result as? String) == "ok" ? Claim.ok : Claim.taken
            if res == .ok {
                Task.detached {
                    guard let old = try? await db.collection("usernames").whereField("uid", isEqualTo: uid)
                        .limit(to: 10).getDocuments() else { return }
                    for d in old.documents where d.documentID != k { try? await d.reference.delete() }
                }
            }
            return res
        } catch {
            print("[KT] username claim: \(error.localizedDescription)")
            // someone created it between our read and our write: the rules refuse an overwrite (PERMISSION_DENIED = 7)
            if (error as NSError).code == 7,
               let cur = try? await ref.getDocument(), cur.exists, (cur.data()?["uid"] as? String) != uid {
                return .taken
            }
            return .error
        }
    }

    /// The person's username as the app stores it (`username`, else `profileDNA.username`). nil when it couldn't be read.
    static func current(uid: String) async -> String? {
        guard FirebaseBoot.isConfigured else { return nil }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid)
                .collection("userData").document("preferences").getDocument()
            let d = snap.data() ?? [:]
            let direct = (d["username"] as? String) ?? ""
            let dna = ((d["profileDNA"] as? [String: Any])?["username"] as? String) ?? ""
            return (direct.isEmpty ? dna : direct).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("[KT] username read: \(error.localizedDescription)")
            return nil
        }
    }

    /// Save it where the website does (after the claim): users/{uid}/userData/preferences `username` + `profileDNA.username` (merged).
    static func save(_ name: String, uid: String) async throws {
        let v = name.trimmingCharacters(in: .whitespacesAndNewlines)   // the website saves user.trim()
        try await Firestore.firestore().collection("users").document(uid)
            .collection("userData").document("preferences")
            .setData(["username": v, "profileDNA": ["username": v], "updatedAt": FieldValue.serverTimestamp()],
                     merge: true)
    }
}
