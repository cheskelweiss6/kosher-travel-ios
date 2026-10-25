import SwiftUI
import MapKit

/// The website's TrailMapModal ("Interactive Trail Planner"), on Apple Maps: the park's real location from a map
/// search of "{name}, {address}", the Trails Catalog, the selected trail's details and the Map Guide.
///
/// The parks data has no trail coordinates. The website places each trailhead on a circle around the park centre and
/// drew a generated winding line from it; those positions were invented, so they are off here (`showsWebsiteRoutes`).
/// Oct 23 2026: Cheskel approved removing them on the website too (gap G3), so both show the park's real location and
/// the trail list, with the same words.
struct ParkTrailMapView: View {
    let park: StatePark
    static let showsWebsiteRoutes = false

    @Environment(\.dismiss) private var dismiss
    @State private var center: CLLocationCoordinate2D?
    @State private var searching = true
    @State private var position: MapCameraPosition = .automatic
    @State private var selected: Int?

    init(park: StatePark) { self.park = park }

    private struct Resolved {
        let location: CLLocationCoordinate2D
        let path: [CLLocationCoordinate2D]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Interactive Trail Planner", systemImage: "figure.hiking")
                            .font(.caption.weight(.heavy))
                            .textCase(.uppercase)
                            .foregroundStyle(Color.textSecondary)
                        Text("\(park.name) Trail Map")
                            .font(.serifTitle(.title2))
                            .foregroundStyle(Color.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    mapStage
                    if let i = selected, park.hikingTrails.indices.contains(i) {
                        selectedCard(park.hikingTrails[i])
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ParkSheetTitle(text: "Trails Catalog")
                        Text("The park's hiking trails. Tap a trail to see its length, difficulty and details.")
                            .font(.footnote).foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(spacing: 10) {
                        ForEach(Array(park.hikingTrails.enumerated()), id: \.offset) { i, t in
                            Button { select(i) } label: { catalogRow(t, on: selected == i) }
                                .buttonStyle(.plain)
                        }
                    }
                    ParkInfoBox {
                        Label("Map Guide", systemImage: "info.circle")
                            .font(.caption.weight(.heavy))
                            .textCase(.uppercase)
                            .foregroundStyle(Color.navy)
                        Text("The pin shows where the park is. The app has no mapped routes for these trails, so none are drawn on the map. Get the official trail map at the park or on its website.")
                            .font(.footnote).foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Theme.pagePadding)
            }
            .background(Color.white)
            .navigationTitle("Trail Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .task(id: park.id) { await locate() }
    }

    // MARK: map

    private var resolved: [Resolved] {
        guard Self.showsWebsiteRoutes, let c = center else { return [] }
        let n = Double(max(park.hikingTrails.count, 1))
        return park.hikingTrails.indices.map { idx in
            let angle = Double(idx) * (360 / n) * .pi / 180
            let head = CLLocationCoordinate2D(latitude: c.latitude + sin(angle) * 0.004, longitude: c.longitude + cos(angle) * 0.004)
            return Resolved(location: head, path: Self.windingPath(head, seed: idx))
        }
    }

    /// web generateWindingPath
    private static func windingPath(_ start: CLLocationCoordinate2D, seed: Int) -> [CLLocationCoordinate2D] {
        var out = [start]
        var lat = start.latitude
        var lng = start.longitude
        let angle = Double(seed) * 135 * .pi / 180 + 0.4
        for i in 0..<14 {
            let d = Double(i)
            let w = angle + sin(d * 1.3) * 0.35 + cos(d * 0.7) * 0.15
            lat += sin(w) * 0.0012
            lng += cos(w) * 0.0012
            out.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        return out
    }

    @ViewBuilder
    private var mapStage: some View {
        let routes = resolved
        ZStack {
            Map(position: $position) {
                if let c = center {
                    Marker(park.name, systemImage: "leaf", coordinate: c).tint(Color.navy)
                }
                ForEach(Array(routes.enumerated()), id: \.offset) { i, r in
                    MapPolyline(coordinates: r.path)
                        .stroke(Color.navy.opacity(selected == i ? 1 : 0.6), lineWidth: selected == i ? 6 : 4)
                    Annotation(park.hikingTrails[i].name, coordinate: r.location) {
                        Button { select(i) } label: {
                            Image(systemName: "figure.hiking")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.navy, in: Circle())
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapControls { MapCompass(); MapScaleView() }
            if searching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Finding the park on the map...").font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
            } else if center == nil {
                Text("This park couldn't be found on the map.")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .hairline(radius: Theme.cardRadius)
    }

    private func locate() async {
        searching = true
        defer { searching = false }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = "\(park.name), \(park.address)"
        if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
            setCenter(item.placemark.coordinate)
            return
        }
        if !park.address.isEmpty, let mark = try? await CLGeocoder().geocodeAddressString(park.address).first,
           let loc = mark.location {
            setCenter(loc.coordinate)
        }
    }

    private func setCenter(_ c: CLLocationCoordinate2D) {
        center = c
        position = .camera(MapCamera(centerCoordinate: c, distance: 6000))
    }

    private func select(_ i: Int) {
        selected = i
        let routes = resolved
        if routes.indices.contains(i) {
            withAnimation(Motion.camera) { position = .camera(MapCamera(centerCoordinate: routes[i].location, distance: 3000)) }
        }
    }

    // MARK: rows

    private func catalogRow(_ t: ParkTrail, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(t.name).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !t.difficulty.isEmpty { ParkDifficultyTag(difficulty: t.difficulty) }
            }
            if !t.length.isEmpty {
                Label(t.length, systemImage: "figure.walk").font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
            }
            if !t.description.isEmpty {
                Text(t.description).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(on ? Color.surface : Color.white, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(on ? Color.navy.opacity(0.5) : Color.hairline, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private func selectedCard(_ t: ParkTrail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(t.name).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
                Spacer(minLength: 4)
                if !t.difficulty.isEmpty { ParkDifficultyTag(difficulty: t.difficulty) }
            }
            if !t.length.isEmpty {
                Label("Length: \(t.length)", systemImage: "location.north").font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
            }
            if !t.description.isEmpty {
                Text(t.description).font(.footnote).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white)
        .hairline(radius: Theme.cardRadius)
    }
}
