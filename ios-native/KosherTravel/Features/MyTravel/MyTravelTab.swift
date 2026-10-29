import SwiftUI

/// My Travel (upcoming trips, bucket list, saved posts, past trips, Travel Map, badges, shared itineraries) is not
/// rebuilt natively yet, so the shell shows the live screen inside the native tab (parity checklist phase 7).
/// The page is loaded in the background at launch and kept alive (MyTravelWarm.swift), so the tab opens instantly.
struct MyTravelTab: View {
    var body: some View {
        NavigationStack {
            WarmWebScreen(page: .myTravel, tab: .myTravel)
                .toolbar {
                    // Web: the header's account corner sits on every tab.
                    ToolbarItem(placement: .topBarTrailing) { AccountToolbarButtons() }
                }
        }
    }
}
