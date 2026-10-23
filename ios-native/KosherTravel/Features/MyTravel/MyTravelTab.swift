import SwiftUI

/// My Travel (upcoming trips, bucket list, saved posts, past trips, Travel Map, badges, shared itineraries) is not
/// rebuilt natively yet, so the shell shows the live screen inside the native tab (parity checklist phase 7).
struct MyTravelTab: View {
    var body: some View {
        WebTabRoot(route: .myTravel)
    }
}
