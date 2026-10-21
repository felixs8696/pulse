import Foundation
import Testing
import CSQLite
@testable import PulseCore

struct RoutingTests {
    @Test func cursorAgentsUseThePackagedRouterOnAFreshInstall() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("cursor-router/package.json"))
        let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let publisher = try #require(manifest["publisher"] as? String)
        let name = try #require(manifest["name"] as? String)
        let session = Session(provider: .cursor, nativeID: "chat-123", title: "Chat", project: "/tmp/project",
                              updatedAt: Date(), state: .ready)
        let link = try #require(session.deepLink)
        #expect(link.host == "\(publisher).\(name)")
        let query = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first(where: { $0.name == "id" })?.value == "chat-123")
        #expect(query.first(where: { $0.name == "folder" })?.value == "/tmp/project")
    }
    @Test func inheritedITermIDCannotOverrideCursorHost() {
        let reports: [[String: Any]] = [
            ["iterm_session_id": "inherited-pane", "state": "ready"],
            ["host_bundle_id": "com.todesktop.230313mzl4w4u92", "cwd": "/tmp/agent-cwd"]
        ]
        let route = SessionRoute.claude(reports: reports, entrypoint: "claude-vscode", cursorWorkspace: "/tmp/multi/workspace.json")
        #expect(route.kind == .cursorClaude)
        #expect(route.workspace == "/tmp/multi/workspace.json")
        let session = Session(provider: .claude, nativeID: "exact-id", title: "Example session", project: "/tmp/other", updatedAt: Date(), state: .ready, terminalID: "inherited-pane", route: route)
        let link = URLComponents(url: session.deepLink!, resolvingAgainstBaseURL: false)!
        #expect(link.host == "local.pulse-router")
        #expect(link.queryItems?.first(where: { $0.name == "id" })?.value == "exact-id")
        #expect(link.queryItems?.first(where: { $0.name == "folder" })?.value == "/tmp/multi/workspace.json")
        #expect(link.queryItems?.first(where: { $0.name == "kind" })?.value == "claude")
        #expect(session.hostLabel == "Cursor · Claude")
    }
    @Test func latestExplicitHostWinsOverOldSavedTab() {
        let reports: [[String: Any]] = [["host_bundle_id": "com.googlecode.iterm2", "iterm_session_id": "current-pane"], ["host_bundle_id": "com.todesktop.230313mzl4w4u92"]]
        #expect(SessionRoute.claude(reports: reports, entrypoint: "cli", cursorWorkspace: "/tmp/old").kind == .iTerm)
        #expect(SessionRoute.claude(reports: [], entrypoint: nil, cursorWorkspace: nil).kind == .unknown)
    }
    @Test func cursorTerminalKeepsItsExactProcessAncestry() {
        let reports: [[String: Any]] = [["host_bundle_id": "com.todesktop.230313mzl4w4u92", "host_surface": "terminal", "terminal_ancestor_pids": [23, 42]]]
        let route = SessionRoute.claude(reports: reports, entrypoint: "cli", cursorWorkspace: nil)
        #expect(route.kind == .cursorTerminal)
        #expect(route.terminalPIDs == [23, 42])
    }
    @Test func readsExactSessionFromMultiFolderWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage/fixture")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{\"workspace\":\"file:///tmp/Workspaces/saved/workspace.json\"}".utf8).write(to: folder.appendingPathComponent("workspace.json"))
        var db: OpaquePointer?
        sqlite3_open(folder.appendingPathComponent("state.vscdb").path, &db)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TABLE ItemTable(key TEXT,value TEXT); INSERT INTO ItemTable VALUES ('Anthropic.claude-code','{\"panelTabSessions\":[{\"sessionId\":\"session-fork\"}]}');", nil, nil, nil) == SQLITE_OK)
        #expect(CursorClaudeWorkspaces.read(home: root)["session-fork"] == "/tmp/Workspaces/saved/workspace.json")
    }
}
