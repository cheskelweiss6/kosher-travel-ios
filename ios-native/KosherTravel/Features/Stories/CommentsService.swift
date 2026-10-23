import Foundation
import FirebaseFirestore

/// A comment on a post: storyPosts/{postId}/comments/{commentId}
/// { userId, authorName, authorPhoto, text, createdAt, replyTo?, editedAt? } (web commentsService.ts).
struct StoryComment: Identifiable, Hashable {
    var id: String
    var userId: String
    var authorName: String
    var authorPhoto: String
    var text: String
    var createdAtMs: Double
    var replyTo: String
    var editedAtMs: Double?
}

enum CommentsService {
    static let maxLength = 500
    static let adminUid = "oKMrTvuUxWPCH10hCHB1uZwHpYm1"
    private static var db: Firestore { Firestore.firestore() }
    private static func col(_ postId: String) -> CollectionReference {
        db.collection("storyPosts").document(postId).collection("comments")
    }
    private static func ms(_ v: Any?) -> Double? {
        if let t = v as? Timestamp { return t.dateValue().timeIntervalSince1970 * 1000 }
        if let d = v as? Date { return d.timeIntervalSince1970 * 1000 }
        return nil
    }

    /// Oldest first, up to 200 (same query as the web). nil = could not be read.
    static func fetch(_ postId: String) async -> [StoryComment]? {
        guard FirebaseBoot.isConfigured else { return nil }
        do {
            let snap = try await col(postId).order(by: "createdAt").limit(to: 200).getDocuments(source: .server)
            return snap.documents.map { (d: QueryDocumentSnapshot) -> StoryComment in
                let x = d.data()
                return StoryComment(id: d.documentID,
                                    userId: (x["userId"] as? String) ?? "",
                                    authorName: ((x["authorName"] as? String) ?? "").isEmpty ? "Traveler" : ((x["authorName"] as? String) ?? ""),
                                    authorPhoto: (x["authorPhoto"] as? String) ?? "",
                                    text: (x["text"] as? String) ?? "",
                                    createdAtMs: ms(x["createdAt"]) ?? Date().timeIntervalSince1970 * 1000,
                                    replyTo: (x["replyTo"] as? String) ?? "",
                                    editedAtMs: ms(x["editedAt"]))
            }
        } catch {
            print("[KT] comments read failed: \(error)")
            return nil
        }
    }

    static func count(_ postId: String) async -> Int? {
        guard FirebaseBoot.isConfigured else { return nil }
        do { return try await col(postId).count.getAggregation(source: .server).count.intValue } catch { return nil }
    }

    static func add(postId: String, actor: StoryActor, text: String, replyTo: String?) async -> StoryComment? {
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        guard FirebaseBoot.isConfigured, !t.isEmpty else { return nil }
        var base: [String: Any] = ["userId": actor.uid, "authorName": String(actor.name.prefix(80)),
                                   "authorPhoto": actor.photo, "text": t]
        let reply = String((replyTo ?? "").prefix(80))
        if !reply.isEmpty { base["replyTo"] = reply }
        var data = base
        data["createdAt"] = FieldValue.serverTimestamp()
        let ref = col(postId).document()
        do {
            try await ref.setData(data)
            return StoryComment(id: ref.documentID, userId: actor.uid, authorName: String(actor.name.prefix(80)),
                                authorPhoto: actor.photo, text: t, createdAtMs: Date().timeIntervalSince1970 * 1000,
                                replyTo: reply, editedAtMs: nil)
        } catch {
            print("[KT] comment not posted: \(error)")
            return nil
        }
    }

    /// Only text and editedAt change (the rules refuse anything else).
    static func edit(postId: String, commentId: String, text: String) async -> String? {
        let t = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        guard FirebaseBoot.isConfigured, !t.isEmpty else { return nil }
        do {
            try await col(postId).document(commentId).updateData(["text": t, "editedAt": FieldValue.serverTimestamp()])
            return t
        } catch {
            print("[KT] comment edit failed: \(error)")
            return nil
        }
    }

    static func delete(postId: String, commentId: String) async -> Bool {
        guard FirebaseBoot.isConfigured else { return false }
        do { try await col(postId).document(commentId).delete(); return true } catch { return false }
    }

    enum ReportResult { case reported, already, failed }

    /// One report per person per comment, plus a note in the admin's bell, in the same write.
    static func report(post: StoryPost, thumb: String, comment c: StoryComment, me: StoryActor,
                       reason: String = "Inappropriate comment") async -> ReportResult {
        guard FirebaseBoot.isConfigured else { return .failed }
        let rid = "\(post.id)_\(c.id)_\(me.uid)"
        let rref = db.collection("commentReports").document(rid)
        let b = db.batch()
        b.setData(["postId": post.id, "commentId": c.id, "commentUserId": c.userId, "text": String(c.text.prefix(500)),
                   "reason": String(reason.prefix(200)), "userId": me.uid, "createdAt": FieldValue.serverTimestamp()],
                  forDocument: rref)
        if me.uid != adminUid {
            let title = post.title.isEmpty ? (post.cityName.isEmpty ? "a post" : post.cityName) : post.title
            b.setData(["kind": "report", "actorUid": me.uid, "actorName": String(me.name.prefix(80)),
                       "actorPhoto": String(me.photo.prefix(2000)), "postId": post.id, "postTitle": String(title.prefix(120)),
                       "postThumb": thumb.count <= 150_000 ? thumb : "", "commentId": c.id, "text": String(c.text.prefix(140)),
                       "createdAt": FieldValue.serverTimestamp(), "read": false],
                      forDocument: db.collection("users").document(adminUid).collection("notifications").document("cr_\(c.id)_\(me.uid)"))
        }
        do {
            try await b.commit()
            return .reported
        } catch {
            if let mine = try? await rref.getDocument(), mine.exists { return .already }
            print("[KT] comment report failed: \(error)")
            return .failed
        }
    }

    // MARK: the poster's bell (users/{owner}/notifications/c_<commentId>)

    static func notify(post: StoryPost, ownerUid: String, thumb: String, actor: StoryActor, comment c: StoryComment) async {
        guard FirebaseBoot.isConfigured, !ownerUid.isEmpty, ownerUid != actor.uid else { return }
        let title = post.title.isEmpty ? (post.cityName.isEmpty ? "your post" : post.cityName) : post.title
        try? await db.collection("users").document(ownerUid).collection("notifications").document("c_" + c.id).setData([
            "kind": "comment", "actorUid": actor.uid, "actorName": String(actor.name.prefix(80)),
            "actorPhoto": String(actor.photo.prefix(2000)), "postId": post.id, "postTitle": String(title.prefix(120)),
            "postThumb": thumb.count <= 150_000 ? thumb : "", "commentId": c.id, "text": String(c.text.prefix(140)),
            "createdAt": FieldValue.serverTimestamp(), "read": false,
        ])
    }

    static func retract(ownerUid: String, commentId: String) async {
        guard FirebaseBoot.isConfigured, !ownerUid.isEmpty else { return }
        try? await db.collection("users").document(ownerUid).collection("notifications").document("c_" + commentId).delete()
    }
}
