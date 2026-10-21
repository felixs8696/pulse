import Foundation
import Testing
@testable import PulseCore

struct SessionDestinationTests {
    private func claude(_ route: SessionRoute? = nil, terminal: String? = nil) -> Session {
        Session(provider: .claude, nativeID: "one", title: "Agent", project: "/tmp/project",
                updatedAt: Date(), state: .ready, terminalID: terminal, route: route)
    }
    @Test func unknownClaudeHostsStayHiddenEvenWithInheritedTerminalIDs() {
        #expect(!claude().hasOpenDestination)
        #expect(!claude(SessionRoute(.unknown), terminal: "stale-pane").hasOpenDestination)
        for terminal: String? in [nil, "", "   "] {
            #expect(!claude(SessionRoute(.iTerm), terminal: terminal).hasOpenDestination)
        }
        #expect(claude(SessionRoute(.iTerm), terminal: "live-pane").hasOpenDestination)
    }
    @Test func cursorNavigationRequiresEvidenceForTheActualSurface() {
        #expect(claude(SessionRoute(.cursorClaude)).hasOpenDestination)
        #expect(!claude(SessionRoute(.cursorTerminal)).hasOpenDestination)
        #expect(!claude(SessionRoute(.cursorTerminal, terminalPIDs: [-1, 0])).hasOpenDestination)
        #expect(claude(SessionRoute(.cursorTerminal, terminalPIDs: [42])).hasOpenDestination)
        var missingWorkspace = claude(SessionRoute(.cursorClaude)); missingWorkspace.project = ""
        #expect(!missingWorkspace.hasOpenDestination)
        missingWorkspace.route?.workspace = "/tmp/exact.code-workspace"
        #expect(missingWorkspace.hasOpenDestination)
    }
    @Test func knownChatAppsAndNewlyIdentifiedRoutesRemainAccessible() {
        for provider in [Provider.codex, .cursor] {
            var session = claude(); session.provider = provider
            #expect(session.hasOpenDestination)
        }
        var unknown = claude()
        #expect(!unknown.hasOpenDestination)
        unknown.route = SessionRoute(.cursorClaude, workspace: "/tmp/project")
        #expect(unknown.hasOpenDestination)
    }
}
