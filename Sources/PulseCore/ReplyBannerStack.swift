import Foundation

/// One visible card per conversation, shared by every display.
public struct ReplyBannerStack: Sendable {
    public private(set) var sessions: [Session] = []
    public init() {}

    @discardableResult public mutating func upsert(_ replies: [Session]) -> Set<String> {
        var changed: Set<String> = []
        for reply in replies {
            if let index = sessions.firstIndex(where: { $0.id == reply.id }) {
                guard reply.updatedAt >= sessions[index].updatedAt, reply != sessions[index] else { continue }
                sessions[index] = reply
            } else {
                sessions.insert(reply, at: 0)
            }
            changed.insert(reply.id)
        }
        return changed
    }
    public mutating func remove(_ id: String) { sessions.removeAll { $0.id == id } }
    public mutating func removeAll() { sessions.removeAll() }

    /// A human message sent after this reply means its banner has been handled.
    /// Status updates, changed previews, and late-loaded history aren't evidence.
    public func answeredIDs(in latest: [Session]) -> Set<String> {
        let messages = Dictionary(latest.filter { !$0.isSubagent }.map { ($0.id, $0.lastUserMessageAt) },
                                  uniquingKeysWith: { first, second in
            [first, second].compactMap { $0 }.max()
        })
        return Set(sessions.compactMap { reply in
            guard let sentAt = messages[reply.id] ?? nil,
                  sentAt > max(reply.updatedAt, reply.lastUserMessageAt ?? .distantPast) else { return nil }
            return reply.id
        })
    }
}
