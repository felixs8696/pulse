import Foundation

/// Stores only explicit per-session choices. Missing entries keep their original hashed pitch.
public struct SessionTones: Codable, Sendable {
    public private(set) var overrides: [String: Int] = [:]
    public init() {}
    public func value(for sessionID: String) -> Int {
        overrides[sessionID].map { min(100, max(1, $0)) } ?? SessionChime.tone(for: sessionID)
    }
    public mutating func set(_ value: Int?, for sessionID: String) {
        overrides[sessionID] = value.map { min(100, max(1, $0)) }
    }
}
