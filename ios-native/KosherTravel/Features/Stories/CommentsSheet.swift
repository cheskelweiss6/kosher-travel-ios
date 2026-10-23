import SwiftUI

/// Comments on a post, as a sheet: the thread (oldest first), reply, edit or delete your own, report someone else's
/// (the admin can also remove any). Writing needs sign-in.
struct CommentsSheet: View {
    let post: StoryPost
    let ownerUid: String
    let thumb: String
    let onCount: (Int) -> Void

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var comments: [StoryComment] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var text = ""
    @State private var replyTo: String?
    @State private var editing: StoryComment?
    @State private var sending = false
    @State private var error: String?
    @State private var note: String?
    @State private var confirmDelete: StoryComment?
    @State private var sentCount = 0
    @FocusState private var focused: Bool

    init(post: StoryPost, ownerUid: String, thumb: String, onCount: @escaping (Int) -> Void) {
        self.post = post
        self.ownerUid = ownerUid
        self.thumb = thumb
        self.onCount = onCount
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if !loaded {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                    } else if failed {
                        FeedStatusLine(message: "Comments could not load. Pull down to try again.")
                            .listRowSeparator(.hidden)
                    } else if comments.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.title2)
                                .foregroundStyle(Color.navy)
                            Text("No comments yet").font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                            Text("Be the first to say something.").font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(comments) { c in
                            row(c)
                                .id(c.id)
                                .listRowSeparatorTint(Color.hairline)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) { swipe(c) }
                                .contextMenu { menu(c) }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
                .onChange(of: sentCount) { _, _ in
                    if let last = comments.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .navigationTitle(comments.isEmpty ? "Comments" : "Comments (\(comments.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .overlay(alignment: .top) {
                if let note {
                    Text(note)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.navy, in: Capsule())
                        .padding(.top, 8)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: note)
            .task(id: note) {
                guard note != nil else { return }
                try? await Task.sleep(for: .seconds(3))
                note = nil
            }
            .confirmationDialog(deleteTitle, isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let c = confirmDelete { remove(c) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .task { await load() }
    }

    private var deleteTitle: String {
        guard let c = confirmDelete else { return "Delete this comment?" }
        return c.userId == auth.uid ? "Delete this comment?" : "Remove \(c.authorName)'s comment?"
    }

    // MARK: rows

    private func row(_ c: StoryComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Oct 23 2026: the commenter's current username (profiles/{uid}), else the name saved with the comment
            let shownName = StoriesStore.shared.name(uid: c.userId, stored: c.authorName)
            TravelerAvatar(uid: c.userId, stored: c.authorPhoto, name: shownName, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(shownName).font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
                    Text(TimeAgo.string(c.createdAtMs)).font(.caption).foregroundStyle(Color.textSecondary)
                    if c.editedAtMs != nil {
                        Text("edited").font(.caption).foregroundStyle(Color.textTertiary)
                    }
                }
                Text(c.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.navy.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if auth.isSignedIn {
                    Button("Reply") { startReply(c) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, c.replyTo.isEmpty ? 0 : 28)
        .padding(.vertical, 4)
    }

    private func own(_ c: StoryComment) -> Bool { auth.uid != nil && c.userId == auth.uid }

    @ViewBuilder
    private func swipe(_ c: StoryComment) -> some View {
        if own(c) {
            Button(role: .destructive) { confirmDelete = c } label: { Label("Delete", systemImage: "trash") }
            Button { startEdit(c) } label: { Label("Edit", systemImage: "pencil") }
                .tint(Color.navy)
        } else if auth.isSignedIn {
            Button { report(c) } label: { Label("Report", systemImage: "flag") }
                .tint(Color.navy)
            if auth.isAdmin {
                Button(role: .destructive) { confirmDelete = c } label: { Label("Remove", systemImage: "trash") }
            }
        }
    }

    @ViewBuilder
    private func menu(_ c: StoryComment) -> some View {
        Button { UIPasteboard.general.string = c.text } label: { Label("Copy", systemImage: "doc.on.doc") }
        if auth.isSignedIn {
            Button { startReply(c) } label: { Label("Reply", systemImage: "arrowshape.turn.up.left") }
        }
        if own(c) {
            Button { startEdit(c) } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { confirmDelete = c } label: { Label("Delete", systemImage: "trash") }
        } else if auth.isSignedIn {
            Button { report(c) } label: { Label("Report comment", systemImage: "flag") }
            if auth.isAdmin {
                Button(role: .destructive) { confirmDelete = c } label: { Label("Remove comment", systemImage: "trash") }
            }
        }
    }

    // MARK: composer

    @ViewBuilder
    private var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.hairline)
            if !auth.isSignedIn {
                Button { ShellRouter.shared.requireSignIn("Sign in to comment.") } label: {
                    Label("Sign in to comment", systemImage: "person.crop.circle")
                }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.vertical, 14)
            } else {
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Color.alert)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.pagePadding)
                        .padding(.top, 8)
                }
                if editing != nil || replyTo != nil {
                    HStack {
                        Text(editing != nil ? "Editing your comment" : "Replying to \(replyTo ?? "")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Button("Cancel") {
                            editing = nil
                            replyTo = nil
                            text = ""
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.top, 8)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(editing != nil ? "Edit comment" : "Add a comment", text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($focused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.hairline) }
                        .onChange(of: text) { _, v in
                            if v.count > CommentsService.maxLength { text = String(v.prefix(CommentsService.maxLength)) }
                        }
                    Button(action: send) {
                        Group {
                            if sending { ProgressView() } else { Image(systemName: "arrow.up.circle").font(.title) }
                        }
                        .foregroundStyle(canSend ? Color.navy : Color.textTertiary)
                        .frame(width: 40, height: 40)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel(editing != nil ? "Save" : "Send")
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 10)
            }
        }
        .background(.bar)
        .sensoryFeedback(.success, trigger: sentCount)
    }

    private var canSend: Bool {
        !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: actions

    private func load() async {
        let r = await CommentsService.fetch(post.id)
        if let r {
            comments = r
            failed = false
            onCount(r.count)
        } else {
            failed = comments.isEmpty
        }
        loaded = true
    }

    private func startReply(_ c: StoryComment) {
        editing = nil
        replyTo = c.authorName
        text = "@\(c.authorName) "
        focused = true
    }

    private func startEdit(_ c: StoryComment) {
        replyTo = nil
        editing = c
        text = c.text
        focused = true
    }

    private func send() {
        guard let actor = StoryActor.from(auth) else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !sending else { return }
        sending = true
        error = nil
        if let c = editing {
            if t == c.text { editing = nil; text = ""; sending = false; return }
            Task {
                let saved = await CommentsService.edit(postId: post.id, commentId: c.id, text: t)
                sending = false
                guard let saved else { error = "Your change wasn't saved. Check your connection and try again."; return }
                if let i = comments.firstIndex(where: { $0.id == c.id }) {
                    comments[i].text = saved
                    comments[i].editedAtMs = Date().timeIntervalSince1970 * 1000
                }
                editing = nil
                text = ""
            }
            return
        }
        // a reply only counts as one while the text still starts with @Name (same as the web)
        let reply = replyTo.flatMap { t.hasPrefix("@\($0)") ? $0 : nil }
        Task {
            let c = await CommentsService.add(postId: post.id, actor: actor, text: t, replyTo: reply)
            sending = false
            guard let c else { error = "Your comment wasn't posted. Check your connection and tap Send again."; return }
            comments.append(c)
            onCount(comments.count)
            text = ""
            replyTo = nil
            sentCount += 1
            await CommentsService.notify(post: post, ownerUid: ownerUid, thumb: thumb, actor: actor, comment: c)
        }
    }

    private func remove(_ c: StoryComment) {
        let mine = own(c)
        Task {
            let ok = await CommentsService.delete(postId: post.id, commentId: c.id)
            guard ok else { note = "Couldn't delete it. Try again."; return }
            comments.removeAll { $0.id == c.id }
            onCount(comments.count)
            if editing?.id == c.id { editing = nil; text = "" }
            if mine { await CommentsService.retract(ownerUid: ownerUid, commentId: c.id) }
        }
    }

    private func report(_ c: StoryComment) {
        guard let me = StoryActor.from(auth) else { return }
        Task {
            switch await CommentsService.report(post: post, thumb: thumb, comment: c, me: me) {
            case .reported: note = "Reported. Thanks for telling us."
            case .already: note = "You already reported this comment."
            case .failed: note = "The report wasn't sent. Try again."
            }
        }
    }
}
