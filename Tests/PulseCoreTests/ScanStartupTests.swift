import Foundation
import Testing
import CSQLite
@testable import PulseCore

struct ScanStartupTests {
    private final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var started: [Provider] = []
        private var finished: Set<Provider> = []
        private var slow: Set<Provider> = []
        func record(_ event: SessionScanCoordinator.Event) {
            lock.lock(); defer { lock.unlock() }
            switch event {
            case .started(let provider): started.append(provider)
            case .slow(let provider): slow.insert(provider)
            case .finished(let result): finished.formUnion(result.sources.map(\.provider))
            }
        }
        func snapshot() -> ([Provider], Set<Provider>, Set<Provider>) {
            lock.lock(); defer { lock.unlock() }
            return (started, finished, slow)
        }
    }

    @Test func blockedSourceDoesNotBlockOtherAppsOrStartDuplicateScans() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let events = Events()
        let coordinator = SessionScanCoordinator(slowAfter: 0.05) { provider, _ in
            if provider == .claude { _ = gate.wait(timeout: .now() + 3) }
            return ScanResult(sessions: [], sources: [SourceHealth(provider, count: 0, message: "Done", available: true)])
        }
        coordinator.refresh(receive: { events.record($0) })
        for _ in 0..<100 {
            let snapshot = events.snapshot()
            if snapshot.1.contains(.codex) && snapshot.1.contains(.cursor) && snapshot.2.contains(.claude) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let snapshot = events.snapshot()
        #expect(snapshot.1 == [.codex, .cursor])
        #expect(snapshot.2 == [.claude])
        coordinator.refresh(receive: { events.record($0) })
        #expect(events.snapshot().0.filter { $0 == .claude }.count == 1)
        gate.signal()
        for _ in 0..<100 {
            if events.snapshot().1.contains(.claude) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(events.snapshot().1.contains(.claude))
    }

    @Test func rollingWeekFiltersBeforeReadingAndOlderChatsReturnAfterActivity() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        var db: OpaquePointer?
        #expect(sqlite3_open(root.appendingPathComponent(".codex/state_5.sqlite").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let cutoff = Int(now.timeIntervalSince1970 - 7 * 86_400)
        let sql = "CREATE TABLE threads(id TEXT,title TEXT,cwd TEXT,updated_at INTEGER,rollout_path TEXT,source TEXT,archived INTEGER); INSERT INTO threads VALUES ('old','Old chat','/tmp',0,'','cli',0),('recent','Recent chat','/tmp',\(cutoff),'','cli',0),('archived','Archived','/tmp',1800000000,'','cli',1);"
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        let scanner = SessionScanner(home: root)
        #expect(scanner.scan(provider: .codex, now: now).sessions.map(\.nativeID) == ["recent"])
        #expect(Set(scanner.scan(provider: .codex, pinnedIDs: ["codex:old"], now: now).sessions.map(\.nativeID)) == ["old", "recent"])
        #expect(scanner.scan(provider: .codex, now: now.addingTimeInterval(1)).sessions.isEmpty)
        #expect(sqlite3_exec(db, "UPDATE threads SET updated_at=1800000000 WHERE id='old'", nil, nil, nil) == SQLITE_OK)
        #expect(scanner.scan(provider: .codex, now: now.addingTimeInterval(1)).sessions.map(\.nativeID) == ["old"])
    }

    @Test func claudeSkipsOldAndChildTranscriptsButRetainsPins() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(".claude/projects/demo")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("parent/subagents"), withIntermediateDirectories: true)
        let old = folder.appendingPathComponent("old.jsonl")
        try Data().write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: old.path)
        try Data().write(to: folder.appendingPathComponent("recent.jsonl"))
        try Data().write(to: folder.appendingPathComponent("parent/subagents/child.jsonl"))
        let scanner = SessionScanner(home: root)
        #expect(scanner.scan(provider: .claude).sessions.map(\.nativeID) == ["recent"])
        #expect(Set(scanner.scan(provider: .claude, pinnedIDs: ["claude:old"]).sessions.map(\.nativeID)) == ["old", "recent"])
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: old.path)
        #expect(Set(scanner.scan(provider: .claude).sessions.map(\.nativeID)) == ["old", "recent"])
    }

    @Test func legacyCursorFiltersNumericJSONDatesAndKeepsPinnedOldChats() throws {
        let now = Date()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var db: OpaquePointer?
        #expect(sqlite3_open(folder.appendingPathComponent("state.vscdb").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let recent = #"{"name":"Recent","lastUpdatedAt":TIMESTAMP}"#.replacingOccurrences(of: "TIMESTAMP", with: String(now.timeIntervalSince1970 * 1000))
        let old = #"{"name":"Old","lastUpdatedAt":1}"#
        #expect(sqlite3_exec(db, "CREATE TABLE cursorDiskKV(key TEXT,value TEXT); INSERT INTO cursorDiskKV VALUES ('composerData:old','\(old)'),('composerData:recent','\(recent)');", nil, nil, nil) == SQLITE_OK)
        let scanner = SessionScanner(home: root)
        #expect(scanner.scan(provider: .cursor, now: now).sessions.map(\.nativeID) == ["recent"])
        #expect(Set(scanner.scan(provider: .cursor, pinnedIDs: ["cursor:old"], now: now).sessions.map(\.nativeID)) == ["old", "recent"])
    }
}
