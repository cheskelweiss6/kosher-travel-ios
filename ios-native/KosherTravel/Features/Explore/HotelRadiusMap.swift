import SwiftUI
import MapKit

/// "Walking Distance (1 Mile) from {hotel}" (RadiusMapModal.tsx): the hotel found by name in the city, and the
/// city's listed places within one mile of it (restaurants navy, others teal, the hotel purple).
struct HotelRadiusMap: View {
    let hotel: PlaceItem
    let cityName: String
    let places: [PlaceItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var center: CLLocationCoordinate2D?
    @State private var searched = false
    @State private var camera: MapCameraPosition = .automatic

    private var nearby: [PlaceItem] {
        guard let c = center else { return [] }
        let r = 3958.8
        return places.filter { p in
            guard p.id != hotel.id, let q = p.coordinate else { return false }
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
                            if let q = p.coordinate {
                                Marker(p.venue.name, coordinate: q)
                                    .tint(p.category == .restaurant ? Color.navy : Color(red: 0.08, green: 0.72, blue: 0.65))
                            }
                        }
                    }
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
            .task { await locate() }
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

    private func set(_ c: CLLocationCoordinate2D) {
        center = c
        camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 3600, longitudinalMeters: 3600))
    }
}
