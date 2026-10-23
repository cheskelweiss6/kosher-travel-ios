import SwiftUI

// MARK: - Shared pieces for the state page's park tabs

/// The tab's heading (web: "font-extrabold text-sm" title, a grey line under it, then a hairline).
struct ParkTabHeader<Trailing: View>: View {
    var systemImage: String? = nil
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let systemImage { Image(systemName: systemImage).font(.subheadline) }
                        Text(title)
                    }
                    .font(.headline)
                    .foregroundStyle(Color.navy)
                    .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                trailing
            }
            Rectangle().fill(Color.hairline).frame(height: 1)
        }
    }
}

extension ParkTabHeader where Trailing == EmptyView {
    init(systemImage: String? = nil, title: String, subtitle: String) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

/// The website's empty box: white, hairline, centred bold line and a lighter line under it.
struct ParkEmptyBox: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(Color.textSecondary)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.white)
        .hairline(radius: Theme.cardRadius)
    }
}

/// Shows its content once the parks data is read; a quiet loading row before, and the website's error words if the
/// file could not be read (web parksStore notify: "Couldn't load the parks for this state. Check your connection.").
struct ParkLoadGate<Content: View>: View {
    @ViewBuilder var content: Content
    private var store: ParkStore { ParkStore.shared }

    var body: some View {
        Group {
            if store.isLoaded {
                content
            } else if store.loadFailed {
                HStack {
                    FeedStatusLine(message: "Couldn't load the parks for this state.")
                    Spacer()
                    Button("Retry") { Task { await store.load() } }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.navy)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading parks").font(.footnote).foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            }
        }
        .task { await store.load() }
    }
}

// MARK: - State Parks tab (web App.tsx 7955-8015)

/// "Official State Parks in {state}". Travelers' parks (NATIVE-TRAVELER-PLACES' TravelerParkCard) go first when given,
/// like the website; with none of either, the website's "being finalized" box.
struct StateParksTab<TravelerParks: View>: View {
    let stateName: String
    let travelerParkCount: Int
    let travelerParks: TravelerParks
    @State private var open: StatePark?
    private var store: ParkStore { ParkStore.shared }

    init(stateName: String, travelerParkCount: Int, @ViewBuilder travelerParks: () -> TravelerParks) {
        self.stateName = stateName
        self.travelerParkCount = travelerParkCount
        self.travelerParks = travelerParks()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ParkTabHeader(title: "Official State Parks in \(stateName)",
                          subtitle: "Explore stunning scenery, trails, and activities at these official state parks.")
            if travelerParkCount > 0 {
                LazyVGrid(columns: ParkGrid.columns, spacing: 16) { travelerParks }
            }
            ParkLoadGate {
                let parks = store.stateParks(in: stateName)
                if parks.isEmpty {
                    if travelerParkCount == 0 {
                        ParkEmptyBox(title: "State Parks database is being finalized for \(stateName).",
                                     detail: "Please select another state or request additions in our AI Planner chat.")
                    }
                } else {
                    LazyVGrid(columns: ParkGrid.columns, spacing: 16) {
                        ForEach(parks) { p in
                            StateParkCard(park: p, stateName: stateName, style: .tab) { open = p }
                        }
                    }
                }
            }
        }
        .sheet(item: $open) { StateParkSheet(park: $0) }
    }
}

extension StateParksTab where TravelerParks == EmptyView {
    init(stateName: String) {
        self.init(stateName: stateName, travelerParkCount: 0) { EmptyView() }
    }
}

// MARK: - National Parks tab (web App.tsx 8023-8191)

struct NationalParksTab: View {
    let stateName: String
    @State private var filter: NationalParkFilter = .all
    @State private var expanded: Set<String> = []
    @State private var open: NationalPark?
    private var store: ParkStore { ParkStore.shared }

    init(stateName: String) { self.stateName = stateName }

    /// The website keeps every group open for California and shows no toggle there.
    private var alwaysOpen: Bool { stateName == "California" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("National Parks & Monuments in \(stateName)")
                        .font(.headline)
                        .foregroundStyle(Color.navy)
                        .accessibilityAddTraits(.isHeader)
                    Text("Breathtaking federal reserves, national parks, and historic sites managed by the NPS.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                chips
                Rectangle().fill(Color.hairline).frame(height: 1)
            }
            ParkLoadGate {
                if store.nationalParks(in: stateName).isEmpty {
                    ParkEmptyBox(title: "NPS database is being finalized for \(stateName).",
                                 detail: "Please select another state or request additions in our AI Planner chat.")
                } else {
                    let groups = store.nationalParkGroups(in: stateName, filter: filter)
                    if groups.isEmpty {
                        ParkEmptyBox(title: "No sites found for this category in \(stateName).")
                    } else {
                        VStack(alignment: .leading, spacing: 32) {
                            ForEach(groups) { g in group(g) }
                        }
                    }
                }
            }
        }
        .sheet(item: $open) { NationalParkSheet(park: $0) }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NationalParkFilter.allCases) { f in
                    let on = filter == f
                    Button {
                        filter = f
                    } label: {
                        Text(f.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? Color.white : Color.navy)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .background(on ? Color.navy : Color.white, in: Capsule())
                            .overlay { if !on { Capsule().strokeBorder(Color.hairline, lineWidth: 1) } }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
        .sensoryFeedback(.selection, trigger: filter)
    }

    @ViewBuilder
    private func group(_ g: NationalParkGroup) -> some View {
        let isOpen = alwaysOpen || expanded.contains(g.id)
        let visible = isOpen ? g.parks : Array(g.parks.prefix(4))
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(g.title.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Color.navy)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .hairline(radius: 6)
                Text("\(g.parks.count) sites")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
                Spacer(minLength: 0)
                if g.parks.count > 4 && !alwaysOpen {
                    Button(isOpen ? "Show less" : "Show all \(g.parks.count)") { toggle(g.id) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .frame(minHeight: 44)
                }
            }
            LazyVGrid(columns: ParkGrid.columns, spacing: 16) {
                ForEach(visible) { p in
                    NationalParkCard(park: p, stateName: stateName, style: .tab) { open = p }
                }
            }
            if g.parks.count > 4 && !isOpen && !alwaysOpen {
                Button { toggle(g.id) } label: {
                    Text("View \(g.parks.count - 4) more \(g.moreNoun)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .hairline(radius: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }
}

// MARK: - Tribal & Scenic tab (web App.tsx 8200-8256)

struct TribalScenicTab: View {
    let stateName: String
    @State private var open: NationalPark?
    private var store: ParkStore { ParkStore.shared }

    init(stateName: String) { self.stateName = stateName }

    var body: some View {
        let parks = store.isLoaded ? store.tribalAndScenic(in: stateName) : []
        VStack(alignment: .leading, spacing: 16) {
            ParkTabHeader(systemImage: "sun.max", title: "Tribal & Scenic Natural Landmarks in \(stateName)",
                          subtitle: "Sovereign Navajo & Indigenous Tribal Parks, BLM Wilderness, and iconic Southwest natural wonders.") {
                if store.isLoaded {
                    Text("\(parks.count) Iconic Landmarks")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.navy)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.surface, in: Capsule())
                        .overlay { Capsule().strokeBorder(Color.hairline, lineWidth: 1) }
                        .fixedSize()
                }
            }
            ParkLoadGate {
                if parks.isEmpty {
                    ParkEmptyBox(title: "No Tribal & Scenic Landmarks recorded for \(stateName).",
                                 detail: "Please check National and State Parks for reserves in this state.")
                } else {
                    LazyVGrid(columns: ParkGrid.columns, spacing: 16) {
                        ForEach(parks) { p in
                            NationalParkCard(park: p, stateName: stateName, style: .tribal) { open = p }
                        }
                    }
                }
            }
        }
        .sheet(item: $open) { NationalParkSheet(park: $0) }
    }
}
