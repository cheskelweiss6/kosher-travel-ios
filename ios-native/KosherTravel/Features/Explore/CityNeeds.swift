import SwiftUI

/// One row of "Your kosher needs in <city>" (kosherPrefs.ts cityNeedRows).
struct CityNeedRow: Identifiable {
    let need: String
    let ok: Bool
    let text: String
    var sub: String? = nil
    var id: String { need }
}

enum CityNeeds {
    static let plannerOnly = ["Shabbos walking distance", "Shabbos-friendly hotel (no key card)"]

    /// A shul listed with a daily minyan (its tags, hours, description or notes say so).
    static func dailyMinyan(_ v: Venue) -> Bool {
        if (v.tags ?? []).contains(where: { $0.range(of: #"daily\s*minyan"#, options: [.regularExpression, .caseInsensitive]) != nil }) { return true }
        let t = [v.hours ?? "", v.description, v.notes ?? ""].joined(separator: " ")
        return t.range(of: #"daily\s*minyan|daily\s*(shacharis|shacharit|services)|minyan\s*daily"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func mentionsKitchen(_ v: Venue) -> Bool {
        [v.description, v.kosherNotes ?? "", v.name].joined(separator: " ")
            .range(of: "kitchen|fridge|refrigerator|microwave", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func rows(_ page: CityPage, sections: [CitySection], needs: [String]) -> [CityNeedRow] {
        func items(_ c: PlaceCategory) -> [PlaceItem] { sections.first { $0.category == c }?.items ?? [] }
        let shuls = items(.shul), chabad = items(.chabad).count, groceries = items(.grocery).count
        var out: [CityNeedRow] = []
        for n in needs {
            switch n {
            case "Near a shul":
                out.append(.init(need: n, ok: !shuls.isEmpty, text: shuls.isEmpty ? "No shul listed here" : "\(shuls.count) \(shuls.count == 1 ? "shul" : "shuls") listed"))
            case "Daily minyan nearby":
                let k = shuls.filter { dailyMinyan($0.venue) }.count
                out.append(.init(need: n, ok: k > 0, text: k > 0 ? "\(k) \(k == 1 ? "shul lists" : "shuls list") a daily minyan" : "No daily minyan listed",
                                 sub: k > 0 ? nil : "Call the shul or Chabad to check"))
            case "Chabad house":
                out.append(.init(need: n, ok: chabad > 0, text: chabad > 0 ? "\(chabad) Chabad \(chabad == 1 ? "house" : "houses")" : "No Chabad house listed"))
            case "Mikvah nearby":
                let m = items(.mikvah).first?.venue.name
                out.append(.init(need: n, ok: m != nil, text: m ?? "No mikvah listed"))
            case "Kosher grocery nearby":
                out.append(.init(need: n, ok: groceries > 0, text: groceries > 0 ? "\(groceries) kosher \(groceries == 1 ? "grocery" : "groceries")" : "No kosher grocery listed"))
            case "Inside an eruv":
                let has = page.eruv != nil
                out.append(.init(need: n, ok: has, text: has ? "Eruv info listed" : "No eruv listed"))
            case SavedKosherPrefs.ownFood:
                let k = items(.hotel).filter { mentionsKitchen($0.venue) }.count
                let bits = [groceries > 0 ? "\(groceries) kosher \(groceries == 1 ? "grocery" : "groceries")" : "no kosher grocery listed",
                            k > 0 ? "\(k) \(k == 1 ? "hotel lists" : "hotels list") a kitchen or fridge" : "no hotel here lists a kitchen or fridge"]
                out.append(.init(need: n, ok: groceries > 0 || k > 0, text: bits.joined(separator: " · ")))
            default: break
            }
        }
        return out
    }
}

/// The top of the city hub: "No shul, Chabad house or kosher grocery listed in X." when nothing is saved, else
/// "Your kosher needs in X" with a row per saved need (App.tsx hub, KosherPrefsUI.tsx CityNeedsCard).
struct CityNeedsBlock: View {
    let page: CityPage
    let sections: [CitySection]
    private let store = ProfileStore.shared
    @State private var editing = false

    var body: some View {
        let needs = store.kosherPrefs?.needs ?? []
        if needs.isEmpty {
            missingNote
        } else {
            card(needs)
        }
    }

    @ViewBuilder private var missingNote: some View {
        let has = { (c: PlaceCategory) in sections.contains { $0.category == c && !$0.items.isEmpty } }
        let missing = [has(.shul) ? nil : "shul", has(.chabad) ? nil : "Chabad house", has(.grocery) ? nil : "kosher grocery"].compactMap { $0 }
        if !missing.isEmpty {
            let list = missing.count == 1 ? missing[0] : missing.dropLast().joined(separator: ", ") + " or " + missing.last!
            Text("No \(list) listed in \(page.name).")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .hairline(radius: 12)
        }
    }

    @ViewBuilder private func card(_ needs: [String]) -> some View {
        let rows = CityNeeds.rows(page, sections: sections, needs: needs)
        let planner = needs.filter { CityNeeds.plannerOnly.contains($0) }
        if !rows.isEmpty || !planner.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Your kosher needs in \(page.name)").font(.subheadline.weight(.semibold)).foregroundStyle(Color.navy)
                    Spacer()
                    Button("Edit") { editing = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.navy)
                        .frame(minHeight: 30)
                }
                ForEach(rows) { r in
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            if r.ok {
                                Circle().fill(Color.navy)
                                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                            } else {
                                Circle().strokeBorder(Color.hairline, lineWidth: 1)
                                Capsule().fill(Color.textTertiary).frame(width: 6, height: 1.5)
                            }
                        }
                        .frame(width: 18, height: 18)
                        .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.need).font(.footnote.weight(.medium)).foregroundStyle(Color.navy)
                            Text(r.sub.map { "\(r.text) · \($0)" } ?? r.text).font(.caption).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    if r.id != rows.last?.id || !planner.isEmpty { Divider().overlay(Color.hairline) }
                }
                if !planner.isEmpty {
                    Text("\(planner.joined(separator: ", ")): not listed on city pages yet. The trip planner takes \(planner.count == 1 ? "it" : "them") into account.")
                        .font(.caption).foregroundStyle(Color.textSecondary)
                        .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .hairline(radius: 16)
            .sheet(isPresented: $editing) {
                NavigationStack {
                    KosherPrefsView(store: store)
                        .navigationTitle("Kosher preferences")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { editing = false } } }
                }
            }
        }
    }
}
