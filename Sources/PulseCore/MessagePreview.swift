import Foundation

public enum MessagePreview {
    public static func clean(_ text: String) -> String? {
        var result = text
        for tag in ["environment_context", "user_instructions", "system-reminder", "permissions instructions"] {
            result = result.replacingOccurrences(of: "<\(tag)>[\\s\\S]*?</\(tag)>", with: "", options: .regularExpression)
        }
        // Codex wraps attachment metadata ahead of the user's actual request. Extract
        // before whitespace folding and truncation so a long file list cannot hide it.
        let filesHeader = #"\A\s*# Files mentioned by the user:"#
        var attached = false
        if result.range(of: filesHeader, options: .regularExpression) != nil {
            attached = true
            if let request = result.range(of: #"(?m)^## My request:[ \t]*"#, options: .regularExpression) {
                result = String(result[request.upperBound...])
            } else {
                // An attachment-only turn should not reuse the previous turn's query.
                return "[Attachment]"
            }
        }
        let imageTag = #"(?s)<image\b(?=[^>]*\bpath=)[^>]*>.*?</image>"#
        if result.range(of: imageTag, options: .regularExpression) != nil {
            attached = true
            result = result.replacingOccurrences(of: imageTag, with: "", options: .regularExpression)
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty && attached { return "[Attachment]" }
        guard !result.isEmpty, !result.hasPrefix("[Request interrupted by user"),
              !result.hasPrefix("The following is the Codex agent history added"),
              !result.hasPrefix("<turn_aborted>"), !result.hasPrefix("<subagent_notification>"),
              !result.hasPrefix("<task-notification>") else { return nil }
        return String(result.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(1600))
    }

    private static func content(_ value: Any?) -> String? {
        if let preview = clean(JSON.text(value)) { return preview }
        if let blocks = value as? [[String: Any]], blocks.contains(where: {
            ["image", "input_image", "image_url", "input_file", "file"].contains($0["type"] as? String ?? "")
        }) { return "[Attachment]" }
        return nil
    }

    public static func codexItem(_ item: [String: Any]) -> String? {
        let type = (item["type"] as? String ?? "").lowercased()
        guard type == "usermessage" || (type == "message" && item["role"] as? String == "user") else { return nil }
        return content(item["content"])
    }

    public static func codex(_ events: [[String: Any]]) -> String? {
        for event in events.reversed() {
            let payload = event["payload"] as? [String: Any] ?? [:]
            if event["type"] as? String == "event_msg" {
                if payload["type"] as? String == "user_message", let text = content(payload["message"]) { return text }
                if let item = payload["item"] as? [String: Any], let text = codexItem(item) { return text }
            } else if event["type"] as? String == "response_item", let text = codexItem(payload) { return text }
        }
        return nil
    }

    static func lastUserMessageDate(_ events: [[String: Any]], provider: Provider) -> Date? {
        var latest: Date?
        var replayedTurnDate: Date?
        for event in events {
            let payload = event["payload"] as? [String: Any] ?? [:]
            if provider == .codex, event["type"] as? String == "event_msg",
               ["task_started", "turn_started"].contains(payload["type"] as? String ?? "") {
                // Replayed logs keep original turn times inside their payloads.
                if let started = JSON.date(payload["started_at"]), let recorded = JSON.date(event["timestamp"]),
                   recorded.timeIntervalSince(started) > 60 { replayedTurnDate = started }
                else { replayedTurnDate = nil }
            }
            let preview: String?
            switch provider {
            case .codex: preview = codex([event])
            case .claude: preview = claude([event])
            case .cursor: preview = nil
            }
            if preview != nil, let date = replayedTurnDate ?? JSON.date(event["timestamp"]) { latest = date }
        }
        return latest
    }

    public static func claude(_ events: [[String: Any]]) -> String? {
        for event in events.reversed() {
            guard event["type"] as? String == "user", event["isMeta"] as? Bool != true,
                  event["isCompactSummary"] as? Bool != true, event["toolUseResult"] == nil,
                  let message = event["message"] as? [String: Any] else { continue }
            if let text = content(message["content"]) { return text }
        }
        return nil
    }
}
