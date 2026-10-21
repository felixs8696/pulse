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
