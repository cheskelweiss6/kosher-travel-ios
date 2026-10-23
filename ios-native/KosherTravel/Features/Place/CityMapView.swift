import SwiftUI
import MapKit

/// The city's listings on a map (outline symbols per category). Pins come from the data's coordinates or, when a
/// listing only has an address, from Apple's geocoder on this phone. Listings without an address get no pin.
struct CityMapView: View {
    let page: CityPage
    let items: [PlaceItem]
    var onOpenStory: ((String) -> Void)? = nil

    @State private var coords: [String: CLLocationCoordinate2D] = [:]
    @State private var camera: MapCameraPosition = .automatic
    @State private var selection: String?
    @State private var sheetItem: PlaceItem?
    @State private var filter: PlaceCategory?
    @State private var pending = 0
    @State private var noAddress = 0
    @State private var centered = false

    private var categories: [PlaceCategory] {
        var out: [PlaceCategory] = []
        for i in items where !out.contains(i.category) { out.append(i.category) }
        return out
    }

    private var shown: [PlaceItem] {
        items.filter { filter == nil || $0.category == filter }
    }

    private struct Pin: Identifiable {
        let id: String
        let name: String
        let icon: String
        let coordinate: CLLocationCoordinate2D
    }

    private var pins: [Pin] {
        shown.compactMap { item in
            guard let c = coords[item.id] else { return nil }
            return Pin(id: item.id, name: item.venue.name, icon: item.systemImage, coordinate: c)
        }
    }

    var body: some View {
        Map(position: $camera, selection: $selection) {
            ForEach(pins) { pin in
                Marker(pin.name, systemImage: pin.icon, coordinate: pin.coordinate)
                    .tint(Color.navy)
                    .tag(pin.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top, spacing: 0) { chips }
        .safeAreaInset(edge: .bottom, spacing: 0) { status }
        .navigationTitle("\(page.name) map")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selection) { _, id in
            guard let id, let item = items.first(where: { $0.id == id }) else { return }
            sheetItem = item
        }
        .sheet(item: $sheetItem, onDismiss: { selection = nil }) { item in
            PlaceDetailView(item: item, onOpenStory: onOpenStory)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sensoryFeedback(.selection, trigger: selection)
        .task { await locateAll() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CityMapChip(title: "All", systemImage: "square.grid.2x2", on: filter == nil) { filter = nil }
                ForEach(categories, id: \.self) { c in
                    CityMapChip(title: c.chip, systemImage: c.systemImage, on: filter == c) { filter = (filter == c) ? nil : c }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.vertical, 10)
        }
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 0.5) }
    }

    @ViewBuilder
    private var status: some View {
        let pinned = shown.filter { coords[$0.id] != nil }.count
        let text: String = {
            if pending > 0 { return "Finding addresses on the map: \(pending) left" }
            var t = "\(pinned) of \(shown.count) on the map"
            if noAddress > 0 && pinned < shown.count { t += ". Places without an address are not pinned" }
            return t
        }()
        HStack(spacing: 8) {
            if pending > 0 { ProgressView().controlSize(.small) }
            Text(text).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 0.5) }
    }

    private func locateAll() async {
        var next: [String: CLLocationCoordinate2D] = [:]
        var todo: [PlaceItem] = []
        var missing = 0
        for item in items {
            if let c = item.coordinate { next[item.id] = c; continue }
            let a = item.venue.address
            if a.isEmpty { missing += 1; continue }
            if let c = await PlaceGeocoder.shared.cached(a) { next[item.id] = c } else { todo.append(item) }
        }
        coords = next
        noAddress = missing
        pending = todo.count
        recenter()
        for item in todo {
            if Task.isCancelled { return }
            if let c = await PlaceGeocoder.shared.coordinate(for: item.venue.address) {
                coords[item.id] = c
                if !centered { recenter() }
            }
            pending -= 1
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        recenter()
    }

    /// Frame the pins near the city (pins far from it, e.g. a resort an hour away, still show when you zoom out).
    private func recenter() {
        let all = Array(coords.values)
        guard !all.isEmpty else {
            if let c = page.center {
                camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 20_000, longitudinalMeters: 20_000))
            }
            return
        }
        var pts = all
        if let c = page.center {
            let near = all.filter { abs($0.latitude - c.latitude) < 0.6 && abs($0.longitude - c.longitude) < 0.6 }
            if !near.isEmpty { pts = near }
        }
        let lats = pts.map(\.latitude), lngs = pts.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.02, (maxLat - minLat) * 1.4), longitudeDelta: max(0.02, (maxLng - minLng) * 1.4))
        withAnimation(.easeInOut(duration: 0.3)) { camera = .region(MKCoordinateRegion(center: center, span: span)) }
        centered = pts.count >= 3
    }
}

private struct CityMapChip: View {
    let title: String
    let systemImage: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Color.white : Color.navy)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(on ? Color.navy : Color.white, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.navy : Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
