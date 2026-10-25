import SwiftUI
import FirebaseFirestore

/// "Link to my article" for your own post (Cheskel, Oct 25 2026, urgent: "I don't see the option to link an article
/// to my post"). The website has it in the post's "…" sheet and, since Oct 25, in the post composer; the app's •••
/// menu had only Edit and Delete. Saves the post's linkedArticleId, the field "Read the full article" and the Links
/// sheet read (web storyService setLinkedArticle: one update of that field, or its removal).
enum StoryArticleLink {
    static func set(postId: String, articleId: String?) async -> Bool {
        guard FirebaseBoot.isConfigured, !postId.isEmpty else { return false }
        let value: Any
        if let id = articleId, !id.isEmpty { value = id } else { value = FieldValue.delete() }
        do {
            try await Firestore.firestore().collection(StoryActions.posts).document(postId)
                .updateData(["linkedArticleId": value])
            return true
        } catch {
            print("[KT] link article failed: \(error)")
            return false
        }
    }
}

/// The picker: your articles first, then other travelers' live articles, with search; Remove the link when set.
struct StoryLinkArticleSheet: View {
    let postId: String
    let current: String
    let myUid: String

    @Environment(\.dismiss) private var dismiss
    private var store: StoriesStore { .shared }
    @State private var query = ""
    @State private var saving = false
    @State private var failed = false
    @State private var done = 0

    private func matches(_ a: StoryPost) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        return [a.title, a.placeLine, a.cityName, a.authorName].contains { $0.lowercased().contains(q) }
    }
    private func isMine(_ a: StoryPost) -> Bool {
        let owner = store.extra(a.id)?.userId ?? a.userId
        return !myUid.isEmpty && owner == myUid
    }
    private var mine: [StoryPost] { store.articles.filter { isMine($0) && $0.id != postId && matches($0) } }
    private var others: [StoryPost] { Array(store.articles.filter { !isMine($0) && $0.id != postId && matches($0) }.prefix(40)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if mine.isEmpty {
                        Text(query.isEmpty ? "You have no articles yet. Write one from Share, then Article." : "None of yours match.")
                            .font(.subheadline).foregroundStyle(Color.textSecondary)
                    }
                    ForEach(mine) { row($0, showAuthor: false) }
                } header: { Text("Your articles") }
                if !others.isEmpty {
                    Section {
                        ForEach(others) { row($0, showAuthor: true) }
                    } header: { Text("Other articles") }
                }
                if !current.isEmpty {
                    Section {
                        Button(role: .destructive) { pick(nil) } label: {
                            Text("Remove the link").frame(maxWidth: .infinity)
                        }
                        .disabled(saving)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search articles by title or place")
            .navigationTitle("Link an article")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .overlay { if saving { ProgressView().controlSize(.large) } }
            .alert("Couldn't save the link yet. Try again soon.", isPresented: $failed) { Button("OK", role: .cancel) {} }
            .sensoryFeedback(.success, trigger: done)
            .task { await store.loadIfNeeded() }
        }
    }

    private func row(_ a: StoryPost, showAuthor: Bool) -> some View {
        Button { pick(a.id) } label: {
            HStack(spacing: 12) {
                StoryCoverImage(post: a, maxPixel: 200)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.title.isEmpty ? "Article" : a.title)
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy).lineLimit(2)
                    Text(showAuthor ? [a.placeLine, a.authorName].filter { !$0.isEmpty }.joined(separator: " · ") : a.placeLine)
                        .font(.caption).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if a.id == current {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.navy)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .accessibilityLabel("\(a.title), \(a.placeLine)\(a.id == current ? ", linked" : "")")
    }

    private func pick(_ id: String?) {
        guard !saving else { return }
        saving = true
        Task {
            let ok = await StoryArticleLink.set(postId: postId, articleId: id)
            if ok {
                await store.reload(postId)
                if let id, !id.isEmpty { await store.ensure(id) }
                done += 1
                saving = false
                dismiss()
            } else {
                saving = false
                failed = true
            }
        }
    }
}
