import Foundation

/// The AI Planner chat server (web: runPlannerRequest / plannerRequestBody in src/App.tsx, server chat-api/_worker.js).
/// POST https://www.yourkoshertravel.com/kt-ai/api/chat with JSON; the answer is one JSON object (not streamed):
///   { message, suggestions?, away?: { "<city>": { mi, min } }, profile, meta }   or   { error, message?, retryable? }
/// Only this chat's messages are sent (no profile, saved trips or other chats: Cheskel, Oct 20), plus the chat's
/// trip settings and the latest day-by-day plan, exactly like the web.
enum PlannerAPI {
    static let endpoint = URL(string: "https://www.yourkoshertravel.com/kt-ai/api/chat")!
    static let timeout: TimeInterval = 75     // the web gives up at 75 s and shows Retry

    struct Answer {
        var message: String
        var suggestions: [String]
        var away: [String: Int]
        var articles: [PlannerArticleRef] = []
    }

    struct Failure: Error {
        var message: String
        var retryable: Bool
    }

    static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = timeout
        cfg.timeoutIntervalForResource = timeout
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    /// The request body (web: plannerRequestBody).
    static func body(for history: [ChatMessage]) -> [String: Any] {
        var body: [String: Any] = [
            "messages": history.map { ["id": $0.id, "role": $0.role, "content": $0.content] },
            // The server tells the AI about the app's Make PDF / Maps / Share / Calendar buttons only for this client,
            // and lists the app places an answer names (the website never sends it, so its answers are unchanged).
            "client": "ios-native",
        ]
        let filters = PlannerText.filters(from: history)
        if !filters.isEmpty { body["tripFilters"] = filters.dictionary }
        if let last = history.last, last.isFiltersNote { body["tripUpdate"] = last.label ?? "" }
        let plan = PlannerText.latestItinerary(history)
        if !plan.isEmpty { body["currentItinerary"] = plan }
        return body
    }

    /// One request, with one quiet retry on a busy moment or a dropped connection (same as the web).
    static func ask(_ history: [ChatMessage]) async throws -> Answer {
        do {
            return try await once(history)
        } catch let f as Failure where f.retryable {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            return try await once(history)
        }
    }

    private static func once(_ history: [ChatMessage]) async throws -> Answer {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body(for: history))
        req.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch is CancellationError {
            throw CancellationError()
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            if e.code == .timedOut { throw Failure(message: "That took too long. Please tap Retry.", retryable: false) }
            if e.code == .notConnectedToInternet {
                throw Failure(message: "You seem to be offline. Check your connection and tap Retry.", retryable: false)
            }
            throw Failure(message: "Sorry, I couldn't answer just now. Please tap Retry.", retryable: true)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let message = (json["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code = json["error"] as? String
        // NOT_CONFIGURED is a friendly answer from the server: shown as a normal reply.
        let failed = !(200..<300).contains(status) || message.isEmpty || (code != nil && code != "NOT_CONFIGURED")
        if failed {
            let serverMessage = message.isEmpty ? nil : message
            switch code {
            case "QUOTA_EXCEEDED_DAILY":
                throw Failure(message: serverMessage ?? "The AI planner has reached today's limit. Please try again tomorrow.", retryable: false)
            case "RATE_LIMITED":
                throw Failure(message: serverMessage ?? "You're sending messages very quickly. Please wait a minute and tap Retry.", retryable: false)
            case "TOO_LARGE":
                throw Failure(message: serverMessage ?? "This chat is too long. Please start a new chat.", retryable: false)
            default:
                let retryable = (json["retryable"] as? Bool) ?? true
                throw Failure(message: serverMessage ?? "Sorry, I couldn't answer just now. Please tap Retry.", retryable: retryable)
            }
        }
        let suggestions = ((json["suggestions"] as? [Any]) ?? [])
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .map { String($0.prefix(60)) }
        var away: [String: Int] = [:]
        if let a = json["away"] as? [String: Any] {
            for (k, v) in a.prefix(8) {
                guard let m = v as? [String: Any], let mi = (m["mi"] as? NSNumber)?.doubleValue, mi > 0 else { continue }
                away[String(k.prefix(60))] = Int(mi.rounded())
            }
        }
        let text = (json["message"] as? String) ?? message
        if let list = json["places"] as? [[String: Any]] {
            PlannerPlaceMemory.remember(list.prefix(40).compactMap { PlannerMapPlace(json: $0) }, forAnswer: text)
        }
        let articles = ((json["articles"] as? [[String: Any]]) ?? []).prefix(3).compactMap { PlannerArticleRef(json: $0) }
        return Answer(message: text, suggestions: Array(suggestions), away: away, articles: Array(articles))
    }
}

/// Text rules shared with the web planner (PlannerChat.tsx / tripFilters.ts).
enum PlannerText {
    /// 🕍 shows as a Star of David on iPhone: the chat never shows 🕍, ✡ or 🔯 (they become 🏛), same as the web.
    static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1F54D}\u{FE0F}", with: "\u{1F3DB}")
            .replacingOccurrences(of: "\u{1F54D}", with: "\u{1F3DB}")
            .replacingOccurrences(of: "\u{2721}\u{FE0F}", with: "\u{1F3DB}")
            .replacingOccurrences(of: "\u{2721}", with: "\u{1F3DB}")
            .replacingOccurrences(of: "\u{1F52F}", with: "\u{1F3DB}")
    }

    /// A day-by-day plan (web: isItineraryAnswer).
    static func isItinerary(_ content: String) -> Bool {
        let lines = sanitize(content).components(separatedBy: "\n")
        let day = #"^\s*(?:#{1,4}\s*|[-*]\s+|\d+\.\s+)?(?:\*\*|__)?\s*(?:\p{So}\x{FE0F}?\s*)?day\s*\d+\b"#
        let weekday = #"^\s*(?:#{1,4}\s*|[-*]\s+)?(?:\*\*|__)?\s*(?:\p{So}\x{FE0F}?\s*)?(?:erev\s+shabbos|motzei\s+shabbos|friday|saturday|sunday|monday|tuesday|wednesday|thursday|shabbos|shabbat)\b[^\n]{0,40}(?:\*\*|:|$)"#
        func test(_ pattern: String, _ line: String) -> Bool {
            line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if lines.contains(where: { test(day, $0) }) { return true }
        return lines.filter { test(weekday, $0) }.count >= 2
    }

    /// The latest day-by-day plan in the chat (sent so follow-ups adjust the same trip).
    static func latestItinerary(_ messages: [ChatMessage]) -> String {
        for m in messages.reversed() where m.isAssistant && isItinerary(m.content) {
            return String(m.content.prefix(6000))
        }
        return ""
    }

    /// The chat's current trip settings: the latest snapshot carried on its messages (web: filtersFromMessages,
    /// without the text inference for a typed first question).
    static func filters(from messages: [ChatMessage]) -> TripFilters {
        var f = TripFilters()
        for m in messages { if let x = m.filters, !x.isEmpty { f = x } }
        return f
    }
}
