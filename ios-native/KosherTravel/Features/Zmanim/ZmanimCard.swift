// The Zmanim card, ported from the website's src/components/zmanim/ZmanimCard.tsx (read-only source):
//  - compact: one slim row on city and state pages (ZmanimCompact); a tap opens the full zmanim in a sheet;
//  - full: the whole card (ZmanimCard default export), used on the Shabbat page.
// Same words, order, numbers and options as the website. Everything is computed on the phone.
import SwiftUI
import CoreLocation

// MARK: - Public API

/// `ZmanimCard(place:compact:)`: the website's `<ZmanimCardLazy place={{ id, name, state }} compact />` (city page),
/// `place={{ state }}` (state page), and the full card without `compact` (Shabbat page).
struct ZmanimCard: View {
    let place: ZmanimPlace
    let compact: Bool
    var title: String = "Zmanim"

    init(place: ZmanimPlace, compact: Bool, title: String = "Zmanim") {
        self.place = place
        self.compact = compact
        self.title = title
    }

    var body: some View {
        if compact {
            ZmanimCompactCard(place: place, title: title)
        } else {
            ZmanimFullCard(place: place, title: title, bare: false, override: nil)
        }
    }
}

// MARK: - Colors and type (the website's slate scale)

enum ZmanimColor {
    static let slate900 = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
    static let slate800 = Color(red: 30 / 255, green: 41 / 255, blue: 59 / 255)
    static let slate700 = Color(red: 51 / 255, green: 65 / 255, blue: 85 / 255)
    static let slate600 = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
    static let slate500 = Color.textSecondary
    static let slate400 = Color.textTertiary
    static let slate300 = Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255)
    static let slate100 = Color(red: 241 / 255, green: 245 / 255, blue: 249 / 255)
    static let sheetBg = Color(red: 246 / 255, green: 246 / 255, blue: 248 / 255)
    static let searchBg = Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)
    static let error = Color(red: 185 / 255, green: 28 / 255, blue: 28 / 255)
}

/// The website's pixel sizes, scaled with Dynamic Type.
struct ZmanimFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let serif: Bool
    init(size: CGFloat, weight: Font.Weight, serif: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
        self.serif = serif
    }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: serif ? .serif : .default))
    }
}

extension View {
    func zFont(_ size: CGFloat, _ weight: Font.Weight = .regular, serif: Bool = false) -> some View {
        modifier(ZmanimFontModifier(size: size, weight: weight, serif: serif))
    }
}

// MARK: - Shared helpers

enum ZmanimText {
    static let short: [ZmanimKey: String] = [
        .alos: "Alos", .misheyakir: "Misheyakir", .netz: "Netz", .shmaMGA: "Shma (MGA)", .shmaGRA: "Shma (GRA)",
        .tefillaMGA: "Tefilla (MGA)", .tefillaGRA: "Tefilla (GRA)", .chatzos: "Chatzos", .minchaGedola: "Mincha Gedola",
        .minchaKetana: "Mincha Ketana", .plag: "Plag Hamincha", .shkia: "Shkia", .tzeis: "Tzeis",
        .candles: "Candle lighting", .fastBegins: "Fast begins", .fastEnds: "Fast ends", .havdalahRT: "Rabbeinu Tam",
    ]
    static let wd = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    /// label.replace(/ \(.*\)$/, '')
    static func dropParen(_ label: String) -> String {
        guard label.hasSuffix(")"), let r = label.range(of: " (") else { return label }
        return String(label[..<r.lowerBound])
    }
    /// label.match(/^(.*) \((.*)\)$/) → (main, opinion)
    static func splitParen(_ label: String) -> (String, String?) {
        guard label.hasSuffix(")"), let r = label.range(of: " (", options: .backwards) else { return (label, nil) }
        let inner = label[r.upperBound..<label.index(before: label.endIndex)]
        return (String(label[..<r.lowerBound]), String(inner))
    }
    static func shortName(_ it: ZmanimItem) -> String {
        if it.key == .havdalah { return it.label.hasPrefix("Yom Tov") ? "Yom Tov ends" : "Shabbos ends" }
        return short[it.key] ?? dropParen(it.label)
    }
    /// "6:12 PM" → ("6:12", "PM")
    static func splitTime(_ t: String) -> (String, String) {
        guard let r = t.range(of: " ", options: .backwards), r.lowerBound != t.startIndex else { return (t, "") }
        return (String(t[..<r.lowerBound]), String(t[r.upperBound...]))
    }
    static func city(_ label: String) -> String {
        let l = label.hasPrefix("Near ") ? String(label.dropFirst(5)) : label
        return l.components(separatedBy: ",").first ?? l
    }
    static var nowMs: Double { Date().timeIntervalSince1970 * 1000 }
    /// where.label.replace(/^Near /, 'near ')
    static func noteLabel(_ label: String) -> String {
        label.hasPrefix("Near ") ? "near " + String(label.dropFirst(5)) : label
    }
}


// MARK: - Compact card (city and state pages)

struct ZmanimCompactCard: View {
    let place: ZmanimPlace
    var title: String = "Zmanim"
    @State private var override: ZmanimWhere?
    @State private var open = false
    @State private var width: CGFloat = 0

    private struct Pick { let label: String; let it: ZmanimItem }
    private struct ViewData { let next: ZmanimItem; let tomorrow: Bool; let keys: [Pick] }

    private func compute(_ where_: ZmanimWhere, now: Double, opts: ZmanimOpts) -> ViewData? {
        let today = ZmanimDates.today(in: where_.tz)
        func day(_ d: String) -> ZmanimDay { ZmanimEngine.day(d, lat: where_.lat, lng: where_.lng, tz: where_.tz, opts: opts) }
        func upcoming(_ z: ZmanimDay) -> [ZmanimItem] {
            let list = (z.items.filter { $0.core } + z.highlights).filter { ($0.ms ?? -Double.infinity) > now && $0.ms != nil }
            return list.enumerated().sorted { ($0.element.ms ?? 0) != ($1.element.ms ?? 0) ? ($0.element.ms ?? 0) < ($1.element.ms ?? 0) : $0.offset < $1.offset }.map(\.element)
        }
        var base = day(today)
        var tomorrow = false
        var next = upcoming(base).first
        if next == nil {
            base = day(ZmanimDates.addDays(today, 1))
            tomorrow = true
            next = upcoming(base).first ?? base.items.first
        }
        guard let next else { return nil }
        var pick: [Pick] = []
        let candles = base.highlights.first { $0.key == .candles }
        let ends = base.highlights.first { $0.key == .havdalah }
        let shk = base.items.first { $0.key == .shkia }
        let tz = base.items.first { $0.key == .tzeis }
        if let candles { pick.append(Pick(label: "Candles", it: candles)) }
        if let ends { pick.append(Pick(label: ZmanimText.shortName(ends), it: ends)) }
        if let shk { pick.append(Pick(label: "Shkia", it: shk)) }
        if candles == nil && ends == nil {
            // A weekday: the coming candle lighting (Friday, or an earlier Yom Tov).
            for n in 1...6 {
                let z = day(ZmanimDates.addDays(base.date, n))
                if let c = z.highlights.first(where: { $0.key == .candles }) {
                    pick.append(Pick(label: "Candles \(ZmanimText.wd[z.weekday])", it: c))
                    break
                }
            }
        }
        if let tz { pick.append(Pick(label: "Tzeis", it: tz)) }
        let keys = pick.filter { !($0.it == next) && !($0.it.key == next.key && $0.it.ms == next.ms) }.prefix(2)
        return ViewData(next: next, tomorrow: tomorrow, keys: Array(keys))
    }

    var body: some View {
        let pageWhere = ZmanimPlaces.resolve(place)
        if let where_ = override ?? pageWhere {
            TimelineView(.everyMinute) { ctx in
                let now = ctx.date.timeIntervalSince1970 * 1000
                if let v = compute(where_, now: now, opts: ZmanimPrefsStore.shared.opts) {
                    row(where_, v)
                }
            }
            .sheet(isPresented: $open) {
                ZmanimFullSheet(title: "\(title) · \(ZmanimText.city(where_.label))", onClose: { open = false }) {
                    ZmanimFullCard(place: place, title: title, bare: true, override: $override)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ where_: ZmanimWhere, _ v: ViewData) -> some View {
        let time = ZmanimEngine.format(v.next.ms, tz: where_.tz)
        let split = ZmanimText.splitTime(time)
        let hm = split.0, ap = split.1
        let nextName = ZmanimText.shortName(v.next)
        let second = v.keys.first
        Button {
            open = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .zFont(16)
                    .foregroundStyle(Color.navy)
                (Text(title).fontWeight(.semibold).foregroundStyle(Color.navy)
                 + Text(" · ").foregroundStyle(ZmanimColor.slate400)
                 + Text(v.tomorrow ? "Tomorrow" : "Next").foregroundStyle(ZmanimColor.slate500)
                 + Text(" · ").foregroundStyle(ZmanimColor.slate400)
                 + Text("\(nextName) \(hm)\(ap.isEmpty ? "" : " \(ap)")").fontWeight(.medium).foregroundStyle(Color.navy).monospacedDigit())
                    .zFont(14)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let second, width >= 400 {
                    Text("\(second.label) \(ZmanimEngine.format(second.it.ms, tz: where_.tz))")
                        .zFont(12)
                        .monospacedDigit()
                        .foregroundStyle(ZmanimColor.slate500)
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .zFont(16)
                    .foregroundStyle(ZmanimColor.slate400)
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(ZmanimPressStyle(radius: 12))
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .hairline(radius: 12)
        .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { w in width = w }
        .accessibilityLabel("Zmanim for \(where_.label). Next: \(nextName) \(time)\(v.tomorrow ? " tomorrow" : ""). See all zmanim")
        .accessibilityAddTraits(.isButton)
    }
}

/// Grey wash on press, like the website's hover/active state.
struct ZmanimPressStyle: ButtonStyle {
    var radius: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.surface : Color.clear, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// The full zmanim over the page (ZmanimFullSheet): clock, title, close X; the card below scrolls.
struct ZmanimFullSheet<Content: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .zFont(19)
                    .foregroundStyle(Color.navy)
                    .accessibilityHidden(true)
                Text(title)
                    .zFont(17, .semibold)
                    .foregroundStyle(Color.navy)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .zFont(20)
                        .foregroundStyle(Color.navy)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close zmanim")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.top, 14)
            .frame(minHeight: 52)
            Rectangle().fill(ZmanimColor.slate100).frame(height: 1)
            ScrollView {
                content()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.white)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
    }
}

// MARK: - Full card

struct ZmanimFullCard: View {
    let place: ZmanimPlace
    var title: String = "Zmanim"
    /// Inside the full-zmanim sheet: no outer card; the sheet's header carries the title.
    var bare: Bool = false
    /// A place picked in the sheet, owned by the compact card so it shows there too.
    var override: Binding<ZmanimWhere?>?

    @State private var overrideLocal: ZmanimWhere?
    @State private var dateSel: String = ""
    @State private var all = false
    @State private var optsOpen = false
    @State private var locOpen = false
    @State private var pickerOpen = false

    private var currentOverride: ZmanimWhere? { override?.wrappedValue ?? (override == nil ? overrideLocal : nil) }
    private func setOverride(_ w: ZmanimWhere?) {
        if let override { override.wrappedValue = w } else { overrideLocal = w }
    }

    var body: some View {
        if let where_ = currentOverride ?? ZmanimPlaces.resolve(place) {
            TimelineView(.everyMinute) { ctx in
                content(where_, nowMs: ctx.date.timeIntervalSince1970 * 1000)
            }
            .sheet(isPresented: $optsOpen) { ZmanimOpinionsSheet(onClose: { optsOpen = false }) }
            .sheet(isPresented: $locOpen) {
                ZmanimLocationSheet(current: where_.label, onClose: { locOpen = false }) { p in
                    setOverride(ZmanimWhere(lat: p.lat, lng: p.lng, tz: p.tz, label: p.name))
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ where_: ZmanimWhere, nowMs: Double) -> some View {
        let today = ZmanimDates.today(in: where_.tz)
        let date = dateSel.isEmpty ? today : dateSel
        let z = ZmanimEngine.day(date, lat: where_.lat, lng: where_.lng, tz: where_.tz, opts: ZmanimPrefsStore.shared.opts)
        let items = all ? z.items : z.items.filter { $0.core }
        let names = z.names.filter { !$0.isEmpty }
        let weekParsha = z.parsha ?? ZmanimCalendar.day(ZmanimDates.addDays(date, (6 - z.weekday + 7) % 7)).names.first { $0.hasPrefix("Parshas ") }
        let isToday = date == today

        VStack(alignment: .leading, spacing: 0) {
            if bare {
                HStack(spacing: 8) {
                    locButton(where_)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    optsButton
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .zFont(20)
                        .foregroundStyle(Color.navy)
                        .accessibilityHidden(true)
                    Text(title)
                        .zFont(17, .semibold)
                        .foregroundStyle(Color.navy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    optsButton
                }
                locButton(where_)
                    .padding(.top, 4)
            }

            // Day switcher: previous, the date (tap to pick), next.
            HStack(spacing: 8) {
                circleButton("chevron.left", label: "Previous day") { dateSel = ZmanimDates.addDays(date, -1) }
                Button { pickerOpen = true } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(z.weekday == 6 ? "Shabbos" : ZmanimDates.weekdayLong(date))
                                .zFont(15, .semibold).foregroundStyle(ZmanimColor.slate900).lineLimit(1)
                            if let weekParsha {
                                Text(ZmanimHebrew.parshaEn(weekParsha))
                                    .zFont(13).foregroundStyle(ZmanimColor.slate600).lineLimit(1)
                            }
                            Text("\(ZmanimDates.dayLabel(date))\(isToday ? " · Today" : "")")
                                .zFont(12).foregroundStyle(ZmanimColor.slate500).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(ZmanimHebrew.dayHe[z.weekday])
                                .zFont(15, .semibold).foregroundStyle(ZmanimColor.slate900).lineLimit(1)
                            let ph = ZmanimHebrew.parshaHe(weekParsha)
                            if weekParsha != nil && !ph.isEmpty {
                                Text(ph).zFont(13).foregroundStyle(ZmanimColor.slate600).lineLimit(1)
                            }
                            let hd = ZmanimHebrew.dateHe(date)
                            Text(hd.isEmpty ? ZmanimHebrew.dateEn(date) : hd)
                                .zFont(12).foregroundStyle(ZmanimColor.slate500).lineLimit(1)
                        }
                        .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(ZmanimPressStyle(radius: 12))
                .hairline(radius: 12)
                .accessibilityHint("Choose a date")
                .popover(isPresented: $pickerOpen) {
                    ZmanimDatePopover(date: date) { picked in
                        dateSel = picked
                        pickerOpen = false
                    }
                    .presentationCompactAdaptation(.popover)
                }
                circleButton("chevron.right", label: "Next day") { dateSel = ZmanimDates.addDays(date, 1) }
            }
            .padding(.top, 8)

            if !isToday {
                Button { dateSel = today } label: {
                    Text("Back to today")
                        .zFont(14, .medium)
                        .foregroundStyle(Color.navy)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            if !names.isEmpty {
                Text(names.joined(separator: " · "))
                    .zFont(13)
                    .foregroundStyle(ZmanimColor.slate600)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }

            if !z.highlights.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(z.highlights.enumerated()), id: \.offset) { i, h in
                        if i > 0 { Rectangle().fill(Color.navy.opacity(0.10)).frame(height: 1) }
                        ZmanimRow(it: h, tz: where_.tz, strong: h.key == .candles || h.key == .havdalah,
                                  past: isToday && h.ms != nil && (h.ms ?? 0) < nowMs)
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.navy.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.navy.opacity(0.15), lineWidth: 1))
                .padding(.top, 12)
            }

            Text(isToday ? "Upcoming zmanim" : "Zmanim")
                .zFont(13, .semibold)
                .foregroundStyle(ZmanimColor.slate500)
                .padding(.top, 12)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.key) { i, it in
                    if i > 0 { Rectangle().fill(ZmanimColor.slate100).frame(height: 1) }
                    ZmanimRow(it: it, tz: where_.tz, strong: false, past: isToday && it.ms != nil && (it.ms ?? 0) < nowMs)
                }
            }
            .padding(.top, 2)

            Button {
                withAnimation(Motion.expand) { all.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(all ? "Show fewer" : "Show all zmanim").zFont(14, .semibold)
                    Image(systemName: "chevron.down")
                        .zFont(14)
                        .rotationEffect(.degrees(all ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.navy)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(ZmanimPressStyle(radius: 12))
            .padding(.top, 4)
            .accessibilityValue(all ? "Expanded" : "Collapsed")

            Text("Times for \(ZmanimText.noteLabel(where_.label)). Check with your local rav.")
                .zFont(12)
                .foregroundStyle(ZmanimColor.slate500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, bare ? 0 : 16)
        .padding(.top, bare ? 0 : 12)
        .padding(.bottom, bare ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: bare ? 0 : 16, style: .continuous))
        .modifier(ZmanimOptionalHairline(on: !bare, radius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zmanim for \(where_.label)")
    }

    private var optsButton: some View {
        Button { optsOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "gearshape").zFont(17).accessibilityHidden(true)
                Text("My zmanim").zFont(14, .medium)
            }
            .foregroundStyle(Color.navy)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(ZmanimPressStyle(radius: 22))
        .padding(.trailing, -8)
        .fixedSize()
        .accessibilityLabel("My zmanim opinions")
    }

    private func locButton(_ where_: ZmanimWhere) -> some View {
        Button { locOpen = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse").zFont(16).accessibilityHidden(true)
                Text(where_.label).zFont(14, .medium).lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").zFont(15).accessibilityHidden(true)
            }
            .foregroundStyle(Color.navy)
            .padding(.leading, 8)
            .padding(.trailing, 12)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(ZmanimPressStyle(radius: 22))
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
        .padding(.leading, -4)
        .accessibilityLabel("Location: \(where_.label). Change location")
    }

    private func circleButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .zFont(18, .medium)
                .foregroundStyle(Color.navy)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(ZmanimPressStyle(radius: 22))
        .background(Color.white, in: Circle())
        .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
        .accessibilityLabel(label)
    }
}

struct ZmanimOptionalHairline: ViewModifier {
    let on: Bool
    let radius: CGFloat
    @ViewBuilder
    func body(content: Content) -> some View {
        if on { content.hairline(radius: radius) } else { content }
    }
}

/// The website's invisible date input, as a native calendar popover.
struct ZmanimDatePopover: View {
    let date: String
    let onPick: (String) -> Void
    @State private var value = Date()

    var body: some View {
        DatePicker("Choose a date", selection: $value, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .tint(Color.navy)
            .labelsHidden()
            .padding(12)
            .frame(minWidth: 320)
            .onAppear { value = ZmanimDates.toPicker(date) }
            .onChange(of: value) { _, v in
                let s = ZmanimDates.fromPicker(v)
                if s != date && ZmanimDates.isISO(s) { onPick(s) }
            }
    }
}

/// One zman: the time big on the left; on the right the Hebrew name and, under it, the English name with the opinion
/// in grey ("Alos Hashachar · 72 min"). Times already passed today are greyed.
struct ZmanimRow: View {
    let it: ZmanimItem
    let tz: String
    var strong: Bool = false
    var past: Bool = false

    var body: some View {
        let parts = ZmanimText.splitParen(it.label)
        let main = parts.0, opinion = parts.1
        let sub = [opinion, it.note].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let he = it.key == .havdalah && it.label.hasPrefix("Yom Tov") ? "מוצאי יום טוב" : (ZmanimHebrew.zman[it.key] ?? "")
        let t = ZmanimEngine.format(it.ms, tz: tz)
        let split = ZmanimText.splitTime(t)
        let hm = split.0, ap = split.1
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(hm)
                    .zFont(21, strong ? .bold : .semibold)
                    .monospacedDigit()
                    .foregroundStyle(past ? ZmanimColor.slate400 : Color.navy)
                if !ap.isEmpty {
                    Text(ap)
                        .zFont(12, .medium)
                        .foregroundStyle(past ? ZmanimColor.slate400 : ZmanimColor.slate500)
                }
            }
            .fixedSize()
            VStack(alignment: .trailing, spacing: 2) {
                if !he.isEmpty {
                    Text(he)
                        .zFont(16, strong ? .bold : .semibold)
                        .foregroundStyle(past ? ZmanimColor.slate400 : ZmanimColor.slate900)
                        .multilineTextAlignment(.trailing)
                }
                Text(sub.isEmpty ? main : "\(main) · \(sub)")
                    .zFont(12.5)
                    .foregroundStyle(past ? ZmanimColor.slate400 : ZmanimColor.slate500)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(it.label), \(t)\(past ? ", passed" : "")")
    }
}

// MARK: - Sheet chrome (the website's BottomSheet: handle, serif title, Done)

struct ZmanimSheetChrome<Content: View, Footer: View>: View {
    let title: String
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .zFont(18, .bold, serif: true)
                    .foregroundStyle(ZmanimColor.slate900)
                    .accessibilityAddTraits(.isHeader)
                HStack {
                    Spacer()
                    Button("Done", action: onClose)
                        .zFont(15, .semibold)
                        .foregroundStyle(Color.navy)
                        .frame(minHeight: 44)
                        .padding(.horizontal, 8)
                }
                .padding(.trailing, 4)
            }
            .frame(height: 44)
            .padding(.top, 16)
            .padding(.bottom, 4)
            ScrollView {
                content()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            footer()
        }
        .background(ZmanimColor.sheetBg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(22)
        .presentationBackground(ZmanimColor.sheetBg)
    }
}

// MARK: - "My zmanim" opinions

struct ZmanimOpinionsSheet: View {
    let onClose: () -> Void

    private static func nightChip(_ v: ZmanimNightOpt) -> String {
        switch v {
        case .deg8_5: return "8.5° (stars)"
        case .deg7_083: return "7.083° (3 small stars)"
        case .m72: return "72 min (Rabbeinu Tam)"
        default: return "\(v.rawValue.dropFirst()) min"
        }
    }

    var body: some View {
        let store = ZmanimPrefsStore.shared
        let o = store.opts
        ZmanimSheetChrome(title: "My zmanim", onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Choose the opinions you hold. Every Zmanim card, the trip planner and the AI use them. Saved on this phone, and to your account when you're signed in.")
                    .zFont(14)
                    .foregroundStyle(ZmanimColor.slate500)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 12)
                VStack(alignment: .leading, spacing: 0) {
                    ZmanimChoice(title: "Alos Hashachar", value: o.alos, options: ZmanimAlosOpt.allCases, label: { ZmanimLabels.alos($0) }) { v in store.save { $0.alos = v } }
                    ZmanimChoice(title: "Misheyakir (talis and tefillin)", value: o.misheyakir, options: ZmanimMisheyakirOpt.allCases, label: { ZmanimLabels.misheyakir($0) }) { v in store.save { $0.misheyakir = v } }
                    ZmanimChoice(title: "Sof Zman Shma and Tefilla", value: o.shma, options: ZmanimShmaOpt.allCases, label: { $0 == .both ? "MGA and GRA" : $0 == .mga ? "MGA" : "GRA" }) { v in store.save { $0.shma = v } }
                    ZmanimChoice(title: "Mincha and Plag", value: o.mincha, options: ZmanimMinchaOpt.allCases, label: { $0 == .mga72 ? "MGA (72 min)" : "GRA" }) { v in store.save { $0.mincha = v } }
                    ZmanimChoice(title: "Tzeis (nightfall)", value: o.tzeis, options: ZmanimNightOpt.allCases, label: { Self.nightChip($0) }) { v in store.save { $0.tzeis = v } }
                    ZmanimChoice(title: "Candle lighting (before shkia)", value: o.candle, options: ZmanimOpts.candleOptions, label: { "\($0) min" }) { v in store.save { $0.candle = v } }
                    ZmanimChoice(title: "Motzei Shabbos / Yom Tov ends", value: o.havdalah, options: ZmanimNightOpt.allCases, label: { Self.nightChip($0) }) { v in store.save { $0.havdalah = v } }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline.opacity(0.7), lineWidth: 1))
                Text("Now: \(ZmanimLabels.summary(o)).")
                    .zFont(12)
                    .foregroundStyle(ZmanimColor.slate500)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 12)
            }
        } footer: {
            Button(action: onClose) {
                Text("Done")
                    .zFont(16, .semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.navy, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }
}

struct ZmanimChoice<T: Hashable>: View {
    let title: String
    let value: T
    let options: [T]
    let label: (T) -> String
    let onPick: (T) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .zFont(14, .semibold)
                .foregroundStyle(ZmanimColor.slate900)
                .accessibilityAddTraits(.isHeader)
            ZmanimFlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { o in
                    let on = o == value
                    Button {
                        onPick(o)
                    } label: {
                        HStack(spacing: 6) {
                            if on { Image(systemName: "checkmark").zFont(13, .semibold).accessibilityHidden(true) }
                            Text(label(o)).zFont(14, .medium)
                        }
                        .foregroundStyle(on ? Color.white : ZmanimColor.slate700)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(on ? Color.navy : Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(on ? Color.clear : ZmanimColor.slate300, lineWidth: 1))
                        .animation(Motion.select, value: on)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(Motion.Haptic.selection, trigger: on)
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
        }
        .padding(.bottom, 16)
    }
}

/// Chips that wrap onto new lines (the website's flex-wrap).
struct ZmanimFlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { y += rowH + spacing; x = 0; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Location: current location or any city

@Observable
final class ZmanimLocator: NSObject, CLLocationManagerDelegate {
    private(set) var busy = false
    private(set) var error = ""
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var onFix: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    private static let offMessage = "Location is off for Kosher Travel. Turn it on in iPhone Settings > Kosher Travel, or search for a city below."

    func locate(_ done: @escaping (CLLocation) -> Void) {
        error = ""
        guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil else {
            error = "Location isn’t available. Search for a city instead."
            return
        }
        onFix = done
        switch manager.authorizationStatus {
        case .denied, .restricted:
            error = Self.offMessage
        case .notDetermined:
            busy = true
            manager.requestWhenInUseAuthorization()
        default:
            if let l = manager.location, abs(l.timestamp.timeIntervalSinceNow) < 600 { finish(l); return }
            busy = true
            manager.requestLocation()
        }
    }

    private func finish(_ l: CLLocation) {
        busy = false
        let cb = onFix
        onFix = nil
        cb?(l)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard onFix != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            busy = true
            manager.requestLocation()
        case .denied, .restricted:
            busy = false
            error = Self.offMessage
            onFix = nil
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard onFix != nil, let l = locations.last else { return }
        finish(l)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError e: Error) {
        guard onFix != nil else { return }
        busy = false
        onFix = nil
        if let ce = e as? CLError, ce.code == .denied { error = Self.offMessage }
        else { error = "Could not get your location. Search for a city below." }
    }
}

struct ZmanimLocationSheet: View {
    var current: String?
    let onClose: () -> Void
    let onPick: (ZmanimSavedPlace) -> Void

    @State private var q = ""
    @State private var locator = ZmanimLocator()
    @FocusState private var searchFocused: Bool

    private func pick(_ p: ZmanimSavedPlace) {
        ZmanimPrefsStore.shared.savePlace(p)
        onPick(p)
        onClose()
    }

    private func locate() {
        locator.locate { loc in
            let lat = loc.coordinate.latitude, lng = loc.coordinate.longitude
            let near = ZmanimPlaces.nearestStoryCity(lat, lng, maxKm: 60)
            let name = near.map { "Near \($0.name), \(ZmanimPlaces.short($0.sub))" } ?? "My location"
            pick(ZmanimSavedPlace(name: name, lat: lat, lng: lng, tz: ZmanimPlaces.tzNear(lat, lng, fallback: ZmanimPlaces.guessTz), gps: true))
        }
    }

    var body: some View {
        let trimmed = q.trimmingCharacters(in: .whitespacesAndNewlines)
        let hits = ZmanimPlaces.search(q)
        ZmanimSheetChrome(title: "Zmanim location", onClose: onClose) {
            VStack(alignment: .leading, spacing: 0) {
                if let current, !current.isEmpty {
                    (Text("Now showing: ").foregroundStyle(ZmanimColor.slate500)
                     + Text(current).fontWeight(.medium).foregroundStyle(ZmanimColor.slate800))
                        .zFont(14)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 12)
                }
                Button(action: locate) {
                    HStack(spacing: 12) {
                        Image(systemName: "scope").zFont(20).accessibilityHidden(true)
                        Text(locator.busy ? "Finding your location…" : "Use my current location")
                            .zFont(16, .semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(Color.navy)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(locator.busy)
                .opacity(locator.busy ? 0.6 : 1)
                if !locator.error.isEmpty {
                    Text(locator.error)
                        .zFont(14)
                        .foregroundStyle(ZmanimColor.error)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)
                        .accessibilityAddTraits(.isStaticText)
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").zFont(17).foregroundStyle(ZmanimColor.slate400).accessibilityHidden(true)
                    TextField("Search a city or state", text: $q)
                        .font(.system(size: 16))
                        .foregroundStyle(ZmanimColor.slate900)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($searchFocused)
                        .accessibilityLabel("Search a city or state")
                    if !q.isEmpty {
                        Button { q = "" } label: {
                            Image(systemName: "xmark").zFont(17).foregroundStyle(ZmanimColor.slate400)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, -8)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(ZmanimColor.searchBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 16)
                if !trimmed.isEmpty {
                    VStack(spacing: 0) {
                        if hits.isEmpty {
                            Text("No match yet. Try the nearest big city.")
                                .zFont(14)
                                .foregroundStyle(ZmanimColor.slate500)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(hits.enumerated()), id: \.element.key) { i, h in
                            if i > 0 { Rectangle().fill(ZmanimColor.slate100).frame(height: 1) }
                            Button {
                                let name: String
                                if h.key.hasPrefix("st:"), let s = ZmanimData.stateMain[h.name] { name = "\(s.city), \(h.name)" }
                                else { name = "\(h.name), \(h.sub)" }
                                pick(ZmanimSavedPlace(name: name, lat: h.lat, lng: h.lng, tz: h.tz))
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.and.ellipse").zFont(17).foregroundStyle(ZmanimColor.slate400).accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(h.name).zFont(15).foregroundStyle(ZmanimColor.slate900).lineLimit(1)
                                        Text(h.sub).zFont(13).foregroundStyle(ZmanimColor.slate500).lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                                .frame(minHeight: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(ZmanimPressStyle(radius: 8))
                        }
                    }
                    .padding(.top, 4)
                }
            }
        } footer: {
            EmptyView()
        }
    }
}
