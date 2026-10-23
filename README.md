# Your Kosher Travel: native iOS app

The SwiftUI source of the Your Kosher Travel iPhone app (https://www.yourkoshertravel.com). The app itself lives in [`ios-native/`](ios-native/README.md).

- Every push to `main` or `ios-feature/**` runs the **iOS SwiftUI** workflow: a simulator build (no signing). Put `[shots]` in the commit message to also take screenshots; they are published to the branch `ios-qa/<branch>`.
- No keys or passwords are kept in this repository. The Firebase config (`GoogleService-Info.plist`) is written at build time from the repository secret `GOOGLE_SERVICE_INFO_PLIST_BASE64`. The Firebase web API key that appears in the code is the same public key the website uses; access is controlled by Firestore security rules.
