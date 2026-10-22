import Foundation
import Testing
@testable import PulseCore

struct ClaudeDesktopTests {
    let desktopID = "local_00000000-0000-4000-8000-000000000001"
    let cliID = "00000000-0000-4000-8000-000000000002"

    @Test func desktopLinkUsesDesktopIDAndNeverCreatesANewSession() throws {
        let route = SessionRoute.claude(reports: [], entrypoint: nil, cursorWorkspace: nil, desktopSessionID: desktopID)
        let session = Session(provider: .claude, nativeID: cliID, title: "Example", project: "/tmp", updatedAt: Date(), state: .ready, route: route)
        #expect(session.hasOpenDestination)
        #expect(session.hostLabel == "Claude Desktop · Code")
        let link = try #require(session.deepLink)
        #expect(link.absoluteString == "claude://code/continue?session=\(desktopID)")
    }
    @Test func desktopHostWithoutMappingCannotOpenWrongChat() {
        let route = SessionRoute.claude(reports: [["host_bundle_id": "com.anthropic.claudefordesktop", "iterm_session_id": "inherited"]], entrypoint: nil, cursorWorkspace: nil)
        let session = Session(provider: .claude, nativeID: cliID, title: "Example", project: "/tmp", updatedAt: Date(), state: .ready, terminalID: "inherited", route: route)
        #expect(route.kind == .claudeDesktop)
        #expect(!session.hasOpenDestination)
        #expect(session.deepLink == nil)
    }
    @Test func explicitLiveHostBeatsOldDesktopMapping() {
        let route = SessionRoute.claude(reports: [["host_bundle_id": "com.googlecode.iterm2"]], entrypoint: nil, cursorWorkspace: nil, desktopSessionID: desktopID)
        #expect(route.kind == .iTerm)
    }
    @Test func malformedIDsCannotBecomeNavigationLinks() {
        for id in ["last", "local_../../new", "local_valid?session=last", ""] {
            let session = Session(provider: .claude, nativeID: cliID, title: "Example", project: "/tmp", updatedAt: Date(), state: .ready,
                                  route: SessionRoute(.claudeDesktop, desktopSessionID: id))
            #expect(!session.hasOpenDestination)
        }
    }
    @Test func scannerMapsDesktopTranscriptsAndExcludesArchivedSessions() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let metadata = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions/account/org")
        let project = home.appendingPathComponent(".claude/projects/example")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let now = Date()
        let message: [String: Any] = ["type": "user", "cwd": "/tmp/project", "timestamp": ISO8601DateFormatter().string(from: now), "message": ["role": "user", "content": "Check the tests"]]
        try JSONSerialization.data(withJSONObject: message).write(to: project.appendingPathComponent(cliID + ".jsonl"))
        let path = metadata.appendingPathComponent(desktopID + ".json")
        func write(archived: Bool) throws {
            try JSONSerialization.data(withJSONObject: ["sessionId": desktopID, "cliSessionId": cliID, "isArchived": archived, "lastActivityAt": now.timeIntervalSince1970 * 1000]).write(to: path)
        }
        try write(archived: false)
        let scanner = SessionScanner(home: home)
        let result = scanner.scan(provider: .claude, now: now)
        let session = try #require(result.sessions.first)
        #expect(session.route?.desktopSessionID == desktopID)
        #expect(session.hasOpenDestination)
        #expect(session.lastUserMessage == "Check the tests")
        try write(archived: true)
        #expect(scanner.scan(provider: .claude, now: now).sessions.isEmpty)
    }
}
