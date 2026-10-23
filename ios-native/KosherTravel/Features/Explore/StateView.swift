import SwiftUI

/// A state page (the native rebuild lives in Features/StatePage/StatePageView.swift).
struct StateView: View {
    @Environment(ExploreStore.self) private var store
    let stateId: String

    var body: some View {
        if let state = store.state(stateId) {
            StatePageView(state: state)
        } else {
            ContentUnavailableView("Not found", systemImage: "map", description: Text("This state is not in the app yet."))
        }
    }
}

/// A Caribbean / Central America island or country page (Features/StatePage/CountryPageView.swift).
struct CountryView: View {
    @Environment(ExploreStore.self) private var store
    let countryId: String

    var body: some View {
        if let c = store.country(countryId) {
            CountryPageView(country: c)
        } else {
            ContentUnavailableView("Not found", systemImage: "map", description: Text("This place is not in the app yet."))
        }
    }
}
