import SwiftUI
import FirebaseCore

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // The Firebase config file is added at build time (CI secret). Without it the app still reads the
        // public feed over HTTPS, so a build never breaks on a missing file.
        _ = FirebaseBoot.isConfigured
        ImagePipeline.configureCache()
        return true
    }
}

@main
struct KosherTravelApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var explore = ExploreStore()
    @State private var feed = StoryFeed()
    @State private var auth = AuthStore()

    init() {
        setvbuf(stdout, nil, _IONBF, 0)   // QA logs: print() reaches the simulator log file right away
        Theme.applyAppearance()
        print("[KT] launch route=\(LaunchRoute.current ?? "none")")
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .modifier(YahrzeitLifecycle())   // yahrzeit alerts booked on the phone (Features/Yahrzeit)
                .environment(explore)
                .environment(feed)
                .environment(auth)
                .tint(Color.navy)
                .preferredColorScheme(.light)
        }
    }
}
