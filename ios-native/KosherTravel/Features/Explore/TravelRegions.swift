import Foundation

/// The app's travel regions (Cheskel, Oct 23 2026: "United States region, just say United States. Remove the word North
/// America. The Caribbean: whichever countries of the Caribbean, put Caribbean. Other countries that are in other places,
/// create another region for everything in a region."). The same table as the website's src/regions.ts.
///
/// The bundled data keeps its old `region` field (Mexico and Central America were filed under "Caribbean", the United States
/// under "North America") for the code that keys on it; the region a person SEES is read from the country here.
enum TravelRegions {
    static let unitedStates = "United States"
    static let caribbean = "Caribbean"
    static let mexicoCentralAmerica = "Mexico & Central America"

    /// Display order (only regions with places are shown).
    static let order = [unitedStates, "Canada", caribbean, mexicoCentralAmerica, "South America", "Europe", "Africa", "Asia",
                        "Oceania", "Middle East"]

    static func key(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
        return folded.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : " " }.joined()
            .split(separator: " ").joined(separator: " ")
    }

    private static let table: [String: String] = {
        var t: [String: String] = [:]
        func put(_ region: String, _ names: [String]) { for n in names { t[TravelRegions.key(n)] = region } }
        put(TravelRegions.unitedStates, ["United States", "United States of America", "USA", "US", "U.S.", "U.S.A.", "America"])
        put("Canada", ["Canada"])
        // Bermuda is in the Atlantic, but travelers and the app have always listed it with the islands
        put(TravelRegions.caribbean, ["Anguilla", "Antigua and Barbuda", "Antigua", "Aruba", "Bahamas", "The Bahamas", "Barbados", "Bermuda",
                        "Bonaire", "British Virgin Islands", "BVI", "Cayman Islands", "Grand Cayman", "Cuba", "Curacao", "Dominica",
                        "Dominican Republic", "Punta Cana", "Grenada", "Guadeloupe", "Haiti", "Jamaica", "Martinique", "Montserrat",
                        "Puerto Rico", "Saba", "Saint Barthelemy", "St Barts", "St Barths", "Saint Barts", "Saint Kitts and Nevis",
                        "St Kitts and Nevis", "Saint Lucia", "St Lucia", "Saint Martin", "St Martin", "Sint Maarten", "St Maarten",
                        "Saint Vincent and the Grenadines", "St Vincent and the Grenadines", "Sint Eustatius", "Statia",
                        "Trinidad and Tobago", "Turks and Caicos", "Turks and Caicos Islands", "US Virgin Islands",
                        "U.S. Virgin Islands", "USVI", "Virgin Islands", "St Thomas", "St John", "St Croix"])
        put(TravelRegions.mexicoCentralAmerica, ["Mexico", "Belize", "Guatemala", "Honduras", "El Salvador", "Nicaragua", "Costa Rica", "Panama"])
        put("South America", ["Argentina", "Bolivia", "Brazil", "Chile", "Colombia", "Ecuador", "Guyana", "Paraguay", "Peru",
                              "Suriname", "Uruguay", "Venezuela", "French Guiana"])
        put("Europe", ["Albania", "Andorra", "Austria", "Belarus", "Belgium", "Bosnia and Herzegovina", "Bulgaria", "Croatia",
                       "Cyprus", "Czech Republic", "Czechia", "Denmark", "England", "Estonia", "Finland", "France", "Germany",
                       "Gibraltar", "Greece", "Hungary", "Iceland", "Ireland", "Italy", "Latvia", "Liechtenstein", "Lithuania",
                       "Luxembourg", "Malta", "Moldova", "Monaco", "Montenegro", "Netherlands", "Holland", "North Macedonia",
                       "Norway", "Poland", "Portugal", "Romania", "Russia", "San Marino", "Scotland", "Serbia", "Slovakia",
                       "Slovenia", "Spain", "Sweden", "Switzerland", "Ukraine", "United Kingdom", "UK", "Great Britain", "Wales",
                       "Northern Ireland", "Vatican City"])
        put("Africa", ["South Africa", "Morocco", "Egypt", "Tunisia", "Kenya", "Tanzania", "Ethiopia", "Namibia", "Botswana",
                       "Zimbabwe", "Zambia", "Mauritius", "Seychelles", "Nigeria", "Ghana", "Rwanda", "Uganda", "Madagascar"])
        put("Asia", ["China", "Hong Kong", "Japan", "South Korea", "Korea", "Taiwan", "Thailand", "Vietnam", "Cambodia", "Laos",
                     "Myanmar", "Malaysia", "Singapore", "Indonesia", "Bali", "Philippines", "India", "Nepal", "Sri Lanka",
                     "Maldives", "Mongolia", "Kazakhstan", "Uzbekistan", "Armenia", "Azerbaijan"])
        put("Oceania", ["Australia", "New Zealand", "Fiji", "French Polynesia", "Tahiti", "Bora Bora", "Samoa", "Tonga", "Vanuatu",
                        "Papua New Guinea", "Guam", "Palau"])
        put("Middle East", ["United Arab Emirates", "UAE", "Dubai", "Abu Dhabi", "Bahrain", "Qatar", "Oman", "Jordan",
                            "Saudi Arabia", "Kuwait", "Turkey", "Turkiye", "Lebanon"])
        return t
    }()

    /// The region a country belongs to ("" when the country is not in the table).
    static func region(country: String) -> String { table[key(country)] ?? "" }

    /// The region to show for a place: its country's region; else its stored region with "North America" read as
    /// United States (never shows "North America").
    static func label(region: String, country: String) -> String {
        let r = self.region(country: country)
        if !r.isEmpty { return r }
        if region == "North America" { return unitedStates }
        if region == "Central America" { return mexicoCentralAmerica }
        return region
    }

    /// Is a destination on this region page? The United States page's internal region stays "North America".
    static func contains(region page: String, country: String, storedRegion: String) -> Bool {
        let r = label(region: storedRegion, country: country)
        if page == "North America" || page == unitedStates { return r == unitedStates }
        return r == page
    }
}
