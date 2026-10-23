import Foundation
import Observation

private struct ParkFile: Decodable {
    let state: [String: [StatePark]]
    let national: [String: [NationalPark]]
    let tribal: [String: [NationalPark]]
}

/// The website's parks data (Resources/parks.json), read the first time a park view or query needs it, never at launch
/// (the website also loads its parks chunk only when a state page opens). Lookups follow the website's own functions.
@MainActor
@Observable
final class ParkStore {
    static let shared = ParkStore()

    private(set) var isLoaded = false
    private(set) var loadFailed = false

    @ObservationIgnored private var stateDB: [String: [StatePark]] = [:]
    @ObservationIgnored private var nationalDB: [String: [NationalPark]] = [:]
    @ObservationIgnored private var tribalDB: [String: [NationalPark]] = [:]
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var activityCache: [String: [ParkActivity]] = [:]

    private init() {}

    /// Reads parks.json off the main thread. Safe to call from every view's `.task`; only the first call reads.
    func load() async {
        if isLoaded { return }
        if let loading { await loading.value; return }
        let task = Task { @MainActor in
            let file = await Task.detached(priority: .userInitiated) { () -> ParkFile? in
                guard let url = Bundle.main.url(forResource: "parks", withExtension: "json"),
                      let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                    print("[KT] parks.json is missing from the app bundle")
                    return nil
                }
                do {
                    return try JSONDecoder().decode(ParkFile.self, from: data)
                } catch {
                    print("[KT] parks.json did not decode: \(error)")
                    return nil
                }
            }.value
            if let file {
                self.stateDB = file.state
                self.nationalDB = file.national
                self.tribalDB = file.tribal
                self.loadFailed = false
                self.isLoaded = true
            } else {
                self.loadFailed = true
            }
            self.loading = nil
        }
        loading = task
        await task.value
    }

    // MARK: keys (the website's normalising)

    /// `stateName.toLowerCase().trim()`
    static func stateKey(_ state: String) -> String {
        state.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// web parkStateKey: the D.C. state page ("Washington DC") reads the parks stored under "dc".
    static func nationalKey(_ state: String) -> String {
        let s = stateKey(state)
        return (s == "washington dc" || s == "washington, d.c." || s == "district of columbia") ? "dc" : s
    }

    // MARK: queries

    /// web getStateParksForState / STATE_PARKS_DATABASE[state.toLowerCase()] (curated parks replace a region's list).
    func stateParks(in state: String) -> [StatePark] {
        let k = Self.stateKey(state)
        guard !k.isEmpty else { return [] }
        return stateDB[k] ?? []
    }

    /// web getNationalParksForState. (Every US state and DC has national sites in the data, so the website's
    /// placeholder "{State} National Park Site" never shows for a state page; it is not ported.)
    func nationalParks(in state: String) -> [NationalPark] {
        let k = Self.nationalKey(state)
        guard !k.isEmpty else { return [] }
        return nationalDB[k] ?? []
    }

    /// web getTribalAndScenicParksForState: the lower-cased name with -/_ as spaces, else its hyphenated form.
    func tribalAndScenic(in state: String) -> [NationalPark] {
        let lower = Self.stateKey(state)
        guard !lower.isEmpty else { return [] }
        let normalized = lower.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        let hyphenated = normalized.split(whereSeparator: { $0.isWhitespace }).joined(separator: "-")
        return tribalDB[normalized] ?? tribalDB[hyphenated] ?? []
    }

    func hasNationalParks(in state: String) -> Bool { !nationalParks(in: state).isEmpty }
    func hasTribalAndScenic(in state: String) -> Bool { !tribalAndScenic(in: state).isEmpty }

    /// The National Parks tab's groups, in the website's order, empty groups left out, narrowed by the chip.
    func nationalParkGroups(in state: String, filter: NationalParkFilter = .all) -> [NationalParkGroup] {
        let all = nationalParks(in: state)
        let defs: [(String, String, NationalParkFilter, (String) -> Bool)] = [
            ("parks", "National Parks", .parks, { $0 == "National Park" }),
            ("monuments", "National Monuments", .monuments, { $0 == "National Monument" }),
            ("historic", "Historical Sites & Memorials", .historic,
             { ["National Historical Park", "National Historic Site", "National Memorial"].contains($0) }),
            ("nature", "Nature & Recreation", .nature,
             { ["National Preserve", "National Seashore/Lakeshore", "National Recreation Area", "Other"].contains($0) }),
            ("trails", "Historic Trails", .trails, { $0 == "National Trails" }),
        ]
        return defs.map { d in
            NationalParkGroup(id: d.0, title: d.1, filter: d.2, parks: all.filter { d.3($0.designation) })
        }.filter { !$0.parks.isEmpty && (filter == .all || filter == $0.filter) }
    }

    /// web getParkActivitiesForState: state park trails, then each national site's scenic drives and trails, unique by
    /// name, at most 12. (The website's invented fallback activities were removed in Oct 2026, so nothing is added.)
    func activities(in state: String) -> [ParkActivity] {
        let normalized = Self.stateKey(state)
        guard !normalized.isEmpty else { return [] }
        if let hit = activityCache[state] { return hit }
        let stateParks = stateDB[normalized] ?? []
        let national = nationalDB[Self.nationalKey(normalized)] ?? []
        var out: [ParkActivity] = []
        var seen = Set<String>()

        func add(_ name: String, kind: String, parkId: String, parkName: String, image: String, desc: String, duration: String,
                 category: String, badge: String) {
            let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !seen.contains(key), out.count < 12 else { return }
            seen.insert(key)
            out.append(ParkActivity(id: "\(parkId)-\(kind)-\(out.count)", name: name, category: category, badge: badge,
                                    parkName: parkName, state: state, image: image, description: desc, duration: duration))
        }

        for park in stateParks {
            for t in park.hikingTrails {
                add(t.name, kind: "trail", parkId: park.id, parkName: park.name, image: park.image, desc: t.description,
                    duration: t.length, category: "Hiking & Walking", badge: "Hiking & Trails")
            }
        }
        for park in national {
            for d in park.scenicDrives {
                add(d.name, kind: "drive", parkId: park.id, parkName: park.name, image: park.image, desc: d.description,
                    duration: d.length.isEmpty ? "Scenic Route" : d.length, category: "Scenic Drives", badge: "Scenic Drive")
            }
            for t in park.hikingTrails {
                add(t.name, kind: "trail", parkId: park.id, parkName: park.name, image: park.image, desc: t.description,
                    duration: t.length, category: "Hiking & Walking", badge: "Hiking & Trails")
            }
        }
        if isLoaded { activityCache[state] = out }
        return out
    }
}
