import SwiftUI
import UIKit

/// THE motion system for the whole app (Cheskel, Oct 24 2026: "one motion system, one place").
/// Every animation timing, spring, transition, press effect and haptic in the app comes from here; screens never write
/// their own durations or springs. Documented in PRODUCT_STATUS.md ("Motion system").
///
/// Rules
/// - Restraint: motion only shows what changed, gives feedback, or keeps your place. No loops, no confetti.
/// - Never in the way: animations never delay an action, block a tap or change navigation. Taps fire at once; the
///   animation runs beside them and can be interrupted at any moment (springs pick up from where they are).
/// - Native first: system navigation push/pop, swipe-back, sheets and tab switching are left exactly as iOS does them.
/// - Reduce Motion (Settings > Accessibility > Motion): movement (slides, scale, springs, scrolling) becomes a short
///   fade or an instant change. Nothing is ever communicated by motion alone.
enum Motion {

    // MARK: Durations (seconds)
    /// Press-down feedback on a card or button: starts the instant a finger lands.
    static let pressDuration: Double = 0.12
    /// Fades and small state changes (a chip turning navy, a photo fading in, a label appearing).
    static let quick: Double = 0.2
    /// Expanding / collapsing a section, a toast sliding in, a map camera move, scrolling to a section.
    static let standard: Double = 0.3
    /// Content appearing for the first time on a screen (cards rising into place).
    static let gentle: Double = 0.35

    // MARK: Press feedback
    /// How far a pressed card shrinks (subtle: 3%).
    static let pressScale: CGFloat = 0.97
    /// How far a pressed big card shrinks (it carries a heart / save button on top, so it moves less).
    static let pressScaleLarge: CGFloat = 0.985
    /// How much a pressed card dims.
    static let pressOpacity: Double = 0.88
    /// The distance first-appearing cards rise (points).
    static let appearOffset: CGFloat = 10

    // MARK: Reduce Motion
    /// True when the person turned on Reduce Motion. Read live, so the switch applies without relaunching.
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }

    // MARK: Animations
    /// Small visual state changes: a selected chip or tab, a filled heart, a photo or label fading in. (A fade, so it
    /// is the same with Reduce Motion.)
    static var fade: Animation { .easeOut(duration: quick) }
    /// Selection moving between options (tabs, filter chips, a highlighted card).
    static var select: Animation { reduceMotion ? fade : .snappy(duration: quick) }
    /// Expanding / collapsing content, showing / hiding a section, a toast or banner coming in.
    static var expand: Animation { reduceMotion ? fade : .snappy(duration: standard) }
    /// Paging photos, zooming a photo, a confirmation label appearing after a real success.
    static var move: Animation { reduceMotion ? fade : .spring(response: 0.35, dampingFraction: 0.86) }
    /// Press-down / release of a card or button.
    static var press: Animation { reduceMotion ? .easeOut(duration: pressDuration) : .spring(response: 0.22, dampingFraction: 0.78) }
    /// Content appearing for the first time (cards rising into place once, never on every scroll).
    static var appear: Animation { .easeOut(duration: gentle) }
    /// Loading spinner -> content, error -> retry: a crossfade, never a delay (content shows the moment it is ready).
    static var content: Animation { .easeOut(duration: quick) }
    /// Scrolling to a section or the newest message. nil (an instant jump) with Reduce Motion.
    static var scroll: Animation? { reduceMotion ? nil : .smooth(duration: standard) }
    /// Moving a map camera (the map stays still with Reduce Motion: nil = jump straight there).
    static var camera: Animation? { reduceMotion ? nil : .easeInOut(duration: standard) }

    // MARK: Transitions
    /// A banner / toast / note coming in from an edge (a plain fade with Reduce Motion).
    static func slide(_ edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
    /// Content replacing a spinner or placeholder.
    static var reveal: AnyTransition { .opacity }

    // MARK: Haptics (restrained: never on every tap)
    /// The only haptics the app plays, and when:
    enum Haptic {
        /// Something was really saved / sent / completed (save, favorite, add to trip, post a comment, AI answer done,
        /// signed in). Only after the operation actually succeeded.
        static let success: SensoryFeedback = .success
        /// A request really failed (shown together with the error text).
        static let error: SensoryFeedback = .error
        /// The selection changed: a tab, a filter chip, a star rating, a photo page, a toggle-like choice.
        static let selection: SensoryFeedback = .selection
        /// A light tap for a meaningful action starting (like, send a message, open the composer).
        static let tap: SensoryFeedback = .impact(weight: .light)
    }
}

// MARK: - Press feedback

/// Cards, tiles and big buttons: shrink a little and dim while the finger is down, spring back on release.
/// The button's action fires exactly as before (on release); the effect never delays it or changes the tap area.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = Motion.pressScale

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, scale: scale)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyleConfiguration
        let scale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                // Reduce Motion: no shrinking, just the dim.
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
                .opacity(configuration.isPressed ? Motion.pressOpacity : 1)
                .animation(Motion.press, value: configuration.isPressed)
        }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Cards, tiles and big buttons (see PressableButtonStyle).
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    /// Big cards that carry a save / heart button on top: moves less so the overlay stays aligned.
    static var pressableLarge: PressableButtonStyle { PressableButtonStyle(scale: Motion.pressScaleLarge) }
}

// MARK: - First appearance

extension View {
    /// Rises and fades in once, the first time the view appears (not again on scroll back). Reduce Motion: no rise.
    func motionAppear(_ appeared: Bool) -> some View {
        self
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared || Motion.reduceMotion ? 0 : Motion.appearOffset)
    }
}
