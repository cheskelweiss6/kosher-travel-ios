import SwiftUI
import Observation
import FirebaseFirestore

/// Report and Block, the same as the web/Capacitor app (src/components/safety: actions.ts, SafetyUI.tsx,
/// safetyService.ts; Apple guideline 1.2). Same Firestore documents:
///   users/{me}/blocks/{theirUid}  { name, photo, at }  (owner-only)
///   storyReports/{postId}_{me}    (StoryActions.reportPost) + one note in the admin's bell
///   users/{admin}/notifications/rp_{postId}_{me}
@Observable
final class StorySafety {
    static let shared = StorySafety()
    static let adminUid = "oKMrTvuUxWPCH10hCHB1uZwHpYm1"

    /// The web's POST_REASONS (the owner's report email knows these words).
    static let postReasons = ["Not appropriate", "Shows people it should not", "Wrong place", "Spam or advertising",
                              "Uses my photo or video without permission", "Something else"]

    struct Blocked: Hashable { var uid: String; var name: String; var photo: String }

    private(set) var blocked: [String: Blocked] = [:]
    @ObservationIgnored private var loadedFor: String?

    private var db: Firestore { Firestore.firestore() }

    func isBlocked(_ uid: String) -> Bool { !uid.isEmpty && blocked[uid] != nil }

    /// Reads the person's block list once per sign-in.
    @MainActor
    func load(uid: String?) async {
        guard let uid, FirebaseBoot.isConfigured else { blocked = [:]; loadedFor = nil; return }
        if loadedFor == uid { return }
        loadedFor = uid
        do {
            let snap = try await db.collection("users").document(uid).collection("blocks").limit(to: 500).getDocuments()
            var map: [String: Blocked] = [:]
            for d in snap.documents {
                let x = d.data()
                map[d.documentID] = Blocked(uid: d.documentID, name: x["name"] as? String ?? "Traveler", photo: x["photo"] as? String ?? "")
            }
            blocked = map
        } catch {
            print("[KT] blocks not read: \(error)")
            loadedFor = nil
        }
    }

    /// Block: their posts leave every list on this phone at once and stay hidden. They aren't told.
    @MainActor
    func block(me: StoryActor, uid: String, name: String, photo: String) async -> Bool {
        guard FirebaseBoot.isConfigured, !uid.isEmpty, uid != me.uid else { return false }
        do {
            try await db.collection("users").document(me.uid).collection("blocks").document(uid).setData([
                "name": String((name.isEmpty ? "Traveler" : name).prefix(80)),
                "photo": String(photo.prefix(2000)),
                "at": FieldValue.serverTimestamp(),
            ])
        } catch {
            print("[KT] block not saved: \(error)")
            return false
        }
        blocked[uid] = Blocked(uid: uid, name: name.isEmpty ? "Traveler" : name, photo: photo)
        return true
    }

    @MainActor
    func unblock(me: String, uid: String) async -> Bool {
        guard FirebaseBoot.isConfigured else { return false }
        do { try await db.collection("users").document(me).collection("blocks").document(uid).delete() } catch {
            print("[KT] unblock not saved: \(error)")
            return false
        }
        blocked[uid] = nil
        return true
    }

    /// The web's notifyPostReport: one note in the admin's bell (no email, no push).
    func notifyPostReport(post: StoryPost, thumb: String, me: StoryActor, text: String) async {
        guard FirebaseBoot.isConfigured, me.uid != Self.adminUid else { return }
        let reportId = "\(post.id)_\(me.uid)"
        var d: [String: Any] = [
            "kind": "report", "actorUid": me.uid, "actorName": String((me.name.isEmpty ? "Traveler" : me.name).prefix(80)),
            "actorPhoto": String(me.photo.prefix(2000)), "targetType": "post", "targetId": String(post.id.prefix(200)),
            "reportId": reportId, "text": String(text.prefix(140)), "createdAt": FieldValue.serverTimestamp(), "read": false,
            "postId": String(post.id.prefix(80)),
            "postTitle": String((post.title.isEmpty ? (post.cityName.isEmpty ? "a post" : post.cityName) : post.title).prefix(120)),
        ]
        if !thumb.isEmpty && thumb.count <= 150_000 { d["postThumb"] = thumb }
        do {
            try await db.collection("users").document(Self.adminUid).collection("notifications").document("rp_\(reportId)").setData(d)
        } catch {
            print("[KT] bell note for the post report not written: \(error)")
        }
    }

    static func reportText(_ reason: String, _ note: String) -> String {
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? reason : "\(reason): \(n)"
    }
}

/// The web's report sheet (SafetyUI openReportSheet): pick a reason, an optional note, Send report; Block the author
/// underneath. Used by the Get Inspired feed and the post page.
struct StoryReportSheet: View {
    let post: StoryPost
    let ownerUid: String
    let thumb: String
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String?
    @State private var note = ""
    @State private var busy = false
    @State private var message: (ok: Bool, text: String)?
    @State private var confirmBlock = false

    private var what: String { post.isGuide ? "article" : "post" }
    private var authorName: String { post.authorName.isEmpty ? "this traveler" : post.authorName }
    private var canBlock: Bool { !ownerUid.isEmpty && ownerUid != auth.uid }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick a reason. The Kosher Travel team reviews every report within 24 hours. \(ownerUid.isEmpty ? "Nobody is told who reported." : "\(authorName) isn\u{2019}t told who reported.")")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        ForEach(StorySafety.postReasons, id: \.self) { r in
                            Button { reason = r } label: {
                                HStack(spacing: 8) {
                                    Text(r)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(reason == r ? Color.navy : Color.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    if reason == r { Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.navy) }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 48)
                                .contentShape(Rectangle())
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(reason == r ? Color.navy : Color.hairline, lineWidth: reason == r ? 1.5 : 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(reason == r ? [.isSelected] : [])
                        }
                    }
                    Text("Add a note (optional)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, 4)
                    TextField("What should we look at?", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
                        .onChange(of: note) { _, v in if v.count > 500 { note = String(v.prefix(500)) } }
                    if let message {
                        Text(message.text)
                            .font(.subheadline)
                            .foregroundStyle(message.ok ? Color.navy : Color.alert)
                    }
                    Button { send() } label: {
                        HStack(spacing: 8) {
                            if busy { ProgressView().tint(.white) } else { Image(systemName: "flag") }
                            Text("Send report")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .opacity(reason == nil || busy ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(reason == nil || busy)
                    if canBlock {
                        Divider().padding(.top, 8)
                        Button { blockTapped() } label: {
                            Label("Block \(authorName)", systemImage: "person.crop.circle.badge.xmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.navy)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.navy, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Text("Hide everything they post. They aren\u{2019}t told.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(Theme.pagePadding)
            }
            .navigationTitle("Report this \(what)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .storyBlockConfirm(isPresented: $confirmBlock, name: authorName) { await doBlock() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func send() {
        guard let reason, !busy else { return }
        guard let actor = StoryActor.from(auth) else {
            dismiss()
            ShellRouter.shared.requireSignIn("Sign in to report a post.")
            return
        }
        busy = true
        let text = StorySafety.reportText(reason, note)
        let p = post
        let t = thumb
        Task {
            let r = await StoryActions.reportPost(p.id, reason: String(text.prefix(200)), uid: actor.uid)
            busy = false
            switch r {
            case .ok:
                await StorySafety.shared.notifyPostReport(post: p, thumb: t, me: actor, text: text)
                dismiss()
                ShellRouter.shared.showToast("Thanks. The team will check it.")
            case .already:
                message = (true, "You already reported this \(what).")
            case .failed:
                message = (false, "The report wasn't sent. Try again.")
            }
        }
    }

    private func blockTapped() {
        guard auth.isSignedIn else {
            dismiss()
            ShellRouter.shared.requireSignIn("Sign in to block a traveler.")
            return
        }
        confirmBlock = true
    }

    @MainActor
    private func doBlock() async {
        guard let actor = StoryActor.from(auth) else { return }
        if await StorySafety.shared.block(me: actor, uid: ownerUid, name: post.authorName, photo: post.authorPhoto) {
            dismiss()
            ShellRouter.shared.showToast("\(authorName) is blocked.")
        } else {
            message = (false, "Couldn't block. Try again.")
        }
    }
}

extension View {
    /// The web's block confirmation (SafetyUI openBlockSheet).
    func storyBlockConfirm(isPresented: Binding<Bool>, name: String, perform: @escaping @MainActor () async -> Void) -> some View {
        alert("Block \(name)?", isPresented: isPresented) {
            Button("Block", role: .destructive) { Task { await perform() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won\u{2019}t see their posts, articles, photos, comments or reviews anywhere in the app. They aren\u{2019}t told. You can unblock them any time in Settings > Blocked users.")
        }
    }
}
