import SwiftUI

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
