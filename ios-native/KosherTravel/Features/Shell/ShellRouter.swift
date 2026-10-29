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
    /// Web setWizardCity (a city page's Plan Trip): the city the planner's trip builder starts with. The planner reads
    /// it when it appears, opens its trip builder for that city and clears it.
    var plannerTripCity: String?
    /// The toast on screen (set through showToast).
    var toast: ShellToast?
    /// The app's sign-in state (set by RootTabView), so the sign-in sheet can open over any screen.
    @ObservationIgnored var auth: AuthStore?
    /// The failure notice above the tab bar (web NoticeBar), set through notify.
    var notice: ShellNotice?
    /// A shared link to open over the current tab.
    var deepLink: DeepLinkTarget?
    /// V2-FULL-1029: what another tab's page asked the Stories tab to open (the website's stories request as JSON: the
    /// composer for a city, a post, a traveler). RootTabView hands it to the Stories page and clears it.
    var storiesRequest: String?
    /// The Profile page, opened from the header's avatar / settings button (web: the header button, not a tab;
    /// the web's tab bar has 4 tabs: Explore, AI Planner, My Travel, Stories).
    var showProfile = false
    /// Open the notifications list as soon as the Profile page appears (the header's bell).
    var profileOpensBell = false

    func open(tab name: String, prompt: String? = nil) {
        switch name {
        case "planner": selectedTab = .planner
        case "mytravel", "travelmap": selectedTab = .myTravel
        case "stories": selectedTab = .stories
        case "profile": showProfile = true
        default: selectedTab = .explore
        }
        if let prompt, !prompt.isEmpty { plannerPrompt = prompt }
    }
}
