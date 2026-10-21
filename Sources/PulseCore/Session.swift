import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable {
    case claude, codex, cursor
    public var label: String {
        switch self { case .claude: return "Claude Code"; case .codex: return "Codex"; case .cursor: return "Cursor" }
    }
}

public enum AgentState: String, Codable, Sendable {
    case running, waiting, ready, idle, unknown
    public var label: String {
        switch self {
        case .running: return "Working"
        case .waiting: return "Waiting"
        case .ready: return "Reply ready"
        case .idle: return "Idle"
        case .unknown: return "Status unavailable"
        }
    }
    public var needsAttention: Bool { self == .waiting || self == .ready }
}

public struct Session: Identifiable, Codable, Sendable, Equatable {
    public var id: String { "\(provider.rawValue):\(nativeID)" }
    public var provider: Provider
    public var nativeID: String
    public var title: String
    public var project: String
    public var updatedAt: Date
    public var state: AgentState
    public var detail: String
    public var terminalID: String?
    public var transcript: String?
    public var isSubagent: Bool
    public var lastUserMessage: String?
    public var lastUserMessageAt: Date?
    /// The latest turn was restored from history rather than run live in this session.
    public var replayedAt: Date?
    public var route: SessionRoute?
    public var entrypoint: String?

    public init(provider: Provider, nativeID: String, title: String, project: String, updatedAt: Date,
                state: AgentState, detail: String = "", terminalID: String? = nil,
                transcript: String? = nil, isSubagent: Bool = false, lastUserMessage: String? = nil, lastUserMessageAt: Date? = nil, replayedAt: Date? = nil, route: SessionRoute? = nil, entrypoint: String? = nil) {
        self.provider = provider; self.nativeID = nativeID; self.title = title; self.project = project
        self.updatedAt = updatedAt; self.state = state; self.detail = detail
        self.terminalID = terminalID; self.transcript = transcript; self.isSubagent = isSubagent
        self.replayedAt = replayedAt
        self.lastUserMessageAt = lastUserMessageAt
        self.lastUserMessage = lastUserMessage; self.route = route; self.entrypoint = entrypoint
    }
    public var projectName: String { URL(fileURLWithPath: project).lastPathComponent }
    public var hostLabel: String {
        switch provider {
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .claude:
            switch route?.kind {
            case .cursorClaude: return "Cursor · Claude"
            case .cursorTerminal: return "Cursor · Terminal"
            case .iTerm: return "iTerm · Claude"
            default: return "Claude · Host unknown"
            }
        }
    }
    /// Log discovery alone is not enough to offer navigation back to a Claude session.
    public var hasOpenDestination: Bool {
        guard provider == .claude else { return deepLink != nil }
        switch route?.kind {
        case .iTerm: return !(terminalID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        case .cursorClaude: return !(route?.workspace ?? project).isEmpty && deepLink != nil
        case .cursorTerminal:
            return !(route?.workspace ?? project).isEmpty && (route?.terminalPIDs ?? []).contains { $0 > 0 } && deepLink != nil
        case .unknown, nil: return false
        }
    }
    public var deepLink: URL? {
        var c = URLComponents()
        switch provider {
        case .codex: c.scheme = "codex"; c.host = "threads"; c.path = "/\(nativeID)"
        case .cursor:
            c.scheme = "cursor"; c.host = "local.pulse-router"; c.path = "/open"
            c.queryItems = [URLQueryItem(name: "id", value: nativeID), URLQueryItem(name: "folder", value: project)]
        case .claude:
            guard route?.kind == .cursorClaude || route?.kind == .cursorTerminal else { return nil }
            c.scheme = "cursor"; c.host = "local.pulse-router"; c.path = "/open"
            c.queryItems = [URLQueryItem(name: "id", value: nativeID),
                            URLQueryItem(name: "folder", value: route?.workspace ?? project),
                            URLQueryItem(name: "kind", value: route?.kind == .cursorTerminal ? "terminal" : "claude"),
                            URLQueryItem(name: "pids", value: (route?.terminalPIDs ?? []).map(String.init).joined(separator: ","))]
        }
        return c.url
    }
    /// Working order follows human messages, never tool activity or status changes.
    public static func sortedByLastUserMessage(_ sessions: [Session]) -> [Session] {
        sessions.sorted {
            let lhs = $0.lastUserMessageAt ?? .distantPast
            let rhs = $1.lastUserMessageAt ?? .distantPast
            return lhs == rhs ? $0.id < $1.id : lhs > rhs
        }
    }
    public static func sorted(_ sessions: [Session], pins: Set<String>) -> [Session] {
        sessions.sorted {
            if pins.contains($0.id) != pins.contains($1.id) { return pins.contains($0.id) }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }
}

public struct SourceHealth: Codable, Sendable, Equatable {
    public var provider: Provider
    public var count: Int
    public var message: String
    public var available: Bool
    public init(_ provider: Provider, count: Int, message: String, available: Bool) {
        self.provider = provider; self.count = count; self.message = message; self.available = available
    }
}

public struct ScanResult: Codable, Sendable {
    public var sessions: [Session]
    public var sources: [SourceHealth]
    public init(sessions: [Session], sources: [SourceHealth]) { self.sessions = sessions; self.sources = sources }
}

enum JSON {
    private static let fractionalDate: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter
    }()
    private static let plainDate = ISO8601DateFormatter()
    static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func object(_ text: String) -> [String: Any]? { object(Data(text.utf8)) }
    static func date(_ value: Any?) -> Date? {
        if let n = value as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue > 10_000_000_000 ? n.doubleValue / 1000 : n.doubleValue) }
        guard let text = value as? String else { return nil }
        return fractionalDate.date(from: text) ?? plainDate.date(from: text)
    }
    static func text(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let blocks = value as? [[String: Any]] { return blocks.compactMap { $0["text"] as? String }.joined(separator: " ") }
        return ""
    }
    static func title(_ text: String, fallback: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.isEmpty ? fallback : String(line.prefix(140))
    }
}
