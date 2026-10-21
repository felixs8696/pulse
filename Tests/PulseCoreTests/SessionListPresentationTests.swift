import Foundation
import Testing
@testable import PulseCore

struct SessionListPresentationTests {
    private func session(_ id: String, title: String? = nil) -> Session {
        Session(provider: .codex, nativeID: id, title: title ?? id, project: "/tmp",
                updatedAt: Date(timeIntervalSince1970: 100), state: .running)
    }

    @Test func completionFadesInItsOriginalSlotBeforeReleasingSpace() {
        let a = session("a"), b = session("b"), c = session("c")
        var list = SessionListPresentation()
        list.reset(to: [a, b, c])
        list.stage([c, a])
        #expect(list.rows == [a, b, c])
        #expect(list.exitingIDs == [b.id])
        list.finishRemovals()
        #expect(list.rows == [c, a])
        #expect(list.exitingIDs.isEmpty)
    }

    @Test func updatesDuringFadeCommitOnlyTheLatestSnapshotWithoutChangingOldGeometry() {
        let a = session("a"), b = session("b"), c = session("c")
        let revised = session("a", title: "A much longer title that would change the row height")
        var list = SessionListPresentation()
        list.reset(to: [a, b])
        list.stage([a])
        list.stage([c, revised])
        #expect(list.rows == [a, b])
        #expect(list.exitingIDs == [b.id])
        list.finishRemovals()
        #expect(list.rows == [c, revised])
    }

    @Test func resumingDuringFadeCancelsThePendingDeparture() {
        let a = session("a"), b = session("b")
        var list = SessionListPresentation()
        list.reset(to: [a, b])
        list.stage([b])
        #expect(list.exitingIDs == [a.id])
        list.stage([b, a])
        #expect(list.exitingIDs.isEmpty)
        #expect(list.rows == [b, a])
        list.finishRemovals()
        #expect(list.rows == [b, a])
    }

    @Test func lastRowLeavesBeforeEmptyStateAndReducedMotionCanSkipStaging() {
        let a = session("a")
        var list = SessionListPresentation()
        list.reset(to: [a])
        list.stage([])
        #expect(list.rows == [a])
        #expect(list.exitingIDs == [a.id])
        list.finishRemovals()
        #expect(list.rows.isEmpty)
        list.reset(to: [a])
        list.stage([])
        list.reset(to: [])
        #expect(list.rows.isEmpty && list.exitingIDs.isEmpty)
    }
}
