import SwiftUI

/*
 README: Parks (NATIVE-PARKS). The website's state parks, national parks, tribal & scenic landmarks and park activities,
 with the same data, merge rules, cards and sheets as the website (App.tsx state page, StateParkDetailModal,
 NationalParkDetailModal, TrailMapModal, parkActivitiesData.ts).

 DATA (Resources/parks.json, made by ios-native/scripts/export-parks.sh from the website's TS; loaded lazily, on the
 first park view or query, never at launch):

     @MainActor ParkStore.shared                      // @Observable
         await ParkStore.shared.load()                // safe to call many times; views below call it themselves
         .isLoaded / .loadFailed
         .stateParks(in: "New York") -> [StatePark]                       // web STATE_PARKS_DATABASE[state.toLowerCase()]
         .nationalParks(in: "Washington DC") -> [NationalPark]            // web getNationalParksForState (DC -> "dc")
         .nationalParkGroups(in: state, filter: .all) -> [NationalParkGroup]  // the National Parks tab groups + chips
         .tribalAndScenic(in: "New Mexico") -> [NationalPark]             // web getTribalAndScenicParksForState
         .activities(in: state) -> [ParkActivity]                         // web getParkActivitiesForState (max 12)
         .hasNationalParks(in:) / .hasTribalAndScenic(in:)                // tab visibility, like the web's tab bar

 CITIES & AREAS TAB SECTIONS (each hides itself when empty and opens its own sheet; pass the state's display name):

     StateParksSection(stateName: "Utah") { selectTab(.stateParks) }        // "View all (N)" when more than 6
     NationalParksSection(stateName: "Utah") { selectTab(.nationalParks) }  // "View all (N)" when more than 6
     ParkActivitiesSection(stateName: "Utah")

 TAB CONTENTS (plain VStacks for the state page's ScrollView; headers, empty texts and sheets included):

     StateParksTab(stateName: "Utah")
     StateParksTab(stateName: "Utah", travelerParkCount: n) { ForEach(...) { TravelerParkCard(...) } }  // web: travelers' parks first
     NationalParksTab(stateName: "Utah")      // filter chips All / Parks / Monuments / Historic / Nature / Trails, groups, Show all
     TribalScenicTab(stateName: "Utah")

 CARDS (tap action is yours; the sections and tabs above already wire them to the sheets):

     StateParkCard(park:, stateName:, style: .section | .tab, action:)
     NationalParkCard(park:, stateName:, style: .section | .tab | .tribal, action:)
     ParkActivityCard(activity:)               // not tappable, like the web

 SHEETS (present with .sheet(item:)):

     StateParkSheet(park: StatePark)          // reviews under "sp-{id}", Trail Map
     NationalParkSheet(park: NationalPark)    // national AND tribal/scenic parks; reviews under "np-{id}"
     ParkTrailMapView(park: StatePark)        // MapKit "Interactive Trail Planner"

 Reviews use the website's Firestore placeReviews documents (placeKind "park", no destId), read with PlaceReviewService.
*/

/// The website's text rules for park cards and sheets.
enum ParkText {
    /// `address.split(',')[1]?.trim() || address.split(',')[0]?.trim() || state` (Cities & Areas park cards).
    static func secondOrFirstPart(_ address: String, state: String) -> String {
        let parts = address.components(separatedBy: ",")
        if parts.count > 1 {
            let s = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        let first = (parts.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return first.isEmpty ? state : first
    }

    /// `address.split(',')[1]?.trim() || state` (State Parks tab cards).
    static func secondPart(_ address: String, state: String) -> String {
        let parts = address.components(separatedBy: ",")
        if parts.count > 1 {
            let s = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        return state
    }

    /// `address.split(',').slice(-2).join(', ').trim()` (National Parks / Tribal tab cards and the national park header).
    static func lastTwoParts(_ address: String) -> String {
        let parts = address.components(separatedBy: ",")
        return parts.suffix(2).joined(separator: ", ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func lastTwoParts(_ address: String, state: String) -> String {
        let s = lastTwoParts(address)
        return s.isEmpty ? state : s
    }

    /// The website's emoji-free card badge for a national site on the Cities & Areas tab.
    static func sectionBadge(_ designation: String) -> String {
        if designation.contains("Monument") { return "National Monument" }
        if designation.contains("Historic") { return "Historic Site" }
        return "National Park"
    }
}

/// The image host's sized copies (web hostedSizedUrl): /c/t/ about 200 px, /c/m/ about 600 px, /c/ the original.
enum ParkImage {
    static let base = "https://kosher-travel-img.sites.tab.bot"

    static func sized(_ url: String, width: Int) -> String {
        let u = url.trimmingCharacters(in: .whitespaces)
        let prefix = base + "/"
        guard u.hasPrefix(prefix) else { return u }
        let rest = String(u.dropFirst(prefix.count))           // "wm/x.webp"
        let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "wm" || parts[0] == "venues", !parts[1].isEmpty,
              !parts[1].contains("?"), !parts[1].contains("#") else { return u }
        let size = width <= 200 ? "t/" : (width <= 600 ? "m/" : "")
        return "\(base)/c/\(size)\(parts[0])/\(parts[1])"
    }
}

/// Opens a park link the way the rest of the app does (maps through the chooser, web pages in Safari).
@MainActor
enum ParkLinks {
    static func open(_ string: String) {
        let s = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s) ?? URL(string: s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else { return }
        _ = LinkOpener.handle(url)
    }

    static func call(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel:\(digits)") else { return }
        _ = LinkOpener.handle(url)
    }
}
