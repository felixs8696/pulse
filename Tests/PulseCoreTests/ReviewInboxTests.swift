import Foundation
import Testing
@testable import PulseCore

struct ReviewInboxTests {
    @Test func readRepliesSortBelowUnreadByRecencyAndNewReplyReturnsToUnread() {
        var inbox = ReviewInbox()
        let olderUnread = session("a", time: 100)
        let newerRead = session("b", time: 300)
        let newerUnread = session("c", time: 200)
        inbox.markHandled(newerRead)
        #expect(inbox.sorted([newerRead, olderUnread, newerUnread]).map(\.nativeID) == ["c", "a", "b"])
        #expect(!inbox.isRead(session("b", time: 400)))
    }
    @Test func respondingCountsAsReadButNextReplyIsUnread() {
        let inbox = ReviewInbox()
        var reply = session(time: 100)
        reply.lastUserMessageAt = Date(timeIntervalSince1970: 200)
        #expect(inbox.isRead(reply))
        #expect(!inbox.needsReview(reply))
        reply.updatedAt = Date(timeIntervalSince1970: 300)
        #expect(!inbox.isRead(reply))
        #expect(inbox.isRead(session(state: .running)))
    }

    func session(_ id: String = "example", state: AgentState = .ready, time: Double = 100) -> Session {
        Session(provider: .claude, nativeID: id, title: id, project: "/tmp", updatedAt: Date(timeIntervalSince1970: time), state: state)
    }
    @Test func explicitReadAndUnreadSurviveRestartsAndUpdateTheDailyCount() throws {
        let reply = session(time: Date().timeIntervalSince1970)
        var inbox = ReviewInbox()
        #expect(SessionScope.needsReviewToday(reply, inbox: inbox))
        inbox.markHandled(reply)
        #expect(inbox.isRead(reply))
        #expect(!SessionScope.needsReviewToday(reply, inbox: inbox))
        var restored = try JSONDecoder().decode(ReviewInbox.self, from: JSONEncoder().encode(inbox))
        #expect(restored.isRead(reply))
        restored.markUnread(reply)
        let unread = try JSONDecoder().decode(ReviewInbox.self, from: JSONEncoder().encode(restored))
        #expect(!unread.isRead(reply))
        #expect(SessionScope.needsReviewToday(reply, inbox: unread))
    }
    @Test func unreadActionCannotChangeANewerReadReplyOrBypassDailyExpiry() {
        var inbox = ReviewInbox()
        let old = session(time: 100)
        let newer = session(time: 200)
        inbox.markHandled(newer)
        inbox.markUnread(old)
        #expect(inbox.isRead(newer))
        #expect(inbox.needsReview(session(time: 300)))
        inbox.markUnread(newer)
        #expect(inbox.needsReview(newer))
        #expect(!SessionScope.needsReviewToday(newer, inbox: inbox))
        var child = newer; child.isSubagent = true
        inbox.markHandled(child)
        #expect(!inbox.isRead(child))
        #expect(!inbox.needsReview(child))
    }
    @Test func olderRepliesRemainAccessibleWithoutAcknowledgingThem() throws {
        var inbox = ReviewInbox()
        let reply = session()
        #expect(inbox.needsReview(reply)) // Retained in history; daily count is a separate policy.
        let restarted = try JSONDecoder().decode(ReviewInbox.self, from: JSONEncoder().encode(inbox))
        #expect(restarted.needsReview(reply))
        inbox.markHandled(reply)
        #expect(!inbox.needsReview(reply))
        let restored = try JSONDecoder().decode(ReviewInbox.self, from: JSONEncoder().encode(inbox))
        #expect(!restored.needsReview(reply))
        #expect(restored.needsReview(session(time: 200)))
    }
    @Test func dailyInboxExpiresAtLocalMidnightAndKeepsOlderHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        // The day after the spring clock change is only 23 hours after the previous midnight.
        let midnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9)))
        let now = midnight.addingTimeInterval(60)
        let yesterday = session(time: midnight.addingTimeInterval(-1).timeIntervalSince1970)
        let today = session("today", time: midnight.timeIntervalSince1970)
        var child = today; child.isSubagent = true
        var running = yesterday; running.state = .running
        var inbox = ReviewInbox()
        #expect(!SessionScope.needsReviewToday(yesterday, inbox: inbox, now: now, calendar: calendar))
        #expect(SessionScope.isOlder(yesterday, now: now, calendar: calendar))
        #expect(inbox.needsReview(yesterday))
        #expect(SessionScope.needsReviewToday(today, inbox: inbox, now: now, calendar: calendar))
        #expect(!SessionScope.isOlder(today, now: now, calendar: calendar))
        #expect(!SessionScope.needsReviewToday(child, inbox: inbox, now: now, calendar: calendar))
        #expect(!SessionScope.isOlder(child, now: now, calendar: calendar))
        #expect(!SessionScope.isOlder(running, now: now, calendar: calendar))
        inbox.markHandled(today)
        #expect(!SessionScope.needsReviewToday(today, inbox: inbox, now: now, calendar: calendar))
        // Moving the clock into tomorrow expires a reply without erasing its history.
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))
        #expect(!SessionScope.needsReviewToday(today, inbox: ReviewInbox(), now: tomorrow, calendar: calendar))
        #expect(SessionScope.isOlder(today, now: tomorrow, calendar: calendar))
    }
    @Test func respondingClearsTheInboxAndTheNextReplyReturns() {
        let inbox = ReviewInbox()
        #expect(inbox.needsReview(session()))
        #expect(!inbox.needsReview(session(state: .running, time: 200)))
        #expect(inbox.needsReview(session(state: .waiting, time: 220)))
        #expect(inbox.needsReview(session(state: .ready, time: 300)))
    }
    @Test func handlingAcknowledgesOnlyTheDisplayedEventNotLaterActivity() {
        var inbox = ReviewInbox()
        inbox.markHandled(session(state: .waiting))
        #expect(inbox.needsReview(session(state: .ready)))
        #expect(inbox.needsReview(session(state: .waiting, time: 101)))
        var child = session(); child.isSubagent = true
        #expect(!inbox.needsReview(child))
    }
    @Test func scopedCountMatchesRowsEvenWhenGlobalInboxIsNonempty() {
        var inbox = ReviewInbox()
        let example = session()
        let other = session("other")
        let sessions = [example, other]
        inbox.markHandled(example)
        let global = sessions.filter { inbox.needsReview($0) }
        let scoped = SessionScope.matching(sessions, provider: nil, query: "example")
        #expect(global.count == 1)
        #expect(scoped.filter { inbox.needsReview($0) }.isEmpty)
        let cleared = SessionScope.matching(sessions, provider: nil, query: "")
        #expect(cleared.filter { inbox.needsReview($0) }.count == global.count)
        #expect(SessionScope.matching(sessions, provider: .codex, query: "").isEmpty)
    }
}
