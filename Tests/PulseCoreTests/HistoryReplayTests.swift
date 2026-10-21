import Foundation
import Testing
import CSQLite
@testable import PulseCore

struct HistoryReplayTests {
    private let original = Date(timeIntervalSince1970: 1_792_538_000)
    private var replay: Date { original.addingTimeInterval(86_400) }
    private func event(_ type: String, at date: Date, fields: [String: Any] = [:]) -> [String: Any] {
        var payload = fields; payload["type"] = type
        return ["type": "event_msg", "timestamp": date.timeIntervalSince1970, "payload": payload]
    }
    private var restored: [[String: Any]] {
        [event("task_started", at: replay, fields: ["started_at": original.timeIntervalSince1970]),
         event("user_message", at: replay, fields: ["message": "Review this"]),
         event("agent_message", at: replay, fields: ["message": "Done"]),
         event("task_complete", at: replay, fields: ["completed_at": original.addingTimeInterval(30).timeIntervalSince1970])]
    }

    @Test func replayUsesOriginalTurnTimesInsteadOfImportTime() {
        let status = StatusParser.codex(restored, now: replay)
        #expect(status.0 == .ready)
        #expect(status.1 == original.addingTimeInterval(30))
        #expect(StatusParser.codexReplayDate(restored) == replay)
        #expect(MessagePreview.lastUserMessageDate(restored, provider: .codex) == original)
    }

    @Test func missingCompletionTimeDoesNotFallBackToImportTime() {
        var events = restored
        events[3] = event("task_complete", at: replay)
        #expect(StatusParser.codex(events, now: replay).1 == original)
    }

    @Test func restoredRepliesNeverEnterWaitingOrChimeButANewLiveTurnCan() {
        var session = Session(provider: .codex, nativeID: "restored", title: "Old chat", project: "", updatedAt: replay,
                              state: .ready, replayedAt: replay)
        let inbox = ReviewInbox()
        #expect(!inbox.needsReview(session))
        #expect(!SessionScope.needsReviewToday(session, inbox: inbox, now: replay))
        var sounds = AttentionTracker(startedAt: replay.addingTimeInterval(-60))
        _ = sounds.update([], availableProviders: [.codex])
        #expect(sounds.update([session], availableProviders: [.codex]).isEmpty)
        let live = restored + [event("task_started", at: replay.addingTimeInterval(60), fields: ["started_at": replay.addingTimeInterval(60).timeIntervalSince1970]),
                               event("user_message", at: replay.addingTimeInterval(61), fields: ["message": "Now fix this"]),
                               event("task_complete", at: replay.addingTimeInterval(90), fields: ["completed_at": replay.addingTimeInterval(90).timeIntervalSince1970])]
        #expect(StatusParser.codexReplayDate(live) == nil)
        #expect(MessagePreview.lastUserMessageDate(live, provider: .codex) == replay.addingTimeInterval(61))
        session.replayedAt = nil; session.updatedAt = replay.addingTimeInterval(90)
        #expect(inbox.needsReview(session))
        #expect(sounds.update([session], availableProviders: [.codex]) == [session.id])
    }

    @Test func scannerExcludesReplayThenRecognizesALiveTurnInTheSameFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        let log = root.appendingPathComponent("rollout.jsonl")
        func write(_ events: [[String: Any]]) throws {
            var data = Data()
            for event in events { data.append(try JSONSerialization.data(withJSONObject: event)); data.append(10) }
            try data.write(to: log)
        }
        try write(restored)
        var database: OpaquePointer?
        sqlite3_open(root.appendingPathComponent(".codex/state_5.sqlite").path, &database)
        defer { sqlite3_close(database) }
        let sql = "CREATE TABLE threads(id TEXT,title TEXT,cwd TEXT,updated_at INTEGER,rollout_path TEXT,source TEXT,archived INTEGER); INSERT INTO threads VALUES ('restored','Old chat','/tmp',0,'\(log.path)','vscode',0);"
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        let scanner = SessionScanner(home: root)
        let old = try #require(scanner.scan().sessions.first)
        #expect(old.replayedAt == replay)
        #expect(old.updatedAt == original.addingTimeInterval(30))
        #expect(old.lastUserMessageAt == original)
        #expect(!ReviewInbox().needsReview(old))
        let liveDate = Date()
        try write(restored + [event("task_started", at: liveDate, fields: ["started_at": liveDate.timeIntervalSince1970]),
                              event("user_message", at: liveDate, fields: ["message": "A new request"]),
                              event("task_complete", at: liveDate.addingTimeInterval(30))])
        let live = try #require(scanner.scan().sessions.first)
        #expect(live.replayedAt == nil)
        #expect(live.lastUserMessage == "A new request")
        #expect(SessionScope.needsReviewToday(live, inbox: ReviewInbox(), now: liveDate))
    }

    @Test func normalSteeringInALongLiveTurnUsesTheMessageTime() {
        let events = [event("task_started", at: original, fields: ["started_at": original.timeIntervalSince1970]),
                      event("user_message", at: original.addingTimeInterval(600), fields: ["message": "Also fix the spacing"])]
        #expect(StatusParser.codexReplayDate(events) == nil)
        #expect(MessagePreview.lastUserMessageDate(events, provider: .codex) == original.addingTimeInterval(600))
    }

    @Test func backgroundNotificationsDoNotReplaceTheHumanQueryOrDate() {
        let events = restored + [event("task_started", at: replay, fields: ["started_at": original.addingTimeInterval(600).timeIntervalSince1970]),
                                 event("user_message", at: replay, fields: ["message": "<task-notification><summary>Background command completed</summary></task-notification>"])]
        #expect(MessagePreview.codex(events) == "Review this")
        #expect(MessagePreview.lastUserMessageDate(events, provider: .codex) == original)
    }
}
