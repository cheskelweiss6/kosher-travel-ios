import SwiftUI
import PhotosUI
import GoogleSignIn

enum ProfileRoute: Hashable {
    case settings, contact, name, story(String)
    case people(following: Bool)   // the Followers / Following lists (tap a count)
    case web(WebRoute)   // a live-app screen inside the native shell
}

/// The Profile tab (the web's ProfileView): sign-in call to action when signed out; photo, name, counts, your stories,
/// saved posts and settings when signed in; the bell in the toolbar.
struct ProfileTab: View {
    @Environment(AuthStore.self) private var auth
    @Environment(StoryFeed.self) private var feed
    @Environment(\.openURL) private var openURL
    @State private var store = ProfileStore.shared
    @Environment(\.dismiss) private var dismiss
    /// Shown as a sheet from the header's account button (the web has no Profile tab).
    var presented = false
    @State private var path: [ProfileRoute] = []
    @State private var signIn: SignInSheet.Mode?
    @State private var showBell = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoBusy = false
    @State private var photoError: String?
    @State private var routed = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if auth.isSignedIn {
                    signedIn
                } else if auth.ready {
                    signedOut
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.white)
            .navigationTitle("Profile")
            .toolbar { profileToolbar }
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .settings: ProfileSettingsView(store: store, onSignIn: { signIn = .signIn })
                case .contact: ContactView()
                case .name: NameEditView(store: store)
                case .story(let id): StoryDetailView(postId: id)
                case .web(let r): WebScreen(route: r)
                case .people(let following): ProfileFollowList(showFollowing: following)
                }
            }
        }
        .sheet(item: $signIn) { mode in
            SignInSheet(mode: mode)
        }
        .sheet(isPresented: $showBell) {
            NotificationsSheet(store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: auth.uid) {
            await store.bind(uid: auth.uid)
        }
        .task {
            await feed.loadIfNeeded()
        }
        .onAppear(perform: openLaunchRoute)
        .onAppear {
            // The header's bell opens the Profile page with the notifications list on top.
            if ShellRouter.shared.profileOpensBell {
                ShellRouter.shared.profileOpensBell = false
                if auth.isSignedIn { showBell = true }
            }
        }
        // the Google sign-in callback is handled app-wide (RootTabView → DeepLinks.handle)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item) }
        }
        .alert("Profile photo", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(photoError ?? "")
        }
    }

    // MARK: toolbar

    @ToolbarContentBuilder private var profileToolbar: some ToolbarContent {
        if presented {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("profile-done")
            }
        }
        if auth.isSignedIn {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showBell = true } label: {
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
                .accessibilityIdentifier("profile-bell")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink(value: ProfileRoute.settings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: signed out

    private var signedOut: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 64, weight: .ultraLight))
                        .foregroundStyle(Color.navy)
                    Text("Your travel profile")
                        .font(.serifTitle(.title2))
                        .foregroundStyle(Color.navy)
                    Text("Sign in to save trips and articles, share your stories, follow travelers and get notified when someone comments.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)

                VStack(spacing: 10) {
                    Button { signIn = .signIn } label: {
                        Text("Sign in")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile-signin")
                    Button { signIn = .signUp } label: {
                        Text("Create an account")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.navy)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .hairline(radius: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                linkRows(signedIn: false)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: signed in

    private var shownName: String {
        if !store.username.isEmpty { return store.username }
        if !auth.displayName.isEmpty { return auth.displayName }
        return auth.email.split(separator: "@").first.map(String.init) ?? "Traveler"
    }

    private var signedIn: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                counts(proxy)
                storiesSection
                    .id("your-stories")
                savedSection
                shellRows
                linkRows(signedIn: true)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.reload() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Menu {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(auth.photoURL.isEmpty ? "Add a photo" : "Change photo", systemImage: "photo")
                }
                if !auth.photoURL.isEmpty {
                    Button(role: .destructive) {
                        Task { await removePhoto() }
                    } label: { Label("Remove photo", systemImage: "trash") }
                }
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    ProfileAvatar(name: shownName, photo: auth.photoURL, size: 84)
                        .overlay {
                            if photoBusy {
                                Circle().fill(Color.white.opacity(0.7))
                                ProgressView()
                            }
                        }
                    Image(systemName: "camera")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.navy)
                        .frame(width: 28, height: 28)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
                }
            }
            .accessibilityLabel("Profile photo")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(shownName)
                        .font(.serifTitle(.title2))
                        .foregroundStyle(Color.navy)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    NavigationLink(value: ProfileRoute.name) {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .accessibilityLabel("Edit name")
                }
                if !auth.email.isEmpty {
                    Text(auth.email)
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                TagLabel(text: "Member")
            }
            Spacer(minLength: 0)
        }
    }

    /// Each count opens its list (Instagram style); Posts scrolls to "Your stories".
    private func counts(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            countCell(store.followers, store.followers == 1 ? "Follower" : "Followers") {
                path.append(.people(following: false))
            }
            Rectangle().fill(Color.hairline).frame(width: 1, height: 32)
            countCell(store.following, "Following") {
                path.append(.people(following: true))
            }
            Rectangle().fill(Color.hairline).frame(width: 1, height: 32)
            countCell(store.storiesLoaded ? store.stories.count : nil, store.stories.count == 1 ? "Post" : "Posts") {
                withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("your-stories", anchor: .top) }
            }
        }
        .padding(.vertical, 4)
        .hairline(radius: 14)
    }

    private func countCell(_ n: Int?, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(n.map { "\($0)" } ?? "\u{2013}")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color.navy)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(n.map { "\($0)" } ?? "") \(label)")
        .accessibilityHint(label == "Posts" || label == "Post" ? "Shows your stories" : "Shows the list")
    }

    // MARK: Your stories

    private var storiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Your stories")
                if store.pendingCount > 0 {
                    Text("\(store.pendingCount) waiting")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            if !store.storiesLoaded {
                LoadingCards(count: 3, minWidth: 150, aspect: 0.8)
                    .padding(.horizontal, -Theme.pagePadding)
            } else if store.storiesFailed && store.stories.isEmpty {
                FeedStatusLine(message: "Your stories could not load. Pull down to try again.")
            } else if store.stories.isEmpty {
                EmptyNote(title: "No stories yet", detail: "Share a trip from the Stories tab and it shows up here.",
                          systemImage: "photo.on.rectangle")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(store.stories) { s in
                            storyCard(s)
                                .containerRelativeFrame(.horizontal) { len, _ in
                                    Layout.peekWidth(len, min: 150, spacing: 12)
                                }
                        }
                    }
                }
                .contentMargins(.horizontal, Theme.pagePadding, for: .scrollContent)
                .padding(.horizontal, -Theme.pagePadding)
            }
        }
    }

    @ViewBuilder private func storyCard(_ s: OwnStory) -> some View {
        let canOpen = s.status == "live" && feed.post(s.id) != nil
        Button {
            if canOpen { path.append(.story(s.id)) }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Color.surface
                    .aspectRatio(0.8, contentMode: .fit)
                    .overlay {
                        if s.cover.isEmpty {
                            Image(systemName: s.isVideo ? "video" : "photo")
                                .foregroundStyle(Color.textTertiary)
                        } else {
                            RemoteImage(url: s.cover, maxPixel: 500)
                        }
                    }
                    .overlay(alignment: .center) {
                        if s.isVideo {
                            Image(systemName: "play")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.navy)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.92), in: Circle())
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .hairline(radius: 12)
                Text(s.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                StoryStatusPill(status: s.status)
                if s.status == "rejected" && !s.rejectReason.isEmpty {
                    Text(s.rejectReason)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(canOpen ? "Opens it" : "")
    }

    // MARK: Saved

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Saved", count: store.saved.count)
            if !store.savedLoaded {
                ProgressView().frame(maxWidth: .infinity)
            } else if store.saved.isEmpty {
                EmptyNote(title: "Nothing saved yet", detail: "Tap the bookmark on an article or post to keep it here.",
                          systemImage: "bookmark")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.saved.enumerated()), id: \.element.id) { i, item in
                        if i > 0 { Divider().overlay(Color.hairline) }
                        savedRow(item)
                    }
                }
                .padding(.horizontal, 12)
                .hairline(radius: 14)
            }
        }
    }

    private func savedRow(_ item: SavedPostItem) -> some View {
        let canOpen = feed.post(item.id) != nil
        let livePost = feed.post(item.id)
        let title = item.title.isEmpty ? (livePost?.title ?? "Saved post") : item.title
        let thumb = item.thumb.isEmpty ? (livePost?.cover?.cardImage ?? "") : item.thumb
        return Button {
            if canOpen { path.append(.story(item.id)) }
        } label: {
            HStack(spacing: 12) {
                Color.surface
                    .frame(width: 56, height: 56)
                    .overlay {
                        if thumb.isEmpty {
                            Image(systemName: item.isGuide ? "doc.richtext" : "photo").foregroundStyle(Color.textTertiary)
                        } else {
                            RemoteImage(url: thumb, maxPixel: 200)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(canOpen ? (item.isGuide ? "Article" : "Post") : "No longer available")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
                if canOpen {
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                Task { _ = await store.unsave(item) }
            } label: { Label("Remove from saved", systemImage: "bookmark.slash") }
        }
    }

    // MARK: rows

    /// Profile parts not rebuilt natively yet (your posts, reviews and reminders tabs; the owner's tools): the live
    /// screens inside the shell, so nothing from the website's profile is missing.
    private var shellRows: some View {
        VStack(spacing: 0) {
            rowButton("square.grid.2x2", "Posts, reviews and reminders") { path.append(.web(.profileWeb)) }
            if auth.isAdmin {
                Divider().overlay(Color.hairline)
                rowButton("checkmark.seal", "Review posts") { path.append(.web(.adminReview)) }
                Divider().overlay(Color.hairline)
                rowButton("tray", "Inbox") { path.append(.web(.adminInbox)) }
            }
        }
        .padding(.horizontal, 14)
        .hairline(radius: 14)
    }

    private func linkRows(signedIn: Bool) -> some View {
        VStack(spacing: 0) {
            rowButton("gearshape", "Settings") { path.append(.settings) }
            Divider().overlay(Color.hairline)
            rowButton("text.bubble", "Contact us") { path.append(.contact) }
            Divider().overlay(Color.hairline)
            rowButton("doc.text", "Terms", external: true) { openURL(URL(string: "https://www.yourkoshertravel.com/terms")!) }
            Divider().overlay(Color.hairline)
            rowButton("hand.raised", "Privacy", external: true) { openURL(URL(string: "https://www.yourkoshertravel.com/privacy")!) }
            if signedIn {
                Divider().overlay(Color.hairline)
                rowButton("rectangle.portrait.and.arrow.right", "Sign out", chevron: false) { auth.signOut() }
                    .accessibilityIdentifier("profile-signout")
            }
        }
        .padding(.horizontal, 14)
        .hairline(radius: 14)
    }

    private func rowButton(_ icon: String, _ label: String, external: Bool = false, chevron: Bool = true,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Color.navy).frame(width: 24)
                Text(label).foregroundStyle(Color.navy)
                Spacer()
                if chevron {
                    Image(systemName: external ? "arrow.up.right" : "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: actions

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        photoBusy = true
        defer { photoBusy = false; photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = "That photo couldn't be opened. Try a different one."
                return
            }
            let url = try await store.setProfilePhoto(data)
            auth.setLocal(photoURL: url)
        } catch {
            photoError = AuthFlows.friendly(error)
        }
    }

    private func removePhoto() async {
        photoBusy = true
        defer { photoBusy = false }
        do {
            try await store.removeProfilePhoto()
            auth.setLocal(photoURL: "")
        } catch {
            photoError = AuthFlows.friendly(error)
        }
    }

    /// QA / deep link: "tab:profile/<signin|signup|reset|settings|contact>".
    private func openLaunchRoute() {
        guard !routed, let route = LaunchRoute.current, route.hasPrefix("tab:profile/") else { return }
        routed = true
        let screen = String(route.dropFirst("tab:profile/".count))
        Task { @MainActor in
            // let the tab switch settle before presenting
            try? await Task.sleep(for: .milliseconds(700))
            switch screen {
            case "signin": signIn = .signIn
            case "signup": signIn = .signUp
            case "reset": signIn = .reset
            case "settings": path = [.settings]
            case "contact": path = [.contact]
            case "bell": if auth.isSignedIn { showBell = true }
            default: break
            }
        }
    }
}

extension SignInSheet.Mode: Identifiable {
    var id: Self { self }
}

/// In review / Live / Not approved (MyStories.tsx StatusPill), outline style.
struct StoryStatusPill: View {
    let status: String
    private var icon: String {
        switch status {
        case "pending": return "clock"
        case "rejected": return "xmark"
        default: return "checkmark"
        }
    }
    private var text: String {
        switch status {
        case "pending": return "In review"
        case "rejected": return "Not approved"
        default: return "Live"
        }
    }

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(status == "rejected" ? Color.alert : Color.navy)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .hairline(radius: 6)
    }
}
