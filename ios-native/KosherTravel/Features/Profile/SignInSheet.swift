import SwiftUI
import AuthenticationServices

/// Sign in, create an account, or reset the password (the web's AuthModal), as a native sheet.
struct SignInSheet: View {
    enum Mode: Hashable { case signIn, signUp, reset }

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @State private var mode: Mode
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?
    @State private var success: String?
    @State private var signedIn = 0
    @FocusState private var focus: Field?

    enum Field: Hashable { case first, last, email, password, confirm }

    init(mode: Mode) {
        _mode = State(initialValue: mode)
    }

    private var title: String {
        switch mode {
        case .signIn: return "Sign in"
        case .signUp: return "Create account"
        case .reset: return "Reset password"
        }
    }
    private var subtitle: String {
        switch mode {
        case .signIn: return "Save your trips and favorite places."
        case .signUp: return "Join travelers sharing kosher spots."
        case .reset: return "We'll email you a link to reset it."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.title.weight(.bold))
                            .foregroundStyle(Color.navy)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.top, 8)

                    if mode != .reset {
                        providerButtons
                        divider
                    }
                    fields
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Color.alert)
                            .accessibilityIdentifier("auth-error")
                    }
                    if let success {
                        Label(success, systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(Color.navy)
                    }
                    primaryButton
                    footerLinks
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 32)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .disabled(busy)
            .sensoryFeedback(.success, trigger: signedIn)
            .onChange(of: mode) { _, _ in error = nil; success = nil }
            .onChange(of: auth.isSignedIn) { _, now in if now { signedIn += 1; dismiss() } }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: parts

    private var providerButtons: some View {
        VStack(spacing: 10) {
            if AppleSignIn.isEnabled {
                SignInWithAppleButton(.continue) { _ in } onCompletion: { _ in }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        // the real flow runs through AppleSignInCoordinator (nonce + Firebase credential)
                        Color.clear.contentShape(Rectangle()).onTapGesture { run { try await AppleSignInCoordinator.signIn() } }
                    }
                    .accessibilityIdentifier("auth-apple")
            }
            Button {
                run { try await AuthFlows.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    GoogleMark()
                        .frame(width: 18, height: 18)
                    Text("Continue with Google")
                        .font(.body.weight(.semibold))
                }
                .foregroundStyle(Color.navy)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Color.white)
                .hairline(radius: 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("auth-google")
        }
    }

    private var divider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.hairline).frame(height: 1)
            Text("or").font(.footnote).foregroundStyle(Color.textSecondary).fixedSize()
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }

    @ViewBuilder private var fields: some View {
        VStack(spacing: 12) {
            if mode == .signUp {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { firstField; lastField }
                    VStack(spacing: 12) { firstField; lastField }
                }
            }
            AuthField(label: "Email", systemImage: "envelope") {
                TextField("Email address", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(mode == .reset ? .send : .next)
                    .onSubmit { if mode == .reset { submit() } else { focus = .password } }
            }
            if mode != .reset {
                AuthField(label: "Password", systemImage: "lock") {
                    SecureField(mode == .signUp ? "At least 6 characters" : "Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .submitLabel(mode == .signUp ? .next : .go)
                        .onSubmit { if mode == .signUp { focus = .confirm } else { submit() } }
                }
            }
            if mode == .signUp {
                AuthField(label: "Confirm password", systemImage: "lock") {
                    SecureField("Type it again", text: $confirm)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                }
            }
            if mode == .signIn {
                HStack {
                    Spacer()
                    Button("Forgot password?") { mode = .reset }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .accessibilityIdentifier("auth-forgot")
                }
            }
        }
    }

    private var firstField: some View {
        AuthField(label: "First name", systemImage: "person") {
            TextField("First name", text: $firstName)
                .textContentType(.givenName)
                .focused($focus, equals: .first)
                .submitLabel(.next)
                .onSubmit { focus = .last }
        }
    }

    private var lastField: some View {
        AuthField(label: "Last name", systemImage: "person") {
            TextField("Last name", text: $lastName)
                .textContentType(.familyName)
                .focused($focus, equals: .last)
                .submitLabel(.next)
                .onSubmit { focus = .email }
        }
    }

    private var primaryButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if busy { ProgressView().tint(.white) }
                Text(mode == .signIn ? "Sign in" : mode == .signUp ? "Create account" : "Send reset link")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("auth-submit")
    }

    @ViewBuilder private var footerLinks: some View {
        HStack(spacing: 4) {
            Spacer()
            switch mode {
            case .signIn:
                Text("New here?").foregroundStyle(Color.textSecondary)
                Button("Create an account") { mode = .signUp }.fontWeight(.semibold)
            case .signUp:
                Text("Have an account?").foregroundStyle(Color.textSecondary)
                Button("Sign in") { mode = .signIn }.fontWeight(.semibold)
            case .reset:
                Button("Back to sign in") { mode = .signIn }.fontWeight(.semibold)
            }
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(Color.navy)
    }

    // MARK: actions

    private func submit() {
        error = nil
        success = nil
        let mail = email.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .signIn:
            guard !mail.isEmpty, !password.isEmpty else { error = "Please enter your email and password."; return }
            run { try await AuthFlows.signIn(email: mail, password: password) }
        case .signUp:
            guard !firstName.trimmingCharacters(in: .whitespaces).isEmpty,
                  !lastName.trimmingCharacters(in: .whitespaces).isEmpty else { error = "Please enter your first and last name."; return }
            guard mail.contains("@"), mail.contains(".") else { error = "Please enter a valid email address."; return }
            guard password.count >= 6 else { error = "Password must be at least 6 characters long."; return }
            guard password == confirm else { error = "Passwords do not match. Please re-enter."; return }
            run {
                let shown = try await AuthFlows.signUp(firstName: firstName, lastName: lastName, email: mail, password: password)
                auth.setLocal(displayName: shown)
            }
        case .reset:
            guard !mail.isEmpty else { error = "Please enter your email address."; return }
            run {
                try await AuthFlows.sendPasswordReset(email: mail)
                success = "Check your email for a link to reset your password."
            }
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        focus = nil
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                try await work()
            } catch is CancellationError {
                // closed by the person
            } catch {
                self.error = AuthFlows.friendly(error)
            }
        }
    }
}

/// A labelled field with an outline icon and a hairline border.
struct AuthField<Content: View>: View {
    let label: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 20)
                content
                    .font(.body)
                    .foregroundStyle(Color.navy)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Color.white)
            .hairline(radius: 12)
        }
    }
}

/// Google's "G", drawn in navy outline to match the app's icon style (no colored logo, no emoji).
struct GoogleMark: View {
    var body: some View {
        Text("G")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(Color.navy)
            .accessibilityHidden(true)
    }
}
