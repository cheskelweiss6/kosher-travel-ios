// Travel-time chip, the "Travel times from" bar and its picker sheet. Port of the website's src/components/TravelTime.tsx
// (Cheskel, Oct 22 2026): same words, numbers and behaviour.
import SwiftUI

/// A destination to look up (city / area), as the website passes it: name, country, state.
struct TravelPlace: Hashable {
    var name: String
    var country: String?
    var state: String?
    init(name: String, country: String? = nil, state: String? = nil) {
        self.name = name
        self.country = country
        self.state = state
    }
}

private enum TTColors {
    static let slate100 = Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255)
    static let slate300 = Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255)
    static let slate600 = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
}

/// "~2h 10m | ~5h" (or "~2h 10m flight | ~5h drive" with `words`). Shows nothing until the origin and the place are known.
struct TravelChip: View {
    enum Tone { case light, dark }
    private enum Target { case at(TTPoint?), place(TravelPlace), usState(String) }

    private let target: Target
    private let tone: Tone
    private let words: Bool

    @Environment(ExploreStore.self) private var explore
    @ScaledMetric(relativeTo: .caption2) private var fontSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2) private var iconSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var height: CGFloat = 24

    /// Exact point, when the data has it (state, country tile).
    init(at point: TTPoint?, tone: Tone = .light, words: Bool = false) {
        target = .at(point); self.tone = tone; self.words = words
    }
    init(at lat: Double, _ lng: Double, us: Bool, tone: Tone = .light, words: Bool = false) {
        self.init(at: TTPoint(lat: lat, lng: lng, us: us), tone: tone, words: words)
    }
    /// A destination to look up (city / area).
    init(place: TravelPlace, tone: Tone = .light, words: Bool = false) {
        target = .place(place); self.tone = tone; self.words = words
    }
    init(name: String, country: String?, state: String?, tone: Tone = .light, words: Bool = false) {
        self.init(place: TravelPlace(name: name, country: country, state: state), tone: tone, words: words)
    }
    /// A US state by name (placed at its main city).
    init(usState: String, tone: Tone = .light, words: Bool = false) {
        target = .usState(usState); self.tone = tone; self.words = words
    }
    // Conveniences for the app's own models (same lookups the website does for the same tiles).
    init(state: USState, tone: Tone = .light, words: Bool = false) { self.init(usState: state.name, tone: tone, words: words) }
    init(country: CaribbeanCountry, tone: Tone = .light, words: Bool = false) {
        self.init(at: TTPoint(lat: country.lat, lng: country.lng, us: false), tone: tone, words: words)
    }
    init(city: CityInfo, tone: Tone = .light, words: Bool = false) {
        self.init(place: TravelPlace(name: city.name, country: "United States", state: city.state), tone: tone, words: words)
    }
    init(destination d: Destination, tone: Tone = .light, words: Bool = false) {
        self.init(place: TravelPlace(name: d.name, country: d.country, state: d.state), tone: tone, words: words)
    }

    private var point: TTPoint? {
        let cities = explore.data?.cities ?? []
        switch target {
        case .at(let p):
            return p
        case .usState(let name):
            guard let s = TTGeo.stateCoords(name, states: explore.states, cities: cities) else { return nil }
            return TTPoint(lat: s.lat, lng: s.lng, us: true)
        case .place(let p):
            return TTGeo.placeCoords(name: p.name, country: p.country, state: p.state, states: explore.states, cities: cities)
        }
    }

    var body: some View {
        let origin = TravelOrigin.shared
        let t: TravelTimes = point.map { origin.times(toLat: $0.lat, lng: $0.lng, placeUS: $0.us) } ?? TravelTimes()
        let dark = tone == .dark
        let _ = origin.startSoon(cities: explore.data?.cities ?? [])
        Group {
            if !t.isEmpty {
                HStack(spacing: 6) {
                    if let f = t.flight { part("airplane", "~\(f)\(words ? " flight" : "")") }
                    if t.flight != nil && t.drive != nil {
                        Rectangle()
                            .fill(dark ? Color.white.opacity(0.35) : Color.hairline)
                            .frame(width: 1, height: 12)
                    }
                    if let d = t.drive { part("car", "~\(d)\(words ? " drive" : "")") }
                }
                .font(.system(size: fontSize, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(dark ? Color.white : Color.navy)
                .padding(.horizontal, 10)
                .frame(minHeight: height)
                .background {
                    if dark {
                        Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            .overlay(Capsule().fill(Color.black.opacity(0.35)))
                    } else {
                        Capsule().fill(Color.white)
                    }
                }
                .overlay(Capsule().strokeBorder(dark ? Color.white.opacity(0.25) : Color.hairline, lineWidth: 1))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibility(t, origin.origin?.label))
            }
        }
    }

    private func part(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: iconSize * 0.85, weight: .regular))
                .foregroundStyle(tone == .dark ? Color.white.opacity(0.9) : Color.navy.opacity(0.7))
                .accessibilityHidden(true)
            Text(text)
        }
    }

    private func accessibility(_ t: TravelTimes, _ label: String?) -> String {
        let parts = [t.flight.map { "about \($0) flight" }, t.drive.map { "about \($0) drive" }].compactMap { $0 }
        let from = (label?.isEmpty == false) ? label! : "you"
        return "From \(from): \(parts.joined(separator: ", "))"
    }
}

/// "Travel times from Brooklyn, NY · Change", or the gentle "Show travel times from my location" link.
struct TravelOriginBar: View {
    @Environment(ExploreStore.self) private var explore
    @State private var open = false
    @ScaledMetric(relativeTo: .caption) private var fontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var pinSize: CGFloat = 14

    var body: some View {
        let store = TravelOrigin.shared
        HStack(spacing: 6) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: pinSize * 0.85))
                .foregroundStyle(Color.navy.opacity(0.6))
                .accessibilityHidden(true)
            if let o = store.origin {
                (Text("Travel times from ")
                    + Text(o.label).fontWeight(.semibold).foregroundStyle(Color.navy)
                    + Text(o.source == .ip ? " (approx.)" : ""))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Button { open = true } label: {
                    Text("Change")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.navy)
                        .underline(true, color: TTColors.slate300)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .padding(.vertical, -12)
                }
                .buttonStyle(.plain)
                .fixedSize()
            } else {
                Button { open = true } label: {
                    Text(store.status == .locating ? "Finding your location…" : "Show travel times from my location")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.navy)
                        .underline(true, color: TTColors.slate300)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .padding(.vertical, -12)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: fontSize))
        .foregroundStyle(Color.textSecondary)
        .onAppear { store.start(cities: explore.data?.cities ?? []) }
        .sheet(isPresented: $open) {
            TravelOriginSheet()
        }
    }
}

/// The "Travel times from" picker: use my current location, or pick a city.
struct TravelOriginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ExploreStore.self) private var explore
    @State private var query = ""
    @State private var busy = false
    @FocusState private var searchFocused: Bool

    private var hits: [TTGeo.Hit] {
        TTGeo.search(query, states: explore.states, cities: explore.data?.cities ?? [])
    }

    var body: some View {
        let store = TravelOrigin.shared
        let st = store.status
        let results = hits
        VStack(spacing: 0) {
            HStack {
                Text("Travel times from")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.navy)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .padding(.trailing, -8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let o = store.origin {
                        (Text("Now: ")
                            + Text(o.label).fontWeight(.semibold).foregroundStyle(Color.navy)
                            + Text(o.source == .ip ? " (approximate, from your internet connection)" : o.source == .gps ? " (your location)" : ""))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                    }

                    Button(action: locate) {
                        HStack(spacing: 12) {
                            Image(systemName: "location")
                                .font(.system(size: 15))
                                .foregroundStyle(Color.navy)
                                .frame(width: 36, height: 36)
                                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(busy || st == .locating ? "Finding you…" : "Use my current location")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.navy)
                                Text("Only used on your phone, rounded to your city")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .opacity(busy ? 0.6 : 1)

                    if st == .denied || st == .error {
                        Text(st == .denied ? "Location is off for Kosher Travel. Pick your city instead:" : "Couldn't get your location. Pick your city instead:")
                            .font(.system(size: 13))
                            .foregroundStyle(TTColors.slate600)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.textTertiary)
                            .accessibilityHidden(true)
                        TextField("", text: $query, prompt: Text("Or pick your home city").foregroundStyle(Color.textTertiary))
                            .font(.system(size: 16))
                            .foregroundStyle(Color.navy)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .focused($searchFocused)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(searchFocused ? Color.navy : Color.hairline, lineWidth: 1))

                    if !results.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.offset) { i, h in
                                if i > 0 { Rectangle().fill(TTColors.slate100).frame(height: 1) }
                                Button {
                                    store.pick(lat: h.lat, lng: h.lng, label: h.label, us: h.us)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(h.label)
                                            .font(.system(size: 15))
                                            .foregroundStyle(Color.navy)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14))
                                            .foregroundStyle(TTColors.slate300)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(minHeight: 48)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hairline, lineWidth: 1))
                    }

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && results.isEmpty {
                        Text("No match yet. Try the nearest big city.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textSecondary)
                    }

                    Text("Times are rough estimates: a direct flight (plus about 40 min for take-off and landing) and, inside the US, a drive by highway.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { store.start(cities: explore.data?.cities ?? []) }
    }

    private func locate() {
        busy = true
        TravelOrigin.shared.locateMe { ok in
            busy = false
            if ok {
                dismiss()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchFocused = true }
            }
        }
    }
}
