import Foundation
import CoreGraphics
import Testing
@testable import PulseCore

struct InteractionTests {
    @Test func compactPillStaysAnchoredAndShelfSwitchesSides() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = ShelfPlacement(anchor: CGPoint(x: 90, y: 870), screen: screen)
        #expect(left.pillFrame == CGRect(x: 30, y: 754, width: 60, height: 116))
        #expect(!left.opensOnLeft)
        let right = ShelfPlacement(anchor: CGPoint(x: 1420, y: 870), screen: screen)
        #expect(right.opensOnLeft)
        #expect(screen.contains(left.shelfFrame))
        #expect(screen.contains(right.shelfFrame))
    }
    @Test func gapBetweenVisibleEdgesIsConstantAtEveryScreenEdge() {
        for screen in [CGRect(x: 0, y: 24, width: 1440, height: 876), CGRect(x: -1440, y: -900, width: 1440, height: 876)] {
            for x in [screen.minX + 60, screen.midX, screen.maxX] {
                for y in [screen.minY + 116, screen.midY, screen.maxY] {
                    let placement = ShelfPlacement(anchor: CGPoint(x: x, y: y), screen: screen)
                    let pill = placement.pillFrame.insetBy(dx: 12, dy: 12)
                    let shelf = placement.shelfFrame.insetBy(dx: 12, dy: 12)
                    let gap = placement.opensOnLeft ? pill.minX - shelf.maxX : shelf.minX - pill.maxX
                    #expect(gap == ShelfPlacement.gap)
                    #expect(screen.contains(placement.shelfFrame))
                    #expect(screen.contains(placement.pillFrame))
                }
            }
        }
    }
    @Test func bottomEdgeClampsShelfVerticallyWithoutIncreasingItsGap() {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let placement = ShelfPlacement(anchor: CGPoint(x: -20, y: 120), screen: screen)
        #expect(placement.pillFrame == CGRect(x: -80, y: 4, width: 60, height: 116))
        #expect(placement.shelfFrame.minY == 0)
        #expect(placement.opensOnLeft)
        #expect(placement.pillFrame.minX - placement.shelfFrame.maxX + 24 == 10)
    }
    @Test func codexPreviewUsesLastHumanMessageRatherThanToolsOrAssistant() {
        let events: [[String: Any]] = [
            ["type": "event_msg", "payload": ["type": "user_message", "message": "First task"]],
            ["type": "event_msg", "payload": ["type": "item_completed", "item": ["type": "UserMessage", "content": [["type": "text", "text": "Please fix the click behavior"]]]]],
            ["type": "event_msg", "payload": ["type": "agent_message", "message": "I will"]],
            ["type": "response_item", "payload": ["type": "function_call_output", "output": "Tool result"]]
        ]
        #expect(MessagePreview.codex(events) == "Please fix the click behavior")
    }
    @Test func claudePreviewSkipsToolResultsAndCompaction() {
        let events: [[String: Any]] = [
            ["type": "user", "message": ["content": "Initial request"]],
            ["type": "user", "message": ["content": [["type": "text", "text": "Also add my last message"]]]],
            ["type": "user", "message": ["content": [["type": "tool_result", "content": "not a user message"]]]],
            ["type": "user", "isCompactSummary": true, "message": ["content": "Generated recap"]],
            ["type": "user", "isMeta": true, "message": ["content": "Injected instructions"]]
        ]
        #expect(MessagePreview.claude(events) == "Also add my last message")
    }
    @Test func contextWrappersAreExcludedButUserTextIsKept() {
        #expect(MessagePreview.clean("<environment_context>private setup</environment_context>\nMake it smooth\nplease") == "Make it smooth please")
        #expect(MessagePreview.clean("<system-reminder>generated reminder</system-reminder>") == nil)
    }
    @Test func transcriptRetainsUserResponseItemsButNotToolOutputs() {
        let data = Data("""
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Latest prompt"}]}}
        {"type":"response_item","payload":{"type":"function_call_output","output":"Tool output"}}
        """.utf8)
        let events = TranscriptSlice.parse(data, dropFirst: false)
        #expect(events.count == 1)
        #expect(MessagePreview.codex(events) == "Latest prompt")
    }
}
