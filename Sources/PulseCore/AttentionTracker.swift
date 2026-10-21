import Foundation

/// Detects newly ready replies independently of list filters and acknowledgments.
public struct AttentionTracker: Sendable {
    private struct Event: Equatable, Sendable {
        var state: AgentState
        var date: Date
    }
    private var observed: [String: Event] = [:]
    private var announced: [String: Event] = [:]
    private var initialized: Set<Provider> = []
    private let startedAt: Date

    public init(startedAt: Date = Date()) { self.startedAt = startedAt }

    public mutating func update(_ sessions: [Session], availableProviders: Set<Provider>) -> [String] {
        var alerts: [String] = []
        for session in sessions where !session.isSubagent && availableProviders.contains(session.provider) {
            let event = Event(state: session.state, date: session.updatedAt)
            let previous = observed[session.id]
            observed[session.id] = event
            guard session.state == .ready, session.replayedAt == nil else { continue }
            // Keep existing replies silent, but don't lose a genuine completion
            // that arrived while the source's first scan was still in progress.
            guard initialized.contains(session.provider) else {
                announced[session.id] = event
                if event.date > startedAt { alerts.append(session.id) }
                continue
            }
            guard announced[session.id] != event else { continue }
            let changed = previous.map { $0.state != event.state || event.date > $0.date } ?? (event.date > startedAt)
            guard changed else { continue }
            announced[session.id] = event
            alerts.append(session.id)
        }
        initialized.formUnion(availableProviders)
        return alerts
    }
}
