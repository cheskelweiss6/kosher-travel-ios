import SwiftUI
import Observation

/// App-wide requests that any screen (native or embedded) can make: switch tab, ask for sign-in, hand the AI
/// Planner a question. RootTabView owns the tab selection and the sign-in sheet.
@Observable
final class ShellRouter {
    static let shared = ShellRouter()

    var selectedTab: AppTab = .explore
    /// Set to show the native sign-in sheet from anywhere (an embedded screen asks for it too).
    var signIn: SignInSheet.Mode?
    /// A question the AI Planner should send when it next appears (set together with selectedTab = .planner).
    var plannerPrompt: String?
    /// The toast on screen (set through showToast).
    var toast: ShellToast?

    func open(tab name: String, prompt: String? = nil) {
        switch name {
        case "planner": selectedTab = .planner
        case "mytravel", "travelmap": selectedTab = .myTravel
        case "stories": selectedTab = .stories
        case "profile": selectedTab = .profile
        default: selectedTab = .explore
        }
        if let prompt, !prompt.isEmpty { plannerPrompt = prompt }
    }
}
