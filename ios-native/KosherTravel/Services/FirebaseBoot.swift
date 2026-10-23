import Foundation
import FirebaseCore

/// Configures Firebase exactly once, before anything touches it (stores are created before the app delegate runs).
enum FirebaseBoot {
    static let isConfigured: Bool = {
        if FirebaseApp.app() == nil,
           Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        return FirebaseApp.app() != nil
    }()
}
