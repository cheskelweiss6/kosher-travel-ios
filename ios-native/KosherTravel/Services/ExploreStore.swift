import Foundation
import Observation

/// The built-in travel data (exported from the website's data files into explore.json).
@Observable
final class ExploreStore {
    private(set) var data: ExploreData?
    private(set) var loadError: String?

    init() { load() }

    func load() {
        guard let url = Bundle.main.url(forResource: "explore", withExtension: "json") else {
            loadError = "Travel data is missing from this build."
            return
        }
        do {
            data = try JSONDecoder().decode(ExploreData.self, from: Data(contentsOf: url))
        } catch {
            loadError = "Travel data could not be read."
        }
    }

    var states: [USState] { data?.states ?? [] }
    var caribbean: [CaribbeanCountry] { data?.caribbean ?? [] }

    func state(_ id: String) -> USState? { states.first { $0.id == id } }
    func country(_ id: String) -> CaribbeanCountry? { caribbean.first { $0.id == id } }

    private func same(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }

    func areas(in state: USState) -> [AreaCard] {
        guard let data else { return [] }
        return state.cities.map { (name: String) -> AreaCard in
            if let c = data.cities.first(where: { same($0.state, state.name) && same($0.name, name) }) {
                return AreaCard(id: "us:\(c.id)", name: c.name, subtitle: "\(state.name), United States", photo: c.photo,
                                hasGrocery: !c.groceries.isEmpty, hasChabad: !c.chabad.isEmpty, hasPage: true)
            }
            if let d = data.destinations.first(where: { same($0.state, state.name) && same($0.name, name) }) {
                return AreaCard(id: "dest:\(d.id)", name: d.name, subtitle: "\(state.name), United States", photo: d.image,
                                hasGrocery: !d.groceries.isEmpty, hasChabad: !d.chabad.isEmpty, hasPage: true)
            }
            return AreaCard(id: "name:\(state.id):\(name)", name: name, subtitle: "\(state.name), United States", photo: "",
                            hasGrocery: false, hasChabad: false, hasPage: false)
        }
    }

    func areas(in country: CaribbeanCountry) -> [AreaCard] {
        guard let data else { return [] }
        let inCountry = data.destinations.filter { $0.region == "Caribbean" && same($0.country, country.name) }
        var out: [AreaCard] = []
        var used = Set<String>()
        func card(_ d: Destination) -> AreaCard {
            AreaCard(id: "dest:\(d.id)", name: d.name, subtitle: country.name, photo: d.image,
                     hasGrocery: !d.groceries.isEmpty, hasChabad: !d.chabad.isEmpty, hasPage: true)
        }
        for name in country.cities {
            if let d = inCountry.first(where: { same($0.name, name) }) { out.append(card(d)); used.insert(d.id) }
        }
        for d in inCountry where !used.contains(d.id) { out.append(card(d)); used.insert(d.id) }
        return out
    }

    func detail(for key: String) -> AreaDetail? {
        guard let data else { return nil }
        func sections(chabad: [Venue], shuls: [Venue], restaurants: [Venue], groceries: [Venue], hotels: [Venue], attractions: [Venue]) -> [AreaSection] {
            [
                AreaSection(title: "Kosher Restaurants", systemImage: "fork.knife", venues: restaurants),
                AreaSection(title: "Kosher Grocery", systemImage: "cart", venues: groceries),
                AreaSection(title: "Chabad", systemImage: "house", venues: chabad),
                AreaSection(title: "Shuls", systemImage: "building.columns", venues: shuls),
                AreaSection(title: "Hotels", systemImage: "bed.double", venues: hotels),
                AreaSection(title: "Things to Do", systemImage: "binoculars", venues: attractions),
            ].filter { !$0.venues.isEmpty }
        }
        if key.hasPrefix("us:"), let c = data.cities.first(where: { "us:\($0.id)" == key }) {
            return AreaDetail(name: c.name, subtitle: "\(c.state), United States", photo: c.photo, description: c.description,
                              airport: c.airport, airportDistance: c.airportDistance, weather: c.weather,
                              sections: sections(chabad: c.chabad, shuls: c.shuls, restaurants: c.restaurants,
                                                 groceries: c.groceries, hotels: c.hotels, attractions: c.attractions))
        }
        if key.hasPrefix("dest:"), let d = data.destinations.first(where: { "dest:\($0.id)" == key }) {
            let sub = d.state.isEmpty ? d.country : "\(d.state), \(d.country)"
            return AreaDetail(name: d.name, subtitle: sub, photo: d.image, description: d.description,
                              airport: d.airport, airportDistance: d.airportDistance, weather: d.weather,
                              sections: sections(chabad: d.chabad, shuls: d.shuls, restaurants: d.restaurants,
                                                 groceries: d.groceries, hotels: d.hotels, attractions: d.attractions))
        }
        return nil
    }
}
