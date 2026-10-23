import Foundation
import FirebaseFirestore

/// The signed-in person as the web writes them on likes, comments, follows and notes (web authorOf()).
struct StoryActor {
    var uid: String
    var name: String
    var photo: String

    @MainActor
    static func from(_ auth: AuthStore) -> StoryActor? {
        guard let uid = auth.uid else { return nil }
        let username = StoriesStore.shared.username
        let emailName = auth.email.split(separator: "@").first.map(String.init) ?? ""
        let name = [username, auth.displayName, emailName].first { !$0.isEmpty } ?? "Traveler"
        return StoryActor(uid: uid, name: name, photo: auth.photoURL)
    }
}

/// Every social write of the Stories tab. Same documents, ids and fields as the web app
/// (storyService.ts setReaction / recordView / reportStory, savedPosts.ts, followService.ts, notificationsService.ts),
/// which is what the live security rules accept.
enum StoryActions {
    static let posts = "storyPosts"
    private static var db: Firestore { Firestore.firestore() }
    private static func clip(_ s: String, _ n: Int) -> String { String(s.prefix(n)) }
    private static func postTitle(_ p: StoryPost, fallback: String) -> String {
        clip(p.title.isEmpty ? (p.cityName.isEmpty ? fallback : p.cityName) : p.title, 120)
    }
    private static func thumbOf(_ e: StoryExtra?) -> String {
        let t = e?.media.first?.thumb ?? ""
        return t.count <= 150_000 ? t : ""
    }

    // MARK: like (one transaction: exactly +1 / -1 with the person's id, like the web)

    static func setLike(post: StoryPost, extra: StoryExtra?, actor: StoryActor, on: Bool) async -> (on: Bool, count: Int)? {
        guard FirebaseBoot.isConfigured else { return nil }
        let ref = db.collection(posts).document(post.id)
        let uid = actor.uid
        do {
            let raw = try await db.runTransaction { (tx, errorPointer) -> Any? in
                let snap: DocumentSnapshot
                do { snap = try tx.getDocument(ref) } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
                guard let d = snap.data() else {
                    errorPointer?.pointee = NSError(domain: "KTStories", code: 404, userInfo: [NSLocalizedDescriptionKey: "post-gone"])
                    return nil
                }
                let list = ((d["likedUserIds"] as? [Any]) ?? []).compactMap { $0 as? String }
                let count = StoryExtra.num(d["likesCount"]).map { Int($0) } ?? list.count
                let has = list.contains(uid)
                if has == on { return [on ? 1 : 0, count] }
                let next = on ? list + [uid] : list.filter { $0 != uid }
                let nextCount = count + (on ? 1 : -1)
                tx.updateData(["likedUserIds": next, "likesCount": nextCount], forDocument: ref)
                return [on ? 1 : 0, nextCount]
            }
            guard let pair = raw as? [Int], pair.count == 2 else { return nil }
            let result = (on: pair[0] == 1, count: pair[1])
            // the poster's bell (someone else's post only); never blocks the like
            if let owner = extra?.userId, !owner.isEmpty, owner != uid {
                let note = db.collection("users").document(owner).collection("notifications").document("l_\(post.id)_\(uid)")
                if result.on {
                    try? await note.setData([
                        "kind": "like", "actorUid": uid, "actorName": clip(actor.name, 80), "actorPhoto": clip(actor.photo, 2000),
                        "postId": post.id, "postTitle": postTitle(post, fallback: "your post"), "postThumb": thumbOf(extra),
                        "createdAt": FieldValue.serverTimestamp(), "read": false,
                    ])
                } else {
                    try? await note.delete()
                }
            }
            return result
        } catch {
            print("[KT] like not saved: \(error)")
            return nil
        }
    }

    // MARK: view count (+1 once per signed-in viewer per post; the views/{uid} marker can exist only once)

    static func recordView(post: StoryPost, extra: StoryExtra?, uid: String?) async -> Bool {
        guard FirebaseBoot.isConfigured, let uid, post.status == "live" else { return false }
        if let owner = extra?.userId, owner == uid { return false }
        let key = "kt_story_viewed_v1"
        var seen = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] ?? [:]
        let mark = uid + ":" + post.id
        if seen[mark] == true { return false }
        let remember = {
            seen[mark] = true
            UserDefaults.standard.set(seen, forKey: key)
        }
        let postRef = db.collection(posts).document(post.id)
        let viewRef = postRef.collection("views").document(uid)
        let b = db.batch()
        b.setData(["at": FieldValue.serverTimestamp()], forDocument: viewRef)
        b.updateData(["viewsCount": FieldValue.increment(Int64(1))], forDocument: postRef)
        do {
            try await b.commit()
            remember()
            return true
        } catch {
            // already counted from another phone: don't try again from this one
            if let snap = try? await viewRef.getDocument(), snap.exists { remember() }
            return false
        }
    }

    // MARK: save (users/{uid}/savedPosts/{postId})

    static func setSaved(post: StoryPost, extra: StoryExtra?, uid: String, on: Bool) async -> Bool {
        guard FirebaseBoot.isConfigured else { return false }
        let ref = db.collection("users").document(uid).collection("savedPosts").document(post.id)
        do {
            if on {
                var body: [String: Any] = ["postId": post.id, "savedAt": FieldValue.serverTimestamp(),
                                           "type": post.isGuide ? "guide" : "quick"]
                if !post.title.isEmpty { body["title"] = clip(post.title, 200) }
                let first = extra?.media.first
                let t = first.map { $0.thumb.isEmpty ? $0.url : $0.thumb } ?? ""
                if t.hasPrefix("https://") && t.count <= 1000 { body["thumb"] = t }
                try await ref.setData(body)
            } else {
                try await ref.delete()
            }
            return true
        } catch {
            print("[KT] save not changed: \(error)")
            return false
        }
    }

    // MARK: follow (one batch: my following, their followers, their bell note f_<me>)

    static func setFollow(actor: StoryActor, target uid: String, targetName: String, targetPhoto: String, on: Bool) async -> Bool {
        guard FirebaseBoot.isConfigured, uid != actor.uid, !uid.isEmpty else { return false }
        let mine = db.collection("users").document(actor.uid).collection("following").document(uid)
        let theirs = db.collection("users").document(uid).collection("followers").document(actor.uid)
        let note = db.collection("users").document(uid).collection("notifications").document("f_" + actor.uid)
        let b = db.batch()
        if on {
            b.setData(["createdAt": FieldValue.serverTimestamp(), "name": clip(targetName.isEmpty ? "Traveler" : targetName, 80),
                       "photo": clip(targetPhoto, 2000)], forDocument: mine)
            b.setData(["createdAt": FieldValue.serverTimestamp(), "name": clip(actor.name, 80),
                       "photo": clip(actor.photo, 2000)], forDocument: theirs)
            b.setData(["kind": "follow", "actorUid": actor.uid, "actorName": clip(actor.name, 80),
                       "actorPhoto": clip(actor.photo, 2000), "createdAt": FieldValue.serverTimestamp(), "read": false],
                      forDocument: note)
        } else {
            b.deleteDocument(mine)
            b.deleteDocument(theirs)
            b.deleteDocument(note)
        }
        do { try await b.commit(); return true } catch {
            print("[KT] follow not changed: \(error)")
            return false
        }
    }

    static func followerCount(_ uid: String) async -> Int? {
        guard FirebaseBoot.isConfigured, !uid.isEmpty else { return nil }
        do {
            let agg = try await db.collection("users").document(uid).collection("followers").count.getAggregation(source: .server)
            return agg.count.intValue
        } catch {
            print("[KT] follower count failed: \(error)")
            return nil
        }
    }

    // MARK: report a post (storyReports/{postId}_{uid} + reportCount +1 in one batch)

    enum ReportResult { case ok, already, failed }

    static func reportPost(_ postId: String, reason: String, uid: String) async -> ReportResult {
        guard FirebaseBoot.isConfigured else { return .failed }
        let rid = "\(postId)_\(uid)"
        let rref = db.collection("storyReports").document(rid)
        if let mine = try? await rref.getDocument(), mine.exists { return .already }
        let b = db.batch()
        b.setData(["storyId": postId, "reason": clip(reason, 200), "userId": uid, "createdAt": FieldValue.serverTimestamp()],
                  forDocument: rref)
        b.updateData(["reportCount": FieldValue.increment(Int64(1))], forDocument: db.collection(posts).document(postId))
        do { try await b.commit(); return .ok } catch {
            print("[KT] report not saved: \(error)")
            return .failed
        }
    }

    // MARK: share link (the web's ?story=<id>)

    static func shareURL(_ postId: String) -> URL {
        var c = URLComponents(string: "https://www.yourkoshertravel.com/")!
        c.queryItems = [URLQueryItem(name: "story", value: postId)]
        return c.url!
    }
}
