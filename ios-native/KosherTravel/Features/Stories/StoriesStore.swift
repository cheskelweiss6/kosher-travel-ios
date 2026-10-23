import Foundation
import Observation
import FirebaseCore
import FirebaseFirestore

/// The Stories tab's own live data: every live post with its extra fields (author id, like list, links, products,
/// video settings), the signed-in person's following list, saved ids and current profile photos.
/// One shared instance, so the post viewer reads the same state from the Stories tab and from Explore.
@Observable
final class StoriesStore {
    static let shared = StoriesStore()

    private(set) var posts: [StoryPost] = []
    private(set) var extras: [String: StoryExtra] = [:]
    private(set) var isLoading = false
    private(set) var loadedOnce = false
    private(set) var errorMessage: String?

    // signed-in person
    private(set) var meUid: String?
    private(set) var following: Set<String> = []
    private(set) var followingLoaded = false
    private(set) var saved: Set<String> = []
    private(set) var username = ""

    /// profiles/{uid}.photoURL (the traveler's current photo; "" = removed it). Missing key = not read yet / no doc.
    private(set) var livePhotos: [String: String] = [:]
    @ObservationIgnored private var photoRequested: Set<String> = []
    /// profiles/{uid}.username (Oct 23 2026, Cheskel: "apply new user names the old posts"): the traveler's current
    /// username, so old posts, comments and reviews show it. Missing key or "" = the name stored with the post.
    private(set) var liveNames: [String: String] = [:]

    static let hideAtReports = 3

    var articles: [StoryPost] { posts.filter { isArticle($0) } }
    var inspiration: [StoryPost] { posts.filter { !isArticle($0) } }

    func isArticle(_ p: StoryPost) -> Bool { p.isGuide || !p.stops.isEmpty }
    func extra(_ id: String) -> StoryExtra? { extras[id] }
    func post(_ id: String) -> StoryPost? { posts.first { $0.id == id } }
    func posts(by uid: String) -> [StoryPost] { posts.filter { extras[$0.id]?.userId == uid } }

    /// The photo to show for a traveler: their current profile photo when they set one in the app, else the stored one.
    func photo(uid: String, stored: String) -> String {
        if !uid.isEmpty, let live = livePhotos[uid] { return live }
        return stored
    }

    /// The name to show for a traveler: their current username when they set one, else the stored name.
    /// Reads profiles/{uid} once per traveler (shared with the live photo).
    func name(uid: String, stored: String) -> String {
        guard !uid.isEmpty else { return stored }
        if let live = liveNames[uid], !live.isEmpty { return live }
        if Thread.isMainThread { requestPhoto(uid) }
        return stored
    }

    /// The person's own new username ("" = removed) shows at once everywhere on this phone.
    func setLiveName(_ uid: String, _ name: String) {
        guard !uid.isEmpty else { return }
        liveNames[uid] = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: feed

    @MainActor
    func loadIfNeeded() async {
        if !loadedOnce && !isLoading { await refresh() }
    }

    @MainActor
    func refresh() async {
        isLoading = true
        defer { isLoading = false; loadedOnce = true }
        do {
            let raws = try await StoryDocs.live()
            var ex: [String: StoryExtra] = [:]
            var list: [StoryPost] = []
            for r in raws {
                guard let p = StoryPost(id: r.id, data: r.data) else { continue }
                guard p.status == "live", p.reportCount < Self.hideAtReports else { continue }
                list.append(p)
                ex[r.id] = StoryExtra(id: r.id, data: r.data)
            }
            posts = list.sorted { $0.createdAtMs > $1.createdAtMs }
            for (k, v) in ex { extras[k] = v }
            errorMessage = nil
            print("[KT] stories feed docs=\(posts.count)")
            for e in ex.values where !e.userId.isEmpty { requestPhoto(e.userId) }
        } catch {
            print("[KT] stories feed failed: \(error)")
            if posts.isEmpty { errorMessage = "Traveler posts could not load. Pull down to try again." }
        }
    }

    /// Makes sure one post (and its extra fields) is here, e.g. when it is opened from Explore or a link.
    @MainActor
    func ensure(_ id: String) async {
        if extras[id] != nil && post(id) != nil { return }
        guard let r = await StoryDocs.one(id) else { return }
        let ex = StoryExtra(id: id, data: r.data)
        extras[id] = ex
        if post(id) == nil, let p = StoryPost(id: id, data: r.data), p.status == "live" {
            posts.append(p)
            posts.sort { $0.createdAtMs > $1.createdAtMs }
        }
        if !ex.userId.isEmpty { requestPhoto(ex.userId) }
    }

    /// A post its poster (or the admin) deleted: off every list at once.
    @MainActor
    func remove(_ id: String) {
        posts.removeAll { $0.id == id }
        extras[id] = nil
    }

    /// Reads one post again after it was edited, so the new words, photos and links show at once.
    @MainActor
    func reload(_ id: String) async {
        guard let r = await StoryDocs.one(id) else { return }
        extras[id] = StoryExtra(id: id, data: r.data)
        if let p = StoryPost(id: id, data: r.data) {
            if let i = posts.firstIndex(where: { $0.id == id }) { posts[i] = p } else if p.status == "live" {
                posts.append(p)
                posts.sort { $0.createdAtMs > $1.createdAtMs }
            }
        }
    }

    /// A traveler's live posts (their page), merged into the store.
    @MainActor
    func loadAuthor(_ uid: String) async -> Bool {
        do {
            let raws = try await StoryDocs.byAuthor(uid)
            for r in raws {
                guard let p = StoryPost(id: r.id, data: r.data), p.status == "live", p.reportCount < Self.hideAtReports else { continue }
                extras[r.id] = StoryExtra(id: r.id, data: r.data)
                if let i = posts.firstIndex(where: { $0.id == r.id }) { posts[i] = p } else { posts.append(p) }
            }
            posts.sort { $0.createdAtMs > $1.createdAtMs }
            return true
        } catch {
            print("[KT] author posts failed: \(error)")
            return false
        }
    }

    // MARK: local updates after a write

    @MainActor
    func applyLike(postId: String, uid: String, on: Bool, count: Int) {
        guard var e = extras[postId] else { return }
        if on { if !e.likedUserIds.contains(uid) { e.likedUserIds.append(uid) } }
        else { e.likedUserIds.removeAll { $0 == uid } }
        e.likesCount = max(0, count)
        extras[postId] = e
    }

    @MainActor
    func applyView(postId: String) {
        guard var e = extras[postId] else { return }
        e.viewsCount += 1
        extras[postId] = e
    }

    @MainActor
    func setSaved(_ id: String, _ on: Bool) {
        if on { saved.insert(id) } else { saved.remove(id) }
    }

    @MainActor
    func setFollowing(_ uid: String, _ on: Bool) {
        if on { following.insert(uid) } else { following.remove(uid) }
    }

    // MARK: signed-in person

    /// Reads the person's following list, saved posts and username once per sign-in (cleared on sign-out).
    @MainActor
    func syncAccount(uid: String?) async {
        guard uid != meUid else {
            if uid == nil { followingLoaded = true }
            return
        }
        meUid = uid
        following = []
        saved = []
        username = ""
        followingLoaded = uid == nil
        guard let uid, FirebaseBoot.isConfigured else { followingLoaded = true; return }
        let db = Firestore.firestore()
        async let f = try? db.collection("users").document(uid).collection("following").getDocuments()
        async let s = try? db.collection("users").document(uid).collection("savedPosts").getDocuments()
        async let pref = try? db.collection("users").document(uid).collection("userData").document("preferences").getDocument()
        let (fs, ss, ps) = await (f, s, pref)
        guard meUid == uid else { return }
        following = Set(fs?.documents.map(\.documentID) ?? [])
        saved = Set(ss?.documents.map(\.documentID) ?? [])
        username = ((ps?.data()?["username"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        followingLoaded = true
    }

    // MARK: live profile photos and usernames (profiles/{uid}, public read)

    func requestPhoto(_ uid: String) {
        guard !uid.isEmpty, FirebaseBoot.isConfigured, !photoRequested.contains(uid) else { return }
        photoRequested.insert(uid)
        Task { @MainActor in
            guard let snap = try? await Firestore.firestore().collection("profiles").document(uid).getDocument(),
                  snap.exists, let d = snap.data() else { return }
            if let v = d["photoURL"] as? String { self.livePhotos[uid] = v }
            if let n = d["username"] as? String, self.liveNames[uid] == nil {
                self.liveNames[uid] = n.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
