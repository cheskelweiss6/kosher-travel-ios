import SwiftUI
import FirebaseFirestore

// MARK: - Delete account (DeletePage in SettingsSheet.tsx)

struct DeleteAccountView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let store: ProfileStore
    enum Step { case intro, confirm, working, done }
    @State private var step: Step = .intro
    @State private var password = ""
    @State private var label = ""
    @State private var error: String?
    @State private var email = ""

    private var postsText: String {
        guard store.storiesLoaded, !store.storiesFailed else { return "all your posts" }
        let n = store.stories.count
        return n == 1 ? "your 1 post and its photos" : "your \(n) posts and their photos"
    }

    var body: some View {
        Form {
            if step == .done {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Color.navy)
                        Text("Your account is deleted").font(.headline).foregroundStyle(Color.navy)
                        Text("Thanks for traveling with us.").font(.subheadline).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("This deletes your account for good.").font(.headline).foregroundStyle(Color.navy)
                        Text("Deleted with it: your sign-in (\(email)), \(postsText), your comments and likes, your saved trips, chats and preferences.")
                        Text("Your posts are deleted, not kept under another name. Reports you sent stay private with the site owner. This can't be undone.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.vertical, 4)
                }
                if step == .intro {
                    Section {
                        Button("Continue") { step = .confirm }
                            .foregroundStyle(Color.alert)
                            .accessibilityIdentifier("delete-continue")
                    }
                } else {
                    Section {
                        if auth.signInKind == "password" {
                            SecureField("Enter your password to confirm", text: $password)
                                .textContentType(.password)
                                .disabled(step == .working)
                        } else {
                            Text("\(auth.signInKind == "apple" ? "Apple" : "Google") will ask you to confirm it's you.")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    if let error { FormNote(ok: false, text: error) }
                    Section {
                        Button(role: .destructive, action: go) {
                            HStack(spacing: 8) {
                                if step == .working { ProgressView(); Text("\(label)\u{2026}") } else { Text("Delete my account") }
                            }
                        }
                        .disabled(step == .working)
                        .accessibilityIdentifier("delete-final")
                    }
                }
            }
        }
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step == .working || step == .done)
        .interactiveDismissDisabled(step == .working)
        .onAppear { if email.isEmpty { email = auth.email } }
    }

    private func go() {
        error = nil
        if auth.signInKind == "password" && password.isEmpty { error = "Enter your password to confirm."; return }
        step = .working
        label = "Checking it\u{2019}s you"
        Task {
            do {
                try await AuthFlows.reauth(password: password)
            } catch is CancellationError {
                step = .confirm
                return
            } catch {
                step = .confirm
                self.error = AuthFlows.friendly(error)
                return
            }
            do {
                try await store.deleteAccount { text in label = text }
                step = .done
            } catch {
                step = .confirm
                self.error = "\(AuthFlows.friendly(error)) Your account is still here. Try again to finish deleting it."
            }
        }
    }
}

// MARK: - Contact us (ContactSheet.tsx: saved to contactMessages and emailed to the owner)

enum ContactService {
    static let chatBase = "https://www.yourkoshertravel.com/kt-ai"
    static let whatsapp = URL(string: "https://wa.me/18455702638?text=Hi%2C%20I%20have%20a%20question%20about%20Your%20Kosher%20Travel")!
    static let email = "yourkoshertravel@gmail.com"
    static let mailto = URL(string: "mailto:yourkoshertravel@gmail.com?subject=Question%20about%20Your%20Kosher%20Travel")!

    enum MailResult { case sent, limited, failed }

    static func save(name: String, email: String, message: String, uid: String?) async -> Bool {
        guard FirebaseBoot.isConfigured else { return false }
        var data: [String: Any] = ["message": String(message.prefix(2000)), "userId": uid ?? "",
                                   "createdAt": FieldValue.serverTimestamp(), "page": "ios-app"]
        if !name.isEmpty { data["name"] = String(name.prefix(100)) }
        if !email.isEmpty { data["email"] = String(email.prefix(200)) }
        do {
            try await Firestore.firestore().collection("contactMessages").document().setData(data)
            return true
        } catch {
            print("[KT] contact not saved: \(error.localizedDescription)")
            return false
        }
    }

    /// The chat server checks rate limits and builds the mail; the app posts it to FormSubmit (ownerMail.ts).
    static func emailOwner(name: String, email: String, message: String) async -> MailResult {
        guard let url = URL(string: chatBase + "/api/contact") else { return .failed }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name, "email": email, "message": message, "website": ""])
        guard let first = try? await URLSession.shared.data(for: req), let http = first.1 as? HTTPURLResponse else { return .failed }
        let data = first.0
        if http.statusCode == 429 { return .limited }
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], (j["ok"] as? Bool) == true else { return .failed }
        if j["mail"] is NSNull { return .sent }
        guard let mail = j["mail"] as? [String: Any], let to = mail["to"] as? String, !to.isEmpty,
              let body = mail["body"] as? [String: Any],
              let enc = to.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let fs = URL(string: "https://formsubmit.co/ajax/\(enc)") else { return .failed }
        var post = URLRequest(url: fs)
        post.httpMethod = "POST"
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue("application/json", forHTTPHeaderField: "Accept")
        post.timeoutInterval = 15
        post.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let second = try? await URLSession.shared.data(for: post), let h2 = second.1 as? HTTPURLResponse,
              (200..<300).contains(h2.statusCode),
              let j2 = try? JSONSerialization.jsonObject(with: second.0) as? [String: Any] else { return .failed }
        let success = j2["success"]
        if (success as? Bool) == true || (success as? String) == "true" { return .sent }
        return .failed
    }
}

struct ContactView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.openURL) private var openURL
    @State private var name = ""
    @State private var email = ""
    @State private var message = ""
    @State private var busy = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        Form {
            if sent {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Color.navy)
                        Text("Sent, thanks").font(.headline).foregroundStyle(Color.navy)
                        Text(email.trimmingCharacters(in: .whitespaces).isEmpty ? "Thanks for writing." : "We'll reply to your email.")
                            .font(.subheadline).foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                Section {
                    Button { openURL(ContactService.whatsapp) } label: {
                        SettingsRow(icon: "phone.bubble", label: "WhatsApp us", value: nil, external: true)
                    }
                    Button { openURL(ContactService.mailto) } label: {
                        SettingsRow(icon: "envelope", label: "Email us", value: ContactService.email, external: true)
                    }
                } footer: {
                    Text("A question, an idea, a correction? It goes straight to the owner of Kosher Travel.")
                }
                Section("Or write here") {
                    TextField("Your name (optional)", text: $name).textContentType(.name)
                    TextField("Your email (optional)", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Your message", text: $message, axis: .vertical)
                        .lineLimit(4...10)
                        .onChange(of: message) { _, v in if v.count > 2000 { message = String(v.prefix(2000)) } }
                        .accessibilityIdentifier("contact-message")
                }
                if let error { FormNote(ok: false, text: error) }
                Section {
                    Button(action: send) {
                        HStack { if busy { ProgressView() }; Text("Send") }
                    }
                    .disabled(busy)
                }
            }
        }
        .foregroundStyle(Color.navy)
        .navigationTitle("Contact us")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if name.isEmpty { name = auth.displayName }
            if email.isEmpty { email = auth.email }
        }
    }

    private func send() {
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { error = "Please write a message."; return }
        if !mail.isEmpty && (!mail.contains("@") || !mail.contains(".") || mail.contains(" ")) {
            error = "That email doesn't look right. Fix it, or leave it empty."
            return
        }
        error = nil
        busy = true
        let who = name.trimmingCharacters(in: .whitespaces)
        let uid = auth.uid
        Task {
            async let saved = ContactService.save(name: who, email: mail, message: msg, uid: uid)
            async let mailed = ContactService.emailOwner(name: who, email: mail, message: msg)
            let (s, m) = await (saved, mailed)
            busy = false
            if m == .limited && !s { error = "You've sent several messages just now. Please try again in a few minutes."; return }
            if !s && m != .sent { error = "Couldn't send your message. Check your connection and try again, or email \(ContactService.email)."; return }
            sent = true
        }
    }
}
