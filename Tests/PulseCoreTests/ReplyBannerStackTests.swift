import Foundation
import Testing
@testable import PulseCore

struct ReplyBannerStackTests {
    private func reply(_ id: String, provider: Provider = .codex, at seconds: Double = 1, title: String = "Reply") -> Session {
        Session(provider: provider, nativeID: id, title: title, project: "/projects/demo",
                updatedAt: Date(timeIntervalSince1970: seconds), state: .ready)
    }
    @Test func independentChatsAreVisibleTogetherNewestFirst() {
        var stack = ReplyBannerStack()
        stack.upsert([reply("one", provider: .claude)])
        stack.upsert([reply("two")])
        #expect(stack.sessions.map(\.id) == ["codex:two", "claude:one"])
    }
    @Test func newReplyReplacesOnlyItsOwnCardWithoutReorderingOtherChats() {
        var stack = ReplyBannerStack()
        stack.upsert([reply("one"), reply("two")])
        let updated = reply("one", at: 2, title: "New reply")
        #expect(stack.upsert([updated]) == [updated.id])
        #expect(stack.sessions.map(\.nativeID) == ["two", "one"])
        #expect(stack.sessions.last?.title == "New reply")
        #expect(stack.sessions.count == 2)
        #expect(stack.upsert([updated]).isEmpty)
        #expect(stack.upsert([reply("one", at: 1)]).isEmpty)
        #expect(stack.sessions.last == updated)
    }
    @Test func sendingAnotherMessageHandlesOnlyThatChatsBanner() {
        var stack = ReplyBannerStack()
        var original = reply("one", at: 10)
        original.lastUserMessageAt = Date(timeIntervalSince1970: 5)
        original.lastUserMessage = "Try again"
        stack.upsert([original, reply("two", at: 10), reply("one", provider: .claude, at: 10)])
        var answered = original
        answered.state = .running
        answered.lastUserMessageAt = Date(timeIntervalSince1970: 11)
        // Repeating exactly the same text is still a new message.
        #expect(stack.answeredIDs(in: [answered]) == ["codex:one"])
        #expect(stack.sessions.count == 3)
    }

    @Test func activityAndLateLoadedHistoryDoNotDismissReplies() {
        var stack = ReplyBannerStack()
        stack.upsert([reply("one", at: 10)])
        var latest = reply("one", at: 20, title: "Updated title")
        latest.state = .running
        #expect(stack.answeredIDs(in: [latest]).isEmpty)
        latest.lastUserMessageAt = Date(timeIntervalSince1970: 9)
        latest.lastUserMessage = "Previously missing preview"
        #expect(stack.answeredIDs(in: [latest]).isEmpty)
        latest.lastUserMessageAt = Date(timeIntervalSince1970: 10)
        #expect(stack.answeredIDs(in: [latest]).isEmpty)
        latest.lastUserMessageAt = Date(timeIntervalSince1970: 21)
        latest.isSubagent = true
        #expect(stack.answeredIDs(in: [latest]).isEmpty)
        #expect(stack.answeredIDs(in: []).isEmpty)
    }

    @Test func newerReplyStartsItsOwnMessageBaseline() {
        var stack = ReplyBannerStack()
        stack.upsert([reply("one", at: 10)])
        var next = reply("one", at: 30)
        next.lastUserMessageAt = Date(timeIntervalSince1970: 20)
        stack.upsert([next])
        #expect(stack.answeredIDs(in: [next]).isEmpty)
        next.lastUserMessageAt = Date(timeIntervalSince1970: 31)
        #expect(stack.answeredIDs(in: [next]) == ["codex:one"])
    }

    @Test func dismissingOneLeavesTheOtherAndProviderIDsCannotCollide() {
        var stack = ReplyBannerStack()
        stack.upsert([reply("same"), reply("same", provider: .claude)])
        #expect(stack.sessions.count == 2)
        stack.remove("codex:same")
        #expect(stack.sessions.map(\.id) == ["claude:same"])
        stack.removeAll()
        #expect(stack.sessions.isEmpty)
    }
}
