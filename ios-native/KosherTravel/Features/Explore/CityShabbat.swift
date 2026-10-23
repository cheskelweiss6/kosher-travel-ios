import SwiftUI

/// The city's Shabbat page (App.tsx activeCitySubCategory 'shabbat'): the full Zmanim card, catering and hospitality,
/// and walking / eruv guidelines, in the website's words.
struct CityShabbatView: View {
    let page: CityPage
    let hasChabad: Bool

    private var eruvText: String {
        guard let e = page.eruv else { return "" }
        return [e.description.isEmpty ? e.name : e.description, e.boundary.isEmpty ? "" : "Boundary: \(e.boundary)", e.notes]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        ScrollView {
            CitySubPageHero()  // website: the city hero stays on top of every sub-page
            VStack(alignment: .leading, spacing: 14) {
                Label("Shabbat & Family Information", systemImage: "calendar")
                    .font(.subheadline.weight(.black)).foregroundStyle(Color.navy)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                    .overlay(alignment: .bottom) { Divider().overlay(Color.hairline) }
                VStack(alignment: .leading, spacing: 16) {
                    ZmanimCard(place: ZmanimPlace(id: page.destId, name: page.name,
                                                  state: page.stateName.isEmpty ? page.country : page.stateName),
                               compact: false)
                    Divider().overlay(Color.hairline)
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Shabbat Catering & Hospitality", systemImage: "wineglass")
                            .font(.caption.weight(.heavy)).foregroundStyle(Color.navy)
                        Group {
                            if hasChabad {
                                Text("Great news! There is a listed local Chabad house center in this city. Tap on the ") + Text("Chabad Directory").bold()
                                    + Text(" category card to view contact info, website links, or enquire about ordering pre-packed Shabbat meals.")
                            } else {
                                Text("Since there are no listed local Chabad houses in \(page.name), we suggest planning self-catering options using our ")
                                    + Text("Kosher Groceries").bold() + Text(" category or contacting adjacent Jewish communities.")
                            }
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
                    }
                    Divider().overlay(Color.hairline)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Shabbat Walking & Eruv Guidelines", systemImage: "figure.walk")
                            .font(.caption.weight(.heavy)).foregroundStyle(Color.navy)
                        if !eruvText.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Local Eruv & Shabbat Status:", systemImage: "shield")
                                    .font(.caption.weight(.heavy)).foregroundStyle(Color.navy)
                                Text(eruvText).font(.caption).foregroundStyle(Color.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .hairline(radius: 12)
                        } else {
                            (Text("Always refer to the ") + Text("Shuls").bold()
                                + Text(" category tab to check active Eruv boundary statuses before carrying items in public domains on Shabbat."))
                                .font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                .padding(18)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .hairline(radius: 16)
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 36)
        }
        .background(Color.white)
    }
}
