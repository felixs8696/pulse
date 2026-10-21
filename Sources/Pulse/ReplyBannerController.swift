import AppKit
import SwiftUI
import QuartzCore
import PulseCore

/// Each conversation has its own lifetime. All displays observe the same stack.
@MainActor
final class ReplyBannerController: ObservableObject {
    private struct Replica {
        let window: NSPanel
        let placement: ReplyBannerPlacement
    }
    @Published private(set) var stack = ReplyBannerStack()
    @Published private(set) var exitingIDs: Set<String> = []
    private var replicas: [Replica] = []
    private var open: ((Session) -> Void)?
    private var expiries: [String: Task<Void, Never>] = [:]
    private var departures: [String: Task<Void, Never>] = [:]
    private var hoveredDisplays: [String: Set<Int>] = [:]
    private var duration = ReplyBannerDuration.fiveSeconds
    var holdsUntilClicked: Bool { !stack.sessions.isEmpty && duration == .untilClicked }
    private var motionDuration: Double { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.1 : 0.25 }

    func enqueue(_ sessions: [Session], placements: [ReplyBannerPlacement], duration: ReplyBannerDuration = .fiveSeconds,
                 preview: Bool = false, open: @escaping (Session) -> Void) {
        guard !placements.isEmpty else { return }
        self.duration = duration
        self.open = open
        let changed = withAnimation(.easeInOut(duration: motionDuration)) { stack.upsert(sessions) }
        guard !changed.isEmpty else { return }
        for id in changed {
            departures.removeValue(forKey: id)?.cancel()
            exitingIDs.remove(id)
            scheduleExpiry(id)
        }
        if replicas.isEmpty {
            for (index, placement) in placements.enumerated() {
                let window = makeWindow()
                window.contentView = NSHostingView(rootView: ReplyBannerStackView(banners: self, display: index,
                                                                                 opensOnLeft: placement.opensOnLeft))
                replicas.append(Replica(window: window, placement: placement))
                let target = placement.stackFrame(count: stack.sessions.count)
                let dx: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (placement.opensOnLeft ? 18 : -18)
                window.setFrame(target.offsetBy(dx: dx, dy: 0), display: false)
                window.alphaValue = 0
                window.orderFrontRegardless()
            }
        }
        layoutStack()
        if preview {
            let pointer = NSEvent.mouseLocation
            (replicas.first { $0.window.screen?.frame.contains(pointer) == true } ?? replicas.first)?.window.makeKey()
        }
    }

    func dismissAll() {
        for task in expiries.values { task.cancel() }
        for task in departures.values { task.cancel() }
        expiries.removeAll()
        departures.removeAll()
        hoveredDisplays.removeAll()
        stack.removeAll()
        exitingIDs.removeAll()
        removeWindows()
    }

    func openReply(_ session: Session) {
        guard !exitingIDs.contains(session.id) else { return }
        // Opening one conversation dismisses its copies, preserving other chats.
        dismiss(session.id)
        open?(session)
    }

    func dismissAnswered(in sessions: [Session]) {
        for id in stack.answeredIDs(in: sessions) { dismiss(id) }
    }

    func hover(_ inside: Bool, id: String, display: Int) {
        guard !exitingIDs.contains(id), stack.sessions.contains(where: { $0.id == id }) else { return }
        if inside { hoveredDisplays[id, default: []].insert(display) }
        else { hoveredDisplays[id]?.remove(display) }
        if hoveredDisplays[id]?.isEmpty == false { expiries.removeValue(forKey: id)?.cancel() }
        else { scheduleExpiry(id) }
    }

    private func scheduleExpiry(_ id: String) {
        expiries.removeValue(forKey: id)?.cancel()
        guard hoveredDisplays[id]?.isEmpty != false, !exitingIDs.contains(id), let seconds = duration.seconds else { return }
        expiries[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }

    func dismiss(_ id: String) {
        guard stack.sessions.contains(where: { $0.id == id }), !exitingIDs.contains(id) else { return }
        expiries.removeValue(forKey: id)?.cancel()
        // Fade in the existing slot before removing it and closing the gap.
        withAnimation(.easeOut(duration: motionDuration)) { _ = exitingIDs.insert(id) }
        let delay = motionDuration
        departures[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.departures.removeValue(forKey: id)
            self.hoveredDisplays.removeValue(forKey: id)
            withAnimation(.easeInOut(duration: self.motionDuration)) {
                self.stack.remove(id)
                self.exitingIDs.remove(id)
            }
            if self.stack.sessions.isEmpty { self.removeWindows() }
            else { self.layoutStack() }
        }
    }

    private func layoutStack() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = motionDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for replica in replicas {
                replica.window.animator().setFrame(replica.placement.stackFrame(count: stack.sessions.count), display: true)
                replica.window.animator().alphaValue = 1
            }
        }
    }

    private func makeWindow() -> NSPanel {
        let panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Replies ready"
        panel.identifier = NSUserInterfaceItemIdentifier("ReplyBanner")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }

    private func removeWindows() {
        let old = replicas
        replicas.removeAll()
        for replica in old {
            replica.window.orderOut(nil)
            replica.window.contentView = nil
            replica.window.close()
        }
    }
}

private struct ReplyBannerStackView: View {
    @ObservedObject var banners: ReplyBannerController
    let display: Int
    let opensOnLeft: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: -16) {
                ForEach(banners.stack.sessions) { session in
                    ReplyBannerView(session: session,
                        open: { banners.openReply(session) },
                        dismiss: { banners.dismiss(session.id) },
                        hover: { banners.hover($0, id: session.id, display: display) })
                        .frame(height: 132)
                        .opacity(banners.exitingIDs.contains(session.id) ? 0 : 1)
                        .offset(x: banners.exitingIDs.contains(session.id) && !reduceMotion ? (opensOnLeft ? 18 : -18) : 0)
                        .allowsHitTesting(!banners.exitingIDs.contains(session.id))
                        .transition(.opacity)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}
