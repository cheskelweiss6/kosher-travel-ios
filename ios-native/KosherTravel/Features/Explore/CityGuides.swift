import SwiftUI
import Observation

/// A tour guide someone added (types.ts TourGuide). The website keeps them on the phone only
/// (localStorage "local_tour_guides"); the app keeps them the same way, in UserDefaults under the same key.
struct TourGuide: Codable, Identifiable, Hashable {
    var id: String
    var guideName: String
    var tourType: String
    var phone: String
    var website: String?
    var languages: [String]?
    var description: String
    var city: String
    var state: String?
    var country: String?
    var region: String?
    var submittedBy: String
    var createdAt: String
}

@Observable
final class TourGuideStore {
    static let shared = TourGuideStore()
    private(set) var guides: [TourGuide] = []
    private static let key = "local_tour_guides"
    /// The website drops its old sample guides by name; nobody else ever had these.
    private static let legacyNames: Set<String> = ["David Sternberg", "Rabbi Aaron Levin", "Yosef Goldstein", "Ari Zaidman", "Moshe Silver",
        "Binyamin Katz", "Jonathan \"Yoni\" Shapiro", "Ezra Mountain", "Baruch Lev", "Michoel Gross", "Trevor \"Tsvi\" Christie",
        "Luis \"Levi\" Hernandez", "Jacob Henriquez", "Laurent Dreyfus", "Giacomo Piperno", "Tad Zukowski", "Marcus Bennett"]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([TourGuide].self, from: data) {
            guides = list.filter { !$0.id.hasPrefix("tg-") || Int($0.id.dropFirst(3)) != nil }
                .filter { !Self.legacyNames.contains($0.guideName) }
        }
    }

    func add(_ g: TourGuide) {
        guides.append(g)
        if let data = try? JSONEncoder().encode(guides) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// Web: guides whose city is this city, or whose state is the city's state.
    func forCity(_ page: CityPage) -> [TourGuide] {
        let c = page.name.lowercased(), s = page.stateName.lowercased()
        return guides.filter { $0.city.lowercased() == c || (!s.isEmpty && ($0.state ?? "").lowercased() == s) }
    }
}

/// The city's Travel Guides page (App.tsx guides sub-page). The website reaches it only when the hub has no inline
/// section, so it shows the same section as the hub.
struct CityGuidesView: View {
    let page: CityPage

    var body: some View {
        ScrollView {
            CitySubPageHero()
            CityTourGuidesSection(page: page)
                .padding(.horizontal, Theme.pagePadding)
                .padding(.top, 12)
                .padding(.bottom, 36)
        }
        .background(Color.white)
    }
}

/// "Tour Guides in {city}" (App.tsx 10940-11008, Caribbean 10866-10934): shown inline on the city hub under the cards,
/// with "Add Tour Guide", the TourGuideCards (guides of this city or this state), or the directory empty box.
struct CityTourGuidesSection: View {
    let page: CityPage
    private let store = TourGuideStore.shared
    @State private var adding = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let list = store.forCity(page)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Tour Guides in \(page.name)", systemImage: "safari")
                        .font(.headline).foregroundStyle(Color.navy)
                    Text("Local guides, customized kosher tours, and Jewish heritage experts in \(page.name).")
                        .font(.footnote).foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 8)
                addButton
            }
            if list.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "safari").font(.title2).foregroundStyle(Color.navy)
                        .frame(width: 48, height: 48).background(Color.surface, in: Circle())
                    Text("\(page.name) Tour Guides Directory").font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
                        .multilineTextAlignment(.center)
                    Text("No tour guides listed yet for \(page.name). Know a local kosher tour guide? Add them here!")
                        .font(.footnote).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
                    addButton
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hairline(radius: 16)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                    ForEach(list) { g in TourGuideCardView(guide: g) }
                }
            }
        }
        .sheet(isPresented: $adding) {
            AddTourGuideSheet(page: page) { g in
                store.add(g)
                ShellRouter.shared.showToast("Tour Guide \"\(g.guideName)\" added successfully!")
            }
        }
    }

    private var addButton: some View {
        Button { adding = true } label: {
            Label("Add Tour Guide", systemImage: "plus")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).frame(minHeight: 36)
                .foregroundStyle(.white)
                .background(Color.navy, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// TourGuideCard.tsx: location badge, rating, tour type, the guide's name, description, phone / website, Reviews,
/// and the "Shared by" footer with the date it was added.
struct TourGuideCardView: View {
    let guide: TourGuide
    @Environment(\.openURL) private var openURL
    @State private var summary: PlaceReviewSummary?
    @State private var showReviews = false

    var body: some View { card(guide) }

    private func card(_ g: TourGuide) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(g.city + ((g.state ?? "").isEmpty ? ((g.country ?? "").isEmpty ? "" : ", \(g.country ?? "")") : ", \(g.state ?? "")"),
                      systemImage: "mappin")
                    .font(.caption2.weight(.heavy)).foregroundStyle(Color.navy)
                    .padding(.horizontal, 7).padding(.vertical, 3).hairline(radius: 6)
                if let langs = g.languages, !langs.isEmpty {
                    Label(langs.joined(separator: ", "), systemImage: "bubble.left.and.bubble.right")
                        .font(.caption2).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let s = summary, s.count > 0 {
                    Label(String(format: "%.1f (%d)", s.avg, s.count), systemImage: "star")
                        .font(.caption2.weight(.bold)).foregroundStyle(Color.navy)
                }
            }
            Text(g.tourType).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
            Text(g.guideName).font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
            Text(g.description).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(2)
            HStack(spacing: 8) {
                // Website: the phone always shows (tel: with digits and + only).
                let digits = g.phone.filter { $0.isNumber || $0 == "+" }
                Button { if let tel = URL(string: "tel:\(digits)") { openURL(tel) } } label: {
                    Label(g.phone, systemImage: "phone").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Color.navy).frame(minHeight: 36)
                if let w = g.website, !w.isEmpty, let url = URL(string: w.lowercased().hasPrefix("http") ? w : "https://" + w) {
                    Button { openURL(url) } label: { Label("Website", systemImage: "globe").font(.caption.weight(.semibold)) }
                        .buttonStyle(.plain).foregroundStyle(Color.navy).frame(minHeight: 36)
                }
            }
            Divider().overlay(Color.hairline)
            // Website (TourGuideCard.tsx): "Reviews (N)" toggles the shared reviews section open under the card.
            Button { withAnimation(.snappy) { showReviews.toggle() } } label: {
                Label((summary?.count ?? 0) > 0 ? "Reviews (\(summary?.count ?? 0))" : "Reviews", systemImage: "text.bubble")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.plain).foregroundStyle(Color.navy).frame(minHeight: 36)
            .accessibilityValue(showReviews ? "Open" : "Closed")
            if showReviews {
                ParkReviewsSection(placeId: "guide-\(g.id)", placeName: g.guideName, placeKind: "guide",
                                   onCount: { _ in Task { await loadSummary(g) } })
            }
            HStack {
                Text("Shared by \(g.submittedBy.isEmpty ? "Community Traveler" : g.submittedBy)")
                Spacer(minLength: 8)
                Text(g.createdAt)
            }
            .font(.caption2).foregroundStyle(Color.textTertiary)
        }
        .padding(16)
        .hairline(radius: 16)
        .task(id: g.id) { await loadSummary(g) }
    }

    /// Website: the count and average show before the reviews are opened (placeId "guide-<id>").
    private func loadSummary(_ g: TourGuide) async {
        if let list = try? await PlaceReviewService.reviews(placeId: "guide-\(g.id)") { summary = PlaceReviewSummary(list) }
    }
}

/// "Add a Tour Guide" (AddTourGuideModal.tsx): the website's fields, defaults, checks and words.
struct AddTourGuideSheet: View {
    let page: CityPage
    let onAdd: (TourGuide) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var guideName = ""
    @State private var tourType = "Jewish Heritage & Walking Tour"
    @State private var phone = ""
    @State private var website = ""
    @State private var languages = "English, Hebrew"
    @State private var description = ""
    @State private var city = ""
    @State private var state = ""
    @State private var submittedBy = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Recommend a verified local kosher travel guide or Jewish heritage expert")
                        .font(.footnote).foregroundStyle(Color.textSecondary)
                }
                Section("Guide") {
                    TextField("Guide Name * (e.g. David Sternberg)", text: $guideName).textContentType(.name)
                    TextField("Tour Type / Specialty", text: $tourType)
                    TextField("Phone Number *", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                    TextField("Website (Optional)", text: $website).keyboardType(.URL).textInputAutocapitalization(.never)
                    TextField("Languages Spoken", text: $languages)
                    TextField("Service Description *", text: $description, axis: .vertical).lineLimit(2...4)
                }
                Section("Where") {
                    TextField("City *", text: $city)
                    TextField("State (e.g. Alabama, Florida)", text: $state)
                }
                Section {
                    TextField("Your Name (Submitter)", text: $submittedBy)
                } footer: {
                    Text("Appears only as \"Shared by [Name]\"")
                }
                if !error.isEmpty {
                    Section { Text(error).foregroundStyle(Color.alert).font(.footnote) }
                }
            }
            .tint(Color.navy)
            .navigationTitle("Add a Tour Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Submit Tour Guide") { submit() }.fontWeight(.semibold) }
            }
            .onAppear {
                if city.isEmpty { city = page.name }
                if state.isEmpty { state = page.stateName }
            }
        }
    }

    private func submit() {
        let t = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if t(guideName).isEmpty { error = "Guide name is required."; return }
        if t(phone).isEmpty { error = "Phone number is required."; return }
        if t(description).isEmpty { error = "Short service description is required."; return }
        if t(city).isEmpty { error = "City is required."; return }
        let langs = languages.split(separator: ",").map { t(String($0)) }.filter { !$0.isEmpty }
        let us = page.country == "United States" || page.country.isEmpty
        let g = TourGuide(
            id: "tg-\(Int(Date().timeIntervalSince1970 * 1000))",
            guideName: t(guideName),
            tourType: t(tourType).isEmpty ? "Kosher Travel & Heritage Guide" : t(tourType),
            phone: t(phone),
            website: t(website).isEmpty ? nil : t(website),
            languages: langs.isEmpty ? ["English"] : langs,
            description: t(description),
            city: t(city),
            state: t(state).isEmpty ? (us ? page.stateName : nil) : t(state),
            country: page.country.isEmpty ? "United States" : page.country,
            region: us ? "United States" : page.area,
            submittedBy: t(submittedBy).isEmpty ? "Community Traveler" : t(submittedBy),
            createdAt: String(ISO8601DateFormatter().string(from: Date()).prefix(10)))
        onAdd(g)
        dismiss()
    }
}
