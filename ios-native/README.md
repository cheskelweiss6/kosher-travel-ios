# Kosher Travel: native iOS app (SwiftUI)

A true native iPhone app (SwiftUI, iOS 17+), rebuilt screen by screen. It replaces the Capacitor app in TestFlight only once it reaches parity.

- Bundle id `com.yourkoshertravel.app`, team 46MB33SVM3. iPhone only for release (`TARGETED_DEVICE_FAMILY = 1`); the CI simulator build also runs on iPad to check the layout.
- Project: [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec in `project.yml`. `cd ios-native && xcodegen generate && open KosherTravel.xcodeproj`.
- Firebase iOS SDK through Swift Package Manager (Auth, Firestore, Storage). `GoogleService-Info.plist` is not in git: CI writes it from the repo secret `GOOGLE_SERVICE_INFO_PLIST_BASE64` (Firebase iOS app "Kosher Travel iOS"). Without it the app still reads the public feed over HTTPS.
- Built-in travel data (states, cities, listings) lives in the website's `src/*.ts` files. `sh ios-native/scripts/export-data.sh` (from the repo root) re-exports it to `KosherTravel/Resources/explore.json`.
- CI: `.github/workflows/ios-swiftui.yml` builds for the simulator on macos-26 (no signing), opens each screen on iPhone SE, iPhone 16, iPhone 16 Pro Max and an iPad, and uploads screenshots (artifact `swiftui-screenshots`; JPEGs also on branch `ios-qa/<branch>`).
- QA deep links: launch with `-ktRoute usa | caribbean | state:<id> | country:<id> | area:us:<cityId> | tab:stories`.

Design rules: white, navy #191e3b, hairline borders, SF Symbols outline icons, no emoji, no gradients, red (#ED4956) only for liked heart / delete / errors. Adaptive layout (no fixed widths), Dynamic Type, safe areas.

Plan and build order: see the plan document shared with Cheskel (screens, data model, effort).
