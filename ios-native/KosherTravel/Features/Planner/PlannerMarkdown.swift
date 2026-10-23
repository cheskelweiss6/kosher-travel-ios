import SwiftUI

/// An AI answer set for reading on a phone, line by line like the web's PlannerMarkdown: calm headings, simple lists,
/// "emoji **Name** — details" rows, rules, and inline bold / italic / links / phone numbers (AttributedString).
struct PlannerMarkdown: View {
    let content: String

    var body: some View {
        let blocks = PlannerBlocks.parse(content)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                blockView(block, first: i == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: PlannerBlocks.Block, first: Bool) -> some View {
        switch block {
        case .heading(let level, let text):
            if level >= 3 {
                Text(PlannerInline.attributed(text))
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, first ? 0 : 10)
            } else {
                Text(PlannerInline.attributed(text))
                    .font(.system(.headline, design: .serif).weight(.bold))
                    .foregroundStyle(Color.navy)
                    .padding(.top, first ? 0 : 10)
            }
        case .bullet(let text, let nested):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("\u{2022}")
                    .foregroundStyle(Color.textTertiary)
                Text(PlannerInline.attributed(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, nested ? 18 : 0)
            .padding(.vertical, 1)
        case .numbered(let n, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).")
                    .monospacedDigit()
                    .foregroundStyle(Color.textTertiary)
                Text(PlannerInline.attributed(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 1)
        case .card(let mark, let name, let detail):
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                if mark == "\u{1F3DB}" {
                    Image(systemName: "building.columns")
                        .font(.footnote)
                        .foregroundStyle(Color.navy)
                        .frame(width: 18)
                } else if !mark.isEmpty {
                    Text(mark).font(.footnote).frame(width: 18)
                }
                Text(cardText(name: name, detail: detail))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 3)
        case .rule:
            Divider().overlay(Color.hairline).padding(.vertical, 6)
        case .paragraph(let text):
            Text(PlannerInline.attributed(text))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 2)
        }
    }

    private func cardText(name: String, detail: String) -> AttributedString {
        var out = PlannerInline.attributed("**\(name)**")
        if !detail.isEmpty {
            var dash = AttributedString(" — ")
            dash.foregroundColor = Color.textSecondary
            out.append(dash)
            out.append(PlannerInline.attributed(detail))
        }
        return out
    }
}

enum PlannerBlocks {
    enum Block: Hashable {
        case heading(Int, String)
        case bullet(String, Bool)
        case numbered(String, String)
        case card(String, String, String)
        case rule
        case paragraph(String)
    }

    private static func match(_ s: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    static func parse(_ content: String) -> [Block] {
        var out: [Block] = []
        for line in PlannerText.sanitize(content).components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            // "🍽 **Name** — details"
            if let m = match(t, #"^(\p{So}|✦|✨)\x{FE0F}?\s*\*\*(.*?)\*\*(.*)$"#) {
                let deco = m[1] == "✨" || m[1] == "✦"
                var detail = m[3].trimmingCharacters(in: .whitespaces)
                if let d = match(detail, #"^[-–—:]\s*(.*)$"#) { detail = d[1] }
                out.append(.card(deco ? "" : m[1], m[2], detail))
                continue
            }
            if let m = match(t, #"^(#{1,6})\s+(.*)$"#) {
                var text = m[2]
                if let b = match(text, #"^\*\*(.*)\*\*$"#) { text = b[1] }
                out.append(.heading(m[1].count, text))
                continue
            }
            if let m = match(t, #"^(\d+)[.)]\s+(.*)$"#) {
                out.append(.numbered(m[1], m[2]))
                continue
            }
            if let m = match(line, #"^(\s*)[-*•]\s+(.*)$"#), !t.hasPrefix("**") {
                out.append(.bullet(m[2], m[1].count >= 2))
                continue
            }
            if match(t, #"^(-{3,}|\*{3,}|_{3,})$"#) != nil {
                out.append(.rule)
                continue
            }
            out.append(.paragraph(t))
        }
        return out
    }
}

/// Inline markdown: **bold**, *italic*, [text](url), bare links and phone numbers become tappable.
enum PlannerInline {
    private static let linkRE = try? NSRegularExpression(pattern:
        #"\[([^\]\n]{1,200})\]\((https?://[^\s)]+)\)|(https?://[^\s<>"'`]+)|((?:\+\d{1,3}[\s.-]?)?\(?\d{1,4}\)?[\s.-]\d{3,4}[\s.-]\d{3,4}(?:[\s.-]\d{2,4})?)"#)

    private static func escapeLabel(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "*", with: "")
    }

    /// Rewrites bare links and phone numbers to markdown links; markdown links are kept.
    static func linkify(_ raw: String) -> String {
        guard let re = linkRE else { return raw }
        let ns = raw as NSString
        var out = ""
        var cursor = 0
        for m in re.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            cursor = m.range.location + m.range.length
            let whole = ns.substring(with: m.range)
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            if let label = group(1), let url = group(2) {
                out += "[\(escapeLabel(label))](\(url))"
            } else if let url = group(3) {
                var clean = url
                var trail = ""
                while let last = clean.last, ".,;:!?*)]".contains(last) {
                    trail = String(last) + trail
                    clean.removeLast()
                }
                if clean.range(of: #"^https?://[^/]*\."#, options: [.regularExpression, .caseInsensitive]) == nil {
                    out += whole
                    continue
                }
                let shown = clean.replacingOccurrences(of: #"^https?://(www\.)?"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: #"/$"#, with: "", options: .regularExpression)
                out += "[\(escapeLabel(shown))](\(clean))" + trail
            } else if let phone = group(4) {
                let digits = phone.filter(\.isNumber)
                if digits.count < 10 || digits.count > 15 { out += whole; continue }
                let trimmed = phone.trimmingCharacters(in: .whitespaces)
                let tel = trimmed.hasPrefix("+") ? "+\(digits)" : (digits.count == 10 ? "+1\(digits)" : "+\(digits)")
                out += "[\(escapeLabel(trimmed))](tel:\(tel))"
            } else {
                out += whole
            }
        }
        out += ns.substring(from: cursor)
        return out
    }

    static func attributed(_ raw: String) -> AttributedString {
        let md = linkify(PlannerText.sanitize(raw)).replacingOccurrences(of: "__", with: "**")
        var a: AttributedString
        if let parsed = try? AttributedString(markdown: md, options: .init(allowsExtendedAttributes: false,
                                                                         interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                                         failurePolicy: .returnPartiallyParsedIfPossible)) {
            a = parsed
        } else {
            a = AttributedString(raw.replacingOccurrences(of: "**", with: ""))
        }
        for run in a.runs where run.link != nil {
            a[run.range].foregroundColor = Color.navy
            a[run.range].underlineStyle = Text.LineStyle(pattern: .solid)
        }
        return a
    }
}
