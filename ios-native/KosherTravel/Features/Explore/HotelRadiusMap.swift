import SwiftUI
import MapKit

/// "Walking Distance (1 Mile) from {hotel}" (RadiusMapModal.tsx): the hotel found by name in the city, and the
/// city's listed places within one mile of it (restaurants navy, others teal, the hotel purple).
/// Oct 23 2026 (gap G5, the website now does the same): a listing with coordinates is placed directly; one with only an
/// address is found with the geocoder (at most 30 per open), and a line says how many are within the mile.
struct HotelRadiusMap: View {
    let hotel: PlaceItem
    let cityName: String
    let places: [PlaceItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var center: CLLocationCoordinate2D?
    @State private var searched = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var found: [String: CLLocationCoordinate2D] = [:]   // PlaceItem.id → geocoded address
    @State private var placing = false

    private func where_(_ p: PlaceItem) -> CLLocationCoordinate2D? { p.coordinate ?? found[p.id] }

    private var nearby: [PlaceItem] {
        guard let c = center else { return [] }
        let r = 3958.8
        return places.filter { p in
            guard p.id != hotel.id, p.venue.name != hotel.venue.name, let q = where_(p) else { return false }
            let dLat = (q.latitude - c.latitude) * .pi / 180, dLon = (q.longitude - c.longitude) * .pi / 180
            let a = sin(dLat / 2) * sin(dLat / 2) + cos(c.latitude * .pi / 180) * cos(q.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
            return r * 2 * atan2(sqrt(a), sqrt(1 - a)) <= 1
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let c = center {
                    Map(position: $camera) {
                        Marker(hotel.venue.name, coordinate: c).tint(.purple)
                        ForEach(nearby) { p in
                            if let q = where_(p) {
                                Marker(p.venue.name, coordinate: q)
                                    .tint(p.category == .restaurant ? Color.navy : Color(red: 0.08, green: 0.72, blue: 0.65))
                            }
                        }
                    }
                    .safeAreaInset(edge: .top) { statusLine }
                } else if searched {
                    VStack(spacing: 14) {
                        Image(systemName: "map").font(.title).foregroundStyle(Color.navy)
                            .frame(width: 48, height: 48).background(Color.surface, in: Circle())
                        Text("Map Preview").font(.headline).foregroundStyle(Color.navy)
                        Button {
                            var c = URLComponents(string: "https://maps.apple.com/")!
                            c.queryItems = [.init(name: "q", value: "\(hotel.venue.name) \(cityName)")]
                            if let u = c.url { openURL(u) }
                        } label: {
                            Text("Open \(hotel.venue.name) in Maps").font(.caption.weight(.semibold))
                                .padding(.horizontal, 16).frame(minHeight: 40)
                                .foregroundStyle(.white).background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surface)
                } else {
                    ProgressView().tint(Color.navy).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Walking Distance (1 Mile) from \(hotel.venue.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .task { await locate(); await placeListings() }
        }
    }

    @MainActor
    private func locate() async {
        defer { searched = true }
        if let c = hotel.coordinate { set(c); return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = "\(hotel.venue.name), \(cityName)"
        if let item = try? await MKLocalSearch(request: req).start().mapItems.first {
            set(item.placemark.coordinate)
        }
    }

    private var statusLine: some View {
        let n = nearby.count
        let text = placing ? "Finding the city's listed places…"
            : n == 0 ? "None of this city's listed places are within 1 mile."
            : "\(n) of this city's listed places \(n == 1 ? "is" : "are") within 1 mile."
        return Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.navy)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 8)
    }

    /// Listings with only an address: one geocoder request at a time (Apple's limit), at most 30.
    @MainActor
    private func placeListings() async {
        guard center != nil else { return }
        let todo = places.filter { $0.id != hotel.id && $0.coordinate == nil && $0.venue.address.trimmingCharacters(in: .whitespaces).count > 4 }
            .prefix(30)
        guard !todo.isEmpty else { return }
        placing = true
        defer { placing = false }
        let geo = CLGeocoder()
        for p in todo {
            if Task.isCancelled { return }
            let addr = p.venue.address.localizedCaseInsensitiveContains(cityName) ? p.venue.address : "\(p.venue.address), \(cityName)"
            if let loc = try? await geo.geocodeAddressString(addr).first?.location {
                found[p.id] = loc.coordinate
            }
        }
    }

    private func set(_ c: CLLocationCoordinate2D) {
        center = c
        camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 3600, longitudinalMeters: 3600))
    }
}
