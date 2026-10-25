import Foundation
import Observation
import FirebaseFirestore

/// The AI Planner's chats: the open conversation, the request in flight, and the saved list.
/// Saved on the device (Application Support, one file per account) and, when signed in, in
/// users/{uid}/chatConversations/{id} with the web's document shape (src/userFirestore.ts saveUserChatSessionToFirestore).
@MainActor
@Observable
final class PlannerStore {
    static let maxChats = 50     // web: MAX_PLANNER_CHATS

    private(set) var sessions: [ChatSession] = []
    private(set) var currentId: String?
    private(set) var messages: [ChatMessage] = []
    private(set) var isGenerating = false
    private(set) var errorText: String?
    /// The answer that is being revealed word by word right now.
    var typingId: String?
    /// Word-by-word reveal of new answers (off for the QA demo so its screenshot shows the whole answer).
    @ObservationIgnored var revealsAnswers = true
    /// Bumped on each new answer / send (haptics, scrolling).
    private(set) var answerCount = 0
    private(set) var sendCount = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var accountKey = "guest"
    @ObservationIgnored private var syncedUid: String?

    init() {
        sessions = Self.readLocal("guest")
    }

    // MARK: sending

    func send(_ text: String, filters: TripFilters? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !isGenerating else { return }
        typingId = nil
        messages.append(ChatMessage(role: "user", content: t, filters: filters))
        sendCount += 1
        persist()
        run(messages)
    }

    /// Edit a sent message in place: replace its text, drop everything after it, ask again (web: submitPlannerEdit).
    func edit(_ id: String, to text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let idx = messages.firstIndex(where: { $0.id == id && $0.isUser }) else { return }
        cancelRequest()
        var history = Array(messages.prefix(idx + 1))
        history[idx].content = t
        history[idx].isEdited = true
        messages = history
        typingId = nil
        sendCount += 1
        persist()
        run(history)
    }

    /// A Filters change mid-chat (web: applyPlannerFilters): a small "Updated for: …" note, then the same plan again.
    func applyFilters(_ next: TripFilters) {
        var history = messages
        if let last = history.last, last.isFiltersNote { history.removeLast() }
        guard history.contains(where: { $0.isUser }) else { return }
        let label = TripFilters.describeChange(PlannerText.filters(from: history), next)
        if label.isEmpty {
            // Changed back to what the plan already uses: drop the waiting note, nothing to ask.
            if history.count != messages.count {
                cancelRequest()
                errorText = nil
                messages = history
                persist()
            }
            return
        }
        cancelRequest()
        var note = ChatMessage(role: "user", content: TripFilters.updateRequestText(label), filters: next.cleaned)
        note.kind = "filters"
        note.label = label
        typingId = nil
        messages = history + [note]
        sendCount += 1
        persist()
        run(messages)
    }

    /// Retry re-sends the chat as it is (it ends with the question).
    func retry() {
        guard !isGenerating else { return }
        guard let last = messages.last, last.isUser else { errorText = nil; return }
        run(messages)
    }

    /// Stop the answer on its way (nothing is added to the chat).
    func stop() {
        guard isGenerating else { return }
        cancelRequest()
        errorText = "Stopped. Tap Retry to ask again."
    }

    private func cancelRequest() {
        task?.cancel()
        task = nil
        token = UUID()
        isGenerating = false
    }

    private func run(_ history: [ChatMessage]) {
        task?.cancel()
        let my = UUID()
        token = my
        errorText = nil
        isGenerating = true
        let chatId = currentId
        task = Task { [weak self] in
            do {
                let answer = try await PlannerAPI.ask(history)
                guard let self, self.token == my, !Task.isCancelled else { return }
                var msg = ChatMessage(role: "assistant", content: answer.message)
                if !answer.suggestions.isEmpty { msg.suggestions = answer.suggestions }
                if !answer.away.isEmpty { msg.away = answer.away }
                if !answer.articles.isEmpty { msg.articles = answer.articles }
                // The chat could have been switched meanwhile; the answer belongs to the chat that asked.
                guard self.currentId == chatId || chatId == nil else { self.finish(my); return }
                self.messages.append(msg)
                self.typingId = self.revealsAnswers ? msg.id : nil
                self.answerCount += 1
                self.persist()
                self.finish(my)
            } catch let f as PlannerAPI.Failure {
                guard let self, self.token == my else { return }
                self.errorText = f.message
                self.finish(my)
            } catch {
                guard let self, self.token == my else { return }
                if !(error is CancellationError) {
                    self.errorText = "Sorry, I couldn't answer just now. Please tap Retry."
                }
                self.finish(my)
            }
        }
    }

    private func finish(_ my: UUID) {
        guard token == my else { return }
        isGenerating = false
        task = nil
    }

    // MARK: chats

    func newChat() {
        cancelRequest()
        errorText = nil
        typingId = nil
        currentId = nil
        messages = []
    }

    func open(_ s: ChatSession) {
        cancelRequest()
        errorText = nil
        typingId = nil
        currentId = s.id
        messages = s.messages
    }

    func delete(_ s: ChatSession) {
        sessions.removeAll { $0.id == s.id }
        if currentId == s.id { newChat() }
        writeLocal()
        if let uid = syncedUid, FirebaseBoot.isConfigured {
            Self.collection(uid).document(s.id).delete { err in
                if let err { print("[KT] planner delete failed: \(err.localizedDescription)") }
            }
        }
    }

    /// Saves the open chat (web: the auto-save effect on plannerMessages). Only a real change moves it to the top.
    private func persist() {
        guard !messages.isEmpty else { return }
        let now = ChatSession.nowString()
        let id = currentId ?? ChatMessage.newId()
        currentId = id
        var saved: ChatSession
        if let i = sessions.firstIndex(where: { $0.id == id }) {
            let old = sessions[i]
            let changed = old.messages.count != messages.count || old.messages.last?.content != messages.last?.content
                || old.messages.last?.isEdited != messages.last?.isEdited
            guard changed else { return }
            saved = old
            saved.messages = messages
            let title = ChatSession.title(for: messages)
            if !title.isEmpty { saved.title = title }
            saved.updatedAt = now
            sessions.remove(at: i)
        } else {
            saved = ChatSession(id: id, title: ChatSession.title(for: messages), date: now, updatedAt: now,
                                messages: messages, sessionType: "planner", fixedDestination: "")
        }
        sessions.insert(saved, at: 0)
        if sessions.count > Self.maxChats {
            let dropped = sessions[Self.maxChats...].filter { $0.id != id }
            sessions = Array(sessions.prefix(Self.maxChats))
            if let uid = syncedUid, FirebaseBoot.isConfigured {
                for s in dropped { Self.collection(uid).document(s.id).delete() }
            }
        }
        writeLocal()
        if let uid = syncedUid { Self.saveRemote(uid, saved) }
    }

    // MARK: account

    /// Called when the signed-in person changes: their own chats (device file + account), merged by chat id.
    func setAccount(uid: String?) {
        guard uid != syncedUid || accountKey != (uid ?? "guest") else { return }
        syncedUid = uid
        accountKey = uid ?? "guest"
        newChat()
        sessions = Self.readLocal(accountKey)
        guard let uid, FirebaseBoot.isConfigured else { return }
        Task { [weak self] in
            let remote = await Self.fetchRemote(uid)
            guard let self, self.syncedUid == uid, let remote else { return }
            self.merge(remote)
        }
    }

    private func merge(_ remote: [ChatSession]) {
        var byId: [String: ChatSession] = [:]
        for s in sessions { byId[s.id] = s }
        var pushUp: [ChatSession] = []
        for r in remote where r.isPlanner {
            if let local = byId[r.id] {
                // keep the newer one; a chat changed on this phone while offline goes back up to the account
                if local.sortDate > r.sortDate.addingTimeInterval(1) { pushUp.append(local) } else { byId[r.id] = r }
            } else {
                byId[r.id] = r
            }
        }
        let remoteIds = Set(remote.map(\.id))
        for s in sessions where !remoteIds.contains(s.id) { pushUp.append(s) }
        sessions = Array(byId.values.sorted { $0.sortDate > $1.sortDate }.prefix(Self.maxChats))
        if let id = currentId, let s = sessions.first(where: { $0.id == id }), !isGenerating { messages = s.messages }
        writeLocal()
        if let uid = syncedUid { for s in pushUp { Self.saveRemote(uid, s) } }
    }

    // MARK: device file

    private static func fileURL(_ key: String) -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = dir.appendingPathComponent("planner", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = key.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return folder.appendingPathComponent("chats-\(safe).json")
    }

    private static func readLocal(_ key: String) -> [ChatSession] {
        guard let url = fileURL(key), let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([ChatSession].self, from: data) else { return [] }
        return list.filter(\.isPlanner).sorted { $0.sortDate > $1.sortDate }
    }

    private func writeLocal() {
        guard let url = Self.fileURL(accountKey) else { return }
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("[KT] planner save failed: \(error.localizedDescription)")
        }
    }

    // MARK: account (Firestore)

    private static func collection(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("chatConversations")
    }

    private static func saveRemote(_ uid: String, _ s: ChatSession) {
        guard FirebaseBoot.isConfigured else { return }
        var doc: [String: Any] = [
            "id": s.id,
            "title": s.title,
            "date": s.date,
            "messages": s.messages.map(\.dictionary),
            "sessionType": s.sessionType ?? "planner",
            "fixedDestination": s.fixedDestination ?? "",
        ]
        doc["updatedAt"] = FieldValue.serverTimestamp()
        collection(uid).document(s.id).setData(doc, merge: true) { err in
            if let err { print("[KT] planner sync failed: \(err.localizedDescription)") }
        }
    }

    private static func fetchRemote(_ uid: String) async -> [ChatSession]? {
        do {
            let snap = try await collection(uid).getDocuments()
            return snap.documents.compactMap { doc -> ChatSession? in
                let d = doc.data()
                let msgs = ((d["messages"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any]).flatMap(ChatMessage.init(dictionary:)) }
                var updated: String?
                if let ts = d["updatedAt"] as? Timestamp { updated = ChatSession.iso.string(from: ts.dateValue()) }
                else if let s = d["updatedAt"] as? String { updated = s }
                var date = (d["date"] as? String) ?? ""
                if date.isEmpty, let ts = d["date"] as? Timestamp { date = ChatSession.iso.string(from: ts.dateValue()) }
                if date.isEmpty { date = updated ?? ChatSession.nowString() }
                let title = (d["title"] as? String) ?? ChatSession.title(for: msgs)
                return ChatSession(id: doc.documentID, title: title, date: date, updatedAt: updated, messages: msgs,
                                   sessionType: (d["sessionType"] as? String) ?? "planner",
                                   fixedDestination: d["fixedDestination"] as? String)
            }
        } catch {
            print("[KT] planner load failed: \(error.localizedDescription)")
            return nil
        }
    }
}
