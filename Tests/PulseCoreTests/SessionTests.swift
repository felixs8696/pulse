import Foundation
import Testing
import CSQLite
@testable import PulseCore

struct SessionTests {
    private let now = Date(timeIntervalSince1970: 1_792_539_000)
    private func event(_ type: String, _ offset: Double = 0) -> [String: Any] {
        ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: now.addingTimeInterval(offset)), "payload": ["type": type]]
    }
    @Test func testCompletionOverridesRunningAndTokenEventsDoNotChangeRecency() {
        let events = [event("task_started"), event("task_complete", 10), event("token_count", 20)]
        let status = StatusParser.codex(events, now: now.addingTimeInterval(30))
        expectEqual(status.0, .ready)
        expectEqual(status.1, now.addingTimeInterval(10))
    }
    @Test func testApprovalResumesOnNewTurn() {
        expectEqual(StatusParser.codex([event("task_started"), event("approval_request", 5)], now: now).0, .waiting)
        expectEqual(StatusParser.codex([event("approval_request"), event("task_started", 5)], now: now).0, .running)
    }
    @Test func testInterruptedAndStaleTurnsAreNotReportedAsWorkingForever() {
        expectEqual(StatusParser.codex([event("task_started"), event("turn_aborted", 5)], now: now).0, .waiting)
        expectEqual(StatusParser.codex([event("task_started")], now: now.addingTimeInterval(25_000)).0, .unknown)
    }
    @Test func testAsyncFinalAnswerDoesNotEndAnActiveCodexTurn() {
        var item = event("item_completed", 5)
        item["payload"] = ["type": "item_completed", "item": ["type": "AgentMessage", "phase": "final_answer"]]
        expectEqual(StatusParser.codex([event("task_started"), item], now: now).0, .running)
    }
    @Test func testClaudeToolResultIsNotMistakenForTurnCompletion() {
        let events: [[String: Any]] = [
            ["type": "assistant", "timestamp": ISO8601DateFormatter().string(from: now), "message": ["content": [["type": "tool_use", "name": "Bash"]], "stop_reason": "tool_use"]],
            ["type": "user", "timestamp": ISO8601DateFormatter().string(from: now), "message": ["content": [["type": "tool_result"]]]]
        ]
        expectEqual(StatusParser.claude(events, now: now).0, .running)
    }
    @Test func testClaudeQuestionAndFinish() {
        let question: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "name": "AskUserQuestion"]]]]
        expectEqual(StatusParser.claude([question], now: now).0, .waiting)
        expectEqual(StatusParser.claude([question, ["type": "system", "subtype": "turn_duration"]], now: now).0, .ready)
    }
    @Test func testAPIBlobDoesNotReplayOldMessages() {
        let old: [String: Any] = ["type": "api-request-blob", "message": ["role": "assistant", "stop_reason": "end_turn"]]
        expectEqual(StatusParser.claude([old], now: now).0, .unknown)
    }
    @Test func testPinsSortFirstWithoutChangingActivityTime() {
        let older = Session(provider: .claude, nativeID: "old", title: "Old", project: "", updatedAt: now, state: .ready)
        let newer = Session(provider: .codex, nativeID: "new", title: "New", project: "", updatedAt: now.addingTimeInterval(60), state: .running)
        let sorted = Session.sorted([newer, older], pins: [older.id])
        expectEqual(sorted.map(\.nativeID), ["old", "new"])
        expectEqual(sorted[0].updatedAt, now)
    }
    @Test func testDeepLinksTargetSpecificConversation() {
        let s = Session(provider: .codex, nativeID: "abc-123", title: "", project: "", updatedAt: now, state: .idle)
        expectEqual(s.deepLink?.absoluteString, "codex://threads/abc-123")
        var cursor = s; cursor.provider = .cursor; cursor.nativeID = "a&b c"
        let components = URLComponents(url: cursor.deepLink!, resolvingAgainstBaseURL: false)!
        expectEqual(components.path, "/open")
        expectEqual(components.queryItems?.first?.value, "a&b c")
    }
    @Test func testTailReaderDropsPartialJSONAndSurvivesTruncatedWrite() {
        let data = Data("partial\n{\"type\":\"good\"}\n{\"type\":\"truncated".utf8)
        expectEqual(TranscriptSlice.parse(data, dropFirst: true).count, 1)
    }
    @Test func testScannerReadsFixtureDatabasesWithoutWritingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let log = root.appendingPathComponent("log.jsonl")
        var prompt = event("user_message", -60)
        prompt["payload"] = ["type": "user_message", "message": "Fix this"]
        var data = try JSONSerialization.data(withJSONObject: prompt)
        data.append(10)
        data.append(try JSONSerialization.data(withJSONObject: event("task_complete")))
        try data.write(to: log)
        let database = root.appendingPathComponent(".codex/state_5.sqlite")
        var handle: OpaquePointer?
        sqlite3_open(database.path, &handle)
        let sql = "CREATE TABLE threads(id TEXT,title TEXT,cwd TEXT,updated_at INTEGER,rollout_path TEXT,source TEXT,archived INTEGER); INSERT INTO threads VALUES ('one','Fixture','/tmp',1792539000,'\(log.path)','vscode',0); INSERT INTO threads VALUES ('archived','Hidden','/tmp',1792539000,'','vscode',1); INSERT INTO threads VALUES ('guardian','Guardian review','/tmp',1792539000,'','{\"subagent\":{\"other\":\"guardian\"}}',0);"
        expectEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        let before = try Data(contentsOf: database)
        let result = SessionScanner(home: root).scan()
        expectEqual(result.sessions.count, 1)
        expectEqual(result.sessions[0].title, "Fixture")
        expectEqual(result.sessions[0].state, .ready)
        #expect(result.sessions[0].lastUserMessageAt == now.addingTimeInterval(-60))
        expectEqual(result.sources.filter(\.available).count, 1)
        expectEqual(try Data(contentsOf: database), before)
    }
    @Test func testReadDatabaseRefusesToCreateMissingFile() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        expectThrows(try ReadDatabase(path))
        expectFalse(FileManager.default.fileExists(atPath: path))
    }
    @Test func testClaudeHooksOverrideInferenceWithoutHeartbeatReordering() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(".claude/projects/project")
        let reports = root.appendingPathComponent(".local/share/pulse/events")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
        let time = Date()
        let formatter = ISO8601DateFormatter()
        let transcript: [String: Any] = ["type": "user", "timestamp": formatter.string(from: time), "cwd": "/tmp/old", "message": ["role": "user", "content": "Fix the search bug"]]
        try JSONSerialization.data(withJSONObject: transcript).write(to: folder.appendingPathComponent("fixture.jsonl"))
        let status: [String: Any] = ["session_id": "fixture", "state": "waiting", "updated_at": formatter.string(from: time.addingTimeInterval(100)), "state_since": formatter.string(from: time.addingTimeInterval(2)), "cwd": "/tmp/current", "iterm_session_id": "w1t2p0:ABC"]
        try JSONSerialization.data(withJSONObject: status).write(to: reports.appendingPathComponent("fixture.json"))
        let scanner = SessionScanner(home: root)
        let result = try #require(scanner.scan().sessions.first)
        expectEqual(result.state, .waiting)
        expectEqual(result.project, "/tmp/current")
        expectEqual(result.terminalID, "w1t2p0:ABC")
        #expect(abs(result.updatedAt.timeIntervalSince(time.addingTimeInterval(2))) < 1)
        var finished = status; finished["state"] = "ready"
        try JSONSerialization.data(withJSONObject: finished).write(to: reports.appendingPathComponent("fixture.json"))
        let rescanned = try #require(scanner.scan().sessions.first)
        expectEqual(rescanned.state, .ready)
        #expect(rescanned.lastUserMessageAt == result.lastUserMessageAt)
        #expect(abs(try #require(result.lastUserMessageAt).timeIntervalSince(time)) < 1)
    }
    @Test func testCursorUsesMessageActivityAndApprovalMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var db: OpaquePointer?
        sqlite3_open(folder.appendingPathComponent("state.vscdb").path, &db)
        defer { sqlite3_close(db) }
        let meta: [String: Any] = ["composerId": "fixture", "name": "Review a patch", "status": "completed", "lastUpdatedAt": now.addingTimeInterval(100).timeIntervalSince1970 * 1000, "hasBlockingPendingActions": true, "fullConversationHeadersOnly": [["type": 1, "createdAt": ISO8601DateFormatter().string(from: now.addingTimeInterval(-60))], ["type": 2, "createdAt": ISO8601DateFormatter().string(from: now)]], "workspaceIdentifier": ["uri": ["fsPath": "/tmp/cursor-project"]]]
        let value = String(decoding: try JSONSerialization.data(withJSONObject: meta), as: UTF8.self)
        let sql = "CREATE TABLE composerHeaders(composerId TEXT,recency INTEGER,value TEXT,isArchived INTEGER); CREATE TABLE cursorDiskKV(key TEXT,value TEXT); INSERT INTO composerHeaders VALUES ('fixture',1792539000000,'\(value)',0); INSERT INTO cursorDiskKV VALUES ('composerData:fixture','\(value)');"
        expectEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let result = try #require(SessionScanner(home: root).scan().sessions.first)
        expectEqual(result.provider, .cursor)
        expectEqual(result.state, .waiting)
        expectEqual(result.updatedAt, now)
        expectEqual(result.project, "/tmp/cursor-project")
        #expect(result.lastUserMessageAt == now.addingTimeInterval(-60))
    }
}

private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(lhs == rhs, sourceLocation: sourceLocation)
}
private func expectFalse(_ value: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!value, sourceLocation: sourceLocation)
}
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try expression(); Issue.record("Expected an error", sourceLocation: sourceLocation) } catch {}
}
