import Foundation
import FirebaseFirestore
import FirebaseAuth

/// Username on old posts (Oct 23 2026, Cheskel: "Pls apply new user names the old posts from user as well").
/// When someone sets, changes or removes their username, their name changes everywhere they posted. Same steps as the
/// website's src/components/account/usernameSync.ts:
///  1. profiles/{uid}.username (public): every screen reads it live (StoriesStore.name), on the website and in the app,
///     so old posts, comments and reviews show the new name at once;
///  2. the name saved on their own posts (storyPosts.authorName) and reviews (placeReviews.userName) is updated too, so
///     search, shares and older app versions show it as well. The rules let the owner change only that one field.
/// Comments keep their saved name and show the live one (one person's comments can't be listed from the phone).
enum AuthorNameSync {
    /// `username` is the new username ("" = removed). Without one, posts carry the account's name.
    @MainActor
    static func apply(uid: String, username: String) {
        guard !uid.isEmpty else { return }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = (Auth.auth().currentUser?.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = String((name.isEmpty ? (account.isEmpty ? "Traveler" : account) : name).prefix(80))
        StoriesStore.shared.setLiveName(uid, name)
        guard FirebaseBoot.isConfigured else { return }
        Task.detached(priority: .utility) {
            let db = Firestore.firestore()
            do {
                try await db.collection("profiles").document(uid)
                    .setData(["username": name, "updatedAt": FieldValue.serverTimestamp()], merge: true)
            } catch { print("[KT] username profiles doc: \(error.localizedDescription)") }
            if let snap = try? await db.collection("storyPosts").whereField("userId", isEqualTo: uid)
                .limit(to: 300).getDocuments() {
                for d in snap.documents where (d.data()["authorName"] as? String) != shown {
                    do { try await d.reference.updateData(["authorName": shown]) }
                    catch { print("[KT] username post \(d.documentID): \(error.localizedDescription)") }
                }
            }
            if let snap = try? await db.collection("placeReviews").whereField("userId", isEqualTo: uid)
                .limit(to: 300).getDocuments() {
                for d in snap.documents where (d.data()["userName"] as? String) != shown {
                    do { try await d.reference.updateData(["userName": shown, "updatedAt": FieldValue.serverTimestamp()]) }
                    catch { print("[KT] username review \(d.documentID): \(error.localizedDescription)") }
                }
            }
        }
    }
}
