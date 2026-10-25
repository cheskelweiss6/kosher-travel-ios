import SwiftUI
import UIKit

/// AI Planner: chat with the Kosher Travel planner (web: components/planner/PlannerChat.tsx + the planner logic in App.tsx).
struct PlannerTab: View {
    @Environment(ExploreStore.self) private var explore
    @Environment(StoryFeed.self) private var feed
    @Environment(AuthStore.self) private var auth

    @State private var store = PlannerStore()
    @State private var path: [ExploreRoute] = []
    @State private var cache = PlannerCache()
    @State private var showHistory = false
    @State private var showBuilder = false
    @State private var editing: ChatMessage?
    @State private var safari: IdentifiedURL?
    @State private var placeSheet: PlaceItem?
    @State private var builderCity: String?
    @State private var routeApplied = false
    @State private var confirmNewChat = false

    static let demoQuestion = "Kosher restaurants in Miami Beach"
    static let starters = [
        "A 7-day kivrei tzadikim trip in Poland & Hungary",   // web PlannerChat STARTERS (Europe public, Oct 24 2026)
        "Kosher restaurants in Miami Beach",
        "A Shabbos-friendly hotel near a shul in Orlando",
        "Where can I find a minyan in Cancun?",
        "Chabad and Shabbos meals in Aruba",
    ]
    static let featuredNames = ["Miami", "Cancun", "Aruba", "Punta Cana", "Orlando", "Los Angeles"]

    private var places: [PlannerPlace] {
        if let p = cache.places { return p }
        let p = PlannerMatches.places(explore.data)
        if explore.data != nil { cache.places = p }
        return p
    }

    private func cards(for msg: ChatMessage) -> [PlannerPlace] {
        if let c = cache.cards[msg.id] { return c }
        let c = PlannerMatches.mentioned(in: msg.content, places: places)
        if cache.places != nil { cache.cards[msg.id] = c }
        return c
    }

    var body: some View {
        NavigationStack(path: $path) {
            chat
                .navigationTitle("AI Planner")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .confirmationDialog("Start a new chat?", isPresented: $confirmNewChat, titleVisibility: .visible) {
                    Button("New chat") { store.newChat() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This chat stays saved in your chats.")
                }
                .navigationDestination(for: ExploreRoute.self) { route in
                    ExploreDestination(route: route)
                }
        }
        .sheet(isPresented: $showHistory) {
            PlannerHistoryView(store: store, signedIn: auth.isSignedIn)
        }
        .sheet(isPresented: $showBuilder) {
            let hasTrip = store.messages.contains { $0.isUser } && builderCity == nil
            TripBuilderSheet(places: places, initial: hasTrip ? PlannerText.filters(from: store.messages) : nil, prefill: builderCity,
                             onCreate: { text, filters in store.send(text, filters: filters) },
                             onApply: { next in store.applyFilters(next) })
        }
        .sheet(item: $editing) { msg in
            EditMessageSheet(original: msg.content) { text in store.edit(msg.id, to: text) }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $safari) { item in
            SafariSheet(url: item.url).ignoresSafeArea()
        }
        .sheet(item: $placeSheet) { item in
            PlaceDetailView(item: item, onOpenStory: { id in
                placeSheet = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { path.append(.story(id)) }
            })
        }
        .task(id: auth.uid ?? "") {
            store.setAccount(uid: auth.uid)
            // after the account's chats are in place, so a question from Ask AI is not wiped by the account switch
            takeShellPrompt()
            takeTripCity()
        }
        .onChange(of: ShellRouter.shared.plannerTripCity) { _, _ in takeTripCity() }
        .onChange(of: showBuilder) { _, on in if !on { builderCity = nil } }
        .task { await feed.loadIfNeeded() }
        .onAppear(perform: applyLaunchRoute)
        .onChange(of: ShellRouter.shared.plannerPrompt) { _, _ in takeShellPrompt() }
        .sensoryFeedback(Motion.Haptic.tap, trigger: store.sendCount)
        .sensoryFeedback(Motion.Haptic.success, trigger: store.answerCount)
        .sensoryFeedback(Motion.Haptic.error, trigger: store.errorText) { _, new in new != nil }
    }

    /// A question handed over by another screen (an embedded page's "Plan with AI"), sent once.
    private func takeShellPrompt() {
        guard let q = ShellRouter.shared.plannerPrompt, !q.isEmpty else { return }
        ShellRouter.shared.plannerPrompt = nil
        path = []
        store.send(q)
    }

    /// A city page's "Plan Trip" (web: setWizardCity + planner tab): Plan a trip opens with that city filled in.
    private func takeTripCity() {
        guard let c = ShellRouter.shared.plannerTripCity, !c.isEmpty else { return }
        ShellRouter.shared.plannerTripCity = nil
        path = []
        builderCity = c
        showBuilder = true
    }

    // MARK: toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                hideKeyboard()
                showHistory = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.navy)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Open chats")
        }
        // Web: "Filters" sits in the planner's own top bar, with the number of picks set for this chat.
        ToolbarItem(placement: .topBarLeading) {
            let count = store.messages.contains { $0.isUser } ? PlannerText.filters(from: store.messages).chipLabels.count : 0
            Button {
                hideKeyboard()
                showBuilder = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Filters").fontWeight(.semibold)
                    if count > 0 {
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Color.navy, in: Capsule())
                    }
                }
                .foregroundStyle(Color.navy)
                .padding(.horizontal, 4)
            }
            .accessibilityLabel(count > 0 ? "Trip filters, \(count) set" : "Trip filters")
        }
        ToolbarItem(placement: .topBarTrailing) {
            // Asks first when the chat has messages: on iOS 26 the answer's Share / Make PDF row scrolls up under this
            // button, and one stray tap emptied the whole chat with no way back (Cheskel's video, Oct 23 2026).
            // Empty chat: nothing to start over (web: disabled={messages.length === 0}).
            Button {
                hideKeyboard()
                if store.messages.isEmpty { store.newChat() } else { confirmNewChat = true }
            } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(store.messages.isEmpty ? Color.textTertiary : Color.navy)
            }
            .disabled(store.messages.isEmpty)
            .accessibilityLabel("Start a new chat")
        }
        // Web: the planner's own header carries the account button.
        ToolbarItem(placement: .topBarTrailing) { AccountToolbarButtons() }
    }

    // MARK: chat

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.messages.isEmpty {
                    welcome
                    Color.clear.frame(height: 1).id("welcomeEnd")
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { i, msg in
                            row(msg, index: i)
                                .id(msg.id)
                        }
                        if store.isGenerating {
                            TypingDots().id("typing")
                        }
                        if let err = store.errorText, !store.isGenerating, store.messages.last?.isUser == true {
                            errorRow(err).id("error")
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            // Cheskel (Oct 23 2026: "How do I get out of the AI planner page?"): a tap on the chat closes the keyboard,
            // so the tab bar is always reachable (links in answers still open: the tap is simultaneous).
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
            .environment(\.openURL, OpenURLAction { url in handleLink(url) })
            .safeAreaInset(edge: .bottom, spacing: 0) { PlannerComposer(store: store) }
            .onChange(of: store.sendCount) { _, _ in
                scroll(proxy, to: "bottom", anchor: .bottom)
            }
            .onChange(of: store.isGenerating) { _, busy in
                if busy { scroll(proxy, to: "bottom", anchor: .bottom) }
            }
            .onChange(of: store.answerCount) { _, _ in
                // the new answer reads from its question down, like ChatGPT
                if let q = store.messages.last(where: { $0.isUser })?.id { scroll(proxy, to: q, anchor: .top) }
            }
            .onChange(of: store.errorText) { _, e in
                if e != nil { scroll(proxy, to: "bottom", anchor: .bottom) }
            }
            .onChange(of: store.currentId) { _, _ in
                Task { @MainActor in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            // Keyboard up: the content above the message box moves up with it (Cheskel's 8:54 video: the box covered
            // "Plan a trip").
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                scroll(proxy, to: store.messages.isEmpty ? "welcomeEnd" : "bottom", anchor: .bottom)
            }
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String, anchor: UnitPoint) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(Motion.scroll) { proxy.scrollTo(id, anchor: anchor) }
        }
    }

    // MARK: welcome

    private var featured: [PlannerPlace] {
        let all = places
        var out: [PlannerPlace] = []
        for name in Self.featuredNames {
            if let p = all.first(where: { $0.name == name }) { out.append(p) }
            if out.count == 3 { break }
        }
        return out
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            let f = featured
            if f.count == 3 {
                HStack(spacing: 8) {
                    ForEach(f) { p in
                        Button { store.send("Plan a kosher trip to \(p.name)") } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                RemoteImage(url: p.photo, maxPixel: 500)
                                    .aspectRatio(4 / 5, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text(p.name)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Color.navy)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Plan a kosher trip to \(p.name)")
                    }
                }
                .padding(.bottom, 22)
            }

            Text("Where are you headed?")
                .font(.system(.title2, design: .serif).weight(.bold))
                .foregroundStyle(Color.navy)
            Text("Ask about kosher food, minyanim and shuls, hotels near a shul, or a full trip plan.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 6)

            Button { showBuilder = true } label: {
                HStack(spacing: 14) {
                    Image(systemName: "map")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.navy, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Plan a trip").font(.body.weight(.semibold)).foregroundStyle(Color.navy)
                        Text("Pick a place, days, budget and travelers").font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary)
                }
                .padding(14)
                .background(Color.white)
                .hairline(radius: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .padding(.top, 20)

            Text("Or ask")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 24)
                .padding(.bottom, 6)
            VStack(spacing: 0) {
                Divider().overlay(Color.hairline)
                ForEach(Self.starters, id: \.self) { s in
                    Button { store.send(s) } label: {
                        HStack(spacing: 12) {
                            Text(s).font(.body).foregroundStyle(Color.navy).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary)
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().overlay(Color.hairline)
                }
            }
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    // MARK: rows

    @ViewBuilder
    private func row(_ msg: ChatMessage, index: Int) -> some View {
        if msg.isFiltersNote {
            HStack(spacing: 10) {
                Rectangle().fill(Color.hairline).frame(height: 1)
                (Text("Updated for: ").foregroundStyle(Color.textSecondary) + Text(msg.label ?? "new trip settings").foregroundStyle(Color.navy))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .layoutPriority(1)
                Rectangle().fill(Color.hairline).frame(height: 1)
            }
            .padding(.vertical, 4)
        } else if msg.isUser {
            userBubble(msg)
        } else {
            assistantRow(msg, index: index)
        }
    }

    private func userBubble(_ msg: ChatMessage) -> some View {
        let text = PlannerText.sanitize(msg.content)
        let lines = text.components(separatedBy: "\n")
        let isTrip = lines.count > 2 && (lines[0].hasPrefix("Plan a trip to ") || lines[0].hasPrefix("Help me plan a trip"))
        return HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 3) {
                Group {
                    if isTrip {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lines[0]).font(.body.weight(.semibold))
                            ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { _, l in
                                Text(l).font(.subheadline).foregroundStyle(Color.white.opacity(0.82))
                            }
                        }
                    } else {
                        Text(text).font(.body)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(Color.navy, in: BubbleShape(mine: true))
                .contentShape(.contextMenuPreview, BubbleShape(mine: true))
                .contextMenu { menu(msg) }
                if msg.isEdited == true {
                    Text("Edited").font(.caption2).foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func assistantRow(_ msg: ChatMessage, index: Int) -> some View {
        let isLast = index == store.messages.count - 1
        let typing = store.typingId == msg.id
        let settled = isLast && !typing && !store.isGenerating && store.errorText == nil
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if typing {
                    TypewriterMarkdown(content: msg.content) { store.typingId = nil }
                } else {
                    // place names open Maps (work actions, Oct 23)
                    PlannerMarkdown(content: PlannerActions.linked(msg, messages: store.messages, cards: cards(for: msg)))
                }
            }
            .font(.body)
            .foregroundStyle(Color(red: 30 / 255, green: 41 / 255, blue: 59 / 255))
            .contentShape(Rectangle())
            .contextMenu { menu(msg) }

            if !typing {
                let cards = cards(for: msg)
                if !cards.isEmpty { destinationCards(cards, away: msg.away ?? [:]) }
                if let articles = articlesFor(index: index) { articlesRow(articles) }
                if PlannerActions.showsBar(for: msg, index: index, messages: store.messages, settled: settled, cards: cards) {
                    PlannerActionBar(message: msg, index: index, messages: store.messages, cards: cards) { text in
                        store.send(text)
                    }
                }
            }
            if settled {
                let chips: [String] = (msg.suggestions ?? []).isEmpty
                    ? (PlannerText.isItinerary(msg.content) ? ["Make it shorter", "Where can I daven?", "Show kosher restaurants"] : [])
                    : Array((msg.suggestions ?? []).prefix(4))
                if !chips.isEmpty { chipRow(chips) }
            }
        }
        .padding(.trailing, 4)
    }

    @ViewBuilder
    private func menu(_ msg: ChatMessage) -> some View {
        Button { UIPasteboard.general.string = msg.content } label: { Label("Copy", systemImage: "doc.on.doc") }
        ShareLink(item: msg.content) { Label("Share", systemImage: "square.and.arrow.up") }
        if msg.isUser && !store.isGenerating {
            Button { editing = msg } label: { Label("Edit", systemImage: "pencil") }
        }
    }

    // Articles: once per place, not repeated under every follow-up (web: useChatArticles). Worked out once per change.
    private func articlesFor(index: Int) -> PlannerMatches.Articles? {
        let msgs = store.messages
        guard index < msgs.count, msgs[index].isAssistant, !feed.posts.isEmpty else { return nil }
        let key = "\(msgs.count)|\(msgs.last?.id ?? "")|\(feed.posts.count)|\(store.typingId ?? "")|\(store.currentId ?? "")"
        if cache.articlesKey != key {
            cache.articlesKey = key
            cache.articles = [:]
            var question = ""
            var shown = Set<String>()
            var lastKey = ""
            for m in msgs where !m.isFiltersNote {
                if m.isUser { question = m.content; continue }
                if m.id == store.typingId { continue }
                guard let hit = PlannerMatches.articles(question: question, answer: m.content, posts: feed.posts, explore: explore) else { continue }
                let k = hit.label + "|" + hit.posts.map(\.id).joined(separator: ",")
                if k == lastKey || hit.posts.allSatisfy({ shown.contains($0.id) }) { continue }
                hit.posts.forEach { shown.insert($0.id) }
                lastKey = k
                cache.articles[m.id] = hit
            }
        }
        return cache.articles[msgs[index].id]
    }

    private func destinationCards(_ items: [PlannerPlace], away: [String: Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open in Kosher Travel")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { p in
                        NavigationLink(value: ExploreRoute.area(p.id)) {
                            VStack(alignment: .leading, spacing: 0) {
                                RemoteImage(url: p.photo, maxPixel: 500)
                                    .frame(height: 104)
                                    .clipped()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                        .font(.system(.subheadline, design: .serif).weight(.bold))
                                        .foregroundStyle(Color.navy)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text((away[p.name].map { "\($0) mi away · " } ?? "") + p.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(Color.textSecondary)
                                            .lineLimit(1)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Color.textTertiary)
                                    }
                                }
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                            }
                            .frame(width: 172)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .hairline(radius: 16)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
    }

    private func articlesRow(_ a: PlannerMatches.Articles) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                (Text("Articles from travelers in ").foregroundStyle(Color.textSecondary) + Text(a.label).foregroundStyle(Color.navy))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let route = a.route {
                    NavigationLink(value: route) {
                        HStack(spacing: 2) {
                            Text("See all")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.navy)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(a.posts) { p in
                        NavigationLink(value: ExploreRoute.story(p.id)) {
                            HStack(spacing: 0) {
                                StoryCoverImage(post: p, maxPixel: 240)
                                    .frame(width: 72, height: 72)
                                    .clipped()
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(p.title.isEmpty ? p.cityName : p.title)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Color.navy)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 6) {
                                        Text(p.authorName).lineLimit(1)
                                        if p.likesCount > 0 {
                                            Label("\(p.likesCount)", systemImage: "heart")
                                                .labelStyle(.titleAndIcon)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(Color.textSecondary)
                                }
                                .padding(.horizontal, 10)
                                Spacer(minLength: 0)
                            }
                            .frame(width: 220, height: 72)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .hairline(radius: 12)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("\(p.title) by \(p.authorName). Opens the article.")
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
    }

    private func chipRow(_ chips: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { c in
                    Button { store.send(c) } label: {
                        Text(c)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.navy)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.navy.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private func errorRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(text).font(.subheadline).foregroundStyle(Color.navy)
            } icon: {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Color.alert)
            }
            Button { store.retry() } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.navy)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .hairline(radius: 18)
    }

    // MARK: links

    private func handleLink(_ url: URL) -> OpenURLAction.Result {
        if let id = PlannerLinks.storyId(url) {
            path.append(.story(id))
            return .handled
        }
        if PlannerAppPlace.isAppLink(url) {
            let found = PlannerAppPlace.resolve(url, data: explore.data)
            if let item = found.item { placeSheet = item } else { PlannerMaps.open(found.maps) }
            return .handled
        }
        if PlannerMaps.isMapsURL(url) {
            PlannerMaps.open(url)
            return .handled
        }
        // phone, WhatsApp (wa.me), mail: the system app, like links on the embedded screens (LinkOpener)
        if case .system(let u)? = LinkOpener.target(for: url) {
            LinkOpener.openSystem(u)
            return .handled
        }
        if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            safari = IdentifiedURL(url: PlannerLinks.affiliate(url))
            return .handled
        }
        return .systemAction
    }

    // MARK: QA

    /// "tab:planner/demo" asks one fixed question on launch; "tab:planner/builder" opens Plan a trip;
    /// "tab:planner/history" opens the chat list.
    private func applyLaunchRoute() {
        guard !routeApplied, let r = LaunchRoute.current, r.hasPrefix("tab:planner/") else { return }
        routeApplied = true
        switch String(r.dropFirst("tab:planner/".count)) {
        case "demo":
            store.newChat()
            store.revealsAnswers = false
            let s = store
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                s.send(Self.demoQuestion)
            }
        case "kever":
            // the kivrei tzadikim starter (Europe routes): checks the caretaker tap-to-call lines render as links
            store.newChat()
            store.revealsAnswers = false
            let s = store
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                s.send(Self.starters[0])
            }
        case "builder": showBuilder = true
        case "history": showHistory = true
        default: break
        }
    }
}

/// iMessage-style bubble: round, with one smaller corner on the sender's side.
struct BubbleShape: Shape {
    var mine: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 20, small: CGFloat = 6
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: r, bottomLeading: mine ? r : small, bottomTrailing: mine ? small : r, topTrailing: r), style: .continuous)
    }
}

/// Three dots while the planner thinks.
struct TypingDots: View {
    var body: some View {
        // 30 redraws a second is plenty for a soft pulse (was every display frame, up to 120 on ProMotion).
        // Reduce Motion: the pulse is an opacity change, not movement, so it stays.
        TimelineView(.animation(minimumInterval: Motion.pulseInterval)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 2.2 - Double(i) * 0.35).truncatingRemainder(dividingBy: 2 * .pi)
                    Circle()
                        .fill(Color.textTertiary)
                        .frame(width: 7, height: 7)
                        .opacity(0.35 + 0.65 * (0.5 + 0.5 * sin(phase * 2.8)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255), in: BubbleShape(mine: false))
        }
        .accessibilityLabel("The planner is typing")
    }
}

/// The answer appears word by word (the server sends it whole; the web shows it the same way).
struct TypewriterMarkdown: View {
    let content: String
    let onDone: () -> Void
    @State private var shown = 0

    var body: some View {
        PlannerMarkdown(content: String(content.prefix(shown)))
            .task {
                let chars = Array(content)
                let total = chars.count
                // about 1.5 to 3 seconds whatever the length
                let ticks = max(20, min(70, total / 12))
                let step = max(3, total / ticks)
                while shown < total {
                    try? await Task.sleep(nanoseconds: 40_000_000)
                    if Task.isCancelled { return }
                    var next = min(total, shown + step)
                    while next < total && !chars[next].isWhitespace { next += 1 }
                    shown = next
                }
                onDone()
            }
    }
}

struct EditMessageSheet: View {
    let original: String
    let onSend: (String) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextField("Message", text: $text, axis: .vertical)
                .lineLimit(3...12)
                .focused($focused)
                .padding(14)
                .hairline(radius: 14)
                .padding(Theme.pagePadding)
                .frame(maxHeight: .infinity, alignment: .top)
                .navigationTitle("Edit message")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { onSend(text); dismiss() }
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { text = original; focused = true }
        }
    }
}

/// Work kept between renders (matching answers to places and articles is not free).
final class PlannerCache {
    var places: [PlannerPlace]?
    var cards: [String: [PlannerPlace]] = [:]
    var articlesKey = ""
    var articles: [String: PlannerMatches.Articles] = [:]
}

/// The message box: its own view, so typing does not redraw the chat.
struct PlannerComposer: View {
    let store: PlannerStore
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.hairline)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color(red: 203 / 255, green: 213 / 255, blue: 225 / 255), lineWidth: 1))
                    .accessibilityLabel("Message the Trip Planner")
                    .submitLabel(.return)
                if store.isGenerating || store.typingId != nil {
                    Button {
                        if store.isGenerating { store.stop() } else { store.typingId = nil }
                    } label: {
                        ZStack {
                            Circle().fill(Color.navy)
                            RoundedRectangle(cornerRadius: 2.5).fill(Color.white).frame(width: 12, height: 12)
                        }
                        .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel("Stop")
                } else {
                    Button(action: submit) {
                        ZStack {
                            Circle().fill(canSend ? Color.navy : Color.textTertiary.opacity(0.5))
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .frame(width: 36, height: 36)
                    }
                    .disabled(!canSend)
                    .accessibilityLabel("Send")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(.bar)
    }

    private func submit() {
        guard canSend, !store.isGenerating else { return }
        let text = draft
        draft = ""
        focused = false   // the answer and the tab bar show again after sending
        store.send(text)
    }
}
