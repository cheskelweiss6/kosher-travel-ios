import SwiftUI
import FirebaseFirestore
import FirebaseStorage

/// Edit and Delete for a post's poster and the admin, the same rules as the website (StoriesTab canEdit / canDelete):
/// Edit opens the website's own post editor (the composer every post is written and edited in) on this post, inside
/// the app; Delete removes the post for everyone, the way the web's deleteStory + deleteAllComments do.
enum StoryOwnerTools {
    /// The poster, or the admin (cheskelweiss6@gmail.com).
    static func canManage(ownerUid: String, auth: AuthStore) -> Bool {
        guard let me = auth.uid else { return false }
        return (!ownerUid.isEmpty && ownerUid == me) || auth.isAdmin
    }

    /// The website's editor opened on this post (src/ktShell.ts screen "edit"; the page's own X or Save closes it).
    static func editRoute(_ postId: String, article: Bool) -> WebRoute {
        WebRoute(screen: "edit", params: ["id": postId], title: article ? "Edit article" : "Edit post")
    }

    /// Deletes the post for everyone: its inline photo docs, the post, then its comments and its uploaded files
    /// (best effort, as on the web). True when the post itself is gone.
    static func delete(postId: String, extra: StoryExtra?) async -> Bool {
        guard FirebaseBoot.isConfigured, !postId.isEmpty else { return false }
        let n = max(extra?.media.count ?? 0, 40)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<n {
                group.addTask {
                    try? await Firestore.firestore().collection(StoryActions.posts).document(postId)
                        .collection("media").document(String(i)).delete()
                }
            }
        }
        do {
            try await Firestore.firestore().collection(StoryActions.posts).document(postId).delete()
        } catch {
            print("[KT] delete post failed: \(error)")
            return false
        }
        // comments go after the post (web deleteAllComments)
        if let snap = try? await Firestore.firestore().collection(StoryActions.posts).document(postId)
            .collection("comments").limit(to: 300).getDocuments() {
            for d in snap.documents { try? await d.reference.delete() }
        }
        // uploaded photos and videos (best effort; the post is already gone)
        var urls: [String] = []
        for m in extra?.media ?? [] { urls.append(m.url); urls.append(m.thumb) }
        for p in extra?.products ?? [] { urls.append(p.img) }
        for u in urls {
            if let path = storagePath(u) { try? await Storage.storage().reference(withPath: path).delete() }
        }
        return true
    }

    /// "…/o/storyMedia%2Fuid%2Fx.jpg?alt=media" -> "storyMedia/uid/x.jpg" (only Firebase Storage download links).
    static func storagePath(_ url: String) -> String? {
        guard url.contains("firebasestorage.googleapis.com"), let r = url.range(of: "/o/") else { return nil }
        var rest = String(url[r.upperBound...])
        if let q = rest.firstIndex(of: "?") { rest = String(rest[..<q]) }
        let path = rest.removingPercentEncoding ?? rest
        return path.isEmpty ? nil : path
    }
}

/// The "..." menu items for the poster and the admin: Edit, and Delete in red (asks first).
struct StoryOwnerMenuItems: View {
    let article: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    var body: some View {
        Button(action: onEdit) {
            Label(article ? "Edit article" : "Edit post", systemImage: "pencil")
        }
        Button(role: .destructive, action: onDelete) {
            Label(article ? "Delete article" : "Delete post", systemImage: "trash")
        }
    }
}

extension View {
    /// The red "Delete this post?" confirmation, then the delete itself.
    func storyDeleteConfirm(isPresented: Binding<Bool>, article: Bool, perform: @escaping () -> Void) -> some View {
        confirmationDialog(article ? "Delete this article?" : "Delete this post?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: perform)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed for everyone. This can't be undone.")
        }
    }
}
