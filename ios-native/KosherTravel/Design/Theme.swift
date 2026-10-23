import SwiftUI
import UIKit

extension Color {
    /// Brand navy #191e3b
    static let navy = Color(red: 25 / 255, green: 30 / 255, blue: 59 / 255)
    /// Liked heart / delete / errors only: #ED4956
    static let alert = Color(red: 237 / 255, green: 73 / 255, blue: 86 / 255)
    /// Hairline borders (slate-200)
    static let hairline = Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)
    /// Secondary text (slate-500)
    static let textSecondary = Color(red: 100 / 255, green: 116 / 255, blue: 139 / 255)
    /// Tertiary text / placeholder icons (slate-400)
    static let textTertiary = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    /// Quiet surface behind images while they load (slate-50)
    static let surface = Color(red: 248 / 255, green: 250 / 255, blue: 252 / 255)
}

enum Theme {
    static let navyUI = UIColor(red: 25 / 255, green: 30 / 255, blue: 59 / 255, alpha: 1)
    static let cardRadius: CGFloat = 16
    static let pagePadding: CGFloat = 20

    static func serif(_ size: CGFloat, weight: UIFont.Weight = .bold) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.serif) { return UIFont(descriptor: d, size: size) }
        return base
    }

    /// System bars (iOS 26 glass / iOS 17 default) with navy titles and navy buttons.
    /// The large titles were invisible on iOS 26 with a custom UINavigationBarAppearance, so only colors are set.
    static func applyAppearance() {
        let bar = UINavigationBar.appearance()
        bar.largeTitleTextAttributes = [.foregroundColor: navyUI]
        bar.titleTextAttributes = [.foregroundColor: navyUI]
        bar.tintColor = navyUI
    }
}

extension Font {
    static func serifTitle(_ style: Font.TextStyle = .title3) -> Font {
        .system(style, design: .serif).weight(.bold)
    }
}

/// A 1-pixel border in the brand's hairline color.
struct HairlineBorder: ViewModifier {
    var radius: CGFloat
    @Environment(\.displayScale) private var scale
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: max(1 / scale, 0.5))
        }
    }
}

extension View {
    func hairline(radius: CGFloat = Theme.cardRadius) -> some View { modifier(HairlineBorder(radius: radius)) }
}
