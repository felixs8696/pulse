import Foundation

struct TranscriptSlice {
    var head: [[String: Any]]
    var tail: [[String: Any]]
    init(path: String) {
        guard let file = FileHandle(forReadingAtPath: path) else { head = []; tail = []; return }
        defer { try? file.close() }
        let size = (try? file.seekToEnd()) ?? 0
        try? file.seek(toOffset: 0)
        let first = (try? file.read(upToCount: 65_536)) ?? Data()
        head = Self.parse(first, dropFirst: false)
        if size > 1_048_576 {
            try? file.seek(toOffset: size - 1_048_576)
            tail = Self.parse((try? file.readToEnd()) ?? Data(), dropFirst: true)
        } else {
            try? file.seek(toOffset: 0)
            tail = Self.parse((try? file.readToEnd()) ?? Data(), dropFirst: false)
        }
    }
    /// Search backwards when a busy turn has pushed its user message out of the tail.
    /// On subsequent scans only inspect appended bytes, retaining the cached message date.
    static func lastUserMessageDate(path: String, provider: Provider, sinceOffset: Int = 0) -> Date? {
        guard let file = FileHandle(forReadingAtPath: path), let size = try? file.seekToEnd() else { return nil }
        defer { try? file.close() }
        // A first scan must not walk gigabytes of old tool output to find one date.
        // Recent history metadata and later appended user messages fill any gap.
        let lowerBound = max(UInt64(max(0, sinceOffset - 65_536)), size > 8_388_608 ? size - 8_388_608 : 0)
        var end = size
        var remainder = Data()
        while end > lowerBound {
            let start = max(lowerBound, end > 262_144 ? end - 262_144 : 0)
            guard (try? file.seek(toOffset: start)) != nil,
                  var data = try? file.read(upToCount: Int(end - start)) else { return nil }
            data.append(remainder)
            if start > 0 {
                if let newline = data.firstIndex(of: 10) {
                    remainder = Data(data[..<newline])
                    data = Data(data[data.index(after: newline)...])
                } else { remainder = data; data = Data() }
            }
            if let date = MessagePreview.lastUserMessageDate(parse(data, dropFirst: false), provider: provider) { return date }
            end = start
        }
        return nil
    }

    static func parse(_ data: Data, dropFirst: Bool) -> [[String: Any]] {
        let lines = data.split(separator: 10, omittingEmptySubsequences: false)
        return lines.dropFirst(dropFirst ? 1 : 0).compactMap { line in
            let prefix = String(decoding: line.prefix(240), as: UTF8.self)
            if prefix.contains("\"type\":\"response_item\"") || prefix.contains("\"type\": \"response_item\"") {
                if !prefix.contains("\"role\":\"user\"") && !prefix.contains("\"role\": \"user\"") { return nil }
            }
            for type in ["api-request-blob", "api-request", "token_usage_record"] {
                if prefix.contains("\"type\":\"\(type)\"") || prefix.contains("\"type\": \"\(type)\"") { return nil }
            }
            return JSON.object(Data(line))
        }
    }
}

public enum StatusParser {
    /// A history replay writes old turns now but preserves their original start time.
    /// The next genuine start clears this provenance, even in the same rollout file.
    static func codexReplayDate(_ events: [[String: Any]]) -> Date? {
        guard let start = events.last(where: {
            let payload = $0["payload"] as? [String: Any] ?? [:]
            return $0["type"] as? String == "event_msg" && ["task_started", "turn_started"].contains(payload["type"] as? String ?? "")
        }), let payload = start["payload"] as? [String: Any],
              let original = JSON.date(payload["started_at"]), let recorded = JSON.date(start["timestamp"]),
              recorded.timeIntervalSince(original) > 60 else { return nil }
        return recorded
    }

    /// Uses lifecycle events rather than filesystem mtimes or token events.
    public static func codex(_ events: [[String: Any]], now: Date = Date()) -> (AgentState, Date?, String) {
        var state: AgentState = .unknown
        var activity: Date?
        var detail = "No lifecycle event available"
        var replayedTurnDate: Date?
        for event in events {
            let payload = event["payload"] as? [String: Any] ?? [:]
            let type = payload["type"] as? String ?? ""
            guard event["type"] as? String == "event_msg" else { continue }
            let recorded = JSON.date(event["timestamp"])
            if ["task_started", "turn_started"].contains(type) {
                if let started = JSON.date(payload["started_at"]), let recorded,
                   recorded.timeIntervalSince(started) > 60 { replayedTurnDate = started }
                else { replayedTurnDate = nil }
            }
            let date = JSON.date(payload["completed_at"]) ?? replayedTurnDate ?? recorded
            switch type {
            case "task_started", "turn_started", "user_message":
                state = .running; activity = date; detail = "Turn in progress"
            case "task_complete", "task_completed", "turn_completed":
                state = .ready; activity = date; detail = "Finished its latest turn"
            case "turn_aborted", "task_failed", "error":
                state = .waiting; activity = date; detail = "Turn stopped; open to review"
            case "approval_request", "request_user_input", "exec_approval_request", "apply_patch_approval_request":
                state = .waiting; activity = date; detail = "Waiting for your input or approval"
            case "agent_message":
                activity = date
            case "item_started", "item_completed":
                let item = payload["item"] as? [String: Any] ?? [:]
                let itemType = (item["type"] as? String ?? "").lowercased()
                if state != .waiting { state = .running; detail = "Turn in progress" }
                if itemType.contains("approval") || itemType == "requestuserinput" {
                    state = type == "item_started" ? .waiting : .running
                    detail = state == .waiting ? "Waiting for your input or approval" : "Turn in progress"
                }
                // A final_answer item can be an async question within a still-running turn.
                // Only task_complete/turn_completed establishes that the turn stopped.
                activity = date
            default: break
            }
        }
        if state == .running, let activity, now.timeIntervalSince(activity) > 21_600 {
            state = .unknown; detail = "No recent lifecycle event; open to check"
        }
        return (state, activity, detail)
    }

    public static func claude(_ events: [[String: Any]], now: Date = Date()) -> (AgentState, Date?, String) {
        var state: AgentState = .unknown
        var activity: Date?
        var detail = "Enable hooks for precise approval status"
        for event in events {
            let type = event["type"] as? String ?? ""
            // api-request-blob carries large historical copies of messages, not new activity.
            guard ["user", "assistant", "system", "progress", "attachment"].contains(type) else { continue }
            let date = JSON.date(event["timestamp"])
            if let date { activity = date }
            let message = event["message"] as? [String: Any] ?? [:]
            if type == "user" { state = .running; detail = "Turn in progress" }
            if type == "assistant" {
                let blocks = message["content"] as? [[String: Any]] ?? []
                let tools = blocks.filter { $0["type"] as? String == "tool_use" }
                if tools.contains(where: { ["AskUserQuestion", "ExitPlanMode"].contains($0["name"] as? String ?? "") }) {
                    state = .waiting; detail = "Waiting for your input"
                } else if !tools.isEmpty {
                    state = .running; detail = "Using tools; approval status requires hooks"
                } else if message["stop_reason"] as? String == "end_turn" {
                    state = .ready; detail = "Finished its latest turn"
                }
            }
            if type == "system", event["subtype"] as? String == "turn_duration" {
                state = .ready; detail = "Finished its latest turn"
            }
        }
        if state == .running, let activity, now.timeIntervalSince(activity) > 21_600 {
            state = .unknown; detail = "No recent lifecycle event; open to check"
        }
        return (state, activity, detail)
    }
}
