import SwiftUI

// MARK: - Shared look for the state / country pages (web: App.tsx region pages)

/// A photo with a second address tried when the first fails (web onError → city hero photo), then a quiet tile.
struct SPImage: View {
    let urls: [String]
    var maxPixel: CGFloat = 900
    var noPhoto: AnyView? = nil
    @State private var image: UIImage?
    @State private var failed = false

    private var list: [String] {
        var seen = Set<String>()
        return urls.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var body: some View {
        Rectangle()
            .fill(Color.surface)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().transition(.opacity)
                } else if failed || list.isEmpty {
                    if let noPhoto { noPhoto } else { NoPhotoTile() }
                }
            }
            .clipped()
            .task(id: list.joined(separator: "|")) {
                image = nil
                failed = false
                if list.isEmpty { failed = true; return }
                for source in list {
                    if let hit = ImagePipeline.shared.cached(source, maxPixel: maxPixel) { image = hit; return }
                    if let loaded = await ImagePipeline.shared.load(source, maxPixel: maxPixel) {
                        withAnimation(.easeOut(duration: 0.2)) { image = loaded }
                        return
                    }
                }
                withAnimation(.easeOut(duration: 0.2)) { failed = true }
            }
            .accessibilityHidden(true)
    }
}

/// A tab's heading: bold title, grey line under it, then a hairline (web "font-extrabold text-sm" + "text-xs" + border-b).
struct SPTabHeader<Trailing: View>: View {
    var systemImage: String? = nil
    let title: String
    let subtitle: String
    var divider = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let systemImage { Image(systemName: systemImage).font(.subheadline) }
                        Text(title)
                    }
                    .font(.headline)
                    .foregroundStyle(Color.navy)
                    .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                trailing
            }
            if divider { Rectangle().fill(Color.hairline).frame(height: 1) }
        }
    }
}

extension SPTabHeader where Trailing == EmptyView {
    init(systemImage: String? = nil, title: String, subtitle: String, divider: Bool = true) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.divider = divider
        self.trailing = EmptyView()
    }
}

/// The website's empty box: white, hairline, centred bold line and a lighter line under it.
struct SPEmptyBox: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.footnote.weight(.bold)).foregroundStyle(Color.textSecondary)
            if let detail { Text(detail).font(.caption).foregroundStyle(Color.textTertiary) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.white)
        .hairline(radius: Theme.cardRadius)
    }
}

/// A navy pill button (web "bg-[#191e3b] text-white font-bold text-xs rounded-xl").
struct SPNavyButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.caption.weight(.bold)) }
                Text(title).font(.caption.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(Color.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}

/// A small icon in a hairline square (web's icon boxes on listing cards).
struct SPIconBox: View {
    let systemImage: String
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(Color.navy)
            .frame(width: size, height: size)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The page's section tabs (web .kt-tabs in the app: a light glass strip, the chosen tab a raised white pill).
struct SPTabStrip: View {
    struct Item: Identifiable, Hashable {
        let id: String
        let title: String
        var count: Int? = nil
    }
    let items: [Item]
    @Binding var selection: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(items) { item in
                        let on = item.id == selection
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { selection = item.id }
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(on ? Color.navy : Color(red: 92 / 255, green: 95 / 255, blue: 107 / 255))
                                if let c = item.count {
                                    Text("\(c)")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(on ? Color.white : Color(red: 115 / 255, green: 115 / 255, blue: 115 / 255))
                                        .padding(.horizontal, 6).padding(.vertical, 3)
                                        .background(on ? Color.navy : Color.white.opacity(0.7), in: Capsule())
                                }
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 38)
                            .background {
                                if on {
                                    Capsule().fill(Color.white.opacity(0.92))
                                        .shadow(color: Color.navy.opacity(0.12), radius: 4, y: 2)
                                        .overlay(Capsule().stroke(Color.navy.opacity(0.08), lineWidth: 0.5))
                                }
                            }
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }
                .padding(4)
            }
            .background(Color.navy.opacity(0.045), in: Capsule())
            .overlay(Capsule().stroke(Color.navy.opacity(0.08), lineWidth: 0.5))
            .sensoryFeedback(.selection, trigger: selection)
            .onChange(of: selection) { _, new in withAnimation { proxy.scrollTo(new, anchor: .center) } }
        }
    }
}

// MARK: - The United States / Caribbean circles

/// A round photo with the city count, name and description on it (web: the state / island circles), with the
/// travel-time chip under it.
struct SPRegionCircle: View {
    let tile: SPRegionTile
    /// United States: the first 10 words of the description; Caribbean: the whole description (2 lines either way).
    let tenWords: Bool
    /// Caribbean: the count sits at the top and a soft shade covers the lower photo.
    let caribbean: Bool
    @ScaledMetric(relativeTo: .caption) private var maxSide: CGFloat = 160

    private var detail: String {
        guard tenWords else { return tile.description }
        return tile.description.split(separator: " ", omittingEmptySubsequences: false).prefix(10).joined(separator: " ")
    }
    private var countText: String { "\(tile.cityCount) \(tile.cityCount == 1 ? "City" : "Cities")" }

    private var badge: some View {
        Text(countText.uppercased())
            .font(.system(size: caribbean ? 9 : 10, weight: .heavy, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 2)
            .background(Color.navy, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(caribbean ? 0.1 : 0), lineWidth: 1))
    }

    var body: some View {
        ZStack {
            SPImage(urls: [tile.image], maxPixel: 480)
            if caribbean {
                LinearGradient(colors: [Color.black.opacity(0.6), .clear], startPoint: .bottom, endPoint: .center)
            }
            VStack(spacing: 4) {
                if !caribbean { badge }
                Text(tile.name)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.95))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 4)
                }
            }
            .shadow(color: .black.opacity(0.85), radius: 5, y: 2)
            .padding(16)
            .frame(maxWidth: maxSide * 0.85)
            if caribbean {
                VStack { badge.padding(.top, 12); Spacer() }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: maxSide)
        .clipShape(Circle())
        .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)
        .contentShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tile.name), \(countText). \(detail)")
    }
}

// MARK: - City card (web renderDestinationCard)

/// The tall photo card for a city on a state or country page: name, "{state}, {country}", travel chip and the save
/// heart on the photo; GROCERY / CHABAD buttons that open the city page at that section. The card opens the city page.
struct SPCityCardView: View {
    let card: SPCityCard
    /// The country-wide card has no city page of its own in the app; its tap goes here instead.
    var onOpenWide: (() -> Void)? = nil
    private let bucket = BucketList.shared
    @ScaledMetric(relativeTo: .title3) private var height: CGFloat = 256

    private var base: some View {
        ZStack(alignment: .topLeading) {
            SPImage(urls: [card.image, card.fallback ?? ""], maxPixel: 900)
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.45), location: 0),
                .init(color: Color.black.opacity(0.2), location: 0.5),
                .init(color: Color.black.opacity(0.9), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.serifTitle(.title3))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .lineLimit(2)
                Text(card.sub)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255))
                TravelChip(name: card.name, country: card.country, state: card.state, tone: .dark)
                    .padding(.top, 4)
            }
            .padding(.trailing, 56)
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    var body: some View {
        let saved = bucket.contains(card.id)
        ZStack(alignment: .topTrailing) {
            if card.key.isEmpty {
                Button { onOpenWide?() } label: { base }.buttonStyle(.plain)
            } else {
                NavigationLink(value: ExploreRoute.area(card.key)) { base }.buttonStyle(.plain)
            }
            Button {
                bucket.toggle(card.id)
            } label: {
                Image(systemName: saved ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(saved ? Color.navy.opacity(0.9) : Color.black.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(saved ? Color.navy : Color.white.opacity(0.1), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: saved)
            .accessibilityLabel(saved ? "Saved: \(card.name)" : "Save \(card.name)")
            .padding(12)
            if !card.key.isEmpty && (card.groc || card.chab) {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        if card.groc { badge("GROCERY", hub: "grocery") }
                        if card.chab { badge("CHABAD", hub: "chabad") }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(height: height)
    }

    private func badge(_ text: String, hub: String) -> some View {
        NavigationLink(value: ExploreRoute.area("\(card.key)/hub:\(hub)")) {
            Text(text)
                .font(.system(size: 10, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.navy, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(card.name) \(text.capitalized)")
    }
}

/// The grid the website lays city cards and listing cards in (1 column on a phone, 2 when wide).
enum SPGrid {
    static let columns = [GridItem(.adaptive(minimum: 300), spacing: 16, alignment: .top)]
    static let tiles = [GridItem(.adaptive(minimum: 150), spacing: 12, alignment: .top)]
}

// MARK: - "No active kosher destinations" (state and country pages)

struct SPNoDestinations: View {
    let place: String
    let systemImage: String
    let line: String
    let example: String
    @State private var text = ""
    @State private var submitted = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color.navy)
                .accessibilityHidden(true)
            Text("No active kosher destinations in \(place) yet".uppercased())
                .font(.caption.weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Color.navy)
                .multilineTextAlignment(.center)
            Text(line)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Rectangle().fill(Color.hairline).frame(height: 1).padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text("RECOMMEND A PLACE")
                    .font(.caption2.weight(.heavy)).tracking(1.2)
                    .foregroundStyle(Color.textTertiary)
                HStack(spacing: 8) {
                    TextField(example, text: $text)
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.hairline, lineWidth: 1))
                        .submitLabel(.send)
                    // Web: the button only changes to "Submitted! ✓"; nothing is saved or sent.
                    SPNavyButton(title: submitted ? "Submitted! ✓" : "Submit") { submitted = true }
                        .sensoryFeedback(.success, trigger: submitted)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: 448)
        .background(Color.white)
        .hairline(radius: 24)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Listing cards (state / country tabs)

/// The pin + city line on a listing card.
struct SPCityLine: View {
    let city: String
    var body: some View {
        if !city.isEmpty {
            Label(city, systemImage: "mappin")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
    }
}

/// "Phone: 555-1234", the number taps to call.
struct SPPhoneLine: View {
    let phone: String
    var label = true
    @Environment(\.openURL) private var openURL
    var body: some View {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if !phone.isEmpty {
            Button {
                if let url = URL(string: "tel:\(digits)") { openURL(url) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "phone").font(.caption2)
                    (Text(label ? "Phone: " : "").foregroundStyle(Color.textSecondary) + Text(phone).foregroundStyle(Color.navy).bold())
                        .font(.caption)
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(digits.count < 5)
            .accessibilityLabel("Call \(phone)")
        }
    }
}

/// White card with a hairline that opens the place sheet (the whole card is the button).
struct SPCardShell<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }
}

/// The card heading: icon box, name, the kind line, and the city on the right.
struct SPCardHead: View {
    let systemImage: String
    let name: String
    let kind: String
    let city: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SPIconBox(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy).lineLimit(2)
                Text(kind.uppercased()).font(.caption2.weight(.heavy)).tracking(0.5).foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 6)
            SPCityLine(city: city)
        }
    }
}

struct SPAddressLine: View {
    let address: String
    var body: some View {
        if !address.isEmpty {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "mappin.and.ellipse").font(.caption2).foregroundStyle(Color.textTertiary)
                Text(address).font(.caption).foregroundStyle(Color.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SPDetailsFooter<Leading: View>: View {
    @ViewBuilder var leading: Leading
    var body: some View {
        VStack(spacing: 10) {
            Rectangle().fill(Color.hairline).frame(height: 1)
            HStack {
                leading
                Spacer(minLength: 8)
                Text("View Details →").font(.caption.weight(.bold)).foregroundStyle(Color.navy)
            }
        }
    }
}

/// A strip of the listing's photos (web PlacePhotosGallery on Shuls / Hotels cards; tapping opens the sheet).
struct SPPhotoStrip: View {
    let photos: [String]
    let category: String
    @ScaledMetric private var height: CGFloat = 128
    var body: some View {
        let list = photos.filter { !$0.isEmpty }
        Group {
            if list.count <= 1 {
                RemoteImage(url: list.first ?? "", maxPixel: 800, venue: true, category: category)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(list, id: \.self) { u in
                            RemoteImage(url: u, maxPixel: 600, venue: true, category: category)
                                .frame(width: height * 1.5, height: height)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Kosher Grocery tab card.
struct SPGroceryCard: View {
    let l: SPListing
    let action: () -> Void
    var body: some View {
        SPCardShell(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                SPCardHead(systemImage: "cart", name: l.name, kind: "Kosher Grocery", city: l.cityName ?? "")
                SPAddressLine(address: l.address)
                SPPhoneLine(phone: l.phone)
                SPDetailsFooter { EmptyView() }
            }
        }
    }
}

/// Shuls tab card.
struct SPShulCard: View {
    let l: SPListing
    let action: () -> Void
    private var kind: String {
        if let t = l.tags?.first, !t.isEmpty { return t }
        if let n = l.nusach, !n.isEmpty { return n }
        return "Shul"
    }
    var body: some View {
        SPCardShell(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                SPCardHead(systemImage: "building.columns", name: l.name, kind: kind, city: l.cityName ?? "")
                SPPhotoStrip(photos: (l.photos?.isEmpty == false ? l.photos! : [l.photo]), category: "synagogue")
                SPAddressLine(address: l.address)
                SPDetailsFooter {
                    if !l.phone.isEmpty {
                        Label(l.phone, systemImage: "phone").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }
}

/// Chabad tab card (state and country).
struct SPChabadCard: View {
    let l: SPListing
    /// Country cards carry only name, Chabad Center, town, address, Rabbi and phone (no Shabbat Meals, website or
    /// Navigate row); the state cards carry them all.
    var full = true
    let action: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        SPCardShell(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                SPCardHead(systemImage: "house", name: l.name, kind: "Chabad Center", city: l.cityName ?? "")
                SPAddressLine(address: l.address)
                if let r = l.rabbi, !r.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "person").font(.caption2).foregroundStyle(Color.textTertiary)
                        (Text("Rabbi: ").foregroundStyle(Color.textSecondary) + Text(r).foregroundStyle(Color.navy).bold()).font(.caption)
                    }
                }
                SPPhoneLine(phone: l.phone)
                if full {
                    if l.shabbatMeals == true {
                        Label("Shabbat Meals", systemImage: "flame")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.navy)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .hairline(radius: 8)
                    }
                    Rectangle().fill(Color.hairline).frame(height: 1)
                    HStack(spacing: 10) {
                        if !l.website.isEmpty && l.website != "N/A",
                           let url = URL(string: l.website.lowercased().hasPrefix("http") ? l.website : "https://\(l.website)") {
                            Button { openURL(url) } label: {
                                Label("Visit website", systemImage: "arrow.up.right.square")
                                    .font(.caption.weight(.bold)).foregroundStyle(Color.navy)
                                    .frame(minHeight: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Contact center").font(.caption.weight(.semibold)).foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                        Button {
                            if let url = SPLinks.mapsSearch("\(l.name) \(l.address) \(l.cityName ?? "")") { openURL(url) }
                        } label: {
                            Label("Navigate", systemImage: "location")
                                .font(.caption.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(minHeight: 34)
                                .background(Color.navy, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Hotels tab card.
struct SPHotelCard: View {
    let l: SPListing
    let action: () -> Void
    @Environment(\.openURL) private var openURL
    var body: some View {
        SPCardShell(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                SPCardHead(systemImage: "bed.double", name: l.name, kind: "Hotel / Lodging", city: l.cityName ?? "")
                SPPhotoStrip(photos: (l.photos?.isEmpty == false ? l.photos! : [l.photo]), category: "hotel")
                SPAddressLine(address: l.address)
                if !l.description.isEmpty {
                    Text(l.description).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(3)
                }
                Rectangle().fill(Color.hairline).frame(height: 1)
                HStack {
                    if let link = l.link, let url = SPLinks.safe(link) {
                        Button { openURL(url) } label: {
                            Text("Book / Visit").font(.caption.weight(.bold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(minHeight: 34)
                                .background(Color.navy, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("Recommended Lodging").font(.caption.weight(.semibold)).foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    if !l.phone.isEmpty {
                        Label(l.phone, systemImage: "phone").font(.caption).foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
    }
}

/// Attractions tab card: photo with a "Landmark" badge (or a no-photo tile with the name), name, description, town.
struct SPAttractionCard: View {
    let l: SPListing
    let action: () -> Void
    @ScaledMetric private var height: CGFloat = 160
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                SPImage(urls: [l.photo], maxPixel: 700, noPhoto: AnyView(
                    VStack(spacing: 6) {
                        Image(systemName: "building.columns").font(.title3)
                        Text(l.name).font(.caption.weight(.bold)).multilineTextAlignment(.center).lineLimit(2)
                    }
                    .foregroundStyle(Color.navy)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.surface)
                ))
                .frame(height: height)
                .frame(maxWidth: .infinity)
                Label("Landmark", systemImage: "building.columns")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.navy)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(10)
            }
            .clipped()
            VStack(alignment: .leading, spacing: 8) {
                Text(l.name).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy).lineLimit(2)
                if !l.description.isEmpty {
                    Text(l.description).font(.caption).foregroundStyle(Color.textSecondary).lineLimit(3)
                }
                HStack {
                    SPCityLine(city: l.cityName ?? "")
                    Spacer()
                    Text("View Details →").font(.caption.weight(.bold)).foregroundStyle(Color.navy)
                }
            }
            .padding(14)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A Things to Do tile: photo (the default photo when it fails), name, town.
struct SPTodoTile: View {
    let l: SPListing
    let fallbackCity: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                SPImage(urls: [l.photo], maxPixel: 500)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(l.name).font(.footnote.weight(.bold)).foregroundStyle(Color.navy).lineLimit(2)
                    .multilineTextAlignment(.leading)
                SPCityLine(city: (l.cityName ?? "").isEmpty ? fallbackCity : (l.cityName ?? ""))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Kosher Restaurants (country) card: type, town, address, "Kashrus:", phone.
struct SPRestaurantCard: View {
    let l: SPListing
    let action: () -> Void
    var body: some View {
        SPCardShell(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                SPCardHead(systemImage: "fork.knife", name: l.name, kind: l.kind.isEmpty ? "Kosher Food" : l.kind, city: l.cityName ?? "")
                SPAddressLine(address: l.address)
                if !l.kashrus.isEmpty {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.seal").font(.caption2).foregroundStyle(Color.textTertiary)
                        (Text("Kashrus: ").foregroundStyle(Color.textSecondary) + Text(l.kashrus).foregroundStyle(Color.navy).bold()).font(.caption)
                    }
                }
                SPPhoneLine(phone: l.phone)
            }
        }
    }
}

/// A Things to Do category card ("All State Activities" / "Family-Friendly").
struct SPCategoryCard: View {
    let cat: SPTodoCategory
    let count: Int
    /// State cards say "N active features" under the name; country cards show the number on the right.
    let country: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        SPIconBox(systemImage: cat.systemImage, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cat.name).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
                            if !country {
                                Text("\(count) active features").font(.caption2.weight(.bold)).foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                    Text(cat.description).font(.caption).foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if country {
                    Text("\(count)").font(.footnote.weight(.bold)).foregroundStyle(Color.navy)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.surface, in: Capsule())
                } else {
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary)
                }
            }
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20).fill(Color.navy).frame(width: 4)
            }
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.hairline, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tour guides

/// A tour guide someone added (web TourGuideCard).
struct SPTourGuideCard: View {
    let g: TourGuide
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label([g.city, g.state ?? ""].filter { !$0.isEmpty }.joined(separator: ", "), systemImage: "mappin")
                    .font(.caption2.weight(.heavy)).foregroundStyle(Color.navy)
                    .padding(.horizontal, 7).padding(.vertical, 3).hairline(radius: 6)
                if let langs = g.languages, !langs.isEmpty {
                    Label(langs.joined(separator: ", "), systemImage: "bubble.left.and.bubble.right")
                        .font(.caption2).foregroundStyle(Color.textSecondary).lineLimit(1)
                }
            }
            Text(g.tourType).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy)
            Text(g.guideName).font(.footnote.weight(.semibold)).foregroundStyle(Color.navy)
            Text(g.description).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(2)
            HStack(spacing: 8) {
                SPPhoneLine(phone: g.phone, label: false)
                if let w = g.website, !w.isEmpty, let url = URL(string: w.lowercased().hasPrefix("http") ? w : "https://" + w) {
                    Button { openURL(url) } label: { Label("Website", systemImage: "globe").font(.caption.weight(.semibold)) }
                        .buttonStyle(.plain).foregroundStyle(Color.navy).frame(minHeight: 36)
                }
            }
            Divider().overlay(Color.hairline)
            Text("Shared by \(g.submittedBy.isEmpty ? "Community Traveler" : g.submittedBy)")
                .font(.caption2).foregroundStyle(Color.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairline(radius: 16)
    }
}

/// The static "{place} Tour Guides Directory" box (web: the country page box and the state's Travel Guides tab).
struct SPGuidesDirectoryBox: View {
    let title: String
    let detail: String
    var action: (title: String, run: () -> Void)? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "safari")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Color.navy)
                .frame(width: 48, height: 48)
                .background(Color.surface, in: Circle())
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Color.navy).multilineTextAlignment(.center)
            Text(detail).font(.caption).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            if let action { SPNavyButton(title: action.title, systemImage: "plus", action: action.run) }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .hairline(radius: 20)
    }
}

// MARK: - Links

enum SPLinks {
    /// Google Maps search link (web `https://www.google.com/maps/search/?api=1&query=…`), opened through the app's map chooser.
    static func mapsSearch(_ q: String) -> URL? {
        var c = URLComponents(string: "https://www.google.com/maps/search/")
        c?.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: q)]
        return c?.url
    }

    /// web safeUrl: http(s) only, a bare domain gets https.
    static func safe(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        let lower = t.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return URL(string: t) }
        if lower.contains(":") { return nil }
        return URL(string: "https://\(t)")
    }
}
