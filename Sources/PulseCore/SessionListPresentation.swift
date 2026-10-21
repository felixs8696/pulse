import Foundation

/// Retains departing rows in their original slots until their fade has finished.
/// The latest snapshot is applied atomically when the reserved space is released.
public struct SessionListPresentation: Sendable {
    public private(set) var rows: [Session] = []
    public private(set) var exitingIDs: Set<String> = []
    private var target: [Session] = []

    public init() {}

    public mutating func reset(to sessions: [Session]) {
        rows = sessions
        target = sessions
        exitingIDs = []
    }

    public mutating func stage(_ sessions: [Session]) {
        target = sessions
        let retained = Set(sessions.map(\.id))
        exitingIDs = Set(rows.map(\.id)).subtracting(retained)
        // With no departure, ordinary reordering can animate immediately.
        // During a fade, freeze the complete old geometry, including text wrapping.
        if exitingIDs.isEmpty { rows = sessions }
    }

    public mutating func finishRemovals() {
        rows = target
        exitingIDs = []
    }
}
