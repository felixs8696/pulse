import Foundation
import Testing
@testable import PulseCore

struct WorkingOrderTests {
    private let now = Date(timeIntervalSince1970: 1_792_539_000)
    private func session(_ id: String, message: Date?) -> Session {
        Session(provider: .codex, nativeID: id, title: id, project: "", updatedAt: now,
                state: .running, lastUserMessageAt: message)
    }

    @Test func activityNeverReordersButANewHumanMessageDoes() {
        var first = session("first", message: now)
        var second = session("second", message: now.addingTimeInterval(-60))
        second.updatedAt = now.addingTimeInterval(600)
        #expect(Session.sortedByLastUserMessage([second, first]).map(\.nativeID) == ["first", "second"])
        #expect(Session.sorted([second, first], pins: []).map(\.nativeID) == ["second", "first"])
        first.updatedAt = now.addingTimeInterval(1200)
        second.lastUserMessageAt = now.addingTimeInterval(60)
        #expect(Session.sortedByLastUserMessage([first, second]).map(\.nativeID) == ["second", "first"])
    }

    @Test func unknownAndEqualDatesHaveStableOrder() {
        let a = session("a", message: nil)
        var b = session("b", message: nil)
        let c = session("c", message: now)
        let d = session("d", message: now)
        b.updatedAt = now.addingTimeInterval(600)
        #expect(Session.sortedByLastUserMessage([d, b, c, a]).map(\.nativeID) == ["c", "d", "a", "b"])
    }

    @Test func onlyHumanEventsAdvanceTheMessageDate() {
        let events: [[String: Any]] = [
            ["type": "user", "timestamp": now.timeIntervalSince1970, "message": ["content": "Fix this"]],
            ["type": "user", "timestamp": now.timeIntervalSince1970 + 1, "message": ["content": [["type": "tool_result", "content": "output"]]]],
            ["type": "user", "timestamp": now.timeIntervalSince1970 + 2, "isMeta": true, "message": ["content": "Injected context"]],
            ["type": "user", "timestamp": now.timeIntervalSince1970 + 3, "isCompactSummary": true, "message": ["content": "Summary"]]
        ]
        #expect(MessagePreview.lastUserMessageDate(events, provider: .claude) == now)
        let codex: [[String: Any]] = [
            ["type": "event_msg", "timestamp": now.timeIntervalSince1970, "payload": ["type": "user_message", "message": "Fix this"]],
            ["type": "response_item", "timestamp": now.timeIntervalSince1970 + 1, "payload": ["type": "message", "role": "user", "content": "<environment_context>generated</environment_context>"]],
            ["type": "event_msg", "timestamp": now.timeIntervalSince1970 + 2, "payload": ["type": "agent_message", "message": "Working"]]
        ]
        #expect(MessagePreview.lastUserMessageDate(codex, provider: .codex) == now)
    }

    @Test func longTranscriptsFindLatestPromptOutsideTailAndAcrossChunkBoundaries() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        func prompt(_ date: Date) throws -> Data {
            var data = try JSONSerialization.data(withJSONObject: ["type": "user", "timestamp": date.timeIntervalSince1970, "message": ["content": String(repeating: "query ", count: 50_000)]])
            data.append(10)
            return data
        }
        let output = Data(("{\"type\":\"assistant\",\"padding\":\"" + String(repeating: "x", count: 80_000) + "\"}\n").utf8)
        var data = try prompt(now.addingTimeInterval(-60))
        data.append(try prompt(now))
        for _ in 0..<20 { data.append(output) }
        try data.write(to: file)
        #expect(MessagePreview.lastUserMessageDate(TranscriptSlice(path: file.path).tail, provider: .claude) == nil)
        #expect(TranscriptSlice.lastUserMessageDate(path: file.path, provider: .claude) == now)
        let originalSize = data.count
        data.append(try prompt(now.addingTimeInterval(60)))
        for _ in 0..<20 { data.append(output) }
        try data.write(to: file)
        #expect(TranscriptSlice.lastUserMessageDate(path: file.path, provider: .claude, sinceOffset: originalSize) == now.addingTimeInterval(60))
        #expect(TranscriptSlice.lastUserMessageDate(path: file.path, provider: .claude, sinceOffset: data.count) == nil)
    }

    @Test func oldSessionDataDecodesWithoutNewTimestamp() throws {
        let encoded = try JSONEncoder().encode(session("old", message: nil))
        #expect(try JSONDecoder().decode(Session.self, from: encoded).lastUserMessageAt == nil)
    }
}
