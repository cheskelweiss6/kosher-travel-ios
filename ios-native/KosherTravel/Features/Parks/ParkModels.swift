import Foundation

/// One hiking trail (web hikingTrails item).
struct ParkTrail: Codable, Hashable {
    var name: String
    var difficulty: String
    var length: String
    var description: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        difficulty = (try? c.decode(String.self, forKey: .difficulty)) ?? ""
        length = (try? c.decode(String.self, forKey: .length)) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
    }
}

/// One scenic drive (web scenicDrives item; a plain string on the website is kept as the name).
struct ParkDrive: Codable, Hashable {
    var name: String
    var length: String
    var description: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        length = (try? c.decode(String.self, forKey: .length)) ?? ""
        description = (try? c.decode(String.self, forKey: .description)) ?? ""
    }

    /// The website's line: `name (length): description`.
    var line: String {
        var s = name
        if !length.isEmpty { s += " (\(length))" }
        if !description.isEmpty { s += ": \(description)" }
        return s
    }
}

struct ParkVisitorCenter: Codable, Hashable {
    var name: String
    var info: String
    var hours: String
    var phone: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        info = (try? c.decode(String.self, forKey: .info)) ?? ""
        hours = (try? c.decode(String.self, forKey: .hours)) ?? ""
        phone = (try? c.decode(String.self, forKey: .phone)) ?? ""
    }

    init() { name = ""; info = ""; hours = ""; phone = "" }
}

/// A state park (web StatePark). Missing values decode as empty.
struct StatePark: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var image: String
    var photoGallery: [String]
    var shortDescription: String
    var fullDescription: String
    var thingsToDo: [String]
    var hikingTrails: [ParkTrail]
    var campingInfo: String
    var fishingBoating: String
    var wildlife: [String]
    var visitorCenter: ParkVisitorCenter
    var hours: String
    var entranceFees: String
    var address: String
    var googleMapsLocation: String
    var officialWebsite: String
    var bestTimeToVisit: String
    var tips: [String]
    var nearbyAttractions: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decode(String.self, forKey: k)) ?? "" }
        func l(_ k: CodingKeys) -> [String] { (try? c.decode([String].self, forKey: k)) ?? [] }
        id = s(.id); name = s(.name); image = s(.image); photoGallery = l(.photoGallery)
        shortDescription = s(.shortDescription); fullDescription = s(.fullDescription); thingsToDo = l(.thingsToDo)
        hikingTrails = (try? c.decode([ParkTrail].self, forKey: .hikingTrails)) ?? []
        campingInfo = s(.campingInfo); fishingBoating = s(.fishingBoating); wildlife = l(.wildlife)
        visitorCenter = (try? c.decode(ParkVisitorCenter.self, forKey: .visitorCenter)) ?? ParkVisitorCenter()
        hours = s(.hours); entranceFees = s(.entranceFees); address = s(.address)
        googleMapsLocation = s(.googleMapsLocation); officialWebsite = s(.officialWebsite)
        bestTimeToVisit = s(.bestTimeToVisit); tips = l(.tips); nearbyAttractions = l(.nearbyAttractions)
    }

    /// The banner / gallery photos: `[image, ...photoGallery]` (empty values dropped).
    var photos: [String] { ParkPhotos.list(image, photoGallery) }
    /// Firestore review id prefix the website uses for state parks.
    var reviewPlaceId: String { "sp-\(id)" }
}

/// A national park, monument or historic site, and also a tribal / scenic landmark (web NationalPark).
struct NationalPark: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var designation: String
    var image: String
    var photoGallery: [String]
    var shortDescription: String
    var fullDescription: String
    var thingsToDo: [String]
    var hikingTrails: [ParkTrail]
    var scenicDrives: [ParkDrive]
    var visitorCenter: ParkVisitorCenter
    var rangerPrograms: [String]
    var campingInfo: String
    var wildlife: [String]
    var bestViewpoints: [String]
    var entranceFees: String
    var hours: String
    var address: String
    var googleMapsLocation: String
    var officialWebsite: String
    var bestTimeToVisit: String
    var accessibilityInfo: String
    var travelTips: [String]
    var nearbyAttractions: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decode(String.self, forKey: k)) ?? "" }
        func l(_ k: CodingKeys) -> [String] { (try? c.decode([String].self, forKey: k)) ?? [] }
        id = s(.id); name = s(.name); designation = s(.designation); image = s(.image); photoGallery = l(.photoGallery)
        shortDescription = s(.shortDescription); fullDescription = s(.fullDescription); thingsToDo = l(.thingsToDo)
        hikingTrails = (try? c.decode([ParkTrail].self, forKey: .hikingTrails)) ?? []
        scenicDrives = (try? c.decode([ParkDrive].self, forKey: .scenicDrives)) ?? []
        visitorCenter = (try? c.decode(ParkVisitorCenter.self, forKey: .visitorCenter)) ?? ParkVisitorCenter()
        rangerPrograms = l(.rangerPrograms); campingInfo = s(.campingInfo); wildlife = l(.wildlife)
        bestViewpoints = l(.bestViewpoints); entranceFees = s(.entranceFees); hours = s(.hours); address = s(.address)
        googleMapsLocation = s(.googleMapsLocation); officialWebsite = s(.officialWebsite)
        bestTimeToVisit = s(.bestTimeToVisit); accessibilityInfo = s(.accessibilityInfo)
        travelTips = l(.travelTips); nearbyAttractions = l(.nearbyAttractions)
    }

    var photos: [String] { ParkPhotos.list(image, photoGallery) }
    /// Firestore review id prefix the website uses for national (and tribal / scenic) parks.
    var reviewPlaceId: String { "np-\(id)" }
}

/// One card of "Park Activities & Outdoor Adventures" (web ParkActivity).
struct ParkActivity: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String      // "Hiking & Walking" / "Scenic Drives"
    let badge: String         // the website's badge without its emoji: "Hiking & Trails" / "Scenic Drive"
    let parkName: String
    let state: String
    let image: String
    let description: String
    let duration: String
}

/// The National Parks tab's filter chips (web: All, Parks, Monuments, Historic, Nature, Trails).
enum NationalParkFilter: String, CaseIterable, Identifiable, Hashable {
    case all = "All", parks = "Parks", monuments = "Monuments", historic = "Historic", nature = "Nature", trails = "Trails"
    var id: String { rawValue }
}

/// One group on the National Parks tab.
struct NationalParkGroup: Identifiable, Hashable {
    let id: String           // parks / monuments / historic / nature / trails
    let title: String        // "National Parks", "National Monuments", ...
    let filter: NationalParkFilter
    let parks: [NationalPark]

    /// The website's "View N more …" words: the title without its first word, lower-cased.
    var moreNoun: String { title.split(separator: " ").dropFirst().joined(separator: " ").lowercased() }
}

enum ParkPhotos {
    static func list(_ image: String, _ gallery: [String]) -> [String] {
        var out: [String] = []
        for p in [image] + gallery {
            let t = p.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !out.contains(t) { out.append(t) }
        }
        return out
    }
}
