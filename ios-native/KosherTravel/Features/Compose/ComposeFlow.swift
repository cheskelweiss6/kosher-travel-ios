import SwiftUI
import WebKit

// MARK: - Entry point

extension View {
    /// The create-post flow: a native chooser sheet (Article / Inspiration) that opens the composer straight at the
    /// chosen kind, full screen. `city` / `region` preset the place, as on the website's city and state pages.
    func composeFlow(isPresented: Binding<Bool>, city: String? = nil, region: String? = nil) -> some View {
        sheet(isPresented: isPresented) {
            ComposeChooserSheet(city: city, region: region)
        }
    }
}

// MARK: - Chooser sheet

/// Cheskel, Oct 23 2026: "Let's make this more attractive and more modern". Two large cards instead of list rows;
/// the words are the website's own.
struct ComposeChooserSheet: View {
    var city: String?
    var region: String?
    @Environment(\.dismiss) private var dismiss
    @State private var route: WebRoute?
    @State private var tapped = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Share")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.navy)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.navy)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .glassCircleIfAvailable()
                .accessibilityLabel("Close")
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.top, 14)

            Text("What would you like to share?")
                .font(.system(size: 15))
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 20)
                .padding(.top, 2)

            HStack(spacing: 12) {
                ComposeKindCard(icon: "book.pages", title: "Article", badge: "Most helpful",
                                line: "Your trip day by day, with photos") { open("guide") }
                    .accessibilityIdentifier("share-article")
                ComposeKindCard(icon: "camera", title: "Inspiration", badge: nil,
                                line: "One place, a photo or video") { open("quick") }
                    .accessibilityIdentifier("share-inspiration")
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)

            Spacer(minLength: 0)
        }
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .sensoryFeedback(Motion.Haptic.tap, trigger: tapped)
        .fullScreenCover(item: $route, onDismiss: afterComposer) { r in
            NavigationStack { WebScreen(route: r, fullScreen: true) }
        }
        .task { await ComposeDone.clear() }
    }

    private func open(_ kind: String) {
        tapped += 1
        route = .compose(as: kind, city: city, region: region)
    }

    /// Back from step 1 lands here again; after a post (or "Keep using the app" while it sends) the sheet closes too.
    private func afterComposer() {
        Task { @MainActor in
            if await ComposeDone.take() { dismiss() }
        }
    }
}

/// One large choice card: an outline icon on a navy disc, the title, an optional badge and one line.
private struct ComposeKindCard: View {
    let icon: String
    let title: String
    let badge: String?
    let line: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.navy))
                Spacer(minLength: 14)
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.navy)
                if let badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.navy)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.navy.opacity(0.08)))
                        .padding(.top, 5)
                }
                Text(line)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color.navy.opacity(0.035)))
            .hairline(radius: 26)
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(ComposePressStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct ComposePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduceMotion ? Motion.pressScale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

private extension View {
    @ViewBuilder
    func glassCircleIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: Circle())
        } else {
            self.background(Circle().fill(Color.navy.opacity(0.06)))
        }
    }
}

// MARK: - "Posted" signal from the composer page

/// The composer page sets a short-lived cookie when a post starts sending (ComposeSkin); the chooser reads it once.
enum ComposeDone {
    @MainActor
    static func take() async -> Bool {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let all = await store.allCookies()
        let hits = all.filter { $0.name == ComposeSkin.doneCookie }
        for c in hits { await store.deleteCookie(c) }
        return !hits.isEmpty
    }

    @MainActor
    static func clear() async { _ = await take() }
}
