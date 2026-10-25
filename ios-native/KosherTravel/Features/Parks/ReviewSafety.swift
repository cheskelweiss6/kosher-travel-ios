import SwiftUI
import FirebaseFirestore

/// Report / Block for reviews and the one-time Terms prompt before a first review, as the web/Capacitor app does it
/// (src/components/ReviewSection.tsx, safety/actions.ts reportReview + ensureTerms, safety/safetyService.ts
/// reportTarget, hasAcceptedTerms, acceptTerms; Apple guideline 1.2). Block reuses StorySafety (users/{me}/blocks),
/// so a blocked traveler's reviews leave every list together with their posts. Same Firestore documents as the web:
///   reports/review_{reviewId}_{me}            { targetType, targetId, targetUserId, targetName, reason, note?, userId, createdAt }
///   users/{admin}/notifications/rp_{reportId}  the admin's bell note
///   users/{me}                                 { termsAcceptedAt, termsVersion } (merge)
enum ReviewSafety {
    /// The web's reportReview reasons, in its order.
    static let reasons = ["Not appropriate", "Not appropriate photo", "Fake or misleading review", "Spam or advertising",
                          "Hateful or harassing", "Something else"]

    enum Result { case ok, already, failed }

    private static func reportedKey(_ id: String) -> String { "kt_reported:\(id)" }

    /// The web's reportTarget(me, { targetType: 'review', ... }).
    @MainActor
    static func report(me: StoryActor, review: PlaceReview, placeName: String, reason: String, note: String) async -> Result {
        guard FirebaseBoot.isConfigured else { return .failed }
        let reportId = "review_\(review.id)_\(me.uid)"
        if UserDefaults.standard.bool(forKey: reportedKey(reportId)) { return .already }
        let db = Firestore.firestore()
        let who = review.userName.isEmpty ? "Traveler" : review.userName
        let targetName = placeName.isEmpty ? who : "\(who) on \(placeName)"
        var data: [String: Any] = [
            "targetType": "review", "targetId": String(review.id.prefix(200)), "targetUserId": review.userId,
            "targetName": String(targetName.prefix(120)), "reason": String(reason.prefix(200)), "userId": me.uid,
            "createdAt": FieldValue.serverTimestamp(),
        ]
        let n = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { data["note"] = String(n.prefix(500)) }
        let batch = db.batch()
        batch.setData(data, forDocument: db.collection("reports").document(reportId))
        if me.uid != StorySafety.adminUid {
            batch.setData([
                "kind": "report", "actorUid": me.uid, "actorName": String((me.name.isEmpty ? "Traveler" : me.name).prefix(80)),
                "actorPhoto": String(me.photo.prefix(2000)), "targetType": "review", "targetId": String(review.id.prefix(200)),
                "reportId": reportId, "text": String("\(targetName) · \(StorySafety.reportText(reason, note))".prefix(140)),
                "createdAt": FieldValue.serverTimestamp(), "read": false,
            ], forDocument: db.collection("users").document(StorySafety.adminUid).collection("notifications").document("rp_\(reportId)"))
        }
        do {
            try await batch.commit()
            UserDefaults.standard.set(true, forKey: reportedKey(reportId))
            return .ok
        } catch {
            // Only the admin can read reports, so a second report of the same review is refused by the rules.
            print("[KT] review report not saved: \(error)")
            return .failed
        }
    }
}

/// The web's Terms of Use agreement, asked once before a first post, comment or review.
enum TermsAgreement {
    static let version = "2026-10-23"   // web TERMS_VERSION
    private static func key(_ uid: String) -> String { "kt_terms_v1:\(uid)" }

    @MainActor
    static func hasAccepted(_ uid: String) async -> Bool {
        if UserDefaults.standard.bool(forKey: key(uid)) { return true }
        guard FirebaseBoot.isConfigured else { return false }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
            let ok = snap.exists && snap.data()?["termsAcceptedAt"] != nil
            if ok { UserDefaults.standard.set(true, forKey: key(uid)) }
            return ok
        } catch {
            return false
        }
    }

    @MainActor
    @discardableResult
    static func accept(_ uid: String) async -> Bool {
        UserDefaults.standard.set(true, forKey: key(uid))
        guard FirebaseBoot.isConfigured else { return false }
        do {
            try await Firestore.firestore().collection("users").document(uid).setData([
                "termsAcceptedAt": FieldValue.serverTimestamp(), "termsVersion": version,
            ], merge: true)
            return true
        } catch {
            print("[KT] terms agreement not saved: \(error)")
            return false
        }
    }
}

/// The web's TermsView sheet ("Before you post"), word for word.
struct TermsAgreementSheet: View {
    let done: (Bool) -> Void
    @State private var agreed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.shield").font(.title2).foregroundStyle(Color.navy)
                    Text("Before you post").font(.title3.weight(.bold)).foregroundStyle(Color.navy)
                }
                Text("Kosher Travel is a friendly place for Jewish travelers. Posts, photos, comments and reviews must be respectful and appropriate. Objectionable content, harassment and spam are removed, and accounts that post them are banned.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    link("Terms of Use", "https://www.yourkoshertravel.com/terms")
                    link("Support", "https://www.yourkoshertravel.com/support")
                }
                Button { agreed.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: agreed ? "checkmark.square" : "square")
                            .contentTransition(.symbolEffect(.replace))
                            .animation(Motion.select, value: agreed)
                            .font(.title3)
                            .foregroundStyle(Color.navy)
                        Text("I agree to the Terms of Use and community rules (no objectionable content).")
                            .font(.subheadline)
                            .foregroundStyle(Color.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(agreed ? [.isSelected] : [])
                Button { finish(true) } label: {
                    Text("Agree and continue")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .opacity(agreed ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!agreed)
                Button { finish(false) } label: {
                    Text("Not now")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.pagePadding)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }

    private func link(_ title: String, _ url: String) -> some View {
        Button { if let u = URL(string: url) { openURL(u) } } label: {
            HStack(spacing: 4) {
                Text(title).underline()
                Image(systemName: "arrow.up.right.square").font(.caption)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.navy)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    private func finish(_ ok: Bool) {
        done(ok)
        dismiss()
    }
}

/// The web's report sheet for a review (SafetyUI openReportSheet, what: 'review'): a reason, an optional note, Send
/// report; Block the author underneath (StorySafety.block, the same confirm as posts).
struct ReviewReportSheet: View {
    let review: PlaceReview
    let placeName: String
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var reason: String?
    @State private var note = ""
    @State private var busy = false
    @State private var message: (ok: Bool, text: String)?
    @State private var confirmBlock = false

    private var authorName: String { review.userName.isEmpty ? "this traveler" : review.userName }
    private var canBlock: Bool { !review.userId.isEmpty && review.userId != auth.uid }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick a reason. The Kosher Travel team reviews every report within 24 hours. \(authorName) isn\u{2019}t told who reported.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 8) {
                        ForEach(ReviewSafety.reasons, id: \.self) { r in
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
                        .font(.body)
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
                        Button { confirmBlock = true } label: {
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
            .navigationTitle("Report this review")
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
            ShellRouter.shared.requireSignIn("Sign in to report a review")
            return
        }
        busy = true
        let r = review
        let place = placeName
        let n = note
        Task {
            let result = await ReviewSafety.report(me: actor, review: r, placeName: place, reason: reason, note: n)
            busy = false
            switch result {
            case .ok:
                dismiss()
                ShellRouter.shared.showToast("Thanks. The team will check it.")
            case .already:
                message = (true, "You already reported this review.")
            case .failed:
                message = (false, "The report wasn't sent. Try again.")
            }
        }
    }

    @MainActor
    private func doBlock() async {
        guard let actor = StoryActor.from(auth) else {
            dismiss()
            ShellRouter.shared.requireSignIn("Sign in to block a traveler.")
            return
        }
        let ok = await StorySafety.shared.block(me: actor, uid: review.userId, name: review.userName, photo: review.userPhoto)
        if ok {
            dismiss()
            ShellRouter.shared.showToast("\(authorName) is blocked.")
        } else {
            message = (false, "Couldn\u{2019}t block. Try again.")
        }
    }
}
