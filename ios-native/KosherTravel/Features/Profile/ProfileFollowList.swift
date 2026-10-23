import SwiftUI
import FirebaseFirestore

/// Profile counts → Instagram-style lists (Cheskel, Oct 23 2026: "Should be able to tap and see who I am following").
/// Following: users/{me}/following/{uid} { name, photo, createdAt }; Followers: users/{me}/followers/{uid} { name, photo,
/// createdAt } — the same documents the Follow button writes (StoryActions.setFollow, web followService.ts).
struct ProfileFollowList: View {
    let showFollowing: Bool
    @Environment(AuthStore.self) private var auth
    private var stories: StoriesStore { .shared }

    struct Person: Identifiable, Hashable {
        var uid: String
        var name: String
        var photo: String
        var at: Double
        var id: String { uid }
    }

    @State private var people: [Person] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var busy: Set<String> = []
    @State private var pendingUnfollow: Person?

    var body: some View {
        Group {
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed && people.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load the list", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try again") { Task { await load() } }
                }
            } else if people.isEmpty {
                ContentUnavailableView(showFollowing ? "Not following anyone yet" : "No followers yet",
                                       systemImage: showFollowing ? "person.badge.plus" : "person.2",
                                       description: Text(showFollowing ? "Tap Follow on a traveler's post or page to see them here."
                                                                       : "When travelers follow you, they show here."))
            } else {
                List(people) { p in
                    HStack(spacing: 12) {
                        NavigationLink {
                            TravelerView(uid: p.uid, name: p.name, photo: p.photo)
                        } label: {
                            HStack(spacing: 12) {
                                TravelerAvatar(uid: p.uid, stored: p.photo, name: p.name, size: 48)
                                Text(p.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Color.navy)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        followButton(p)
                    }
                    .listRowSeparatorTint(Color.hairline)
                }
                .listStyle(.plain)
                .refreshable { await load() }
                .confirmationDialog(pendingUnfollow.map { "Unfollow \($0.name)?" } ?? "Unfollow?",
                                    isPresented: Binding(get: { pendingUnfollow != nil },
                                                         set: { if !$0 { pendingUnfollow = nil } }),
                                    titleVisibility: .visible,
                                    presenting: pendingUnfollow) { p in
                    Button("Unfollow", role: .destructive) {
                        if stories.following.contains(p.uid) { toggle(p) }
                        pendingUnfollow = nil
                    }
                    Button("Cancel", role: .cancel) { pendingUnfollow = nil }
                }
            }
        }
        .background(Color.white)
        .navigationTitle(showFollowing ? "Following" : "Followers")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: auth.uid ?? "") {
            await stories.syncAccount(uid: auth.uid)
            await load()
        }
        .onDisappear { Task { await ProfileStore.shared.reload() } }
    }

    @ViewBuilder
    private func followButton(_ p: Person) -> some View {
        if p.uid != auth.uid {
            let on = stories.following.contains(p.uid)
            Button {
                // "Following" asks first (red Unfollow + Cancel); "Follow" / "Follow back" acts at once.
                if on { pendingUnfollow = p } else { toggle(p) }
            } label: {
                Text(on ? "Following" : (showFollowing ? "Follow" : "Follow back"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(on ? Color.navy : .white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(on ? Color.white : Color.navy, in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? Color.hairline : Color.navy, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy.contains(p.uid))
            .sensoryFeedback(.selection, trigger: on)
            .accessibilityLabel(on ? "Unfollow \(p.name)" : "Follow \(p.name)")
        }
    }

    @MainActor
    private func toggle(_ p: Person) {
        guard let actor = StoryActor.from(auth) else { return }
        let was = stories.following.contains(p.uid)
        stories.setFollowing(p.uid, !was)
        busy.insert(p.uid)
        Task {
            let ok = await StoryActions.setFollow(actor: actor, target: p.uid, targetName: p.name, targetPhoto: p.photo, on: !was)
            busy.remove(p.uid)
            if !ok {
                stories.setFollowing(p.uid, was)
                ShellRouter.shared.showToast("Couldn't change it. Try again.")
            }
        }
    }

    @MainActor
    private func load() async {
        guard let uid = auth.uid, FirebaseBoot.isConfigured else { loaded = true; return }
        do {
            let snap = try await Firestore.firestore().collection("users").document(uid)
                .collection(showFollowing ? "following" : "followers").limit(to: 500).getDocuments(source: .server)
            people = snap.documents.map { d in
                let x = d.data()
                let post = stories.posts(by: d.documentID).first
                var name = (x["name"] as? String) ?? ""
                if name.isEmpty { name = post?.authorName ?? "Traveler" }
                let photo = (x["photo"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? post?.authorPhoto ?? ""
                let at = (x["createdAt"] as? Timestamp)?.dateValue().timeIntervalSince1970 ?? 0
                return Person(uid: d.documentID, name: name, photo: photo, at: at)
            }
            .filter { !StorySafety.shared.isBlocked($0.uid) }
            .sorted { $0.at > $1.at }
            failed = false
        } catch {
            print("[KT] \(showFollowing ? "following" : "followers") not read: \(error)")
            failed = true
        }
        loaded = true
    }
}
