import SwiftUI

/// A short message at the top of the screen (the web's success / error toasts), shown by RootTabView.
struct ShellToast: Identifiable, Equatable {
    struct Action {
        let label: String
        let run: @MainActor () -> Void
    }
    let id = UUID()
    let text: String
    var action: Action? = nil
    static func == (a: ShellToast, b: ShellToast) -> Bool { a.id == b.id }
}

extension ShellRouter {
    @MainActor
    func showToast(_ text: String, seconds: Double = 2.6, action: ShellToast.Action? = nil) {
        let t = ShellToast(text: text, action: action)
        toast = t
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if self.toast?.id == t.id { self.toast = nil }
        }
    }
}

struct ShellToastView: View {
    let toast: ShellToast
    var body: some View {
        HStack(spacing: 6) {
            Text(toast.text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.navy)
                .multilineTextAlignment(.center)
            if let action = toast.action {
                Text("·").foregroundStyle(Color.textTertiary)
                Button(action.label) { action.run() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .underline()
            }
        }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .glassCapsule()
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// The app's error screen: what went wrong in plain words and a Retry button (never a blank screen).
struct ShellErrorView: View {
    var title = "This page didn't load"
    var message = "Check your connection and try again."
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.navy)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.navy)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Retry").font(.body.weight(.semibold)).padding(.horizontal, 22).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.navy)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

extension View {
    /// Liquid Glass on iOS 26 (Cheskel, Oct 23), a light material before it.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func glassRounded(_ radius: CGFloat = 16) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
}
