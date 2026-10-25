import SwiftUI
import UIKit
import PDFKit
import EventKit
import EventKitUI

/// The row of glass chips under an AI plan: Make PDF, Maps, Share, Copy, Add to Calendar.
struct PlannerActionBar: View {
    let message: ChatMessage
    let index: Int
    let messages: [ChatMessage]
    let cards: [PlannerPlace]
    /// Asks the planner a follow-up in this chat (packing list, checklist).
    let onAsk: (String) -> Void

    @State private var pdf: PlannerPDFFile?
    @State private var showMaps = false
    @State private var showCalendar = false
    @State private var copied = false
    @State private var made = 0
    @Environment(AuthStore.self) private var auth
    /// Save to My Travel / Add to Bucket List (Oct 23 2026): the same Firestore data the website writes.
    @State private var savedTripId: String?
    @State private var bucketBusy: String?

    private var plan: ChatMessage { PlannerActions.plan(for: index, messages: messages) ?? message }

    private var mapPlaces: [PlannerMapPlace] {
        let own = PlannerActions.places(for: message, messages: messages, cards: cards)
        if !own.isEmpty { return own }
        return PlannerActions.places(for: plan, messages: messages, cards: cards)
    }

    private var tripTitle: String { PlannerActions.title(messages, plan: plan, cards: cards) }

    private var shareText: String {
        PlannerActions.plainText(plan.content) + "\n\nPlanned with Kosher Travel · yourkoshertravel.com"
    }

    var body: some View {
        let places = mapPlaces
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Make PDF", "doc.richtext") { makePDF(places) }
                if !places.isEmpty {
                    chip(places.count == 1 ? "Open in Maps" : "Maps (\(places.count))", "map") { showMaps = true }
                }
                ShareLink(item: shareText, subject: Text(tripTitle.isEmpty ? "Kosher Travel trip plan" : "Kosher Travel: \(tripTitle)")) {
                    chipLabel("Share", "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                chip(copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = shareText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                }
                chip("Add to Calendar", "calendar.badge.plus") { showCalendar = true }
                chip(savedTripId == nil ? "Save to My Travel" : "Saved", savedTripId == nil ? "bookmark" : "checkmark") { saveTrip() }
                if let t = bucketTarget(places) {
                    let inList = PlannerTrips.inBucket(t.id)
                    chip(bucketBusy == t.name ? "Adding\u{2026}" : (inList ? "In your Bucket List" : "Add to Bucket List"),
                         inList ? "checkmark" : "heart") { addToBucket(t) }
                }
                chip("Packing list", "suitcase") {
                    onAsk("Make a packing list for this trip")
                }
                chip("Checklist", "checklist") {
                    onAsk("Make a checklist for this trip: bookings, kosher food, Shabbos, documents")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -16)
        .sensoryFeedback(.success, trigger: copied) { _, now in now }
        .sensoryFeedback(.impact(weight: .light), trigger: made)
        .sheet(item: $pdf) { file in
            PlannerPDFPreview(file: file)
        }
        .sheet(isPresented: $showMaps) {
            PlannerMapsSheet(places: places, title: tripTitle,
                             days: PlannerActions.dayRoutes(plan.content, places: PlannerActions.places(for: plan, messages: messages, cards: cards)),
                             inBucket: { p in PlannerTrips.inBucket(PlannerTrips.bucketId(name: p.name, city: p.city, destId: nil)) },
                             onBucket: { p in addToBucket(BucketTarget(name: p.name, city: p.city, area: p.area, kind: p.kind, destId: nil, photo: "")) })
        }
        .sheet(isPresented: $showCalendar) {
            PlannerCalendarEditor(event: PlannerCalendarDraft.make(messages: messages, plan: plan, title: tripTitle,
                                                                   notes: shareText)) {
                showCalendar = false
            }
            .ignoresSafeArea()
        }
    }

    private func makePDF(_ places: [PlannerMapPlace]) {
        let planPlaces = PlannerActions.places(for: plan, messages: messages, cards: cards)
        var all = planPlaces
        var seen = Set(planPlaces.map { $0.id })
        for p in places where !seen.contains(p.id) {
            seen.insert(p.id)
            all.append(p)
        }
        if let file = PlannerPDF.make(content: plan.content, title: tripTitle, filters: PlannerText.filters(from: messages), places: all) {
            made += 1
            pdf = file
        }
    }

    // MARK: Save to My Travel / Add to Bucket List

    struct BucketTarget {
        let name: String
        let city: String
        let area: String
        let kind: String
        let destId: String?
        let photo: String
        var id: String { PlannerTrips.bucketId(name: name, city: city, destId: destId) }
    }

    /// One destination answer (its card), or an answer about one place: the chip saves it.
    private func bucketTarget(_ places: [PlannerMapPlace]) -> BucketTarget? {
        if cards.count == 1, let c = cards.first {
            return BucketTarget(name: c.name, city: "", area: c.subtitle, kind: "city", destId: PlannerTrips.destId(fromCard: c.id), photo: c.photo)
        }
        if cards.isEmpty, places.count == 1, let p = places.first {
            return BucketTarget(name: p.name, city: p.city, area: p.area, kind: p.kind, destId: nil, photo: "")
        }
        return nil
    }

    private func viewMyTravel() -> ShellToast.Action {
        ShellToast.Action(label: "View") {
            ShellRouter.shared.toast = nil
            ShellRouter.shared.selectedTab = .myTravel
        }
    }

    private func saveTrip() {
        if savedTripId != nil {
            ShellRouter.shared.selectedTab = .myTravel
            return
        }
        ShellRouter.shared.requireSignIn("Sign in to save trips to My Travel") {
            guard savedTripId == nil, let uid = auth.uid else { return }
            savedTripId = PlannerTrips.save(uid: uid, messages: messages, plan: plan, title: tripTitle)
            made += 1
            ShellRouter.shared.showToast("Saved to My Travel", seconds: 4, action: viewMyTravel())
        }
    }

    private func addToBucket(_ t: BucketTarget) {
        guard bucketBusy == nil else { return }
        if PlannerTrips.inBucket(t.id) {
            ShellRouter.shared.showToast("Already in your Bucket List", seconds: 3, action: viewMyTravel())
            return
        }
        ShellRouter.shared.requireSignIn("Sign in to keep a Bucket List") {
            guard let uid = auth.uid else { return }
            bucketBusy = t.name
            Task { @MainActor in
                let added = await PlannerTrips.addToBucket(uid: uid, name: t.name, city: t.city, area: t.area, kind: t.kind,
                                                           destId: t.destId, photo: t.photo, messages: messages)
                bucketBusy = nil
                made += 1
                ShellRouter.shared.showToast(added ? "Added to your Bucket List" : "Already in your Bucket List", seconds: 4,
                                             action: viewMyTravel())
            }
        }
    }

    private func chip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(title, icon) }
            .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.navy)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .glassCapsule()
            .contentShape(Capsule())
            .accessibilityLabel(title)
    }
}

// MARK: PDF

struct PlannerPDFFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
}

/// A branded trip plan (navy #191e3b and white), drawn on the phone. Place names in the "Places & Maps" list are
/// tappable links to Google Maps inside the PDF.
enum PlannerPDF {
    static let page = CGRect(x: 0, y: 0, width: 612, height: 792)   // US Letter
    static let margin: CGFloat = 46

    private static let navy = UIColor(red: 25 / 255, green: 30 / 255, blue: 59 / 255, alpha: 1)
    private static let ink = UIColor(red: 30 / 255, green: 41 / 255, blue: 59 / 255, alpha: 1)
    private static let grey = UIColor(red: 100 / 255, green: 116 / 255, blue: 139 / 255, alpha: 1)
    private static let line = UIColor(red: 226 / 255, green: 232 / 255, blue: 240 / 255, alpha: 1)

    private static func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        if let d = base.fontDescriptor.withDesign(.serif) { return UIFont(descriptor: d, size: size) }
        return base
    }

    private static func font(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> UIFont {
        var f = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        if italic, let d = f.fontDescriptor.withSymbolicTraits(bold ? [.traitItalic, .traitBold] : .traitItalic) {
            f = UIFont(descriptor: d, size: size)
        }
        return f
    }

    private static func para(before: CGFloat = 0, after: CGFloat = 4, indent: CGFloat = 0) -> NSMutableParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.lineSpacing = 2
        p.firstLineHeadIndent = 0
        p.headIndent = indent
        if indent > 0 { p.tabStops = [NSTextTab(textAlignment: .left, location: indent, options: [:])] }
        return p
    }

    /// Inline markdown (bold, italic, links, phone numbers) as UIKit text.
    private static func inline(_ raw: String, size: CGFloat = 11.5, color: UIColor? = nil, boldAll: Bool = false) -> NSMutableAttributedString {
        let md = PlannerInline.linkify(PlannerText.sanitize(raw)).replacingOccurrences(of: "__", with: "**")
        let parsed = (try? AttributedString(markdown: md, options: .init(allowsExtendedAttributes: false,
                                                                          interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                                          failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(raw.replacingOccurrences(of: "**", with: ""))
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let text = String(parsed[run.range].characters)
            let intent = run.inlinePresentationIntent ?? []
            let bold = boldAll || intent.contains(.stronglyEmphasized)
            let italic = intent.contains(.emphasized)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: font(size, bold: bold, italic: italic),
                .foregroundColor: color ?? ink,
            ]
            if let link = run.link {
                attrs[.link] = link
                attrs[.foregroundColor] = navy
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            out.append(NSAttributedString(string: text, attributes: attrs))
        }
        return out
    }

    private static func plainLine(_ s: String, _ f: UIFont, _ c: UIColor, _ p: NSParagraphStyle) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c, .paragraphStyle: p])
    }

    private static func body(_ content: String, places: [PlannerMapPlace]) -> NSAttributedString {
        let out = NSMutableAttributedString()
        func add(_ a: NSAttributedString, _ p: NSParagraphStyle) {
            let m = NSMutableAttributedString(attributedString: a)
            m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
            m.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: p, .font: font(11.5)]))
            out.append(m)
        }
        for block in PlannerBlocks.parse(content) {
            switch block {
            case .heading(let level, let text):
                if level >= 3 {
                    add(inline(text.uppercased(), size: 9.5, color: grey, boldAll: true), para(before: 10, after: 3))
                } else {
                    let a = inline(text, size: 15, color: navy, boldAll: true)
                    a.addAttribute(.font, value: serif(15, .bold), range: NSRange(location: 0, length: a.length))
                    add(a, para(before: 12, after: 4))
                }
            case .paragraph(let text):
                let t = text.trimmingCharacters(in: .whitespaces)
                if t.range(of: #"^\*\*[^*]{1,60}\*\*:?$"#, options: .regularExpression) != nil {
                    // "**Day 1**", "**For Shabbos**": a section of the plan.
                    let label = t.replacingOccurrences(of: "**", with: "")
                    let a = NSMutableAttributedString(string: label, attributes: [.font: serif(14, .bold), .foregroundColor: navy])
                    add(a, para(before: 12, after: 4))
                } else {
                    add(inline(t), para(after: 5))
                }
            case .bullet(let text, let level):
                let indent: CGFloat = 14 + CGFloat(level) * 14
                let a = NSMutableAttributedString(string: "•\t", attributes: [.font: font(11.5), .foregroundColor: grey])
                a.append(inline(text))
                let p = para(after: 3, indent: indent)
                p.firstLineHeadIndent = CGFloat(level) * 14
                add(a, p)
            case .numbered(let n, let text):
                let a = NSMutableAttributedString(string: "\(n).\t", attributes: [.font: font(11.5), .foregroundColor: grey])
                a.append(inline(text))
                add(a, para(after: 3, indent: 18))
            case .card(let mark, let name, let detail):
                let a = NSMutableAttributedString()
                if !mark.isEmpty {
                    a.append(NSAttributedString(string: mark + "  ", attributes: [.font: font(11.5), .foregroundColor: ink]))
                }
                a.append(inline("**\(name)**"))
                if !detail.isEmpty {
                    a.append(NSAttributedString(string: " — ", attributes: [.font: font(11.5), .foregroundColor: grey]))
                    a.append(inline(detail))
                }
                add(a, para(after: 4))
            case .rule:
                add(NSAttributedString(string: " ", attributes: [.font: font(4)]), para(after: 2))
            }
        }
        if !places.isEmpty {
            add(NSAttributedString(string: "Places & Maps", attributes: [.font: serif(15, .bold), .foregroundColor: navy]),
                para(before: 16, after: 2))
            add(NSAttributedString(string: "Tap a name to open it in Google Maps.", attributes: [.font: font(9.5), .foregroundColor: grey]),
                para(after: 6))
            for p in places {
                let a = NSMutableAttributedString(string: p.name, attributes: [
                    .font: font(11.5, bold: true), .foregroundColor: navy, .link: p.googleURL,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ])
                var sub = p.subtitle
                if let phone = p.phone, !phone.isEmpty { sub += " · " + phone }
                a.append(NSAttributedString(string: "\n" + sub, attributes: [.font: font(9.5), .foregroundColor: grey]))
                add(a, para(after: 6))
            }
        }
        return out
    }

    private static func dateLine(_ f: TripFilters) -> String {
        let inF = DateFormatter()
        inF.locale = Locale(identifier: "en_US_POSIX")
        inF.dateFormat = "yyyy-MM-dd"
        let outF = DateFormatter()
        outF.dateFormat = "MMM d, yyyy"
        if let s = f.startDate, let a = inF.date(from: s) {
            if let e = f.endDate, let b = inF.date(from: e), e != s { return outF.string(from: a) + " – " + outF.string(from: b) }
            return outF.string(from: a)
        }
        if let d = f.days, d > 0 { return "\(d) day\(d == 1 ? "" : "s")" }
        return ""
    }

    static func make(content: String, title: String, filters: TripFilters, places: [PlannerMapPlace]) -> PlannerPDFFile? {
        let text = body(content, places: places)
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        let heading = title.isEmpty ? "Trip plan" : "\(title) trip plan"
        let made = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none)
        let sub = [dateLine(filters), "Made \(made)"].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        let notice = "AI-generated and may contain errors. Check hours and kosher status before you go."

        let firstTop: CGFloat = 132
        let laterTop: CGFloat = 70
        let bottom: CGFloat = 54
        let width = page.width - margin * 2

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "Kosher Travel – \(heading)",
            kCGPDFContextCreator as String: "Kosher Travel",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: format)
        let data = renderer.pdfData { ctx in
            var pageNo = 0
            var nextGlyph = 0
            let total = layout.numberOfGlyphs
            repeat {
                ctx.beginPage()
                pageNo += 1
                let top = pageNo == 1 ? firstTop : laterTop
                drawChrome(ctx.cgContext, first: pageNo == 1, heading: heading, sub: sub, notice: notice, pageNo: pageNo)
                let frame = CGRect(x: margin, y: top, width: width, height: page.height - top - bottom)
                let container = NSTextContainer(size: frame.size)
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                let range = layout.glyphRange(for: container)
                layout.drawBackground(forGlyphRange: range, at: frame.origin)
                layout.drawGlyphs(forGlyphRange: range, at: frame.origin)
                addLinks(layout, storage, container, range, frame.origin)
                if range.length == 0 { break }
                nextGlyph = NSMaxRange(range)
            } while nextGlyph < total && pageNo < 60
        }

        let safeTitle = title.replacingOccurrences(of: #"[/\\:*?"<>|]"#, with: "", options: .regularExpression)
        let name = safeTitle.isEmpty ? "Kosher Travel trip plan.pdf" : "Kosher Travel – \(safeTitle) trip plan.pdf"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TripPDF", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        do {
            try? FileManager.default.removeItem(at: url)
            try data.write(to: url, options: .atomic)
            return PlannerPDFFile(url: url, name: name)
        } catch {
            return nil
        }
    }

    private static func addLinks(_ layout: NSLayoutManager, _ storage: NSTextStorage, _ container: NSTextContainer,
                                 _ glyphs: NSRange, _ origin: CGPoint) {
        guard glyphs.length > 0 else { return }
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        storage.enumerateAttribute(.link, in: chars, options: []) { value, range, _ in
            let url: URL?
            if let u = value as? URL { url = u } else if let s = value as? String { url = URL(string: s) } else { url = nil }
            guard let url else { return }
            let g = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layout.enumerateEnclosingRects(forGlyphRange: g, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                           in: container) { rect, _ in
                UIGraphicsSetPDFContextURLForRect(url, rect.offsetBy(dx: origin.x, dy: origin.y))
            }
        }
    }

    private static func drawChrome(_ cg: CGContext, first: Bool, heading: String, sub: String, notice: String, pageNo: Int) {
        let band = CGRect(x: 0, y: 0, width: page.width, height: first ? 104 : 46)
        navy.setFill()
        UIRectFill(band)
        if first {
            ("Kosher Travel" as NSString).draw(at: CGPoint(x: margin, y: 22), withAttributes: [
                .font: serif(13, .semibold), .foregroundColor: UIColor.white.withAlphaComponent(0.78),
            ])
            let h = NSAttributedString(string: heading, attributes: [.font: serif(24, .bold), .foregroundColor: UIColor.white])
            h.draw(with: CGRect(x: margin, y: 40, width: page.width - margin * 2, height: 32),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            if !sub.isEmpty {
                (sub as NSString).draw(at: CGPoint(x: margin, y: 75), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 10.5), .foregroundColor: UIColor.white.withAlphaComponent(0.78),
                ])
            }
        } else {
            let h = NSAttributedString(string: "Kosher Travel  ·  \(heading)", attributes: [
                .font: serif(11.5, .semibold), .foregroundColor: UIColor.white,
            ])
            h.draw(with: CGRect(x: margin, y: 16, width: page.width - margin * 2, height: 18),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
        }
        // footer
        line.setFill()
        UIRectFill(CGRect(x: margin, y: page.height - 40, width: page.width - margin * 2, height: 0.75))
        let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8.5), .foregroundColor: grey]
        (notice as NSString).draw(with: CGRect(x: margin, y: page.height - 33, width: page.width - margin * 2 - 150, height: 24),
                                  options: [.usesLineFragmentOrigin], attributes: small, context: nil)
        let right = "yourkoshertravel.com  ·  Page \(pageNo)" as NSString
        let size = right.size(withAttributes: small)
        right.draw(at: CGPoint(x: page.width - margin - size.width, y: page.height - 33), withAttributes: small)
    }
}

struct PlannerPDFPreview: View {
    let file: PlannerPDFFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PlannerPDFKitView(url: file.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Trip PDF")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            let pc = UIPrintInteractionController.shared
                            let info = UIPrintInfo(dictionary: nil)
                            info.jobName = file.name
                            info.outputType = .general
                            pc.printInfo = info
                            pc.printingItem = file.url
                            pc.present(animated: true, completionHandler: nil)
                        } label: {
                            Label("Print", systemImage: "printer")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: file.url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ShareLink(item: file.url) {
                        Label("Save, print or send", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.navy, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
        }
    }
}

struct PlannerPDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = UIColor(red: 248 / 255, green: 250 / 255, blue: 252 / 255, alpha: 1)
        v.document = PDFDocument(url: url)
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url { uiView.document = PDFDocument(url: url) }
    }
}

// MARK: Maps

struct PlannerMapsSheet: View {
    let places: [PlannerMapPlace]
    let title: String
    var days: [PlannerDayRoute] = []
    /// Add to Bucket List on each place (Oct 23 2026).
    var inBucket: ((PlannerMapPlace) -> Bool)? = nil
    var onBucket: ((PlannerMapPlace) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var linksText: String {
        let head = title.isEmpty ? "Places (Google Maps links)" : "\(title): places (Google Maps links)"
        return ([head, ""] + places.map { "\($0.name)\n\($0.googleURL.absoluteString)" }).joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let route = PlannerMaps.route(places), places.count <= 11 {
                        Button { PlannerMaps.open(route) } label: {
                            Label("Open all as a route in Google Maps", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                    }
                    ShareLink(item: linksText) {
                        Label("Share all links", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = linksText
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy all links", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
                .foregroundStyle(Color.navy)

                if !days.isEmpty {
                    Section("Route for each day") {
                        ForEach(days) { d in
                            if let url = PlannerMaps.route(d.places) {
                                Button { PlannerMaps.open(url) } label: {
                                    HStack {
                                        Label(d.label, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                        Spacer()
                                        Text("\(d.places.count) stops").font(.footnote).foregroundStyle(Color.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .foregroundStyle(Color.navy)
                }

                Section {
                    ForEach(places) { p in
                        HStack(spacing: 2) {
                        Button { PlannerMaps.open(p.googleURL) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: icon(p.kind))
                                    .font(.body)
                                    .foregroundStyle(Color.navy)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.body.weight(.semibold)).foregroundStyle(Color.navy)
                                    Text(p.subtitle).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(2)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.right.square")
                                    .foregroundStyle(Color.textTertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if let onBucket {
                            let saved = inBucket?(p) ?? false
                            Button { onBucket(p) } label: {
                                Image(systemName: saved ? "checkmark" : "heart")
                                    .font(.body)
                                    .foregroundStyle(Color.navy)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(saved ? "\(p.name) is in your Bucket List" : "Add \(p.name) to your Bucket List")
                        }
                        }
                        .contextMenu {
                            if let onBucket {
                                Button { onBucket(p) } label: { Label("Add to Bucket List", systemImage: "heart") }
                            }
                            Button { PlannerMaps.open(p.googleURL) } label: { Label("Google Maps", systemImage: "map") }
                            Button { PlannerMaps.open(p.appleURL) } label: { Label("Apple Maps", systemImage: "map.fill") }
                            Button { PlannerMaps.open(PlannerMaps.directions(p.query)) } label: {
                                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                            }
                            if let phone = p.phone, let tel = telURL(phone) {
                                Button { PlannerMaps.open(tel) } label: { Label("Call \(phone)", systemImage: "phone") }
                            }
                            Button { UIPasteboard.general.string = p.googleURL.absoluteString } label: {
                                Label("Copy link", systemImage: "link")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button { PlannerMaps.open(PlannerMaps.directions(p.query)) } label: {
                                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
                            }
                            .tint(Color.navy)
                            Button { PlannerMaps.open(p.appleURL) } label: { Label("Apple Maps", systemImage: "map") }
                                .tint(Color.textSecondary)
                        }
                    }
                } header: {
                    Text("\(places.count) place\(places.count == 1 ? "" : "s")")
                } footer: {
                    Text("Tap a place for Google Maps. Swipe for directions, or touch and hold for Apple Maps, calling or copying the link.")
                }
            }
            .navigationTitle(title.isEmpty ? "Maps" : title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sensoryFeedback(.success, trigger: copied) { _, now in now }
        }
        .presentationDetents([.medium, .large])
    }

    private func telURL(_ phone: String) -> URL? {
        let digits = phone.filter(\.isNumber)
        guard digits.count >= 10 else { return nil }
        return URL(string: "tel:" + (phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : (digits.count == 10 ? "+1" : "+")) + digits)
    }

    private func icon(_ kind: String) -> String {
        switch kind {
        case "restaurant", "catering": return "fork.knife"
        case "hotel", "rental": return "bed.double"
        case "shul", "chabad": return "building.columns"
        case "mikvah": return "drop"
        case "grocery": return "cart"
        case "sight": return "binoculars"
        default: return "mappin.and.ellipse"
        }
    }
}

// MARK: Calendar

/// What the calendar editor opens with: the trip's dates when the chat has them, else tomorrow for the plan's days.
struct PlannerCalendarDraft {
    var title: String
    var notes: String
    var start: Date
    var end: Date

    static func make(messages: [ChatMessage], plan: ChatMessage, title: String, notes: String) -> PlannerCalendarDraft {
        let f = PlannerText.filters(from: messages)
        let inF = DateFormatter()
        inF.locale = Locale(identifier: "en_US_POSIX")
        inF.dateFormat = "yyyy-MM-dd"
        let cal = Calendar.current
        var days = f.days ?? 0
        if days <= 0 {
            var top = 1
            if let re = try? NSRegularExpression(pattern: #"(?i)\bday\s*(\d{1,2})\b"#) {
                let ns = plan.content as NSString
                for m in re.matches(in: plan.content, range: NSRange(location: 0, length: ns.length)) {
                    if let n = Int(ns.substring(with: m.range(at: 1))) { top = max(top, n) }
                }
            }
            days = top
        }
        days = max(1, min(days, 60))
        let start = f.startDate.flatMap { inF.date(from: $0) }
            ?? cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        let end = f.endDate.flatMap { inF.date(from: $0) } ?? (cal.date(byAdding: .day, value: days - 1, to: start) ?? start)
        let name = title.isEmpty ? "Trip" : "Trip to \(title)"
        var text = notes
        if f.startDate != nil, let z = zmanimNotes(place: f.destination ?? title, start: start, end: max(end, start)) {
            text = z + "\n\n" + notes
        }
        return PlannerCalendarDraft(title: name, notes: text, start: start, end: max(end, start))
    }

    /// Candle lighting and Shabbos/Yom Tov end for the trip's days, from the app's own zmanim (the same as the
    /// Zmanim card), when the place and dates are known.
    static func zmanimNotes(place: String, start: Date, end: Date) -> String? {
        let parts = place.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let name = parts.first, !name.isEmpty,
              let w = ZmanimPlaces.resolve(ZmanimPlace(name: name, state: parts.count > 1 ? parts[1] : "")) else { return nil }
        let cal = Calendar.current
        let tz = TimeZone(identifier: w.tz) ?? .current
        let timeF = DateFormatter()
        timeF.locale = Locale(identifier: "en_US")
        timeF.timeZone = tz
        timeF.dateFormat = "EEE, MMM d, h:mm a"
        var lines: [String] = []
        var d = cal.startOfDay(for: start)
        var n = 0
        while d <= end && n < 21 {
            let day = ZmanimEngine.day(TripBuilderSheet.ymd(d), lat: w.lat, lng: w.lng, tz: w.tz, opts: .defaults)
            for h in day.highlights {
                if let ms = h.ms { lines.append("\(h.label): \(timeF.string(from: Date(timeIntervalSince1970: ms / 1000)))") }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
            n += 1
        }
        guard !lines.isEmpty else { return nil }
        return "Zmanim for \(w.label) (calculated by the app; check with the local shul):\n" + lines.joined(separator: "\n")
    }
}

/// The system's own event editor. On iOS 17 and later it runs outside the app, so adding an event needs no calendar
/// permission and no usage text: the traveler sees the event, edits it and taps Add.
struct PlannerCalendarEditor: UIViewControllerRepresentable {
    let event: PlannerCalendarDraft
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let vc = EKEventEditViewController()
        vc.eventStore = store
        let e = EKEvent(eventStore: store)
        e.title = event.title
        e.notes = event.notes
        e.isAllDay = true
        e.startDate = event.start
        e.endDate = event.end
        vc.event = e
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }
}
