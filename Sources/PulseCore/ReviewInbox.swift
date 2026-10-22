import Foundation

/// An outstanding reply stays outstanding until another turn starts or the user handles it.
/// Opening a chat through Pulse acknowledges its current reply. New replies become unread.
public struct ReviewInbox: Codable, Sendable {
    private struct Event: Codable, Equatable, Sendable {
        let state: AgentState
        let date: Date
        init(_ session: Session) { state = session.state; date = session.updatedAt }
    }
    private var handled: [String: Event] = [:]
    public init() {}

    public func needsReview(_ session: Session) -> Bool {
        !session.isSubagent && session.replayedAt == nil && session.state.needsAttention && !isRead(session)
    }
    public func isRead(_ session: Session) -> Bool {
        !session.isSubagent && (!session.state.needsAttention || session.replayedAt != nil
            || (session.lastUserMessageAt.map { $0 > session.updatedAt } ?? false)
            || handled[session.id] == Event(session))
    }
    public func sorted(_ sessions: [Session]) -> [Session] {
        sessions.sorted {
            if isRead($0) != isRead($1) { return !isRead($0) }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }
    public mutating func markHandled(_ session: Session) {
        guard !session.isSubagent, session.state.needsAttention else { return }
        handled[session.id] = Event(session)
    }
    public mutating func markUnread(_ session: Session) {
        // A stale row cannot undo acknowledgment of a newer reply.
        guard isRead(session) else { return }
        handled.removeValue(forKey: session.id)
    }
}

public enum SessionScope {
    /// Calendar days use the Mac's local time zone, including daylight-saving changes.
    public static func isToday(_ session: Session, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.isDate(session.updatedAt, inSameDayAs: now)
    }
    public static func needsReviewToday(_ session: Session, inbox: ReviewInbox,
                                       now: Date = Date(), calendar: Calendar = .current) -> Bool {
        isToday(session, now: now, calendar: calendar) && inbox.needsReview(session)
    }
    public static func isOlder(_ session: Session, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        !session.isSubagent && session.state != .running && session.updatedAt < calendar.startOfDay(for: now)
    }
    public static func matching(_ sessions: [Session], provider: Provider?, query: String) -> [Session] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessions.filter { session in
            !session.isSubagent
            && (provider == nil || session.provider == provider ||
                (provider == .cursor && (session.route?.kind == .cursorClaude || session.route?.kind == .cursorTerminal)))
            && (query.isEmpty || "\(session.title) \(session.project) \(session.provider.label) \(session.hostLabel) \(session.lastUserMessage ?? "")".localizedCaseInsensitiveContains(query))
        }
    }
}
