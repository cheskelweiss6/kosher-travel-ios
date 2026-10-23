import Foundation
import Observation
import UIKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Models (the documents the web app writes)

/// One of the signed-in traveler's own posts (storyPosts where userId == uid), any status.
struct OwnStory: Identifiable, Hashable {
    let id: String
    let title: String
    let isGuide: Bool
    let status: String          // pending | live | rejected
    let rejectReason: String
    let createdAtMs: Double
    let cover: String
    let isVideo: Bool
    let mediaCount: Int
    /// Storage files of the post (photos, video covers, product photos), removed with the post.
    let storageURLs: [String]

    init(id: String, data d: [String: Any]) {
        self.id = id
        let media = (d["media"] as? [[String: Any]]) ?? []
        let products = (d["products"] as? [[String: Any]]) ?? []
        let t = (d["title"] as? String) ?? ""
        let city = (d["cityName"] as? String) ?? ""
        title = t.isEmpty ? (city.isEmpty ? "Your story" : city) : t
        isGuide = (d["type"] as? String) == "guide"
        let st = (d["status"] as? String) ?? ""
        status = st.isEmpty ? "pending" : st
        rejectReason = (d["rejectReason"] as? String) ?? ""
        createdAtMs = ProfileStore.millis(d["createdAtMs"]) ?? ProfileStore.millis(d["createdAt"]) ?? 0
        let first = media.first
        let thumb = (first?["thumb"] as? String) ?? ""
        let video = (first?["type"] as? String) == "video"
        isVideo = video
        cover = !thumb.isEmpty ? thumb : (video ? "" : ((first?["url"] as? String) ?? ""))
        mediaCount = media.count
        let urls = media.flatMap { [($0["url"] as? String) ?? "", ($0["thumb"] as? String) ?? ""] }
            + products.flatMap { [($0["img"] as? String) ?? "", ($0["thumb"] as? String) ?? ""] }
        storageURLs = urls.filter { $0.contains("firebasestorage.googleapis.com") }
    }
}

/// users/{uid}/savedPosts/{postId} { postId, type, title, thumb, savedAt }
struct SavedPostItem: Identifiable, Hashable {
    let id: String
    let title: String
    let isGuide: Bool
    let thumb: String
    let savedAtMs: Double
}

/// users/{uid}/notifications/{id}; a grouped like row carries every note id in it.
struct BellNote: Identifiable, Hashable {
    let id: String
    let kind: String            // comment | follow | like | review | report
    let actorUid: String
    let actorName: String
    let actorPhoto: String
    let postId: String
    let postTitle: String
    let postThumb: String
    let text: String
    let createdAtMs: Double
    var read: Bool
    let placeName: String
    let rating: Int?
    var ids: [String]
    var others: Int
}

struct BellSwitches: Equatable {
    var comments = true
    var follows = true
    var likes = true
    var reviews = true

    func allows(_ kind: String) -> Bool {
        switch kind {
        case "follow": return follows
        case "like": return likes
        case "review": return reviews
        case "comment", "": return comments
        default: return true
        }
    }
}

/// Saved kosher preferences (kosherPrefs.ts): on this phone, and in users/{uid}/userData/kosherPrefs when signed in.
struct SavedKosherPrefs: Equatable, Codable {
    var needs: [String] = []
    var filtersOn = true
    var updatedAt: Double = 0

    static let food = ["Glatt kosher", "Cholov Yisroel", "Pas Yisroel"]
    static let nearby = ["Near a shul", "Daily minyan nearby", "Chabad house", "Mikvah nearby", "Kosher grocery nearby", "Inside an eruv"]
    static let ownFood = "Bringing my own food"
    static let trip = [ownFood, "Shabbos walking distance", "Shabbos-friendly hotel (no key card)"]
    static let all = food + nearby + trip

    static func clean(_ raw: [String]) -> [String] {
        var set = Set<String>()
        for n in raw {
            if n == "Near a shul or Chabad" { set.insert("Near a shul"); set.insert("Chabad house"); continue }
            if n == "Kitchen or fridge (bringing my own food)" { set.insert(ownFood); continue }
            if all.contains(n) { set.insert(n) }
        }
        return all.filter { set.contains($0) }
    }
}

// MARK: - Store

/// Everything the Profile tab reads and writes for the signed-in person, matching the web app's documents and the live rules.
@Observable
final class ProfileStore {
    static let reviewOwnerUids = ["ZilNixJYqChwhgBopF7OHFcyIX13", "oKMrTvuUxWPCH10hCHB1uZwHpYm1"]
    static let kosherKey = "kt_kosher_prefs_v1"

    private(set) var uid: String?
    private(set) var username = ""
    private(set) var followers: Int?
    private(set) var following: Int?
    private(set) var stories: [OwnStory] = []
    private(set) var storiesLoaded = false
    private(set) var storiesFailed = false
    private(set) var saved: [SavedPostItem] = []
    private(set) var savedLoaded = false
    private(set) var notifPrefs = BellSwitches()
    private(set) var kosherPrefs: SavedKosherPrefs?
    private(set) var rawNotifs: [BellNote]?
    private(set) var notifsOK = true

    @ObservationIgnored private var listener: ListenerRegistration?

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.kosherKey),
           let p = try? JSONDecoder().decode(SavedKosherPrefs.self, from: data) {
            kosherPrefs = SavedKosherPrefs(needs: SavedKosherPrefs.clean(p.needs), filtersOn: p.filtersOn, updatedAt: p.updatedAt)
        }
    }

    deinit { listener?.remove() }

    private var db: Firestore { Firestore.firestore() }
    private func userRef(_ uid: String) -> DocumentReference { db.collection("users").document(uid) }

    /// Notes shown in the bell: the switches applied, likes grouped per post (notifGroup.ts).
    var shownNotifs: [BellNote]? {
        guard let raw = rawNotifs else { return nil }
        var out: [BellNote] = []
        var likeRow: [String: Int] = [:]
        for n in raw where notifPrefs.allows(n.kind) {
            if n.kind != "like" { out.append(n); continue }
            if let i = likeRow[n.postId] {
                out[i].ids.append(n.id)
                out[i].others += 1
                if !n.read { out[i].read = false }
            } else {
                var row = n
                row.ids = [n.id]
                row.others = 0
                likeRow[n.postId] = out.count
                out.append(row)
            }
        }
        return out
    }

    var unreadCount: Int { (shownNotifs ?? []).filter { !$0.read }.count }
    var pendingCount: Int { stories.filter { $0.status == "pending" }.count }

    // MARK: binding to the signed-in person

    @MainActor
    func bind(uid newUid: String?) async {
        guard newUid != uid else { return }
        listener?.remove()
        listener = nil
        uid = newUid
        username = ""
        followers = nil
        following = nil
        stories = []
        storiesLoaded = false
        storiesFailed = false
        saved = []
        savedLoaded = false
        notifPrefs = BellSwitches()
        rawNotifs = nil
        notifsOK = true
        guard let newUid, FirebaseBoot.isConfigured else { return }
        watchNotifications(newUid)
        async let a: Void = loadUsername(newUid)
        async let b: Void = loadCounts(newUid)
        async let c: Void = loadStories(newUid)
        async let d: Void = loadSaved(newUid)
        async let e: Void = loadBellSwitches(newUid)
        async let f: Void = syncKosherPrefs(newUid)
        _ = await (a, b, c, d, e, f)
    }

    @MainActor
    func reload() async {
        guard let uid, FirebaseBoot.isConfigured else { return }
        async let a: Void = loadUsername(uid)
        async let b: Void = loadCounts(uid)
        async let c: Void = loadStories(uid)
        async let d: Void = loadSaved(uid)
        _ = await (a, b, c, d)
    }

    // MARK: username (users/{uid}/userData/preferences: username + profileDNA.username)

    @MainActor
    private func loadUsername(_ uid: String) async {
        guard let snap = try? await userRef(uid).collection("userData").document("preferences").getDocument(),
              self.uid == uid else { return }
        let d = snap.data() ?? [:]
        let direct = (d["username"] as? String) ?? ""
        let dna = ((d["profileDNA"] as? [String: Any])?["username"] as? String) ?? ""
        username = (direct.isEmpty ? dna : direct).trimmingCharacters(in: .whitespaces)
    }

    /// The pencil / Display name: the app's username plus the account's name (ProfileView saveName).
    @MainActor
    func saveName(_ name: String) async throws {
        guard let uid else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        try await userRef(uid).collection("userData").document("preferences")
            .setData(["username": trimmed, "profileDNA": ["username": trimmed]], merge: true)
        username = trimmed
        await AuthFlows.saveAccountName(trimmed)
    }

    /// "Remove username": back to the account's name.
    @MainActor
    func removeUsername() async throws {
        guard let uid else { return }
        try await userRef(uid).collection("userData").document("preferences")
            .setData(["username": "", "profileDNA": ["username": ""]], merge: true)
        username = ""
    }

    // MARK: followers / following (public counts)

    @MainActor
    private func loadCounts(_ uid: String) async {
        let base = userRef(uid)
        let fol = try? await base.collection("followers").count.getAggregation(source: .server)
        let ing = try? await base.collection("following").count.getAggregation(source: .server)
        guard self.uid == uid else { return }
        followers = fol.map { $0.count.intValue }
        following = ing.map { $0.count.intValue }
    }

    // MARK: Your stories (every status)

    @MainActor
    func loadStories(_ uid: String) async {
        do {
            let snap = try await db.collection("storyPosts").whereField("userId", isEqualTo: uid).limit(to: 200).getDocuments()
            guard self.uid == uid else { return }
            stories = snap.documents.map { OwnStory(id: $0.documentID, data: $0.data()) }.sorted { $0.createdAtMs > $1.createdAtMs }
            storiesFailed = false
        } catch {
            print("[KT] my stories not read: \(error.localizedDescription)")
            if self.uid == uid { storiesFailed = true }
        }
        if self.uid == uid { storiesLoaded = true }
    }

    // MARK: Saved (users/{uid}/savedPosts)

    @MainActor
    private func loadSaved(_ uid: String) async {
        do {
            let snap = try await userRef(uid).collection("savedPosts").limit(to: 500).getDocuments()
            guard self.uid == uid else { return }
            saved = snap.documents.map { doc -> SavedPostItem in
                let d = doc.data()
                return SavedPostItem(id: (d["postId"] as? String) ?? doc.documentID,
                                 title: (d["title"] as? String) ?? "",
                                 isGuide: (d["type"] as? String) == "guide",
                                 thumb: (d["thumb"] as? String) ?? "",
                                 savedAtMs: Self.millis(d["savedAt"]) ?? 0)
            }.sorted { $0.savedAtMs > $1.savedAtMs }
        } catch {
            print("[KT] saved not read: \(error.localizedDescription)")
        }
        if self.uid == uid { savedLoaded = true }
    }

    @MainActor
    func unsave(_ item: SavedPostItem) async -> Bool {
        guard let uid else { return false }
        let before = saved
        saved.removeAll { $0.id == item.id }
        do {
            try await userRef(uid).collection("savedPosts").document(item.id).delete()
            return true
        } catch {
            saved = before
            return false
        }
    }

    // MARK: Notifications (bell)

    private func watchNotifications(_ uid: String) {
        let q = userRef(uid).collection("notifications").order(by: "createdAt", descending: true).limit(to: 100)
        listener = q.addSnapshotListener { [weak self] snap, error in
            let docs = snap?.documents ?? []
            let list: [BellNote] = docs.map { doc in
                let x = doc.data()
                let kind = (x["kind"] as? String) ?? ""
                return BellNote(
                    id: doc.documentID,
                    kind: ["follow", "like", "review", "report"].contains(kind) ? kind : "comment",
                    actorUid: (x["actorUid"] as? String) ?? "",
                    actorName: ((x["actorName"] as? String) ?? "").isEmpty ? "Traveler" : ((x["actorName"] as? String) ?? ""),
                    actorPhoto: (x["actorPhoto"] as? String) ?? "",
                    postId: (x["postId"] as? String) ?? "",
                    postTitle: ((x["postTitle"] as? String) ?? "").isEmpty ? "your post" : ((x["postTitle"] as? String) ?? ""),
                    postThumb: (x["postThumb"] as? String) ?? "",
                    text: (x["text"] as? String) ?? "",
                    createdAtMs: Self.millis(x["createdAt"]) ?? Date().timeIntervalSince1970 * 1000,
                    read: (x["read"] as? Bool) == true,
                    placeName: (x["placeName"] as? String) ?? "",
                    rating: (x["rating"] as? NSNumber)?.intValue,
                    ids: [doc.documentID],
                    others: 0)
            }
            let ok = error == nil
            if let error { print("[KT] notifications read failed: \(error.localizedDescription)") }
            Task { @MainActor [weak self] in
                guard let self, self.uid == uid else { return }
                self.rawNotifs = ok ? list : (self.rawNotifs ?? [])
                self.notifsOK = ok
            }
        }
    }

    /// Opening a row marks every note in it read; "Mark all read" marks all shown (markNotificationsRead).
    @MainActor
    func markRead(_ ids: [String]) async {
        guard let uid, !ids.isEmpty else { return }
        if var raw = rawNotifs {
            for i in raw.indices where ids.contains(raw[i].id) { raw[i].read = true }
            rawNotifs = raw
        }
        let batch = db.batch()
        for id in ids.prefix(400) {
            batch.updateData(["read": true], forDocument: userRef(uid).collection("notifications").document(id))
        }
        do { try await batch.commit() } catch { print("[KT] mark read failed: \(error.localizedDescription)") }
    }

    @MainActor
    func markAllRead() async {
        let ids = (shownNotifs ?? []).filter { !$0.read }.flatMap { $0.ids }
        await markRead(ids)
    }

    @MainActor
    func deleteNotification(_ n: BellNote) async {
        guard let uid else { return }
        rawNotifs?.removeAll { n.ids.contains($0.id) }
        for id in n.ids {
            try? await userRef(uid).collection("notifications").document(id).delete()
        }
    }

    // MARK: Notification switches (users/{uid}/userData/notifPrefs)

    @MainActor
    private func loadBellSwitches(_ uid: String) async {
        guard let snap = try? await userRef(uid).collection("userData").document("notifPrefs").getDocument(),
              self.uid == uid, let d = snap.data() else { return }
        notifPrefs = BellSwitches(comments: (d["comments"] as? Bool) != false, follows: (d["follows"] as? Bool) != false,
                                likes: (d["likes"] as? Bool) != false, reviews: (d["reviews"] as? Bool) != false)
    }

    @MainActor
    func setBellSwitches(_ next: BellSwitches) async {
        guard let uid else { return }
        notifPrefs = next
        try? await userRef(uid).collection("userData").document("notifPrefs").setData([
            "comments": next.comments, "follows": next.follows, "likes": next.likes, "reviews": next.reviews,
            "updatedAt": Date().timeIntervalSince1970 * 1000,
        ], merge: true)
    }

    // MARK: Kosher preferences

    @MainActor
    func saveKosherPrefs(needs: [String]? = nil, filtersOn: Bool? = nil) async {
        let p = SavedKosherPrefs(needs: needs.map(SavedKosherPrefs.clean) ?? (kosherPrefs?.needs ?? []),
                            filtersOn: filtersOn ?? (kosherPrefs?.filtersOn ?? true),
                            updatedAt: (Date().timeIntervalSince1970 * 1000).rounded())
        kosherPrefs = p
        if let data = try? JSONEncoder().encode(p) { UserDefaults.standard.set(data, forKey: Self.kosherKey) }
        if let uid { await pushKosher(uid, p) }
    }

    private func pushKosher(_ uid: String, _ p: SavedKosherPrefs) async {
        try? await userRef(uid).collection("userData").document("kosherPrefs")
            .setData(["needs": p.needs, "filtersOn": p.filtersOn, "updatedAt": p.updatedAt], merge: true)
    }

    /// The newer copy wins (syncForUser in kosherPrefs.ts).
    @MainActor
    private func syncKosherPrefs(_ uid: String) async {
        guard let snap = try? await userRef(uid).collection("userData").document("kosherPrefs").getDocument() else { return }
        let local = kosherPrefs
        if let d = snap.data() {
            let remoteAt = Self.millis(d["updatedAt"]) ?? 0
            if local == nil || remoteAt > (local?.updatedAt ?? 0) {
                let p = SavedKosherPrefs(needs: SavedKosherPrefs.clean((d["needs"] as? [String]) ?? []),
                                    filtersOn: (d["filtersOn"] as? Bool) != false,
                                    updatedAt: remoteAt > 0 ? remoteAt : Date().timeIntervalSince1970 * 1000)
                kosherPrefs = p
                if let data = try? JSONEncoder().encode(p) { UserDefaults.standard.set(data, forKey: Self.kosherKey) }
                return
            }
        }
        if let local, local.updatedAt > 0 { await pushKosher(uid, local) }
    }

    // MARK: Profile photo (profilePhoto.ts)

    /// Square 512 px JPEG → storyMedia/{uid}/profile/avatar-<time>.jpg → sign-in, users/{uid}, profiles/{uid}.
    @MainActor
    func setProfilePhoto(_ data: Data) async throws -> String {
        guard let user = Auth.auth().currentUser else { throw AuthFlowError(message: "Sign in to add a profile photo.") }
        guard let image = UIImage(data: data), let jpeg = Self.squareJpeg(image) else {
            throw AuthFlowError(message: "That photo couldn't be opened. Try a different one.")
        }
        let stamp = String(Int64(Date().timeIntervalSince1970 * 1000), radix: 36)
        let ref = Storage.storage().reference(withPath: "storyMedia/\(user.uid)/profile/avatar-\(stamp).jpg")
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"
        meta.cacheControl = "public,max-age=31536000"
        do {
            _ = try await ref.putDataAsync(jpeg, metadata: meta)
            let url = try await ref.downloadURL().absoluteString
            try await savePhotoEverywhere(url)
            return url
        } catch let e as AuthFlowError {
            throw e
        } catch {
            print("[KT] photo upload failed: \(error)")
            throw AuthFlowError(message: "Something went wrong saving your photo. Check your connection and try again.")
        }
    }

    @MainActor
    func removeProfilePhoto() async throws { try await savePhotoEverywhere("") }

    @MainActor
    private func savePhotoEverywhere(_ url: String) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthFlowError(message: "Sign in to add a profile photo.") }
        let change = user.createProfileChangeRequest()
        change.photoURL = url.isEmpty ? nil : URL(string: url)
        try await change.commitChanges()
        try? await userRef(user.uid).setData(["photoURL": url], merge: true)
        try? await db.collection("profiles").document(user.uid).setData(["photoURL": url, "updatedAt": FieldValue.serverTimestamp()])
    }

    static func squareJpeg(_ image: UIImage, size: CGFloat = 512) -> Data? {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let side = min(w, h)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)
        let out = renderer.image { _ in
            let scale = size / side
            let drawW = w * scale, drawH = h * scale
            image.draw(in: CGRect(x: (size - drawW) / 2, y: (size - drawH) / 2, width: drawW, height: drawH))
        }
        return out.jpegData(compressionQuality: 0.85)
    }

    // MARK: Delete account (deleteAccountData in accountService.ts; call AuthFlows.reauth first)

    @MainActor
    func deleteAccount(onStep: @escaping (String) -> Void) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthFlowError(message: "Please sign in again.") }
        let uid = user.uid

        onStep("Deleting your posts")
        let mineSnap = try await db.collection("storyPosts").whereField("userId", isEqualTo: uid).limit(to: 200)
            .getDocuments(source: .server)
        let mine = mineSnap.documents.map { OwnStory(id: $0.documentID, data: $0.data()) }
        for (i, post) in mine.enumerated() {
            onStep("Deleting your posts (\(i + 1) of \(mine.count))")
            try await deletePost(post)
        }

        onStep("Removing your comments and likes")
        if let live = try? await db.collection("storyPosts").whereField("status", isEqualTo: "live").limit(to: 300).getDocuments() {
            let others = live.documents.filter { ($0.data()["userId"] as? String) != uid }
            var start = 0
            while start < others.count {
                let chunk = Array(others[start..<min(start + 8, others.count)])
                start += 8
                await withTaskGroup(of: Void.self) { group in
                    for doc in chunk {
                        group.addTask { await Self.removeTraces(of: uid, on: doc) }
                    }
                }
            }
        }

        onStep("Deleting your trips and saved data")
        for sub in ["trips", "chatConversations", "userData"] {
            if let snap = try? await userRef(uid).collection(sub).limit(to: 500).getDocuments() {
                for d in snap.documents { try? await d.reference.delete() }
            }
        }
        for id in ["kosherPrefs", "preferences", "authoredArticles", "writtenReviews"] {
            try? await userRef(uid).collection("userData").document(id).delete()
        }
        try await userRef(uid).delete()

        onStep("Deleting your account")
        try await user.delete()
        UserDefaults.standard.removeObject(forKey: Self.kosherKey)
    }

    /// deleteStory(): inline photo docs media/0..n, the post, then its Storage files (best effort).
    @MainActor
    private func deletePost(_ post: OwnStory) async throws {
        let ref = db.collection("storyPosts").document(post.id)
        let n = max(post.mediaCount, 40)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<n {
                let media = ref.collection("media").document(String(i))
                group.addTask { _ = try? await media.delete() }
            }
        }
        do {
            try await ref.delete()
        } catch {
            throw AuthFlowError(message: "A post couldn't be deleted. Check your connection and try again.")
        }
        for url in post.storageURLs {
            if let path = Self.storagePath(url) { try? await Storage.storage().reference(withPath: path).delete() }
        }
    }

    /// Their comments (and likes / "helped me") on someone else's live post.
    private static func removeTraces(of uid: String, on doc: QueryDocumentSnapshot) async {
        if let comments = try? await doc.reference.collection("comments").whereField("userId", isEqualTo: uid).limit(to: 100).getDocuments() {
            for c in comments.documents { try? await c.reference.delete() }
        }
        let d = doc.data()
        if ((d["likedUserIds"] as? [String]) ?? []).contains(uid) {
            await removeReaction(uid, ref: doc.reference, listKey: "likedUserIds", countKey: "likesCount")
        }
        if ((d["helpedUserIds"] as? [String]) ?? []).contains(uid) {
            await removeReaction(uid, ref: doc.reference, listKey: "helpedUserIds", countKey: "helpedCount")
        }
    }

    /// setReaction(…, false): one transaction, exactly -1 with their id removed (what the rules accept).
    private static func removeReaction(_ uid: String, ref: DocumentReference, listKey: String, countKey: String) async {
        _ = try? await Firestore.firestore().runTransaction { (tx: FirebaseFirestore.Transaction, errorPointer: NSErrorPointer) -> Any? in
            let snap: DocumentSnapshot
            do {
                snap = try tx.getDocument(ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            guard let d = snap.data() else { return nil }
            var list = (d[listKey] as? [String]) ?? []
            guard list.contains(uid) else { return nil }
            let count = (d[countKey] as? NSNumber)?.intValue ?? list.count
            list.removeAll { $0 == uid }
            tx.updateData([listKey: list, countKey: count - 1], forDocument: ref)
            return nil
        }
    }

    /// "https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?alt=media…" → "<path>"
    static func storagePath(_ url: String) -> String? {
        guard let range = url.range(of: "/o/") else { return nil }
        var rest = String(url[range.upperBound...])
        if let q = rest.firstIndex(of: "?") { rest = String(rest[..<q]) }
        return rest.removingPercentEncoding
    }

    static func millis(_ v: Any?) -> Double? {
        if let ts = v as? Timestamp { return ts.dateValue().timeIntervalSince1970 * 1000 }
        if let d = v as? Date { return d.timeIntervalSince1970 * 1000 }
        if let n = v as? NSNumber { return n.doubleValue }
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }
}
