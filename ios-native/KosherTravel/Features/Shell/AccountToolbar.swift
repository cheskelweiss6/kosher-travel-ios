import SwiftUI

/// The web header's account corner, on every tab (Cheskel's parity rule; App.tsx "User Auth Profile / Sign In"):
/// signed out, a settings button that opens the Profile page; signed in, the notifications bell (with its unread
/// count) and an avatar button that opens the Profile page. The web's tab bar has no Profile tab.
struct AccountToolbarButtons: View {
    @Environment(AuthStore.self) private var auth
    private let store = ProfileStore.shared

    var body: some View {
        HStack(spacing: 14) {
            if auth.isSignedIn {
                Button {
                    ShellRouter.shared.profileOpensBell = true
                    ShellRouter.shared.showProfile = true
                } label: {
                    Image(systemName: "bell")
                        .overlay(alignment: .topTrailing) {
                            if store.unreadCount > 0 {
                                Text(store.unreadCount > 99 ? "99+" : "\(store.unreadCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Color.alert, in: Capsule())
                                    .offset(x: 9, y: -7)
                            }
                        }
                }
                .accessibilityLabel(store.unreadCount > 0 ? "Notifications, \(store.unreadCount) unread" : "Notifications")
                .accessibilityIdentifier("header-bell")

                Button { ShellRouter.shared.showProfile = true } label: { avatar }
                    .accessibilityLabel("View Profile")
                    .accessibilityIdentifier("header-profile")
            } else {
                Button { ShellRouter.shared.showProfile = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings and profile")
                .accessibilityIdentifier("header-settings")
            }
        }
        .task(id: auth.uid) { await store.bind(uid: auth.uid) }
    }

    /// Web: the photo in a round frame, or the first letter of the name (or email) on navy.
    @ViewBuilder private var avatar: some View {
        let size: CGFloat = 28
        if !auth.photoURL.isEmpty, let url = URL(string: auth.photoURL) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    initial
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
        } else {
            initial.frame(width: size, height: size)
        }
    }

    private var initial: some View {
        let source = auth.displayName.isEmpty ? auth.email : auth.displayName
        let letter = source.first.map { String($0).uppercased() } ?? "U"
        return Circle()
            .fill(Color.navy)
            .overlay(Text(letter).font(.caption.weight(.bold)).foregroundStyle(.white))
    }
}

extension ProfileStore {
    /// One store for the header bell and the Profile page, so the unread count shows before Profile is opened.
    static let shared = ProfileStore()
}
