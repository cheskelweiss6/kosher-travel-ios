import Foundation
import Observation
import FirebaseAuth
import FirebaseFirestore

/// The signed-in person (Firebase Auth). Read API for every screen: uid, isSignedIn, isAdmin, displayName, email,
/// photoURL, signOut(), ready. The sign-in flows themselves live in Features/Profile (AuthFlows).
@Observable
final class AuthStore {
    static let adminUid = "oKMrTvuUxWPCH10hCHB1uZwHpYm1"
    /// The web app and the Firestore rules treat this verified email as the admin (AuthContext.tsx ADMIN_EMAIL).
    static let adminEmail = "cheskelweiss6@gmail.com"

    private(set) var uid: String?
    private(set) var displayName = ""
    private(set) var email = ""
    private(set) var photoURL = ""
    private(set) var ready = false
    private(set) var emailVerified = false
    /// "password", "google.com", "apple.com" … for the current sign-in.
    private(set) var providerIds: [String] = []

    var isSignedIn: Bool { uid != nil }
    var isAdmin: Bool {
        guard let uid else { return false }
        if uid == Self.adminUid { return true }
        return email.lowercased() == Self.adminEmail && emailVerified
    }
    /// How this person signs in (same order as the web's signInKind()).
    var signInKind: String {
        if providerIds.contains("password") { return "password" }
        if providerIds.contains("google.com") { return "google" }
        if providerIds.contains("apple.com") { return "apple" }
        return "other"
    }

    @ObservationIgnored private var handle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var docChecked: Set<String> = []

    init() {
        guard FirebaseBoot.isConfigured else { ready = true; return }
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.apply(user)
        }
    }

    deinit {
        if let handle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    func apply(_ user: User?) {
        uid = user?.uid
        let fallback = user?.email?.split(separator: "@").first.map(String.init) ?? ""
        displayName = (user?.displayName?.isEmpty == false ? user?.displayName : nil) ?? (user == nil ? "" : fallback)
        email = user?.email ?? ""
        photoURL = user?.photoURL?.absoluteString ?? ""
        emailVerified = user?.isEmailVerified ?? false
        providerIds = user?.providerData.map { $0.providerID } ?? []
        ready = true
        if let user { ensureUserDoc(user) }
    }

    /// Re-read the sign-in after a name / photo change so every screen shows it.
    @MainActor
    func refresh() async {
        guard FirebaseBoot.isConfigured, let user = Auth.auth().currentUser else { return }
        try? await user.reload()
        apply(Auth.auth().currentUser)
    }

    /// Shown at once after a change (the sign-in profile catches up on the next refresh).
    func setLocal(displayName: String? = nil, photoURL: String? = nil) {
        if let displayName { self.displayName = displayName }
        if let photoURL { self.photoURL = photoURL }
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    /// Same as the web's AuthContext: users/{uid} is created on the first sign-in with Google (or another provider);
    /// when it exists, its displayName wins.
    private func ensureUserDoc(_ user: User) {
        guard !docChecked.contains(user.uid) else { return }
        docChecked.insert(user.uid)
        let ref = Firestore.firestore().collection("users").document(user.uid)
        Task { @MainActor [weak self] in
            do {
                let snap = try await ref.getDocument()
                if snap.exists {
                    if let name = snap.data()?["displayName"] as? String, !name.isEmpty, self?.uid == user.uid {
                        self?.displayName = name
                    }
                    return
                }
                let display = user.displayName ?? ""
                let parts = display.split(separator: " ").map(String.init)
                let fallback = user.email?.split(separator: "@").first.map(String.init) ?? "Traveler"
                try await ref.setData([
                    "uid": user.uid,
                    "email": user.email ?? "",
                    "displayName": display.isEmpty ? fallback : display,
                    "firstName": parts.first ?? "",
                    "lastName": parts.dropFirst().joined(separator: " "),
                    "photoURL": user.photoURL?.absoluteString ?? "",
                    "role": "user",
                    "createdAt": FieldValue.serverTimestamp(),
                    "lastLoginAt": FieldValue.serverTimestamp(),
                ], merge: true)
            } catch {
                self?.docChecked.remove(user.uid)
                print("[KT] profile doc not read: \(error.localizedDescription)")
            }
        }
    }
}
