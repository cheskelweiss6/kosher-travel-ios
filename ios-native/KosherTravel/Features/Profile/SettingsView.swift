import SwiftUI

/// A result line under a form: navy for done, red for a problem.
struct FormNote: View {
    let ok: Bool
    let text: String
    var body: some View {
        Label(text, systemImage: ok ? "checkmark.circle" : "exclamationmark.circle")
            .font(.footnote)
            .foregroundStyle(ok ? Color.navy : Color.alert)
    }
}

/// Settings (SettingsSheet.tsx): one grouped list, iOS style. Every row does its job for real.
struct ProfileSettingsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL
    let store: ProfileStore
    var onSignIn: () -> Void = {}
    @State private var mapsApp = ""

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return b.isEmpty ? v : "\(v) (\(b))"
    }
    private var googleManaged: Bool { auth.signInKind != "password" }

    /// Close Profile, go to Explore, and let the website's page show the guide or the tour there.
    private func openOnboarding(_ what: String) {
        ShellRouter.shared.showProfile = false
        ShellRouter.shared.selectedTab = .explore
        WarmWebPage.explore.run(js: "window.__ktShellOnboarding && window.__ktShellOnboarding('\(what)')")
    }
    private var managedBy: String { auth.signInKind == "apple" ? "Managed by Apple" : "Managed by Google" }

    var body: some View {
        Form {
            if auth.isSignedIn {
                Section("Account") {
                    NavigationLink {
                        NameEditView(store: store)
                    } label: {
                        SettingsRow(icon: "person", label: "Display name", value: shownName)
                    }
                    NavigationLink {
                        EmailChangeView()
                    } label: {
                        SettingsRow(icon: "envelope", label: "Email", value: googleManaged ? managedBy : auth.email)
                    }
                    NavigationLink {
                        PasswordView()
                    } label: {
                        SettingsRow(icon: "key", label: "Password", value: googleManaged ? managedBy : "Change or reset")
                    }
                }
                Section {
                    Toggle("Comments on my posts", isOn: prefBinding(\.comments))
                    Toggle("New followers", isOn: prefBinding(\.follows))
                    Toggle("Likes on my posts", isOn: prefBinding(\.likes))
                    if ProfileStore.reviewOwnerUids.contains(auth.uid ?? "") {
                        Toggle("Reviews", isOn: prefBinding(\.reviews))
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Shown in the bell.")
                }
                .tint(Color.navy)
            } else {
                Section {
                    Button(action: onSignIn) {
                        SettingsRow(icon: "person.crop.circle.badge.plus", label: "Sign in or create an account", value: nil)
                    }
                    .accessibilityIdentifier("settings-signin")
                } header: {
                    Text("Account")
                } footer: {
                    Text("Sign in to change your name, email and password, and to see your posts.")
                }
            }

            Section("Preferences") {
                NavigationLink {
                    KosherPrefsView(store: store)
                } label: {
                    let n = store.kosherPrefs?.needs.count ?? 0
                    SettingsRow(icon: "slider.horizontal.3", label: "My kosher preferences", value: n > 0 ? "\(n) saved" : "Not set")
                }
                NavigationLink {
                    YahrzeitSettingsView()
                } label: {
                    SettingsRow(icon: "bell", label: "Yahrzeit alerts", value: YahrzeitAlerts.shared.prefs.on ? "On" : "Off")
                }
                .accessibilityIdentifier("settings-yahrzeit")
                // Web: SettingsSheet "Open maps in" (same stored choice as the map sheet's "Remember my choice").
                Picker(selection: Binding(get: { mapsApp }, set: { mapsApp = $0; MapApp.preferred = MapApp(rawValue: $0) })) {
                    Text("Ask every time").tag("")
                    ForEach(MapApp.allCases) { Text($0.label).tag($0.rawValue) }
                } label: {
                    Label("Open maps in", systemImage: "map")
                }
                .tint(Color.navy)
                .onAppear { mapsApp = MapApp.preferred?.rawValue ?? "" }
            }

            Section("Privacy and safety") {
                Button { openURL(URL(string: "https://www.yourkoshertravel.com/privacy")!) } label: {
                    SettingsRow(icon: "hand.raised", label: "Privacy", value: nil, external: true)
                }
                Button { openURL(URL(string: "https://www.yourkoshertravel.com/terms")!) } label: {
                    SettingsRow(icon: "doc.text", label: "Terms", value: nil, external: true)
                }
            }

            Section {
                NavigationLink {
                    ContactView()
                } label: {
                    SettingsRow(icon: "text.bubble", label: "Contact us", value: nil)
                }
                // V2-FULL-1029: the website's App guide and tour (SettingsSheet.tsx), shown on the Explore tab page
                if (auth.isSignedIn || LaunchRoute.qaPreview) && WarmWebPage.explore.hasOnboarding {
                    Button { openOnboarding("guide") } label: {
                        SettingsRow(icon: "book", label: "App guide", value: "Features and getting started")
                    }
                    .accessibilityIdentifier("set-guide")
                    Button { openOnboarding("tour") } label: {
                        SettingsRow(icon: "arrow.counterclockwise", label: "Replay the tour", value: nil)
                    }
                    .accessibilityIdentifier("set-tour")
                }
                SettingsRow(icon: "info.circle", label: "About", value: "Version \(version)")
            } header: {
                Text("Help")
            } footer: {
                Text("Kosher Travel \u{00B7} Version \(version)\nKosher food, shuls and trips, shared by travelers.")
            }

            if auth.isSignedIn {
                Section {
                    Button {
                        auth.signOut()
                    } label: {
                        SettingsRow(icon: "rectangle.portrait.and.arrow.right", label: "Sign out", value: nil)
                    }
                    .accessibilityIdentifier("settings-signout")
                    NavigationLink {
                        DeleteAccountView(store: store)
                    } label: {
                        Label("Delete account", systemImage: "trash")
                            .foregroundStyle(Color.alert)
                    }
                }
            }
        }
        .foregroundStyle(Color.navy)
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var shownName: String {
        let n = store.username.isEmpty ? auth.displayName : store.username
        return n.isEmpty ? (auth.email.split(separator: "@").first.map(String.init) ?? "") : n
    }

    private func prefBinding(_ key: WritableKeyPath<BellSwitches, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.notifPrefs[keyPath: key] },
            set: { v in
                var next = store.notifPrefs
                next[keyPath: key] = v
                Task { await store.setBellSwitches(next) }
            })
    }
}

struct SettingsRow: View {
    let icon: String
    let label: String
    let value: String?
    var external = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.navy)
                .frame(width: 24)
            Text(label).foregroundStyle(Color.navy)
            Spacer(minLength: 8)
            if let value, !value.isEmpty {
                Text(value)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if external {
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Name

struct NameEditView: View {
    @Environment(AuthStore.self) private var auth
    let store: ProfileStore
    @State private var value = ""
    @State private var busy = false
    @State private var note: (ok: Bool, text: String)?
    @State private var saved = 0
    @State private var confirmRemove = false

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $value)
                    .textContentType(.name)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .onChange(of: value) { _, v in
                        if v.count > 30 { value = String(v.prefix(30)) }
                        note = nil
                    }
                    .accessibilityIdentifier("name-input")
            } header: {
                Text("Name shown on your posts and reviews")
            } footer: {
                Text("Up to 30 characters.")
            }
            if let note { FormNote(ok: note.ok, text: note.text) }
            Section {
                Button(action: save) {
                    HStack { if busy { ProgressView() }; Text("Save") }
                }
                .disabled(busy)
                if !store.username.isEmpty {
                    Button("Remove username", role: .destructive) { confirmRemove = true }
                        .confirmationDialog("Remove your username?", isPresented: $confirmRemove, titleVisibility: .visible) {
                            Button("Remove username", role: .destructive) {
                                Task {
                                    do { try await store.removeUsername(); value = auth.displayName; note = (true, "Username removed. Default name restored.") }
                                    catch { note = (false, AuthFlows.friendly(error)) }
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                }
            }
        }
        .navigationTitle("Display name")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(Motion.Haptic.success, trigger: saved)
        .onAppear {
            if value.isEmpty { value = store.username.isEmpty ? auth.displayName : store.username }
        }
    }

    private func save() {
        let t = value.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { note = (false, "Your name cannot be empty."); return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.saveName(t)
                auth.setLocal(displayName: t)
                note = (true, "Saved. New posts and reviews show this name.")
                saved += 1
            } catch {
                note = (false, AuthFlows.friendly(error))
            }
        }
    }
}

// MARK: - Email

struct EmailChangeView: View {
    @Environment(AuthStore.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var note: (ok: Bool, text: String)?

    var body: some View {
        Form {
            Section("Current email") { Text(auth.email).foregroundStyle(Color.textSecondary) }
            if auth.signInKind != "password" {
                Section {
                    Text("You sign in with \(auth.signInKind == "apple" ? "Apple" : "Google"), so your email is managed by that account. Change it there and it applies here too.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    if auth.signInKind == "google" {
                        Link("Open Google account", destination: URL(string: "https://myaccount.google.com/security")!)
                    }
                }
            } else {
                Section("New email") {
                    TextField("New email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Current password", text: $password)
                        .textContentType(.password)
                }
                if let note { FormNote(ok: note.ok, text: note.text) }
                Section {
                    Button(action: submit) {
                        HStack { if busy { ProgressView() }; Text("Send confirmation link") }
                    }
                    .disabled(busy)
                }
            }
        }
        .navigationTitle("Email")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        let e = email.trimmingCharacters(in: .whitespaces)
        guard e.contains("@"), e.contains("."), !e.contains(" ") else { note = (false, "That email doesn't look right."); return }
        guard e.lowercased() != auth.email.lowercased() else { note = (false, "That is already your email."); return }
        guard !password.isEmpty else { note = (false, "Enter your current password."); return }
        busy = true
        note = nil
        Task {
            defer { busy = false }
            do {
                try await AuthFlows.changeEmail(current: password, newEmail: e)
                note = (true, "We sent a link to \(e). Your email changes when you tap it. Until then, keep signing in with \(auth.email).")
                password = ""
            } catch is CancellationError {
            } catch {
                note = (false, AuthFlows.friendly(error))
            }
        }
    }
}

// MARK: - Password

struct PasswordView: View {
    @Environment(AuthStore.self) private var auth
    @State private var current = ""
    @State private var next = ""
    @State private var again = ""
    @State private var busy = false
    @State private var note: (ok: Bool, text: String)?
    @State private var resetBusy = false
    @State private var resetNote: (ok: Bool, text: String)?

    var body: some View {
        Form {
            if auth.signInKind != "password" {
                Section {
                    Text("You sign in with \(auth.signInKind == "apple" ? "Apple" : "Google"), so your password is managed by that account. Change it there and it applies here too.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    if auth.signInKind == "google" {
                        Link("Open Google account", destination: URL(string: "https://myaccount.google.com/security")!)
                    }
                }
            } else {
                Section("Change password") {
                    SecureField("Current password", text: $current).textContentType(.password)
                    SecureField("New password (6 or more characters)", text: $next).textContentType(.newPassword)
                    SecureField("New password again", text: $again).textContentType(.newPassword)
                }
                if let note { FormNote(ok: note.ok, text: note.text) }
                Section {
                    Button(action: change) {
                        HStack { if busy { ProgressView() }; Text("Change password") }
                    }
                    .disabled(busy)
                }
                Section {
                    Button(action: reset) {
                        HStack { if resetBusy { ProgressView() }; Text("Email me a reset link") }
                    }
                    .disabled(resetBusy)
                    if let resetNote { FormNote(ok: resetNote.ok, text: resetNote.text) }
                } header: {
                    Text("Forgot it?")
                } footer: {
                    Text("We send a link to \(auth.email).")
                }
            }
        }
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func change() {
        guard !current.isEmpty else { note = (false, "Enter your current password."); return }
        guard next.count >= 6 else { note = (false, "Choose a new password of at least 6 characters."); return }
        guard next == again else { note = (false, "The two new passwords don't match."); return }
        guard next != current else { note = (false, "The new password is the same as the current one."); return }
        busy = true
        note = nil
        Task {
            defer { busy = false }
            do {
                try await AuthFlows.changePassword(current: current, next: next)
                note = (true, "Password changed. Use the new one next time you sign in.")
                current = ""; next = ""; again = ""
            } catch {
                note = (false, AuthFlows.friendly(error))
            }
        }
    }

    private func reset() {
        resetBusy = true
        resetNote = nil
        Task {
            defer { resetBusy = false }
            do {
                try await AuthFlows.sendPasswordReset(email: auth.email)
                resetNote = (true, "Sent to \(auth.email). Check your inbox and spam folder for the link.")
            } catch {
                resetNote = (false, AuthFlows.friendly(error))
            }
        }
    }
}

// MARK: - Kosher preferences

struct KosherPrefsView: View {
    let store: ProfileStore

    var body: some View {
        Form {
            Section {
                Toggle("Use my preferences to filter places", isOn: Binding(
                    get: { store.kosherPrefs?.filtersOn ?? true },
                    set: { v in Task { await store.saveKosherPrefs(filtersOn: v) } }))
            } footer: {
                Text("Saved on this phone, and in your account when you're signed in. They filter place lists and help the trip planner. They're never sent to the AI chat.")
            }
            group("Food", SavedKosherPrefs.food)
            group("Around where you stay", SavedKosherPrefs.nearby)
            group("Trips", SavedKosherPrefs.trip)
        }
        .tint(Color.navy)
        .navigationTitle("Kosher preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ title: String, _ items: [String]) -> some View {
        Section(title) {
            ForEach(items, id: \.self) { item in
                let on = store.kosherPrefs?.needs.contains(item) ?? false
                Button {
                    var needs = store.kosherPrefs?.needs ?? []
                    if on { needs.removeAll { $0 == item } } else { needs.append(item) }
                    Task { await store.saveKosherPrefs(needs: needs) }
                } label: {
                    HStack {
                        Text(item).foregroundStyle(Color.navy)
                        Spacer()
                        Image(systemName: on ? "checkmark.circle" : "circle")
                            .contentTransition(.symbolEffect(.replace))
                            .animation(Motion.select, value: on)
                            .foregroundStyle(on ? Color.navy : Color.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .sensoryFeedback(Motion.Haptic.selection, trigger: on)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
