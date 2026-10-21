import Foundation
import Testing
@testable import PulseCore

struct AttentionTests {
    let now = Date(timeIntervalSince1970: 1_792_539_000)
    func session(_ state: AgentState, _ offset: Double = 1, id: String = "one", provider: Provider = .claude) -> Session {
        Session(provider: provider, nativeID: id, title: "Agent", project: "/tmp", updatedAt: now.addingTimeInterval(offset), state: state)
    }
    @Test func startupIsSilentAndRepeatedPollsDoNotRepeatSounds() {
        var tracker = AttentionTracker(startedAt: now)
        #expect(tracker.update([session(.ready, -1)], availableProviders: [.claude]).isEmpty)
        #expect(tracker.update([session(.running, 2)], availableProviders: [.claude]).isEmpty)
        #expect(tracker.update([session(.waiting, 3)], availableProviders: [.claude]).isEmpty)
        #expect(tracker.update([session(.waiting, 3)], availableProviders: [.claude]).isEmpty)
        #expect(tracker.update([session(.ready, 4)], availableProviders: [.claude]) == ["claude:one"])
        var renamed = session(.ready, 4); renamed.title = "New title"
        #expect(tracker.update([renamed], availableProviders: [.claude]).isEmpty)
    }
    @Test func completionDuringTheFirstScanStillSoundsExactlyOnce() {
        var tracker = AttentionTracker(startedAt: now)
        let ready = session(.ready, 2)
        #expect(tracker.update([ready], availableProviders: [.claude]) == [ready.id])
        #expect(tracker.update([ready], availableProviders: [.claude]).isEmpty)
        // Connecting another source later cannot swallow its new completion either.
        let codex = session(.ready, 5, provider: .codex)
        #expect(tracker.update([codex], availableProviders: [.claude, .codex]) == [codex.id])
    }
    @Test func catchesNewReplyWhenPollingMissesTheRunningState() {
        var tracker = AttentionTracker(startedAt: now)
        _ = tracker.update([session(.ready)], availableProviders: [.claude])
        #expect(tracker.update([session(.ready, 5)], availableProviders: [.claude]) == ["claude:one"])
        _ = tracker.update([session(.unknown, 5)], availableProviders: [.claude])
        #expect(tracker.update([session(.ready, 5)], availableProviders: [.claude]).isEmpty)
    }
    @Test func delayedSourceAndHistoricalDiscoveryDoNotReplayBacklog() {
        var tracker = AttentionTracker(startedAt: now)
        _ = tracker.update([], availableProviders: [.claude])
        #expect(tracker.update([session(.ready, -100, id: "old"), session(.ready, -2, provider: .codex)], availableProviders: [.claude, .codex]).isEmpty)
        #expect(tracker.update([session(.waiting, 3, id: "new")], availableProviders: [.claude]).isEmpty)
        #expect(tracker.update([session(.ready, 4, id: "new")], availableProviders: [.claude]) == ["claude:new"])
    }
    @Test func inputAndApprovalRequestsStaySilentForEveryProvider() {
        for provider in Provider.allCases {
            var tracker = AttentionTracker(startedAt: now)
            _ = tracker.update([session(.running, provider: provider)], availableProviders: [provider])
            for state in [AgentState.waiting, .running, .waiting, .idle, .unknown] {
                #expect(tracker.update([session(state, 2, provider: provider)], availableProviders: [provider]).isEmpty)
            }
            #expect(tracker.update([session(.ready, 3, provider: provider)], availableProviders: [provider]) == ["\(provider.rawValue):one"])
            #expect(tracker.update([session(.ready, 3, provider: provider)], availableProviders: [provider]).isEmpty)
        }
    }
    @Test func unavailableSourceDoesNotResetOrReplayAndAllProvidersAlert() {
        var tracker = AttentionTracker(startedAt: now)
        let providers = Set(Provider.allCases)
        let running = Provider.allCases.map { session(.running, provider: $0) }
        _ = tracker.update(running, availableProviders: providers)
        #expect(tracker.update([], availableProviders: []).isEmpty)
        let ready = Provider.allCases.map { session(.ready, 3, provider: $0) }
        #expect(tracker.update(ready, availableProviders: providers).count == 3)
        #expect(tracker.update(ready, availableProviders: providers).isEmpty)
    }
    @Test func childrenNeverTriggerReviewSoundsEvenWhenRunningOrWaiting() {
        var tracker = AttentionTracker(startedAt: now)
        _ = tracker.update([], availableProviders: Set(Provider.allCases))
        for provider in Provider.allCases {
            for state in [AgentState.running, .waiting, .ready] {
                var child = session(state, 5, provider: provider)
                child.isSubagent = true
                #expect(tracker.update([child], availableProviders: [provider]).isEmpty)
            }
            #expect(tracker.update([session(.ready, 6, provider: provider)], availableProviders: [provider]) == ["\(provider.rawValue):one"])
        }
    }

}
