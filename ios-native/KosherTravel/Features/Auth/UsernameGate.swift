import SwiftUI
import UIKit
import FirebaseAuth

// MARK: - When to ask

/// Asks a signed-in person for a username when they have none (Cheskel, Oct 23 2026: "the operator who is
/// creating an account should ask him for a username"). New accounts (email, Apple, Google) must choose one before
/// they go on; existing accounts without one are asked once after sign-in and may tap Skip.
/// Shown in its own window above everything, so it also works when a sign-in sheet is still closing.
@MainActor
enum UsernameGate {
    private static var window: UIWindow?
    private static var checking: String?

    private static func askedKey(_ uid: String) -> String { "kt_username_asked_v1_\(uid)" }
    nonisolated private static func newKey(_ uid: String) -> String { "kt_username_new_v1_\(uid)" }

    /// The sign-in flows call this when Firebase says the account was just created (kept until a name is saved,
    /// so closing the app does not skip the step).
    nonisolated static func markNew(_ uid: String) { UserDefaults.standard.set(true, forKey: newKey(uid)) }

    private static func isNew(_ uid: String) -> Bool {
        if UserDefaults.standard.bool(forKey: newKey(uid)) { return true }
        guard let user = Auth.auth().currentUser, user.uid == uid,
              let created = user.metadata.creationDate else { return false }
        return Date().timeIntervalSince(created) < 15 * 60
    }

    /// Called on launch and on every sign-in / sign-out (RootTabView, `.usernameGate()`).
    static func check(uid: String?) async {
        guard let uid else { close(); return }
        guard FirebaseBoot.isConfigured, window == nil, checking != uid else { return }
        let required = isNew(uid)
        if !required && UserDefaults.standard.bool(forKey: askedKey(uid)) { return }
        checking = uid
        defer { checking = nil }
        // a just-created account may not have its preferences doc yet; one retry covers a slow first read
        var name = await UsernameRules.current(uid: uid)
        if name == nil {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            name = await UsernameRules.current(uid: uid)
        }
        guard let name, name.isEmpty, Auth.auth().currentUser?.uid == uid else { return }
        // let a closing sign-in sheet finish first
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard Auth.auth().currentUser?.uid == uid else { return }
        show(uid: uid, required: required)
    }

    private static func show(uid: String, required: Bool) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        let page = UsernamePage(uid: uid, required: required) { saved in
            UserDefaults.standard.set(true, forKey: askedKey(uid))
            if saved { UserDefaults.standard.removeObject(forKey: newKey(uid)) }
            close()
        }
        let host = UIHostingController(rootView: page)
        host.view.backgroundColor = .white
        w.rootViewController = host
        w.windowLevel = .normal + 1
        w.overrideUserInterfaceStyle = .light
        w.tintColor = Theme.navyUI
        w.alpha = 0
        w.makeKeyAndVisible()
        window = w
        UIView.animate(withDuration: 0.25) { w.alpha = 1 }
    }

    static func close() {
        guard let w = window else { return }
        window = nil
        w.endEditing(true)
        UIView.animate(withDuration: 0.25, animations: { w.alpha = 0 }) { _ in
            w.isHidden = true
            w.rootViewController = nil
            // hand the keyboard and taps back to the app's own window
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.windowLevel == .normal && !($0 is PassThroughWindow) }?
                .makeKey()
        }
    }
}

extension View {
    /// Mounted once on the root view: asks for a username after sign-in when the account has none.
    func usernameGate() -> some View { modifier(UsernameGateModifier()) }
}

private struct UsernameGateModifier: ViewModifier {
    @Environment(AuthStore.self) private var auth
    func body(content: Content) -> some View {
        content.task(id: auth.ready ? (auth.uid ?? "-") : "?") {
            guard auth.ready else { return }
            await UsernameGate.check(uid: auth.uid)
        }
    }
}

// MARK: - The page

/// "Choose a username": one field with the website's live check, words and limits, and a sticky navy Continue.
struct UsernamePage: View {
    let uid: String
    let required: Bool
    let onDone: (_ saved: Bool) -> Void

    private enum Avail: Equatable { case idle, checking, free, taken, unknown }

    @State private var user = ""
    @State private var avail: Avail = .idle
    @State private var saving = false
    @State private var error: String?
    @State private var claimFailed = false
    @State private var savedTick = 0
    @FocusState private var focused: Bool

    /// Skip shows for existing accounts, and for a new one only after a save could not reach the server.
    private var canSkip: Bool { !required || claimFailed }
    private var trimmed: String { user.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var problem: String? { trimmed.isEmpty ? nil : UsernameRules.problem(user, canSkip: canSkip) }
    private var canSave: Bool {
        !saving && !trimmed.isEmpty && problem == nil && avail != .taken && avail != .checking
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "at")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Color.navy)
                        .frame(width: 60, height: 60)
                        .hairline(radius: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose a username")
                            .font(.title.weight(.bold))
                            .foregroundStyle(Color.navy)
                            .accessibilityAddTraits(.isHeader)
                        Text("Shown on your posts and reviews. You can change it later.")
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)
                    }
                    field
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Color.alert)
                            .accessibilityIdentifier("username-error")
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.white)
            .safeAreaInset(edge: .bottom) { continueBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canSkip {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { onDone(false) }
                            .foregroundStyle(Color.navy)
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(saving)
                            .accessibilityIdentifier("username-skip")
                    }
                }
            }
            .interactiveDismissDisabled()
            .sensoryFeedback(.success, trigger: savedTick)
            .task(id: user) { await liveCheck() }
            .onAppear { focused = true }
        }
        .tint(Color.navy)
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 8) {
            AuthField(label: "Username", systemImage: "at") {
                TextField("Shown on your posts and reviews", text: $user)
                    .font(.system(size: 17))
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { if canSave { save() } }
                    .onChange(of: user) { _, v in
                        error = nil
                        // the website's input stops at 30 characters (maxLength)
                        if v.utf16.count > UsernameRules.maxLength {
                            var t = v
                            while t.utf16.count > UsernameRules.maxLength { t.removeLast() }
                            user = t
                        }
                    }
                    .accessibilityIdentifier("username-field")
            }
            stateLine
                .frame(minHeight: 22, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("username-state")
        }
    }

    @ViewBuilder private var stateLine: some View {
        if let problem {
            Text(problem).font(.subheadline).foregroundStyle(Color.alert)
        } else {
            switch avail {
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Checking…")
                }
                .font(.subheadline).foregroundStyle(Color.textSecondary)
            case .free:
                Label("Available", systemImage: "checkmark.circle")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Color.navy)
            case .taken:
                Text(UsernameRules.takenLine).font(.subheadline).foregroundStyle(Color.alert)
            case .unknown:
                Text(UsernameRules.unknownLine).font(.subheadline).foregroundStyle(Color.textSecondary)
            case .idle:
                Text(UsernameRules.hint).font(.subheadline).foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var continueBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.hairline).frame(height: 1)
            Button(action: save) {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(.white) }
                    Text("Continue").font(.body.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color.navy.opacity(canSave ? 1 : 0.35),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: 560)
            .accessibilityIdentifier("username-continue")
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    // MARK: actions

    /// The website's live check: 450 ms after the last keystroke, only for a name that passes the rules.
    private func liveCheck() async {
        let v = trimmed
        guard !v.isEmpty, UsernameRules.problem(v) == nil else { avail = .idle; return }
        avail = .checking
        try? await Task.sleep(nanoseconds: 450_000_000)
        if Task.isCancelled { return }
        let r = await UsernameRules.availability(v, uid: uid)
        guard !Task.isCancelled, v == trimmed else { return }
        switch r {
        case .free: avail = .free
        case .taken: avail = .taken
        case .unknown: avail = .unknown
        }
    }

    private func save() {
        error = nil
        let v = trimmed
        if let p = UsernameRules.problem(user, canSkip: canSkip) { error = p; return }
        if avail == .taken { error = UsernameRules.takenOnSave; return }
        focused = false
        saving = true
        Task { @MainActor in
            switch await UsernameRules.claim(v, uid: uid) {
            case .ok:
                break
            case .taken:
                saving = false
                avail = .taken
                error = UsernameRules.justTaken
                return
            case .error:
                saving = false
                claimFailed = true
                error = UsernameRules.claimFailed(canSkip: true)
                return
            }
            do {
                try await UsernameRules.save(v, uid: uid)
            } catch {
                saving = false
                self.error = UsernameRules.saveFailed
                return
            }
            savedTick += 1
            // the Profile and Stories screens read the new name (StoryActions signs posts with it)
            await ProfileStore.shared.reload()
            await StoriesStore.shared.syncAccount(uid: nil)
            await StoriesStore.shared.syncAccount(uid: uid)
            saving = false
            onDone(true)
        }
    }
}
