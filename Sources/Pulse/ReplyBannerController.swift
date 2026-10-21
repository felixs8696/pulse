import AppKit
import SwiftUI
import QuartzCore
import PulseCore

/// One reply queue and lifetime control nonactivating copies on every display. It never asks macOS to deliver a notification.
@MainActor
final class ReplyBannerController {
    private struct Replica {
        let window: NSPanel
        let placement: ReplyBannerPlacement
    }
    private var replicas: [Replica] = []
    private var placements: [ReplyBannerPlacement] = []
    private func makeWindow() -> NSPanel {
        let panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Reply ready"
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
    private var pending: [Session] = []
    private var current: Session?
    private var open: ((Session) -> Void)?
    private var expiry: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var hoveredWindows: Set<ObjectIdentifier> = []
    private var closing = false
    private var generation = 0
    private var duration = ReplyBannerDuration.fiveSeconds
    var holdsUntilClicked: Bool { current != nil && duration == .untilClicked }

    func enqueue(_ sessions: [Session], placements: [ReplyBannerPlacement], duration: ReplyBannerDuration = .fiveSeconds, preview: Bool = false, open: @escaping (Session) -> Void) {
        self.duration = duration
        self.placements = placements
        self.open = open
        for session in sessions where current?.id != session.id && !pending.contains(where: { $0.id == session.id }) {
            pending.append(session)
        }
        if current == nil { showNext() }
        if preview {
            let pointer = NSEvent.mouseLocation
            (replicas.first { $0.window.screen?.frame.contains(pointer) == true } ?? replicas.first)?.window.makeKey()
        }
    }

    func dismissAll() {
        generation += 1
        expiry?.cancel()
        transition?.cancel()
        pending.removeAll()
        current = nil
        hoveredWindows.removeAll()
        closing = false
        removeWindows()
    }

    private func showNext() {
        guard current == nil, !pending.isEmpty, !placements.isEmpty else { return }
        let session = pending.removeFirst()
        current = session
        closing = false
        hoveredWindows.removeAll()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        replicas = placements.map { Replica(window: makeWindow(), placement: $0) }
        for replica in replicas {
            let window = replica.window
            let placement = replica.placement
            let id = ObjectIdentifier(window)
            let dx: CGFloat = reduceMotion ? 0 : (placement.opensOnLeft ? 18 : -18)
            window.contentView = NSHostingView(rootView: ReplyBannerView(session: session,
                open: { [weak self] in
                    guard let self, !self.closing else { return }
                    let action = self.open
                    self.dismissAll()
                    action?(session)
                },
                dismiss: { [weak self] in self?.dismissCurrent() },
                hover: { [weak self] inside in
                    guard let self, !self.closing else { return }
                    if inside { self.hoveredWindows.insert(id) }
                    else { self.hoveredWindows.remove(id) }
                    if !self.hoveredWindows.isEmpty { self.expiry?.cancel() }
                    else { self.scheduleExpiry() }
                }))
            window.ignoresMouseEvents = false
            window.setFrame(placement.frame.offsetBy(dx: dx, dy: 0), display: false)
            window.alphaValue = 0
            window.orderFrontRegardless()
        }
        // One animation clock and expiry task drive every copy of the reply.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.1 : 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for replica in replicas {
                replica.window.animator().setFrame(replica.placement.frame, display: true)
                replica.window.animator().alphaValue = 1
            }
        }
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiry?.cancel()
        guard current != nil, hoveredWindows.isEmpty, !closing, let seconds = duration.seconds else { return }
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismissCurrent()
        }
    }

    private func dismissCurrent() {
        guard current != nil, !closing else { return }
        closing = true
        expiry?.cancel()
        for replica in replicas { replica.window.ignoresMouseEvents = true }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.1 : 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for replica in replicas {
                let dx: CGFloat = reduceMotion ? 0 : (replica.placement.opensOnLeft ? 18 : -18)
                replica.window.animator().alphaValue = 0
                replica.window.animator().setFrame(replica.placement.frame.offsetBy(dx: dx, dy: 0), display: true)
            }
        }
        let token = generation
        transition = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.removeWindows()
            self.current = nil
            self.closing = false
            self.showNext()
        }
    }
    private func removeWindows() {
        for replica in replicas {
            replica.window.orderOut(nil)
            replica.window.contentView = nil
            replica.window.close()
        }
        replicas.removeAll()
        hoveredWindows.removeAll()
    }

}
