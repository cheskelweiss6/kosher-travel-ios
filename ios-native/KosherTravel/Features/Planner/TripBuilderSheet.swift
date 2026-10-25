import SwiftUI

/// "Plan a trip": pick options instead of answering many questions (web: PlannerTripBuilder.tsx). It composes the same
/// plain message the web sends and carries the picks as this chat's trip filters. Mid-chat it opens as "Trip filters"
/// with the chat's current picks, and closing it applies only what changed to the same trip (web: mode "edit").
struct TripBuilderSheet: View {
    let places: [PlannerPlace]
    let initial: TripFilters?
    let onCreate: (String, TripFilters) -> Void
    let onApply: ((TripFilters) -> Void)?
    @Environment(\.dismiss) private var dismiss

    static let budgetMin = 500.0, budgetMax = 25000.0, budgetStep = 250.0, budgetDefault = 3000.0
    static let stays = ["Hotel", "Resort", "Vacation rental", "Hotel with kosher program"]
    static let interests = ["Nature", "Theme parks", "City", "Beach", "Museums", "Shopping"]
    static let paces = ["Relaxed", "Balanced", "Packed"]

    @State private var destination: String
    @State private var picked: PlannerPlace?
    @State private var useDates: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var days: Int
    @State private var adults: Int
    @State private var kids: Int
    @State private var budget: Double
    @State private var budgetExact: Bool
    @State private var budgetDraft = ""
    @State private var stays: Set<String>
    @State private var kosher: Set<String>
    @State private var kosherSaved = false
    @State private var interests: Set<String>
    @State private var pace: String
    @State private var applied = false
    @FocusState private var destFocused: Bool
    @FocusState private var budgetFocused: Bool

    private var edit: Bool { initial != nil }

    init(places: [PlannerPlace], initial: TripFilters? = nil, prefill: String? = nil,
         onCreate: @escaping (String, TripFilters) -> Void, onApply: ((TripFilters) -> Void)? = nil) {
        self.places = places
        self.initial = initial
        self.onCreate = onCreate
        self.onApply = onApply
        let f = initial ?? TripFilters()
        let s = Self.date(f.startDate)
        let e = Self.date(f.endDate)
        let span = Self.daysBetween(f.startDate, f.endDate)
        let n = span ?? f.days ?? 5
        let defaultStart = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400 * 14))
        _destination = State(initialValue: f.destination ?? prefill ?? "")
        _picked = State(initialValue: nil)
        _useDates = State(initialValue: s != nil)
        _start = State(initialValue: s ?? defaultStart)
        _end = State(initialValue: e ?? s.flatMap { Calendar.current.date(byAdding: .day, value: max(n, 1) - 1, to: $0) }
                     ?? (Calendar.current.date(byAdding: .day, value: 4, to: defaultStart) ?? defaultStart))
        _days = State(initialValue: min(max(n, 1), 21))
        _adults = State(initialValue: f.adults ?? 2)
        _kids = State(initialValue: f.kids ?? 0)
        _budget = State(initialValue: Double(f.budget ?? Int(Self.budgetDefault)))
        _budgetExact = State(initialValue: f.budget != nil ? !(f.budgetPlus ?? false) : false)
        _stays = State(initialValue: Set(f.stays ?? []))
        _kosher = State(initialValue: Set(f.kosher ?? []))   // planner kosher picks start blank (never the saved prefs)
        _interests = State(initialValue: Set(f.interests ?? []))
        _pace = State(initialValue: f.pace ?? "Balanced")
    }

    private var matches: [PlannerPlace] {
        let q = destination.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2, picked == nil, destFocused else { return [] }
        let n = StoryPost.norm(q)
        return Array(places.filter { StoryPost.norm($0.name).hasPrefix(n) }.prefix(5))
            + places.filter { !StoryPost.norm($0.name).hasPrefix(n) && StoryPost.norm($0.name + " " + $0.subtitle).contains(n) }.prefix(3)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(edit ? "Change anything. Your trip updates when you close this." : "Pick what fits. The planner takes it from there.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                Section {
                    TextField("Search a city or island", text: $destination)
                        .focused($destFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
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

                Section {
                    Toggle("Pick dates", isOn: $useDates.animation(Motion.expand))
                    if useDates {
                        DatePicker("Start", selection: $start, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                        DatePicker("End", selection: $end, in: start...(Calendar.current.date(byAdding: .day, value: 20, to: start) ?? start),
                                   displayedComponents: .date)
                    }
                } header: {
                    HStack {
                        Text("Dates")
                        Spacer()
                        if useDates { Text(Self.shortDates(start, end)).textCase(nil) }
                    }
                } footer: { Text("Optional") }

                Section("How many days") {
                    Stepper("\(days) \(days == 1 ? "day" : "days")", value: $days, in: 1...21)
                }

                Section("Who's going") {
                    Stepper("\(adults) \(adults == 1 ? "adult" : "adults")", value: $adults, in: 1...12)
                    Stepper(value: $kids, in: 0...12) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(kids) \(kids == 1 ? "child" : "kids")")
                            Text("Under 18").font(.caption).foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("$").font(.system(.title, design: .serif).weight(.bold)).foregroundStyle(Color.navy)
                            TextField("Amount", text: $budgetDraft)
                                .keyboardType(.numberPad)
                                .focused($budgetFocused)
                                .font(.system(.largeTitle, design: .serif).weight(.bold))
                                .foregroundStyle(Color.navy)
                                .monospacedDigit()
                                .accessibilityLabel("Budget in dollars for the whole trip")
                            Text("Tap to type").font(.footnote.weight(.medium)).foregroundStyle(Color.textSecondary)
                        }
                        Slider(value: Binding(get: { min(max(budget, Self.budgetMin), Self.budgetMax) },
                                              set: { budget = $0; budgetExact = false; budgetDraft = Self.amountText($0, exact: false) }),
                               in: Self.budgetMin...Self.budgetMax, step: Self.budgetStep)
                            .tint(Color.navy)
                        HStack {
                            Text(Self.money(Self.budgetMin))
                            Spacer()
                            Text(Self.money(12500))
                            Spacer()
                            Text(Self.money(Self.budgetMax) + "+")
                        }
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    }
                } header: { Text("Budget") } footer: { Text("Total for the trip") }

                Section("Where to stay") {
                    ForEach(Self.stays, id: \.self) { s in checkRow(s, selected: stays.contains(s)) { toggle(&stays, s) } }
                }

                Section {
                    kosherGroup("Food", SavedKosherPrefs.food)
                    kosherGroup("Near where I stay", SavedKosherPrefs.nearby)
                    kosherGroup("For my trips", SavedKosherPrefs.trip)
                    Button {
                        Task { await ProfileStore.shared.saveKosherPrefs(needs: SavedKosherPrefs.all.filter { kosher.contains($0) }, filtersOn: true) }
                        kosherSaved = true
                    } label: {
                        HStack {
                            Spacer()
                            if kosherSaved { Image(systemName: "checkmark") }
                            Text(kosherSaved ? "Saved. Used as your filters" : "Save my preferences").fontWeight(.semibold)
                            Spacer()
                        }
                        .foregroundStyle(Color.navy)
                    }
                    .sensoryFeedback(Motion.Haptic.success, trigger: kosherSaved) { _, now in now }
                } header: { Text("Kosher needs") } footer: { Text("Saved choices also filter places in the app") }

                Section("Interests") {
                    ForEach(Self.interests, id: \.self) { s in checkRow(s, selected: interests.contains(s)) { toggle(&interests, s) } }
                    Picker("Pace", selection: $pace) {
                        ForEach(Self.paces, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle(edit ? "Trip filters" : "Plan a trip")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .onAppear { budgetDraft = Self.amountText(budget, exact: budgetExact) }
            .onChange(of: budgetFocused) { _, focused in if !focused { commitBudget() } }
            .onChange(of: start) { _, new in
                end = Calendar.current.date(byAdding: .day, value: days - 1, to: new) ?? new
            }
            .onChange(of: end) { _, new in
                let n = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start),
                                                         to: Calendar.current.startOfDay(for: new)).day ?? 0) + 1
                if n >= 1 && n <= 21 && n != days { days = n }
            }
            .onChange(of: days) { _, n in
                guard useDates else { return }
                let e = Calendar.current.date(byAdding: .day, value: n - 1, to: start) ?? start
                if !Calendar.current.isDate(e, inSameDayAs: end) { end = e }
            }
            .onChange(of: kosher) { _, _ in kosherSaved = false }
            .onDisappear {
                // Web: closing the sheet mid-chat applies what changed (a swipe down too).
                if edit { applyChanges() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(edit ? "Close" : "Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: create) {
                    Text(edit ? "Update my trip" : "Create my trip")
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

    private func kosherGroup(_ title: String, _ options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.medium)).foregroundStyle(Color.textSecondary)
            PlannerChipFlow(options: options, selected: kosher) { o in toggle(&kosher, o) }
        }
        .padding(.vertical, 4)
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
        .sensoryFeedback(Motion.Haptic.selection, trigger: selected)
    }

    private func toggle(_ set: inout Set<String>, _ v: String) {
        if set.contains(v) { set.remove(v) } else { set.insert(v) }
    }

    private func placeLabel(_ p: PlannerPlace) -> String {
        [p.name, p.state.isEmpty ? p.country : p.state].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func commitBudget() {
        let digits = budgetDraft.filter(\.isNumber)
        if let n = Double(String(digits.prefix(8))), n >= 50 {
            budget = min(n, 10_000_000)
            budgetExact = true
        }
        budgetDraft = Self.amountText(budget, exact: budgetExact)
    }

    static func money(_ n: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.locale = Locale(identifier: "en_US")
        return "$" + (f.string(from: NSNumber(value: n.rounded())) ?? "\(Int(n))")
    }

    static func budgetText(_ n: Double) -> String { n >= budgetMax ? money(budgetMax) + "+" : money(n) }

    /// The number shown after "$": exact amounts as typed, slider amounts with "+" at the top.
    static func amountText(_ n: Double, exact: Bool) -> String {
        String((exact ? money(n) : budgetText(n)).dropFirst())
    }

    static func ymd(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(_ s: String?) -> Date? {
        guard let s, s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    static func daysBetween(_ a: String?, _ b: String?) -> Int? {
        guard let x = date(a), let y = date(b) else { return nil }
        let n = Int((y.timeIntervalSince(x) / 86400).rounded()) + 1
        return n >= 1 ? n : nil
    }

    /// "Mar 3–7", "Mar 30–Apr 2" (web: shortDates)
    static func shortDates(_ a: Date, _ b: Date) -> String {
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

    private var placeText: String {
        let typed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        return picked.map(placeLabel) ?? typed
    }

    /// Everything on screen, as this trip's filters (web: full()).
    private func full() -> TripFilters {
        var f = TripFilters()
        let place = placeText
        f.destination = place.isEmpty ? nil : place
        if useDates { f.startDate = Self.ymd(start); f.endDate = Self.ymd(end) }
        f.days = days
        f.adults = adults
        f.kids = kids
        f.budget = Int(budget.rounded())
        f.budgetPlus = !budgetExact && budget >= Self.budgetMax
        f.stays = Self.stays.filter { stays.contains($0) }
        f.kosher = SavedKosherPrefs.all.filter { kosher.contains($0) }
        f.interests = Self.interests.filter { interests.contains($0) }
        f.pace = pace
        return f
    }

    /// Mid-chat: keep the chat's picks and add only what was actually changed here (web: changedOnly()).
    private func changedOnly() -> TripFilters {
        let i = initial ?? TripFilters()
        let now = full()
        var out = i
        let baseDays = Self.daysBetween(i.startDate, i.endDate) ?? i.days ?? 5
        func same(_ a: [String]?, _ b: [String]?) -> Bool { (a ?? []).sorted() == (b ?? []).sorted() }
        if (now.destination ?? "") != (i.destination ?? "") { out.destination = now.destination }
        if (now.startDate ?? "") != (i.startDate ?? "") { out.startDate = now.startDate }
        if (now.endDate ?? "") != (i.endDate ?? "") { out.endDate = now.endDate }
        if now.days != baseDays { out.days = now.days }
        if now.adults != (i.adults ?? 2) || now.kids != (i.kids ?? 0) { out.adults = now.adults; out.kids = now.kids }
        if now.budget != (i.budget ?? Int(Self.budgetDefault)) || (now.budgetPlus ?? false) != (i.budget != nil ? (i.budgetPlus ?? false) : false) {
            out.budget = now.budget
            out.budgetPlus = now.budgetPlus
        }
        if !same(now.stays, i.stays) { out.stays = now.stays }
        if !same(now.kosher, i.kosher) { out.kosher = now.kosher }
        if !same(now.interests, i.interests) { out.interests = now.interests }
        if (now.pace ?? "") != (i.pace ?? "Balanced") { out.pace = now.pace }
        if !useDates { out.startDate = nil; out.endDate = nil }
        return out.cleaned
    }

    private func applyChanges() {
        guard edit, !applied else { return }
        applied = true
        if budgetFocused { commitBudget() }
        onApply?(changedOnly())
    }

    private func create() {
        if edit {
            applyChanges()
            dismiss()
            return
        }
        if budgetFocused { commitBudget() }
        let place = placeText
        let n = days
        var lines: [String] = []
        lines.append(place.isEmpty ? "Help me plan a trip (destination open, suggest a few)" : "Plan a trip to \(place)")
        let who = "\(adults) \(adults == 1 ? "adult" : "adults")" + (kids > 0 ? ", \(kids) \(kids == 1 ? "child" : "kids")" : "")
        let when = useDates ? "\(Self.shortDates(start, end)) · " : ""
        lines.append("\(when)\(n) \(n == 1 ? "day" : "days") · \(who)")
        lines.append(budgetExact || budget < Self.budgetMax ? "Budget: about \(Self.money(budget)) total" : "Budget: \(Self.money(Self.budgetMax))+ total")
        let stayList = Self.stays.filter { stays.contains($0) }
        if !stayList.isEmpty { lines.append("Stay: \(stayList.joined(separator: ", "))") }
        let kosherList = SavedKosherPrefs.all.filter { kosher.contains($0) }
        let needs = kosherList.filter { $0 != SavedKosherPrefs.ownFood }
        if !needs.isEmpty { lines.append("Kosher: \(needs.joined(separator: ", "))") }
        if kosherList.contains(SavedKosherPrefs.ownFood) {
            lines.append("Bringing my own food: kosher restaurants not required; prefer a stay with a kitchen or fridge, and a kosher grocery nearby")
        }
        let interestList = Self.interests.filter { interests.contains($0) }
        lines.append("Interests: \(interestList.isEmpty ? "open" : interestList.joined(separator: ", ")) · \(pace) pace")
        onCreate(lines.joined(separator: "\n"), full())
        dismiss()
    }
}

/// Wrapping chips (web: PrefChips): navy when picked, with a check.
struct PlannerChipFlow: View {
    let options: [String]
    let selected: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        PlannerFlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { o in
                let on = selected.contains(o)
                Button { onToggle(o) } label: {
                    HStack(spacing: 4) {
                        if on { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                        Text(o).font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(on ? Color.white : Color.navy)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 36)
                    .background(on ? Color.navy : Color.white, in: Capsule())
                    .overlay(Capsule().strokeBorder(on ? Color.clear : Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255), lineWidth: 1))
                    .animation(Motion.select, value: on)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(Motion.Haptic.selection, trigger: on)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Lines of views that wrap to the next line when full.
struct PlannerFlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: width.isFinite ? width : widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
