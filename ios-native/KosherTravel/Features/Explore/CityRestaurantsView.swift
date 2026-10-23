import SwiftUI

/// The website's restaurant test: Meat, Dairy or Parve from the hechsher, type, name and description
/// (App.tsx getRestaurantDietaryType, same order of checks).
enum DietType: String, CaseIterable, Identifiable {
    case meat = "Meat", dairy = "Dairy", parve = "Parve"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .meat: return "fork.knife"
        case .dairy: return "cup.and.saucer"
        case .parve: return "leaf"
        }
    }

    static func of(_ v: Venue) -> DietType {
        let type = v.kind.lowercased()
        let name = v.name.lowercased()
        let kashrus = v.kashrus.lowercased()
        let desc = v.description.lowercased()
        func any(_ s: String, _ words: [String]) -> Bool { words.contains { s.contains($0) } }
        // 0. An explicit parve certification wins.
        if any(kashrus, ["parve", "pareve"]) { return .parve }
        // 1. Meat in the type.
        if any(type, ["meat", "fleishig", "grill", "steak", "burger", "shawarma", "shwarma", "deli", "chicken", "bbq"]) { return .meat }
        // 2. Dairy in the hechsher (before "glatt": "OU Glatt Kosher (Dairy)").
        if any(kashrus, ["dairy", "milchig", "chalav", "cholov"]) { return .dairy }
        // 3. Meat in the hechsher.
        if any(kashrus, ["meat", "fleishig", "glatt"]) { return .meat }
        // 4. Dairy in the type.
        if any(type, ["dairy", "milchig", "pizza", "cafe", "pasta", "cream", "vegetarian", "sushi", "bistro", "ice cream", "bakery", "fish"]) { return .dairy }
        // 5. Name and description: dairy, then meat.
        if any(name, ["pizza", "cafe", "bistro", "sushi", "dairy", "cream", "rimon", "spoons", "rustiko", "creamery"])
            || any(desc, ["dairy", "pizza", "milchig", "pasta", "pizzeria"]) { return .dairy }
        if any(name, ["grill", "steak", "burger", "deli", "bar", "meat", "shwarma", "shawarma", "falafel", "fallafel", "reulas",
                      "sabra", "imperial", "fireside", "hotspot", "palace"])
            || any(desc, ["steak", "meat", "grill", "fleishig", "burger"]) { return .meat }
        return .meat
    }
}

/// Saved kosher food filters (kosherPrefs.ts restaurantMisses): which of the person's food needs a restaurant's
/// listing does not show, judged only from its hechsher, type, description and name.
enum KosherFoodFilter {
    static func misses(_ v: Venue, needs: [String], diet: DietType) -> [String] {
        guard !needs.isEmpty else { return [] }
        let t = [v.kashrus, v.kind, v.description, v.name].joined(separator: " ").lowercased()
        let bready = [v.kind, v.name].joined(separator: " ").lowercased()
        var miss: [String] = []
        if needs.contains("Glatt kosher"), diet == .meat, !t.contains("glatt") { miss.append("Glatt kosher") }
        if needs.contains("Cholov Yisroel"), diet == .dairy, !matches(t, #"chol[ou]v\s*yisr|chalav\s*yisr|cholov|\bcy\b"#) { miss.append("Cholov Yisroel") }
        if needs.contains("Pas Yisroel"), matches(bready, "bakery|bagel|pizza|bread|challah|sandwich"),
           !matches(t, #"pas\s*yisr|pat\s*yisr|\bpy\b"#) { miss.append("Pas Yisroel") }
        return miss
    }

    /// The food needs that are switched on (activeFoodPrefs).
    static func active(_ p: SavedKosherPrefs?) -> [String] {
        guard let p, p.filtersOn else { return [] }
        return p.needs.filter { SavedKosherPrefs.food.contains($0) }
    }

    /// The saved food needs, on or off (what the filter chip counts).
    static func saved(_ p: SavedKosherPrefs?) -> [String] {
        (p?.needs ?? []).filter { SavedKosherPrefs.food.contains($0) }
    }

    private static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }
}

/// "My kosher filters" chip above a list (KosherPrefsUI.tsx KosherFilterChip): on/off, how many are hidden, Edit.
struct KosherFilterChip: View {
    let hidden: Int
    let noun: String
    /// The saved needs this list is filtered by (default: the food needs).
    var relevant: [String]? = nil
    private let store = ProfileStore.shared
    @State private var editing = false

    var body: some View {
        let relevant = self.relevant ?? KosherFoodFilter.saved(store.kosherPrefs)
        if let prefs = store.kosherPrefs, !relevant.isEmpty {
            let on = prefs.filtersOn
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(Color.navy)
                VStack(alignment: .leading, spacing: 2) {
                    Text(on ? "My kosher filters: \(relevant.count) on" : "My kosher filters: off")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                    HStack(spacing: 4) {
                        Text(on ? (hidden > 0 ? "\(hidden) \(noun) hidden" : "All \(noun) fit") : "Showing everything")
                            .lineLimit(1)
                        Text("·")
                        Button("Edit") { editing = true }
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.navy)
                    }
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 4)
                Button {
                    Task { await store.saveKosherPrefs(filtersOn: !on) }
                } label: {
                    Text(on ? "Show all" : "Turn on")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .foregroundStyle(on ? Color.navy : Color.white)
                        .background(on ? Color.white : Color.navy, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.hairline : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 8)
            .hairline(radius: 14)
            .sheet(isPresented: $editing) {
                NavigationStack {
                    KosherPrefsView(store: store)
                        .navigationTitle("Kosher preferences")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } }
                        }
                }
            }
        }
    }
}

/// The city's Restaurants page (web: activeCitySubCategory 'restaurants'): Meat / Dairy / Parve tabs with counts,
/// the kosher filter chip, and one card per restaurant with photo, hechsher, address, phone, View Details,
/// Reviews, Directions and Website.
struct CityRestaurantsView: View {
    let items: [PlaceItem]
    let cityName: String
    let summary: (PlaceItem) -> PlaceReviewSummary?
    let onSelect: (PlaceItem) -> Void

    @State private var tab: DietType = .meat
    @Environment(\.openURL) private var openURL
    private let store = ProfileStore.shared

    var body: some View {
        let needs = KosherFoodFilter.active(store.kosherPrefs)
        let hiddenItems = needs.isEmpty ? [] : items.filter { !KosherFoodFilter.misses($0.venue, needs: needs, diet: DietType.of($0.venue)).isEmpty }
        let hiddenIds = Set(hiddenItems.map(\.id))
        let visible = items.filter { !hiddenIds.contains($0.id) }
        let shown = visible.filter { DietType.of($0.venue) == tab }

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Kind", selection: $tab) {
                    ForEach(DietType.allCases) { t in
                        Text("\(t.rawValue) \(visible.filter { DietType.of($0.venue) == t }.count)").tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("restaurants-diet")

                if !items.isEmpty {
                    KosherFilterChip(hidden: hiddenItems.count, noun: "restaurants")
                }

                if items.isEmpty {
                    note("No certified restaurant listings yet.",
                         "We are actively gathering certified kosher diners for \(cityName). Please check with the local Chabad center for the newest home catering or delivery recommendations.")
                } else if shown.isEmpty {
                    let lower = tab.rawValue.lowercased()
                    let filteredOut = hiddenItems.contains { DietType.of($0.venue) == tab }
                    note(filteredOut ? "No \(lower) restaurant here lists \(needs.joined(separator: " / "))." : "No certified \(lower) restaurants found.",
                         "Try switching to another category above, or consult the local Chabad center for current catering or delivery services in \(cityName).")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                        ForEach(shown) { item in card(item) }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color.white)
        .sensoryFeedback(.selection, trigger: tab)
    }

    private func note(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
            Text(detail).font(.footnote).foregroundStyle(Color.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(24)
        .hairline(radius: 16)
    }

    private func card(_ item: PlaceItem) -> some View {
        let diet = DietType.of(item.venue)
        let v = item.venue
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: diet.systemImage)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.navy)
                    .frame(width: 32, height: 32)
                    .hairline(radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.navy)
                        .multilineTextAlignment(.leading)
                    Text(diet.rawValue.uppercased())
                        .font(.caption2.weight(.heavy))
                        .tracking(1)
                        .foregroundStyle(Color.navy)
                    rating(item)
                }
                Spacer(minLength: 4)
                Label(v.kashrus.isEmpty ? "Certified" : v.kashrus, systemImage: "checkmark.shield")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.navy)
                    .lineLimit(2)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .hairline(radius: 8)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            RemoteImage(url: item.photos.first ?? "", maxPixel: 900, venue: true, category: item.photoCategory)
                .frame(maxWidth: .infinity)
                .frame(height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                if !v.address.isEmpty {
                    Label(v.address, systemImage: "mappin")
                        .lineLimit(2)
                }
                if !v.phone.isEmpty, let tel = item.phoneURL {
                    Button { openURL(tel) } label: { Label(v.phone, systemImage: "phone") }
                        .buttonStyle(.plain)
                        .frame(minHeight: 32)
                }
            }
            .font(.footnote)
            .foregroundStyle(Color.textSecondary)
            Divider().overlay(Color.hairline)
            FlowActions {
                chip("View Details", "arrow.right") { onSelect(item) }
                chip(reviewsLabel(summary(item)), "star") { onSelect(item) }
                if let d = item.directionsURL { chip("Directions", "location") { openURL(d) } }
                if let w = item.websiteURL { chip("Website", "globe", on: true) { openURL(w) } }
            }
        }
        .padding(16)
        .background(Color.white)
        .hairline(radius: 16)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(item) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func rating(_ item: PlaceItem) -> some View {
        if let s = summary(item), s.count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill").font(.system(size: 10))
                Text(String(format: "%.1f", s.avg)).font(.caption.weight(.semibold))
                Text("(\(s.count))").font(.caption).foregroundStyle(Color.textSecondary)
            }
            .foregroundStyle(Color.navy)
        }
    }

    /// Web reviewsLabel: "Reviews" with none, else "N review(s)".
    private func reviewsLabel(_ s: PlaceReviewSummary?) -> String {
        guard let s, s.count > 0 else { return "Reviews" }
        return "\(s.count) review\(s.count == 1 ? "" : "s")"
    }

    private func chip(_ title: String, _ icon: String, on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .foregroundStyle(on ? Color.white : Color.navy)
                .background(on ? Color.navy : Color.white, in: Capsule())
                .overlay(Capsule().strokeBorder(on ? Color.clear : Color.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Wrapping row of action chips (the web's kt-actions).
struct FlowActions: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
