import SwiftUI

/// The bell's list (NotificationsSheet.tsx): newest first, likes grouped per post, unread dot, mark all read.
/// Cheskel (Oct 23 2026, 1:16 PM + 1:19 PM): the list was a see-through sheet stacked on the Profile sheet and hard to
/// read. It is now its own page, pushed onto the current navigation stack: its own glass top bar ("Notifications",
/// back chevron, swipe back) over a solid white list. The header bell on every tab and the bell on Profile both push it.
struct NotificationsView: View {
    @Environment(StoryFeed.self) private var feed
    @Environment(AuthStore.self) private var auth
    var store: ProfileStore = .shared
    @State private var openPost: String?
    @State private var openPerson: BellNote?
    @State private var pendingDelete: BellNote?
    @State private var openKivrei = false

    var body: some View {
        Group {
            if let list = LaunchRoute.qaPreview ? BellNote.qaSamples : store.shownNotifs {
                if !store.notifsOK && list.isEmpty {
                    ContentUnavailableView("Couldn't load your notifications", systemImage: "wifi.exclamationmark",
                                           description: Text("Check your connection."))
                } else if list.isEmpty {
                    ContentUnavailableView("No notifications yet", systemImage: "bell",
                                           description: Text("When someone likes or comments on your post, or follows you, it shows up here."))   // the website's words
                } else {
                    List {
                        ForEach(list) { n in
                            Button { openNote(n) } label: { BellNoteRow(n: n) }
                                .buttonStyle(.plain)
                                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                .listRowBackground(Color.white)
                                .listRowSeparatorTint(Color.hairline)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        pendingDelete = n
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                                .accessibilityIdentifier("notif-row")
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            } else {
                ProgressView()
            }
        }
        .animation(Motion.content, value: store.shownNotifs == nil)   // spinner -> list: a crossfade, never a wait
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.unreadCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Mark all read") { Task { await store.markAllRead() } }
                        .accessibilityIdentifier("notif-mark-all")
                }
            }
        }
        .navigationDestination(item: $openPost) { id in
            StoryDetailView(postId: id)
        }
        .navigationDestination(item: $openPerson) { n in
            TravelerView(uid: n.actorUid, name: n.actorName, photo: n.actorPhoto)
        }
        .navigationDestination(isPresented: $openKivrei) {
            WebScreen(route: .kivrei)
        }
        .task(id: auth.uid) { await store.bind(uid: auth.uid) }
        .accessibilityIdentifier("notifications-page")
        // every delete asks first (Cheskel, Oct 23 2026)
        .confirmationDialog("Delete this notification?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { n in
            Button("Delete", role: .destructive) {
                pendingDelete = nil
                Task { await store.deleteNotification(n) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        }
    }

    /// Tapping a note marks it read and opens what it is about: the post (comments, likes, reports) or the person
    /// who followed you. Review notes only mark read (the place page has no native route from here yet).
    private func openNote(_ n: BellNote) {
        if !n.read { Task { await store.markRead(n.ids) } }
        switch n.kind {
        case "follow":
            if !n.actorUid.isEmpty { openPerson = n }
        case "review":
            break
        case "yahrzeit":
            // web: the kever's card; here the website's Kivrei Tzadikim page (it has the card, the heart and the alert)
            openKivrei = true
        case "removed":
            // web: a removed comment opens its post; a removed post / article / review is gone
            if n.targetType == "comment" && !n.postId.isEmpty { openPost = n.postId }
        default:
            // StoryDetailView loads the post itself and says honestly when it was removed.
            if !n.postId.isEmpty { openPost = n.postId }
        }
    }
}

struct BellNoteRow: View {
    let n: BellNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(n.read ? Color.clear : Color.navy)
                .frame(width: 8, height: 8)
                .padding(.top, 16)
                .accessibilityHidden(true)
            ProfileAvatar(name: n.actorName, photo: n.actorPhoto, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                sentence
                    .font(.subheadline)
                    .foregroundStyle(Color.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Label(TimeAgo.string(n.createdAtMs), systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
            if !["follow", "review", "yahrzeit", "removed"].contains(n.kind) && !n.postThumb.isEmpty {
                RemoteImage(url: n.postThumb, maxPixel: 160)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(n.read ? "" : "Unread")
    }

    private var icon: String {
        switch n.kind {
        case "follow": return "person.badge.plus"
        case "like": return "heart"
        case "review": return "star"
        case "report": return "flag"
        case "yahrzeit": return "flame"
        case "removed": return "trash"
        default: return "bubble.left"
        }
    }

    private var sentence: Text {
        let name = Text(n.actorName).fontWeight(.semibold)
        let quote = n.text.isEmpty ? Text("") : Text(": \u{201C}\(n.text)\u{201D}")
        switch n.kind {
        case "follow":
            return name + Text(" started following you")
        case "like":
            let others = n.others > 0 ? Text(" and ") + Text("\(n.others) other\(n.others == 1 ? "" : "s")").fontWeight(.semibold) : Text("")
            return name + others + Text(" liked ") + Text(n.postTitle).fontWeight(.semibold)
        case "review":
            let stars = (n.rating ?? 0) > 0 ? Text(" \u{00B7} \(n.rating ?? 0) star\((n.rating ?? 0) == 1 ? "" : "s")") : Text("")
            return name + Text(" reviewed ") + Text(n.placeName.isEmpty ? "a place" : n.placeName).fontWeight(.semibold) + stars + quote
        case "report":
            // the website's words (NotificationsSheet.tsx)
            switch n.targetType {
            case "post": return name + Text(" reported the post ") + Text(n.postTitle).fontWeight(.semibold) + quote
            case "profile": return name + Text(" reported a profile") + quote
            case "review": return name + Text(" reported a review") + quote
            default: return name + Text(" reported a comment on ") + Text(n.postTitle).fontWeight(.semibold) + quote
            }
        case "removed":
            let what = ["article", "comment", "review"].contains(n.targetType) ? n.targetType : "post"
            let title = n.postTitle.isEmpty || n.postTitle == "your post" ? Text("") : Text(" ") + Text(n.postTitle).fontWeight(.semibold)
            let why = n.text.isEmpty ? Text("") : Text(": \(n.text)")
            return Text("Kosher Travel").fontWeight(.semibold) + Text(" removed your \(what)") + title + why
        case "yahrzeit":
            let who = n.placeName.isEmpty ? n.postTitle : n.placeName
            return Text("Yahrzeit of ") + Text(who).fontWeight(.semibold) + Text(n.text.isEmpty ? "" : " " + n.text)
        default:
            return name + Text(" commented on ") + Text(n.postTitle).fontWeight(.semibold) + quote
        }
    }
}

/// A round profile photo, or the first letter on a quiet circle.
struct ProfileAvatar: View {
    let name: String
    let photo: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if photo.hasPrefix("http") || photo.hasPrefix("data:") {
                RemoteImage(url: photo, maxPixel: size * 3)
            } else {
                Text(String((name.isEmpty ? "T" : name).prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Color.navy)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surface)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

extension BellNote {
    /// Screenshot runs only (LaunchRoute.qaPreview): one note of each kind, in the website's words.
    static var qaSamples: [BellNote] {
        let now = Date().timeIntervalSince1970 * 1000
        func note(_ id: String, _ kind: String, _ name: String, title: String = "", text: String = "", place: String = "",
                  rating: Int? = nil, type: String = "", ago: Double, read: Bool = false, others: Int = 0) -> BellNote {
            BellNote(id: id, kind: kind, actorUid: "qa-\(id)", actorName: name, actorPhoto: "", postId: "", postTitle: title,
                     postThumb: "", text: text, createdAtMs: now - ago * 60_000, read: read, placeName: place, rating: rating,
                     ids: [id], others: others, targetType: type, targetId: "")
        }
        return [
            note("1", "comment", "Yossi K.", title: "Shabbos in Miami Beach", text: "Which shul did you daven at?", ago: 4),
            note("2", "like", "Malky S.", title: "Shabbos in Miami Beach", ago: 25, others: 3),
            note("3", "follow", "Dovid R.", ago: 90),
            note("4", "yahrzeit", "", place: "Rebbe Elimelech of Lizensk", text: "is tomorrow, 21 Adar", ago: 180, read: true),
            note("5", "removed", "", title: "My trip to Cancun", text: "photo not allowed", type: "post", ago: 600, read: true),
            note("6", "review", "Chaya L.", text: "Great food, very clean", place: "Kosher Delight Warsaw", rating: 5, ago: 1500, read: true),
        ]
    }
}
