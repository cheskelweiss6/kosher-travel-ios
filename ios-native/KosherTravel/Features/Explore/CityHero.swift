import SwiftUI
import UIKit

/// The website keeps the city hero (photo, region pill, state, name, travel chip, description) at the top of every
/// city sub-page (App.tsx 10000-10115 are not gated by the sub-page). AreaView hands its hero to the sub-pages through
/// the environment; each sub-page puts `CitySubPageHero()` first in its scroll content, full width.
private struct CityHeroKey: EnvironmentKey {
    static let defaultValue: AnyView? = nil
}

extension EnvironmentValues {
    var cityHero: AnyView? {
        get { self[CityHeroKey.self] }
        set { self[CityHeroKey.self] = newValue }
    }
}

/// The city's hero, when this view sits on a city sub-page (nothing elsewhere).
struct CitySubPageHero: View {
    @Environment(\.cityHero) private var hero

    var body: some View {
        if let hero { hero }
    }
}


/// The website's row on top of the city hero (App.tsx 10026-10085): the glass Back pill with the city name (and
/// "/ Restaurants" on a sub-page), then Save and Plan Trip on the right. The iOS bar is hidden on these pages, so this
/// row is the only back control; the edge swipe still goes back (PopGestureEnabler).
struct CityHeroBar: View {
    let cityName: String
    let destId: String
    var crumb: String = ""

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var confirmUnsave = false
    private let bucket = BucketList.shared

    var body: some View {
        let saved = bucket.contains(destId)
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    // The app's back arrow (website BackArrow = the iOS chevron in the app).
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                    Text(cityName).lineLimit(1)
                    if !crumb.isEmpty {
                        Text("/").font(.caption.weight(.semibold)).foregroundStyle(Color.white.opacity(0.6))
                        Text(crumb).lineLimit(1).foregroundStyle(Color.white.opacity(0.88))
                    }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .glassPill(filled: false)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(crumb.isEmpty ? "Back" : "Back to \(cityName)")

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Button {
                    // Cheskel's rule (Oct 23 9:20): every removal asks first, in red.
                    if saved { confirmUnsave = true } else { bucket.toggle(destId) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart").font(.system(size: 13, weight: .semibold))
                        // Website: the words show from the "sm" width up; a phone shows the heart alone.
                        if sizeClass == .regular { Text(saved ? "Saved" : "Save") }
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(minWidth: 32, minHeight: 32)
                    .glassPill(filled: saved)
                    .animation(Motion.select, value: saved)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(Motion.Haptic.success, trigger: saved)
                .accessibilityLabel(saved ? "Saved. Remove \(cityName) from saved places" : "Save \(cityName)")

                Button {
                    // Website: setWizardCity(name) + the planner tab, i.e. "Plan a trip" with the city in "Where to?".
                    ShellRouter.shared.plannerTripCity = cityName
                    ShellRouter.shared.open(tab: "planner")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: 13, weight: .semibold))
                        Text(sizeClass == .regular ? "Plan Trip" : "Plan")
                    }
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Plan a trip to \(cityName)")
            }
        }
        .confirmationDialog("Remove \(cityName) from your saved places?", isPresented: $confirmUnsave,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) { bucket.toggle(destId) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private extension View {
    /// Website kt-glass-pill: black 45% over a blur with a 15% white hairline; navy when the city is saved.
    @ViewBuilder func glassPill(filled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if filled {
            self.background(Color.navy, in: shape)
        } else {
            self.background(Color.black.opacity(0.45), in: shape)
                .background(Material.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .environment(\.colorScheme, .dark)
        }
    }
}

/// Keeps the edge swipe back working on pages that hide the iOS navigation bar.
struct PopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            install()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            install()
        }
        private func install() {
            guard let nav = navigationController, let pop = nav.interactivePopGestureRecognizer else { return }
            if !(pop.delegate is PopGestureDelegate) {
                let d = PopGestureDelegate(nav: nav)
                objc_setAssociatedObject(nav, &PopGestureDelegate.key, d, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                pop.delegate = d
            }
            pop.isEnabled = true
        }
    }
}

final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static var key: UInt8 = 0
    private weak var nav: UINavigationController?
    init(nav: UINavigationController) { self.nav = nav }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav else { return false }
        return nav.viewControllers.count > 1 && nav.transitionCoordinator == nil
    }
}
