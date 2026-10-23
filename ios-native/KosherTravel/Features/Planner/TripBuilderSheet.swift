import SwiftUI

/// "Plan a trip": pick options instead of answering many questions (web: PlannerTripBuilder.tsx). It composes the same
/// plain message the web sends and carries the picks as this chat's trip settings.
struct TripBuilderSheet: View {
    let places: [PlannerPlace]
    let onCreate: (String, TripFilters) -> Void
    @Environment(\.dismiss) private var dismiss

    static let budgetMin = 500.0, budgetMax = 25000.0, budgetStep = 250.0
    static let stays = ["Hotel", "Resort", "Vacation rental", "Hotel with kosher program"]
    static let interests = ["Nature", "Theme parks", "City", "Beach", "Museums", "Shopping"]
    static let paces = ["Relaxed", "Balanced", "Packed"]

    @State private var destination = ""
    @State private var picked: PlannerPlace?
    @State private var useDates = false
    @State private var start = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400 * 14))
    @State private var end = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400 * 18))
    @State private var days = 5
    @State private var adults = 2
    @State private var kids = 0
    @State private var budget = 3000.0
    @State private var stays: Set<String> = []
    @State private var interests: Set<String> = []
    @State private var pace = "Balanced"
    @FocusState private var destFocused: Bool

    private var matches: [PlannerPlace] {
        let q = destination.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, picked == nil else { return [] }
        let n = StoryPost.norm(q)
        return Array(places.filter { StoryPost.norm($0.name).hasPrefix(n) }.prefix(5))
            + places.filter { !StoryPost.norm($0.name).hasPrefix(n) && StoryPost.norm($0.name + " " + $0.subtitle).contains(n) }.prefix(3)
    }

    private var tripDays: Int {
        guard useDates else { return days }
        let n = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return max(1, n)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("City or country", text: $destination)
                        .focused($destFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onChange(of: destination) { _, new in
                            if let p = picked, new != placeLabel(p) { picked = nil }
                        }
                    ForEach(matches) { p in
                        Button {
                            picked = p
                            destination = placeLabel(p)
                            destFocused = false
                        } label: {
                            HStack {
                                Image(systemName: "mappin.and.ellipse").foregroundStyle(Color.navy)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).foregroundStyle(Color.navy)
                                    Text(p.subtitle).font(.caption).foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                    }
                } header: { Text("Where to?") } footer: { Text("Leave it empty and the planner suggests a few places.") }

                Section("When") {
                    Toggle("Pick dates", isOn: $useDates.animation())
                    if useDates {
                        DatePicker("From", selection: $start, in: Date()..., displayedComponents: .date)
                        DatePicker("To", selection: $end, in: start..., displayedComponents: .date)
                    } else {
                        Stepper("\(days) \(days == 1 ? "day" : "days")", value: $days, in: 1...30)
                    }
                }

                Section("Who") {
                    Stepper("\(adults) \(adults == 1 ? "adult" : "adults")", value: $adults, in: 1...20)
                    Stepper("\(kids) \(kids == 1 ? "child" : "kids")", value: $kids, in: 0...20)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.budgetText(budget))
                            .font(.system(.title, design: .serif).weight(.bold))
                            .foregroundStyle(Color.navy)
                            .monospacedDigit()
                        Slider(value: $budget, in: Self.budgetMin...Self.budgetMax, step: Self.budgetStep)
                    }
                } header: { Text("Budget") } footer: { Text("Total for the trip") }

                Section("Stay") {
                    ForEach(Self.stays, id: \.self) { s in checkRow(s, selected: stays.contains(s)) { toggle(&stays, s) } }
                }

                Section("Interests") {
                    ForEach(Self.interests, id: \.self) { s in checkRow(s, selected: interests.contains(s)) { toggle(&interests, s) } }
                }

                Section("Pace") {
                    Picker("Pace", selection: $pace) {
                        ForEach(Self.paces, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Plan a trip")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: start) { _, new in if end < new { end = new } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: create) {
                    Text("Create my trip")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white)
                        .background(Color.navy, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    private func checkRow(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(Color.navy)
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Color.navy) }
            }
            .contentShape(Rectangle())
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func toggle(_ set: inout Set<String>, _ v: String) {
        if set.contains(v) { set.remove(v) } else { set.insert(v) }
    }

    private func placeLabel(_ p: PlannerPlace) -> String {
        [p.name, p.state.isEmpty ? p.country : p.state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func money(_ n: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return "$" + (f.string(from: NSNumber(value: n.rounded())) ?? "\(Int(n))")
    }

    static func budgetText(_ n: Double) -> String { n >= budgetMax ? money(budgetMax) + "+" : money(n) }

    private static func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// "Mar 3–7", "Mar 30–Apr 2" (web: shortDates)
    private static func shortDates(_ a: Date, _ b: Date) -> String {
        let cal = Calendar.current
        let mon = DateFormatter()
        mon.locale = Locale(identifier: "en_US")
        mon.dateFormat = "MMM"
        let ya = cal.component(.year, from: a), yb = cal.component(.year, from: b)
        let da = cal.component(.day, from: a), db = cal.component(.day, from: b)
        if ya != yb { return "\(mon.string(from: a)) \(da), \(ya)–\(mon.string(from: b)) \(db), \(yb)" }
        if cal.component(.month, from: a) == cal.component(.month, from: b) {
            return da == db ? "\(mon.string(from: a)) \(da)" : "\(mon.string(from: a)) \(da)–\(db)"
        }
        return "\(mon.string(from: a)) \(da)–\(mon.string(from: b)) \(db)"
    }

    private func create() {
        let typed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = picked.map(placeLabel) ?? typed
        let n = tripDays
        var lines: [String] = []
        lines.append(place.isEmpty ? "Help me plan a trip (destination open, suggest a few)" : "Plan a trip to \(place)")
        let who = "\(adults) \(adults == 1 ? "adult" : "adults")" + (kids > 0 ? ", \(kids) \(kids == 1 ? "child" : "kids")" : "")
        let when = useDates ? "\(Self.shortDates(start, end)) · " : ""
        lines.append("\(when)\(n) \(n == 1 ? "day" : "days") · \(who)")
        lines.append(budget < Self.budgetMax ? "Budget: about \(Self.money(budget)) total" : "Budget: \(Self.money(Self.budgetMax))+ total")
        let stayList = Self.stays.filter { stays.contains($0) }
        if !stayList.isEmpty { lines.append("Stay: \(stayList.joined(separator: ", "))") }
        let interestList = Self.interests.filter { interests.contains($0) }
        lines.append("Interests: \(interestList.isEmpty ? "open" : interestList.joined(separator: ", ")) · \(pace) pace")

        var f = TripFilters()
        f.destination = place.isEmpty ? nil : place
        if useDates { f.startDate = Self.ymd(start); f.endDate = Self.ymd(end) }
        f.days = n
        f.adults = adults
        f.kids = kids
        f.budget = Int(budget.rounded())
        f.budgetPlus = budget >= Self.budgetMax
        f.stays = stayList
        f.interests = interestList
        f.pace = pace
        onCreate(lines.joined(separator: "\n"), f)
        dismiss()
    }
}
