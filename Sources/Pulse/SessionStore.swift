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
    @Published var filter: ShelfFilter = .all
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
    private let scanner = SessionScanner()
    private let queue = DispatchQueue(label: "local.pulse.scanner", qos: .utility)
    private var timer: Timer?
    @Published private var openITermPanes: Set<String>?
    @Published private var closedTerminals: Set<String> = []

    init() {
        pillOnEveryDisplay = UserDefaults.standard.object(forKey: "pillOnEveryDisplay") as? Bool ?? true
        replyBannersEnabled = UserDefaults.standard.bool(forKey: "replyBannersEnabled")
        replyBannerDuration = (UserDefaults.standard.object(forKey: "replyBannerDuration") as? Int)
            .flatMap(ReplyBannerDuration.init(rawValue:)) ?? .fiveSeconds
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
        guard !refreshing else { return }
        refreshing = true
        queue.async { [scanner, weak self] in
            let result = scanner.scan()
            Task { @MainActor [weak self] in
                guard let self else { return }
                let panes = await SessionLauncher.openITermPaneIDs()
                if let panes { self.openITermPanes = panes }
                let unavailable = Set(result.sources.filter { !$0.available }.map(\.provider))
                let next = result.sessions + self.sessions.filter { unavailable.contains($0.provider) }
                let live = next.filter { self.isVisible($0) }
                let newAttention = self.attentionTracker.update(live, availableProviders: Set(result.sources.filter(\.available).map(\.provider)))
                let todayIDs = Set(next.filter { SessionScope.isToday($0) }.map(\.id))
                let readyIDs = newAttention.filter { todayIDs.contains($0) }
                if self.soundsEnabled {
                    self.chimes.play(readyIDs, tones: self.sessionTones.overrides)
                }
                if self.replyBannersEnabled, !readyIDs.isEmpty {
                    let byID = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    self.completedReplies.send(readyIDs.compactMap { byID[$0] })
                }
                if self.sessions != next { self.sessions = next }
                if self.sources != result.sources { self.sources = result.sources }
                self.lastScan = Date()
                self.refreshing = false
            }
        }
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
