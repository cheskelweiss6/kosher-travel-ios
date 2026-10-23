import Foundation
import SwiftUI
import UIKit
import AuthenticationServices
import CryptoKit
import Security
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

/// Sign in with Apple is written but switched off: the App ID does not have the "Sign in with Apple" capability yet
/// (and the provisioning profile has no entitlement for it). Turn this on once both are in place.
enum AppleSignIn {
    static let isEnabled = false
}

struct AuthFlowError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The web app's sign-in flows (AuthContext.tsx, AuthModal.tsx, account/accountService.ts) for iOS.
enum AuthFlows {
    static var isAvailable: Bool { FirebaseBoot.isConfigured }

    private static func requireFirebase() throws {
        guard FirebaseBoot.isConfigured else {
            throw AuthFlowError(message: "Sign-in isn't available in this build. Please update the app.")
        }
    }

    // MARK: Google

    @MainActor
    static func signInWithGoogle() async throws {
        try requireFirebase()
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw AuthFlowError(message: "Google sign-in isn't set up for this app yet.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        guard let presenter = topViewController() else {
            throw AuthFlowError(message: "Couldn't open Google sign-in. Try again.")
        }
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch {
            if isGoogleCancel(error) { throw CancellationError() }
            throw error
        }
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthFlowError(message: "Google didn't return a sign-in. Try again.")
        }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                       accessToken: result.user.accessToken.tokenString)
        _ = try await Auth.auth().signIn(with: credential)
    }

    static func isGoogleCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain.contains("GIDSignIn") && ns.code == -5
    }

    @MainActor
    static func googleCredentialForReauth() async throws -> AuthCredential {
        guard let clientID = FirebaseApp.app()?.options.clientID, let presenter = topViewController() else {
            throw AuthFlowError(message: "Couldn't open Google sign-in. Try again.")
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch {
            if isGoogleCancel(error) { throw CancellationError() }
            throw error
        }
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthFlowError(message: "Google didn't return a sign-in. Try again.")
        }
        return GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let window = scene?.windows.first(where: { $0.isKeyWindow }) ?? scene?.windows.first
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    // MARK: Email

    static func signIn(email: String, password: String) async throws {
        try requireFirebase()
        _ = try await Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespaces), password: password)
    }

    /// Same as the web's signUpWithEmail: the account, its name, and users/{uid}.
    static func signUp(firstName: String, lastName: String, email: String, password: String) async throws -> String {
        try requireFirebase()
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        let mail = email.trimmingCharacters(in: .whitespaces)
        let display = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        let result = try await Auth.auth().createUser(withEmail: mail, password: password)
        let user = result.user
        if !display.isEmpty {
            let change = user.createProfileChangeRequest()
            change.displayName = display
            try? await change.commitChanges()
        }
        let shown = display.isEmpty ? (mail.split(separator: "@").first.map(String.init) ?? "Traveler") : display
        try? await Firestore.firestore().collection("users").document(user.uid).setData([
            "uid": user.uid,
            "firstName": first,
            "lastName": last,
            "displayName": shown,
            "email": mail,
            "createdAt": FieldValue.serverTimestamp(),
            "lastLoginAt": FieldValue.serverTimestamp(),
        ])
        return shown
    }

    static func sendPasswordReset(email: String) async throws {
        try requireFirebase()
        try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespaces))
    }

    // MARK: Account changes (accountService.ts)

    /// Confirm it's really them (Firebase asks before password, email and delete changes).
    @MainActor
    static func reauth(password: String?) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthFlowError(message: "Please sign in again.") }
        let ids = user.providerData.map { $0.providerID }
        let credential: AuthCredential
        if ids.contains("password") {
            guard let password, !password.isEmpty else { throw AuthFlowError(message: "Enter your password.") }
            credential = EmailAuthProvider.credential(withEmail: user.email ?? "", password: password)
        } else if ids.contains("google.com") {
            credential = try await googleCredentialForReauth()
        } else if ids.contains("apple.com") {
            credential = try await AppleSignInCoordinator.credential()
        } else {
            throw AuthFlowError(message: "Please sign out and sign in again, then retry.")
        }
        _ = try await user.reauthenticate(with: credential)
    }

    @MainActor
    static func changePassword(current: String, next: String) async throws {
        try await reauth(password: current)
        guard let user = Auth.auth().currentUser else { throw AuthFlowError(message: "Please sign in again.") }
        try await user.updatePassword(to: next)
    }

    /// Firebase emails a link to the new address; the email changes only when they tap it.
    @MainActor
    static func changeEmail(current: String, newEmail: String) async throws {
        try await reauth(password: current)
        guard let user = Auth.auth().currentUser else { throw AuthFlowError(message: "Please sign in again.") }
        try await user.sendEmailVerification(beforeUpdatingEmail: newEmail.trimmingCharacters(in: .whitespaces))
    }

    /// The name on their account (sign-in profile and users/{uid}), next to the app's own username.
    static func saveAccountName(_ name: String) async {
        guard let user = Auth.auth().currentUser else { return }
        let change = user.createProfileChangeRequest()
        change.displayName = name
        try? await change.commitChanges()
        try? await Firestore.firestore().collection("users").document(user.uid).setData(["displayName": name], merge: true)
    }

    // MARK: Plain words for Firebase's errors (friendlyError in accountService.ts)

    static func friendly(_ error: Error) -> String {
        if let e = error as? AuthFlowError { return e.message }
        let ns = error as NSError
        if ns.domain == "FIRAuthErrorDomain" {
            switch ns.code {
            case 17009, 17004: return "That password isn't right. Try again, or send yourself a reset email."
            case 17026: return "Choose a longer password: at least 6 characters."
            case 17007: return "Another account already uses that email."
            case 17008, 17034: return "That email doesn't look right."
            case 17014: return "For your safety, enter your password again and retry."
            case 17010: return "Too many tries. Wait a few minutes and try again."
            case 17020: return "No connection. Check your signal and try again."
            case 17024: return "That account is not the one you are signed in with."
            case 17011: return "No account found with this email."
            case 17006: return "This sign-in isn't available right now. Please contact us."
            case 17999:
                let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription ?? ""
                return underlying.isEmpty ? "Something went wrong. Try again." : underlying
            default: break
            }
        }
        if isGoogleCancel(error) { return "The Google window was closed before it finished." }
        let text = ns.localizedDescription
        return text.isEmpty ? "Something went wrong. Try again." : text
    }
}

// MARK: - Sign in with Apple (hidden while AppleSignIn.isEnabled is false)

/// Runs one Apple authorization and turns it into a Firebase credential (OAuthProvider "apple.com" with a nonce).
@MainActor
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<AuthCredential, Error>?
    private var rawNonce = ""
    private static var running: AppleSignInCoordinator?

    static func credential() async throws -> AuthCredential {
        let coordinator = AppleSignInCoordinator()
        running = coordinator
        defer { running = nil }
        return try await coordinator.start()
    }

    static func signIn() async throws {
        guard FirebaseBoot.isConfigured else { throw AuthFlowError(message: "Sign-in isn't available in this build.") }
        let credential = try await credential()
        _ = try await Auth.auth().signIn(with: credential)
    }

    private func start() async throws -> AuthCredential {
        rawNonce = Self.randomNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AuthCredential, Error>) in
            self.continuation = cont
            controller.performRequests()
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        let apple = authorization.credential as? ASAuthorizationAppleIDCredential
        let token = apple?.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        let fullName = apple?.fullName
        Task { @MainActor in
            guard let token else {
                self.finish(.failure(AuthFlowError(message: "Apple didn't return a sign-in. Try again.")))
                return
            }
            let credential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: self.rawNonce, fullName: fullName)
            self.finish(.success(credential))
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue {
                self.finish(.failure(CancellationError()))
            } else {
                self.finish(.failure(error))
            }
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? ASPresentationAnchor()
        }
    }

    private func finish(_ result: Result<AuthCredential, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        while result.count < length {
            var byte: UInt8 = 0
            if SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess, Int(byte) < charset.count * 4 {
                result.append(charset[Int(byte) % charset.count])
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
