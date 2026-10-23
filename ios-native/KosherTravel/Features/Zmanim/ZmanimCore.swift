// Zmanim math, ported line for line from the website's src/lib/zmanim/core.ts and opts.ts (read-only sources).
// Definitions follow Hebcal: NOAA sun position, sea-level sunrise/sunset (zenith 90.833°), degree zmanim at the
// geometric zenith, GRA hours sunrise→sunset, MGA hours 72 min before sunrise → 72 min after sunset.
// Times are milliseconds since 1970 (Double), exactly like the website's numbers, so every rounding step matches.
import Foundation

// MARK: - Opinions (opts.ts)

enum ZmanimNightOpt: String, CaseIterable, Codable { case deg8_5 = "deg8.5", deg7_083 = "deg7.083", m42, m50, m60, m72 }
enum ZmanimAlosOpt: String, CaseIterable, Codable { case deg16_1 = "deg16.1", m72, m90 }
enum ZmanimMisheyakirOpt: String, CaseIterable, Codable { case deg11_5 = "deg11.5", m50 }
enum ZmanimShmaOpt: String, CaseIterable, Codable { case both, mga, gra }
enum ZmanimMinchaOpt: String, CaseIterable, Codable { case gra, mga72 }

struct ZmanimOpts: Equatable {
    var tzeis: ZmanimNightOpt
    var havdalah: ZmanimNightOpt
    var candle: Int
    var alos: ZmanimAlosOpt
    var misheyakir: ZmanimMisheyakirOpt
    var shma: ZmanimShmaOpt
    var mincha: ZmanimMinchaOpt

    static let defaults = ZmanimOpts(tzeis: .deg8_5, havdalah: .deg8_5, candle: 18, alos: .deg16_1, misheyakir: .deg11_5, shma: .both, mincha: .gra)
    static let candleOptions: [Int] = [18, 20, 22, 30, 40]

    /// cleanZmanimOpts: accepts anything (a saved record) and returns valid options; a missing `tzeis` follows `havdalah`.
    static func clean(_ x: [String: Any]) -> ZmanimOpts {
        let D = defaults
        let havdalah = (x["havdalah"] as? String).flatMap(ZmanimNightOpt.init(rawValue:)) ?? D.havdalah
        var cand = D.candle
        if let n = x["candle"] as? NSNumber, candleOptions.contains(n.intValue), n.doubleValue == Double(n.intValue) { cand = n.intValue }
        else if let s = x["candle"] as? String, let n = Int(s), candleOptions.contains(n) { cand = n }
        return ZmanimOpts(
            tzeis: (x["tzeis"] as? String).flatMap(ZmanimNightOpt.init(rawValue:)) ?? havdalah,
            havdalah: havdalah,
            candle: cand,
            alos: (x["alos"] as? String).flatMap(ZmanimAlosOpt.init(rawValue:)) ?? D.alos,
            misheyakir: (x["misheyakir"] as? String).flatMap(ZmanimMisheyakirOpt.init(rawValue:)) ?? D.misheyakir,
            shma: (x["shma"] as? String).flatMap(ZmanimShmaOpt.init(rawValue:)) ?? D.shma,
            mincha: (x["mincha"] as? String).flatMap(ZmanimMinchaOpt.init(rawValue:)) ?? D.mincha
        )
    }

    var dictionary: [String: Any] {
        ["tzeis": tzeis.rawValue, "havdalah": havdalah.rawValue, "candle": candle, "alos": alos.rawValue,
         "misheyakir": misheyakir.rawValue, "shma": shma.rawValue, "mincha": mincha.rawValue]
    }
}

enum ZmanimLabels {
    static func degOrMin(_ v: String) -> String { v.hasPrefix("deg") ? "\(v.dropFirst(3))°" : "\(v.dropFirst(1)) min" }
    static func havdalah(_ h: ZmanimNightOpt) -> String { h == .m72 ? "72 min, Rabbeinu Tam" : degOrMin(h.rawValue) }
    static func night(_ h: ZmanimNightOpt) -> String { degOrMin(h.rawValue) }
    static func alos(_ a: ZmanimAlosOpt) -> String { degOrMin(a.rawValue) }
    static func misheyakir(_ m: ZmanimMisheyakirOpt) -> String { degOrMin(m.rawValue) }
    static func shma(_ s: ZmanimShmaOpt) -> String { s == .both ? "MGA and GRA" : s == .mga ? "MGA only" : "GRA only" }
    static func mincha(_ m: ZmanimMinchaOpt) -> String { m == .mga72 ? "MGA, 72 min" : "GRA" }
    /// optsSummary: one line naming every opinion.
    static func summary(_ o: ZmanimOpts) -> String {
        "Alos \(alos(o.alos)); Misheyakir \(misheyakir(o.misheyakir)); Sof Zman Shma/Tefilla \(shma(o.shma)); Mincha and Plag \(mincha(o.mincha)); Tzeis \(night(o.tzeis)); Motzei Shabbos/Yom Tov \(havdalah(o.havdalah)); candle lighting \(o.candle) min before shkia"
    }
}

// MARK: - Dates as "YYYY-MM-DD" strings (like the website)

enum ZmanimDates {
    static let dayMs: Double = 86_400_000

    /// JS Math.round (half up, toward +infinity).
    static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    /// Days since 1970-01-01 for a proleptic Gregorian date (same as Date.UTC / 86400000).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
    static func parts(_ date: String) -> (Int, Int, Int)? {
        let p = date.split(separator: "-")
        guard p.count == 3, let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        return (y, m, d)
    }
    static func iso(_ y: Int, _ m: Int, _ d: Int) -> String { String(format: "%04d-%02d-%02d", y, m, d) }
    /// Date.UTC(y, m-1, d) in ms.
    static func utcMidnightMs(_ date: String) -> Double {
        guard let p = parts(date) else { return 0 }
        let (y, m, d) = p
        return Double(daysFromCivil(y, m, d)) * dayMs
    }
    /// new Date(date + 'T12:00:00Z').getUTCDay(): 0 = Sunday … 6 = Saturday.
    static func weekday(_ date: String) -> Int {
        guard let p = parts(date) else { return 0 }
        let (y, m, d) = p
        let n = daysFromCivil(y, m, d)
        return ((n % 7) + 7 + 4) % 7
    }
    static func addDays(_ date: String, _ n: Int) -> String {
        guard let p = parts(date) else { return date }
        let (y, m, d) = p
        let (yy, mm, dd) = civilFromDays(daysFromCivil(y, m, d) + n)
        return iso(yy, mm, dd)
    }
    static func isISO(_ s: String) -> Bool {
        s.count == 10 && s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
    /// Today's date (YYYY-MM-DD) in a time zone.
    static func today(in tz: String, now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: now)
        return iso(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
    /// A date string as a Date at 12:00 UTC (for pickers and labels).
    static func noonUTC(_ date: String) -> Date { Date(timeIntervalSince1970: (utcMidnightMs(date) + 43_200_000) / 1000) }
    static func fromPicker(_ d: Date) -> String {
        // The picker runs in the phone's calendar; take its local Y-M-D.
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return iso(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
    static func toPicker(_ date: String) -> Date {
        guard let p = parts(date) else { return Date() }
        let (y, m, d) = p
        return Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: 12)) ?? Date()
    }

    private static func utcFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }
    private static let shortFmt = utcFormatter("EEE, MMM d")
    private static let longWeekdayFmt = utcFormatter("EEEE")
    private static let shortWeekdayFmt = utcFormatter("EEE")
    /// "Fri, Oct 23" (dayLabel).
    static func dayLabel(_ date: String) -> String { shortFmt.string(from: noonUTC(date)) }
    /// "Friday".
    static func weekdayLong(_ date: String) -> String { longWeekdayFmt.string(from: noonUTC(date)) }
    static func weekdayShort(_ date: String) -> String { shortWeekdayFmt.string(from: noonUTC(date)) }
}

// MARK: - Sun (NOAA)

enum ZmanimSun {
    private static let rad = Double.pi / 180
    private static func julianCenturies(_ ms: Double) -> Double { (ms / ZmanimDates.dayMs + 2_440_587.5 - 2_451_545) / 36525 }
    private static func sunPos(_ T: Double) -> (dec: Double, eq: Double) {
        let L0 = (280.46646 + T * (36000.76983 + T * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let M = 357.52911 + T * (35999.05029 - 0.0001537 * T)
        let e = 0.016708634 - T * (0.000042037 + 0.0000001267 * T)
        let C1 = sin(M * rad) * (1.914602 - T * (0.004817 + 0.000014 * T))
        let C2 = sin(2 * M * rad) * (0.019993 - 0.000101 * T)
        let C3 = sin(3 * M * rad) * 0.000289
        let C = C1 + C2 + C3
        let om = 125.04 - 1934.136 * T
        let lam = L0 + C - 0.00569 - 0.00478 * sin(om * rad)
        let eps0 = 23 + (26 + (21.448 - T * (46.815 + T * (0.00059 - T * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(om * rad)
        let dec = asin(sin(eps * rad) * sin(lam * rad)) / rad
        let tq = tan((eps / 2) * rad)
        let y = tq * tq
        let a1 = y * sin(2 * L0 * rad)
        let a2 = 2 * e * sin(M * rad)
        let a3 = 4 * e * y * sin(M * rad) * cos(2 * L0 * rad)
        let a4 = 0.5 * y * y * sin(4 * L0 * rad)
        let a5 = 1.25 * e * e * sin(2 * M * rad)
        let eq = (4 / rad) * (a1 - a2 + a3 - a4 - a5)
        return (dec, eq)
    }

    /// Local calendar date → UTC ms of the moment the sun's center reaches `zenith` degrees (90.833 = sunrise/sunset).
    static func at(_ date: String, lat: Double, lng: Double, zenith: Double, rising: Bool) -> Double? {
        let base = ZmanimDates.utcMidnightMs(date)
        var t = 720 - 4 * lng
        for _ in 0..<6 {
            let p = sunPos(julianCenturies(base + t * 60000))
            let cosH = (cos(zenith * rad) - sin(lat * rad) * sin(p.dec * rad)) / (cos(lat * rad) * cos(p.dec * rad))
            if cosH > 1 || cosH < -1 { return nil }
            let H = acos(cosH) / rad
            let nt = 720 - 4 * (lng + (rising ? H : -H)) - p.eq
            if abs(nt - t) < 0.001 { t = nt; break }
            t = nt
        }
        return base + ZmanimDates.jsRound(t * 60000)
    }
}

// MARK: - Calendar facts

struct ZmanimCalDay { let flags: [String]; let names: [String] }

enum ZmanimCalendar {
    private static let table: [String: ZmanimCalDay] = {
        var map: [String: ZmanimCalDay] = [:]
        for line in ZmanimCalendarData.text.split(separator: "\n") {
            let p = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let k = p.first, k.count == 8 else { continue }
            let key = "\(k.prefix(4))-\(k.dropFirst(4).prefix(2))-\(k.dropFirst(6).prefix(2))"
            let f = p.count > 1 ? p[1] : ""
            let n = p.count > 2 ? p[2] : ""
            map[key] = ZmanimCalDay(flags: f.isEmpty ? [] : f.components(separatedBy: ","),
                                    names: n.isEmpty ? [] : n.components(separatedBy: ";"))
        }
        return map
    }()

    static func day(_ date: String) -> ZmanimCalDay {
        if let hit = table[date] { return hit }
        // A date the table doesn't list is a plain weekday (outside 2026–2036 at least Friday/Shabbos are known).
        let wd = ZmanimDates.weekday(date)
        return ZmanimCalDay(flags: wd == 5 ? ["c"] : wd == 6 ? ["h"] : [], names: [])
    }
}

// MARK: - The day's zmanim

enum ZmanimKey: String { case alos, misheyakir, netz, shmaMGA, shmaGRA, tefillaMGA, tefillaGRA, chatzos, minchaGedola,
    minchaKetana, plag, shkia, tzeis, tzeisOpt, candles, havdalah, havdalahRT, fastBegins, fastEnds }

struct ZmanimItem: Identifiable, Equatable {
    let key: ZmanimKey
    let label: String
    let ms: Double?
    var core: Bool = false
    var note: String? = nil
    var id: String { "\(key.rawValue)|\(label)" }
}

struct ZmanimDay {
    let date: String
    let weekday: Int
    let lat: Double, lng: Double, tz: String
    let opts: ZmanimOpts
    let names: [String]
    let parsha: String?
    let isShabbos: Bool
    let isYomTov: Bool
    /// Candle lighting / Shabbos ends / fast times for this date, shown on top.
    let highlights: [ZmanimItem]
    /// The day's zmanim in time order; `core` = shown before "Show all".
    let items: [ZmanimItem]
}

enum ZmanimEngine {
    static func day(_ date: String, lat: Double, lng: Double, tz: String, opts: ZmanimOpts) -> ZmanimDay {
        let MIN = 60000.0
        let rise = ZmanimSun.at(date, lat: lat, lng: lng, zenith: 90.833, rising: true)
        let set = ZmanimSun.at(date, lat: lat, lng: lng, zenith: 90.833, rising: false)
        func deg(_ d: Double, _ r: Bool) -> Double? { ZmanimSun.at(date, lat: lat, lng: lng, zenith: 90 + d, rising: r) }
        let alos161 = deg(16.1, true)
        var gra: Double? = nil
        if let rise, let set { gra = (set - rise) / 12 }
        func at(_ h: Double) -> Double? { if let rise, let gra { return rise + gra * h }; return nil }
        let mgaStart: Double? = rise.map { $0 - 72 * MIN }
        var mgaHour: Double? = nil
        if let rise, let set { mgaHour = (set - rise + 144 * MIN) / 12 }
        func mga(_ h: Double) -> Double? { if let mgaStart, let mgaHour { return mgaStart + mgaHour * h }; return nil }
        let tz85 = deg(8.5, false)
        // Hebcal's rounding: candle lighting from sunset with the seconds dropped; havdalah-type times from sunset
        // rounded to the nearest minute.
        let setFloor: Double? = set.map { ($0 / MIN).rounded(.down) * MIN }
        let setRound: Double? = set.map { ZmanimDates.jsRound($0 / MIN) * MIN }
        func afterSet(_ h: ZmanimNightOpt) -> Double? {
            if h == .deg8_5 { return tz85 }
            let raw = h.rawValue
            if raw.hasPrefix("deg") { return deg(Double(raw.dropFirst(3)) ?? 0, false) }
            if let setRound { return setRound + (Double(raw.dropFirst(1)) ?? 0) * MIN }
            return nil
        }
        func beforeRise(_ m: Double) -> Double? { rise.map { $0 - m * MIN } }
        let alosMs: Double? = opts.alos == .deg16_1 ? alos161 : beforeRise(Double(opts.alos.rawValue.dropFirst(1)) ?? 0)
        let cal = ZmanimCalendar.day(date)
        let wd = ZmanimDates.weekday(date)
        let showMGA = opts.shma != .gra, showGRA = opts.shma != .mga
        let m72 = opts.mincha == .mga72
        let mLabel = m72 ? "72 min" : "GRA"
        var items: [ZmanimItem] = [
            ZmanimItem(key: .alos, label: "Alos Hashachar (\(ZmanimLabels.alos(opts.alos)))", ms: alosMs, core: true),
            ZmanimItem(key: .misheyakir, label: "Misheyakir (\(ZmanimLabels.misheyakir(opts.misheyakir)))",
                       ms: opts.misheyakir == .m50 ? beforeRise(50) : deg(11.5, true), core: true),
            ZmanimItem(key: .netz, label: "Netz (sunrise)", ms: rise, core: true),
        ]
        if showMGA { items.append(ZmanimItem(key: .shmaMGA, label: "Sof Zman Shma (MGA)", ms: mga(3), core: true)) }
        if showGRA { items.append(ZmanimItem(key: .shmaGRA, label: "Sof Zman Shma (GRA)", ms: at(3), core: true)) }
        if showMGA { items.append(ZmanimItem(key: .tefillaMGA, label: "Sof Zman Tefilla (MGA)", ms: mga(4))) }
        if showGRA { items.append(ZmanimItem(key: .tefillaGRA, label: "Sof Zman Tefilla (GRA)", ms: at(4))) }
        items.append(ZmanimItem(key: .chatzos, label: "Chatzos (midday)", ms: at(6), core: true))
        items.append(ZmanimItem(key: .minchaGedola, label: "Mincha Gedola (\(mLabel))", ms: m72 ? mga(6.5) : at(6.5), core: true))
        items.append(ZmanimItem(key: .minchaKetana, label: "Mincha Ketana (\(mLabel))", ms: m72 ? mga(9.5) : at(9.5)))
        items.append(ZmanimItem(key: .plag, label: "Plag Hamincha (\(mLabel))", ms: m72 ? mga(10.75) : at(10.75), core: true))
        items.append(ZmanimItem(key: .shkia, label: "Shkia (sunset)", ms: set, core: true))
        items.append(ZmanimItem(key: .tzeis, label: "Tzeis Hakochavim (\(ZmanimLabels.night(opts.tzeis)))", ms: afterSet(opts.tzeis), core: true))

        var highlights: [ZmanimItem] = []
        let f = cal.flags
        if f.contains("fb") { highlights.append(ZmanimItem(key: .fastBegins, label: "Fast begins (\(ZmanimLabels.alos(opts.alos)))", ms: alosMs)) }
        if f.contains("fn") { highlights.append(ZmanimItem(key: .fastBegins, label: "Fast begins (sunset)", ms: set)) }
        if f.contains("c") {
            highlights.append(ZmanimItem(key: .candles, label: "Candle lighting (\(opts.candle) min before shkia)",
                                         ms: setFloor.map { $0 - Double(opts.candle) * MIN }))
        }
        if f.contains("t") {
            highlights.append(ZmanimItem(key: .candles, label: "Candle lighting (not before this time)", ms: afterSet(opts.havdalah), note: "from an existing flame"))
        }
        if f.contains("fe") { highlights.append(ZmanimItem(key: .fastEnds, label: "Fast ends", ms: deg(7.083, false))) }
        if f.contains("h") {
            let isYT = f.contains("y") && wd != 6
            highlights.append(ZmanimItem(key: .havdalah, label: "\(isYT ? "Yom Tov" : "Shabbos") ends (\(ZmanimLabels.havdalah(opts.havdalah)))", ms: afterSet(opts.havdalah)))
            if opts.havdalah != .m72 {
                highlights.append(ZmanimItem(key: .havdalahRT, label: "Rabbeinu Tam (72 min)", ms: setRound.map { $0 + 72 * MIN }))
            }
        }
        return ZmanimDay(
            date: date, weekday: wd, lat: lat, lng: lng, tz: tz, opts: opts,
            names: cal.names.filter { !$0.hasPrefix("Parshas ") },
            parsha: cal.names.first { $0.hasPrefix("Parshas ") },
            isShabbos: wd == 6, isYomTov: f.contains("y"),
            highlights: highlights, items: items
        )
    }

    private static var formatters: [String: DateFormatter] = [:]
    private static let lock = NSLock()
    /// "6:12 PM" in the place's own time zone (rounded to the nearest minute, like Hebcal). "—" when there is none.
    static func format(_ ms: Double?, tz: String) -> String {
        guard let ms else { return "—" }
        lock.lock(); defer { lock.unlock() }
        let f: DateFormatter
        if let hit = formatters[tz] { f = hit } else {
            f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "America/New_York")
            f.dateFormat = "h:mm a"
            f.amSymbol = "AM"
            f.pmSymbol = "PM"
            formatters[tz] = f
        }
        let rounded = ZmanimDates.jsRound(ms / 60000) * 60000
        return f.string(from: Date(timeIntervalSince1970: rounded / 1000))
    }
}
