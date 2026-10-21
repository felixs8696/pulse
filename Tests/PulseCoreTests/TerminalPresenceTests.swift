import Foundation
import Testing
@testable import PulseCore

struct TerminalPresenceTests {
    private func session(_ route: SessionRoute.Kind = .iTerm) -> Session {
        Session(provider: .claude, nativeID: "one", title: "Terminal", project: "/tmp",
                updatedAt: Date(), state: .ready, terminalID: "w0t1p2:live-pane", route: SessionRoute(route))
    }
    @Test func closedPanesDisappearRegardlessOfStateOrAge() {
        for state in [AgentState.ready, .waiting, .running, .unknown, .idle] {
            var value = session(); value.state = state
            #expect(TerminalPresence.isVisible(value, openITermPanes: ["live-pane"]))
            #expect(!TerminalPresence.isVisible(value, openITermPanes: ["other-pane"]))
            #expect(!TerminalPresence.isVisible(value, openITermPanes: []))
        }
    }
    @Test func failedInventoryIsNotEvidenceThatEveryPaneClosed() {
        #expect(TerminalPresence.isVisible(session(), openITermPanes: nil))
        var noPane = session(); noPane.terminalID = nil
        #expect(!TerminalPresence.isVisible(noPane, openITermPanes: []))
    }
    @Test func iTermInventoryCannotHideCursorSessionsOrUnidentifiedHosts() {
        for route in [SessionRoute.Kind.cursorClaude, .cursorTerminal, .unknown] {
            #expect(TerminalPresence.isVisible(session(route), openITermPanes: []))
        }
        #expect(TerminalPresence.paneID("plain-id") == "plain-id")
    }
}
