// Hebrew names for the Zmanim card, ported from the website's src/lib/zmanim/hebrew.ts (Cheskel, Oct 22 2026: his
// zmanim app shows the day, parsha and date in Hebrew, and each zman's Hebrew name).
import Foundation

enum ZmanimHebrew {
    static let zman: [ZmanimKey: String] = [
        .alos: "עלות השחר", .misheyakir: "משיכיר", .netz: "הנץ החמה",
        .shmaMGA: "סוף זמן ק״ש מג״א", .shmaGRA: "סוף זמן ק״ש גר״א", .tefillaMGA: "סוף זמן תפילה מג״א", .tefillaGRA: "סוף זמן תפילה גר״א",
        .chatzos: "חצות", .minchaGedola: "מנחה גדולה", .minchaKetana: "מנחה קטנה", .plag: "פלג המנחה", .shkia: "שקיעה",
        .tzeis: "צאת הכוכבים", .tzeisOpt: "צאת הכוכבים", .candles: "הדלקת נרות", .havdalah: "מוצאי שבת", .havdalahRT: "רבינו תם",
        .fastBegins: "תחילת הצום", .fastEnds: "סוף הצום",
    ]

    private static let parsha: [String: String] = [
        "Bereshis": "בראשית", "Noach": "נח", "Lech-Lecha": "לך לך", "Vayera": "וירא", "Chayei Sara": "חיי שרה", "Toldos": "תולדות",
        "Vayetzei": "ויצא", "Vayishlach": "וישלח", "Vayeshev": "וישב", "Miketz": "מקץ", "Vayigash": "ויגש", "Vayechi": "ויחי",
        "Shemos": "שמות", "Vaera": "וארא", "Bo": "בא", "Beshalach": "בשלח", "Yisro": "יתרו", "Mishpatim": "משפטים", "Terumah": "תרומה",
        "Tetzaveh": "תצוה", "Ki Sisa": "כי תשא", "Vayakhel": "ויקהל", "Pekudei": "פקודי", "Vayikra": "ויקרא", "Tzav": "צו",
        "Shmini": "שמיני", "Tazria": "תזריע", "Metzora": "מצורע", "Achrei Mos": "אחרי מות", "Kedoshim": "קדושים", "Emor": "אמור",
        "Behar": "בהר", "Bechukosai": "בחקתי", "Bamidbar": "במדבר", "Nasso": "נשא", "Beha'aloscha": "בהעלותך", "Sh'lach": "שלח",
        "Korach": "קרח", "Chukas": "חקת", "Balak": "בלק", "Pinchas": "פינחס", "Matos": "מטות", "Masei": "מסעי", "Devarim": "דברים",
        "Vaeschanan": "ואתחנן", "Eikev": "עקב", "Re'eh": "ראה", "Shoftim": "שופטים", "Ki Seitzei": "כי תצא", "Ki Savo": "כי תבוא",
        "Nitzavim": "נצבים", "Vayeilech": "וילך", "Ha'azinu": "האזינו",
    ]

    private static func stripParshas(_ en: String) -> String {
        en.replacingOccurrences(of: #"^Parshas\s+"#, with: "", options: .regularExpression)
    }

    /// "Parshas Lech-Lecha" → "פרשת לך לך"; "Parshas Vayakhel-Pekudei" → "פרשת ויקהל-פקודי".
    static func parshaHe(_ en: String?) -> String {
        guard let en, !en.isEmpty else { return "" }
        let n = stripParshas(en).trimmingCharacters(in: .whitespaces)
        if let hit = parsha[n] { return "פרשת \(hit)" }
        let parts = n.components(separatedBy: "-").map { parsha[$0.trimmingCharacters(in: .whitespaces)] }
        if parts.allSatisfy({ $0 != nil }) { return "פרשת \(parts.compactMap { $0 }.joined(separator: "-"))" }
        return ""
    }
    /// "Parshas Lech-Lecha" → "Lech Lecha".
    static func parshaEn(_ en: String?) -> String {
        guard let en, !en.isEmpty else { return "" }
        let n = stripParshas(en)
        return n == "Lech-Lecha" ? "Lech Lecha" : n
    }

    /// Day names as his app shows them (Yiddish weekdays, "שבת" on Shabbos).
    static let dayHe = ["זונטאג", "מאנטאג", "דינסטאג", "מיטוואך", "דאנערשטאג", "פרייטאג", "שבת"]

    private static let ones = ["", "א", "ב", "ג", "ד", "ה", "ו", "ז", "ח", "ט"]
    private static let tens = ["", "י", "כ", "ל", "מ", "נ", "ס", "ע", "פ", "צ"]
    private static let hundreds = ["ק", "ר", "ש"]
    /// 13 → "י״ג", 15 → "ט״ו", 787 → "תשפ״ז", 1 → "א׳".
    static func gematria(_ n: Int) -> String {
        var s = ""
        var x = n % 1000
        while x >= 400 { s += "ת"; x -= 400 }
        if x >= 100 { s += hundreds[x / 100 - 1]; x %= 100 }
        if x == 15 { s += "טו" } else if x == 16 { s += "טז" } else { s += tens[x / 10] + ones[x % 10] }
        if s.count <= 1 { return "\(s)׳" }
        return "\(s.dropLast())״\(s.suffix(1))"
    }

    private static func monthHe(_ m: String) -> String {
        let k = String(m.lowercased().unicodeScalars.filter { ($0 >= "a" && $0 <= "z") || $0 == " " }.map(Character.init))
            .trimmingCharacters(in: .whitespaces)
        func has(_ re: String) -> Bool { k.range(of: re, options: .regularExpression) != nil }
        if has(#"^adar (ii|2)$"#) { return "אדר ב׳" }
        if has(#"^adar (i|1)$"#) { return "אדר א׳" }
        let table: [(String, String)] = [("^tish", "תשרי"), ("(hesh|chesh)", "חשון"), ("^kis", "כסלו"), ("^tev", "טבת"), ("^sh?e?vat|^shvat", "שבט"),
            ("^adar", "אדר"), ("^nis", "ניסן"), ("^iy", "אייר"), ("^siv", "סיון"), ("^tam", "תמוז"), ("^av$", "אב"), ("^elul", "אלול")]
        return table.first { has($0.0) }?.1 ?? ""
    }

    private static let hebrewCalendar: Calendar = {
        var c = Calendar(identifier: .hebrew)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private static let monthNameFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = hebrewCalendar
        f.locale = Locale(identifier: "en_US")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MMMM"
        return f
    }()

    private static func hebrewParts(_ date: String) -> (day: Int, month: String, year: Int)? {
        let d = ZmanimDates.noonUTC(date)
        let c = hebrewCalendar.dateComponents([.day, .year], from: d)
        guard let day = c.day, let year = c.year else { return nil }
        return (day, monthNameFmt.string(from: d), year)
    }

    /// "2026-10-24" → "י״ג חשון תשפ״ז" ('' when the month can't be read).
    static func dateHe(_ date: String) -> String {
        guard let p = hebrewParts(date) else { return "" }
        let m = monthHe(p.month)
        guard p.day > 0, p.year > 0, !m.isEmpty else { return "" }
        return "\(gematria(p.day)) \(m) \(gematria(p.year))"
    }
    /// The English fallback the website shows when the Hebrew one is empty ("13 Heshvan 5787").
    static func dateEn(_ date: String) -> String {
        guard let p = hebrewParts(date) else { return "" }
        return "\(p.day) \(p.month) \(p.year)"
    }
}
