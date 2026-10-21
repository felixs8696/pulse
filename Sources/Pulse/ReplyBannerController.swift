import AppKit
import SwiftUI
import QuartzCore
import PulseCore

/// Owns a quiet, nonactivating banner. It never asks macOS to deliver a notification.
@MainActor
final class ReplyBannerController {
    private let window: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
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
    }()
    private var pending: [Session] = []
    private var current: Session?
    private weak var pill: NSWindow?
    private var screen = CGRect.zero
    private var open: ((Session) -> Void)?
    private var expiry: Task<Void, Never>?
    private var transition: Task<Void, Never>?
    private var hovered = false
    private var closing = false
    private var generation = 0

    func enqueue(_ sessions: [Session], pill: NSWindow, screen: CGRect, open: @escaping (Session) -> Void) {
        self.pill = pill
        self.screen = screen
        self.open = open
        for session in sessions where current?.id != session.id && !pending.contains(where: { $0.id == session.id }) {
            pending.append(session)
        }
        if current == nil { showNext() }
    }

    func dismissAll() {
        generation += 1
        expiry?.cancel()
        transition?.cancel()
        pending.removeAll()
        current = nil
        hovered = false
        closing = false
        window.orderOut(nil)
        window.contentView = nil
    }

    private func showNext() {
        guard current == nil, !pending.isEmpty, let pill else { return }
        let session = pending.removeFirst()
        current = session
        closing = false
        hovered = false
        let placement = ReplyBannerPlacement(pill: pill.frame, screen: screen)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
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
                self.hovered = inside
                if inside { self.expiry?.cancel() } else { self.scheduleExpiry() }
            }))
        window.ignoresMouseEvents = false
        window.setFrame(placement.frame.offsetBy(dx: dx, dy: 0), display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.1 : 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(placement.frame, display: true)
            window.animator().alphaValue = 1
        }
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiry?.cancel()
        guard current != nil, !hovered, !closing else { return }
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismissCurrent()
        }
    }

    private func dismissCurrent() {
        guard current != nil, !closing else { return }
        closing = true
        expiry?.cancel()
        window.ignoresMouseEvents = true
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let dx: CGFloat = reduceMotion ? 0 : ((pill?.frame.midX ?? window.frame.midX) > window.frame.midX ? 18 : -18)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.1 : 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 0
            window.animator().setFrame(window.frame.offsetBy(dx: dx, dy: 0), display: true)
        }
        let token = generation
        transition = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.window.orderOut(nil)
            self.window.contentView = nil
            self.current = nil
            self.closing = false
            self.showNext()
        }
    }
}
