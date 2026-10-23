import SwiftUI

/// The bell's list (NotificationsSheet.tsx): newest first, likes grouped per post, unread dot, mark all read.
struct NotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoryFeed.self) private var feed
    let store: ProfileStore
    @State private var openPost: String?

    var body: some View {
        NavigationStack {
            Group {
                if let list = store.shownNotifs {
                    if !store.notifsOK && list.isEmpty {
                        ContentUnavailableView("Couldn't load your notifications", systemImage: "wifi.exclamationmark",
                                               description: Text("Check your connection."))
                    } else if list.isEmpty {
                        ContentUnavailableView("No notifications yet", systemImage: "bell",
                                               description: Text("When someone likes or comments on your post, or follows you, it shows up here."))
                    } else {
                        List {
                            ForEach(list) { n in
                                Button { openNote(n) } label: { BellNoteRow(n: n) }
                                    .buttonStyle(.plain)
                                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            Task { await store.deleteNotification(n) }
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .accessibilityIdentifier("notif-row")
                            }
                        }
                        .listStyle(.plain)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if store.unreadCount > 0 {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Mark all read") { Task { await store.markAllRead() } }
                            .accessibilityIdentifier("notif-mark-all")
                    }
                }
            }
            .navigationDestination(item: $openPost) { id in
                StoryDetailView(postId: id)
            }
        }
    }

    private func openNote(_ n: BellNote) {
        if !n.read { Task { await store.markRead(n.ids) } }
        // a note about a live post opens it; follow / review notes only mark read for now
        if !n.postId.isEmpty, n.kind != "follow", n.kind != "review", feed.post(n.postId) != nil {
            openPost = n.postId
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
                    .foregroundStyle(n.read ? Color.textSecondary : Color.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Label(TimeAgo.string(n.createdAtMs), systemImage: icon)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
            if n.kind != "follow" && n.kind != "review" && !n.postThumb.isEmpty {
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
            return name + Text(" reported a comment on ") + Text(n.postTitle).fontWeight(.semibold) + quote
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
