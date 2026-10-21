import AppKit
import SwiftUI
import Combine
import PulseCore

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [Session] = []
    @Published var sources: [SourceHealth] = []
    @Published var pins: Set<String>
    @Published var query = ""
    @Published var provider: Provider?
    @Published var filter: ShelfFilter = .pinned
    @Published var refreshing = false
    @Published var lastScan: Date?
    @Published var error: String?
    @Published var presentation = ShelfPresentation()
    var expanded: Bool { presentation.expanded }
    var heldOpen: Bool { presentation.heldOpen }
    @Published var showConnections = false
    @Published var activeSessionActionsID: String?
    @Published var pillOnEveryDisplay: Bool { didSet {
        defaults.set(pillOnEveryDisplay, forKey: "pillOnEveryDisplay")
    } }
    @Published var replyBannersEnabled: Bool { didSet {
        defaults.set(replyBannersEnabled, forKey: "replyBannersEnabled")
    } }
    @Published var replyBannerDuration: ReplyBannerDuration { didSet {
        defaults.set(replyBannerDuration.rawValue, forKey: "replyBannerDuration")
    } }
    let completedReplies = PassthroughSubject<[Session], Never>()
    @Published private var sessionTones: SessionTones
    @Published var soundsEnabled: Bool { didSet {
        defaults.set(soundsEnabled, forKey: "attentionSoundsEnabled")
        if !soundsEnabled { chimes.stop() }
    } }
    private var attentionTracker = AttentionTracker()
    private let chimes = SessionChimes()
    @Published var launchAtLogin = false
    private var reviewInbox: ReviewInbox
    private let defaults = UserDefaults.standard
    private let scanner = SessionScanCoordinator()
    private var scanningProviders: Set<Provider> = []
    @Published private(set) var slowProviders: Set<Provider> = []
    private var checkingTerminals = false
    private var timer: Timer?
    @Published private var openITermPanes: Set<String>?
    @Published private var closedTerminals: Set<String> = []

    init() {
        pillOnEveryDisplay = UserDefaults.standard.object(forKey: "pillOnEveryDisplay") as? Bool ?? true
        replyBannersEnabled = UserDefaults.standard.object(forKey: "replyBannersEnabled") as? Bool ?? true
        replyBannerDuration = (UserDefaults.standard.object(forKey: "replyBannerDuration") as? Int)
            .flatMap(ReplyBannerDuration.init(rawValue:)) ?? .untilClicked
        soundsEnabled = UserDefaults.standard.object(forKey: "attentionSoundsEnabled") as? Bool ?? true
        pins = Set(UserDefaults.standard.stringArray(forKey: "pins") ?? [])
        sessionTones = UserDefaults.standard.data(forKey: "sessionTonesV1")
            .flatMap { try? JSONDecoder().decode(SessionTones.self, from: $0) } ?? SessionTones()
        // Old “seen” entries included automatic click acknowledgments; they cannot establish handling.
        reviewInbox = UserDefaults.standard.data(forKey: "reviewInboxV2")
            .flatMap { try? JSONDecoder().decode(ReviewInbox.self, from: $0) } ?? ReviewInbox()
    }
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh() {
        scanner.refresh(pinnedIDs: pins) { [weak self] event in
            Task { @MainActor [weak self] in self?.receiveScan(event) }
        }
        // Automation can wait for permission. Never hold chat discovery behind it.
        guard !checkingTerminals else { return }
        checkingTerminals = true
        Task { [weak self] in
            let panes = await SessionLauncher.openITermPaneIDs()
            guard let self else { return }
            if let panes { self.openITermPanes = panes }
            self.checkingTerminals = false
        }
    }
    private func receiveScan(_ event: SessionScanCoordinator.Event) {
        switch event {
        case .started(let provider):
            scanningProviders.insert(provider)
            if !sources.contains(where: { $0.provider == provider }) {
                sources.append(SourceHealth(provider, count: 0, message: "Checking local chats…", available: false))
            }
        case .slow(let provider):
            guard scanningProviders.contains(provider) else { return }
            slowProviders.insert(provider)
            let message = "This app is taking longer to scan. Other apps continue loading. Try quitting and reopening Pulse if it stays stuck."
            sources = sources.map { $0.provider == provider ? SourceHealth(provider, count: $0.count, message: message, available: false) : $0 }
            // Leave the indefinite startup screen even if no source has finished yet.
            lastScan = lastScan ?? Date()
        case .finished(let result):
            guard let health = result.sources.first else { return }
            scanningProviders.remove(health.provider)
            slowProviders.remove(health.provider)
            sources = sources.filter { $0.provider != health.provider } + result.sources
            let next = health.available ? sessions.filter { $0.provider != health.provider } + result.sessions : sessions
            let live = next.filter(isVisible)
            let newAttention = attentionTracker.update(live, availableProviders: health.available ? [health.provider] : [])
            let todayIDs = Set(next.filter { SessionScope.isToday($0) }.map(\.id))
            let readyIDs = newAttention.filter { todayIDs.contains($0) }
            if soundsEnabled { chimes.play(readyIDs, tones: sessionTones.overrides) }
            if replyBannersEnabled, !readyIDs.isEmpty {
                let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                completedReplies.send(readyIDs.compactMap { byID[$0] })
            }
            if sessions != next { sessions = next }
            lastScan = Date()
        }
        refreshing = !scanningProviders.isEmpty
    }
    func needsAttention(_ s: Session) -> Bool {
        SessionScope.needsReviewToday(s, inbox: reviewInbox)
    }
    var visibleBase: [Session] {
        sessions.filter(isVisible)
    }
    private func isVisible(_ session: Session) -> Bool {
        !session.isSubagent && session.hasOpenDestination && !closedTerminals.contains(session.id)
            && TerminalPresence.isVisible(session, openITermPanes: openITermPanes)
    }
    var attentionCount: Int { visibleBase.filter(needsAttention).count }
    var runningCount: Int { visibleBase.filter { $0.state == .running }.count }
    var hasScope: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || provider != nil }
    var matchingBase: [Session] { SessionScope.matching(visibleBase, provider: provider, query: query) }
    var matchingAttentionCount: Int { matchingBase.filter(needsAttention).count }
    var matchingRunningCount: Int { matchingBase.filter { $0.state == .running }.count }
    var matchingPinnedCount: Int { matchingBase.filter { pins.contains($0.id) }.count }
    var filtered: [Session] {
        let matches = matchingBase.filter { session in
            switch filter {
            case .all: return SessionScope.isToday(session) || session.state == .running
            case .pinned: return pins.contains(session.id)
            case .attention: return needsAttention(session)
            case .running: return session.state == .running
            case .older: return SessionScope.isOlder(session)
            }
        }
        return filter == .running ? Session.sortedByLastUserMessage(matches) : Session.sorted(matches, pins: [])
    }
    func showAllNeedsYou() { query = ""; provider = nil; filter = .attention }
    func toggleSounds() {
        soundsEnabled.toggle()
        if soundsEnabled { chimes.play(["pulse:sound-preview"]) }
    }
    func previewSound(_ session: Session) {
        chimes.preview(session.id, tone: sessionTones.overrides[session.id])
    }
    func tone(for session: Session) -> Int { sessionTones.value(for: session.id) }
    func hasCustomTone(_ session: Session) -> Bool { sessionTones.overrides[session.id] != nil }
    func setTone(_ value: Int?, for session: Session) {
        sessionTones.set(value, for: session.id)
        if let data = try? JSONEncoder().encode(sessionTones) { defaults.set(data, forKey: "sessionTonesV1") }
    }
    func togglePin(_ s: Session) {
        if pins.contains(s.id) { pins.remove(s.id) } else { pins.insert(s.id) }
        defaults.set(Array(pins), forKey: "pins")
    }
    func isRead(_ session: Session) -> Bool { reviewInbox.isRead(session) }
    func markRead(_ session: Session) {
        objectWillChange.send()
        reviewInbox.markHandled(session)
        saveReviewInbox()
    }
    func markUnread(_ session: Session) {
        objectWillChange.send()
        reviewInbox.markUnread(session)
        saveReviewInbox()
    }
    func toggleRead(_ session: Session) {
        if isRead(session) { markUnread(session) } else { markRead(session) }
    }
    func markDisplayedRead() {
        let displayed = filtered
        objectWillChange.send()
        for session in displayed { reviewInbox.markHandled(session) }
        saveReviewInbox()
    }
    private func saveReviewInbox() {
        if let data = try? JSONEncoder().encode(reviewInbox) { defaults.set(data, forKey: "reviewInboxV2") }
    }
    func open(_ s: Session) {
        Task {
            do { try await SessionLauncher.open(s); if !heldOpen { presentation.dismiss() } }
            catch LaunchError.closedTerminal { self.closedTerminals.insert(s.id); self.refresh() }
            catch LaunchError.unavailableDestination { self.closedTerminals.insert(s.id); self.refresh() }
            catch { self.error = error.localizedDescription }
        }
    }
}

enum ShelfFilter: String, CaseIterable {
    case pinned = "Pinned", running = "Working", attention = "Waiting", all = "Today", older = "Older"
}
