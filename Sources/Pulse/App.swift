import AppKit
import SwiftUI
import Combine
import Carbon
import QuartzCore
import CoreGraphics
import ServiceManagement
import PulseCore

extension Notification.Name {
    static let previewReplyBanner = Notification.Name("previewReplyBanner")
    static let resetShelf = Notification.Name("resetPulse") }

@main
enum PulseMain {
    static func main() {
        if CommandLine.arguments.contains("--diagnose-health") {
            ScanDiagnostics.run()
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let result = SessionScanner().scan()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(result) { print(String(decoding: data, as: UTF8.self)) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}


@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = SessionStore()
    private var panel: ShelfPanel!
    private var shelfPanel: ShelfPanel!
    private let replyBanners = ReplyBannerController()
    private var displayPills: [String: ShelfPanel] = [:]
    private var displayPositions = UserDefaults.standard.data(forKey: "displayPillPositionsV1")
        .flatMap { try? JSONDecoder().decode(DisplayPillPositions.self, from: $0) } ?? DisplayPillPositions()
    private var statusItem: NSStatusItem!
    private var soundMenuItem: NSMenuItem?
    private var subscriptions: Set<AnyCancellable> = []
    private var hoverTask: Task<Void, Never>?
    private var hotKey: EventHotKeyRef?
    private var topRight = NSPoint.zero
    private var resizing = false
    private var pillHovered = false
    private var shelfHovered = false
    private var dragging = false
    private var animationGeneration = 0
    private var shelfRestingFrame = NSRect.zero
    private struct DragPresentation {
        let geometry: ShelfDragLayout
        let pillView: NSView
        let shelfView: NSView
        let pillAutoresizing: NSView.AutoresizingMask
        let shelfAutoresizing: NSView.AutoresizingMask
    }
    private var dragPresentation: DragPresentation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second launch just reveals the existing instance.
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "io.github.felixs8696.pulse")
        if let other = peers.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: []); NSApplication.shared.terminate(nil); return
        }
        panel = makePillPanel()
        shelfPanel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        shelfPanel.appearance = NSAppearance(named: .darkAqua)
        shelfPanel.title = "Pulse Sessions"
        shelfPanel.identifier = NSUserInterfaceItemIdentifier("PulseSessions")
        shelfPanel.isOpaque = false; shelfPanel.backgroundColor = .clear; shelfPanel.hasShadow = true
        shelfPanel.level = .statusBar; shelfPanel.collectionBehavior = panel.collectionBehavior
        shelfPanel.hidesOnDeactivate = false; shelfPanel.isReleasedWhenClosed = false
        shelfPanel.contentView = NSHostingView(rootView: ShelfView(store: store,
            onHover: { [weak self] inside in self?.shelfHovered = inside; self?.updateHover() },
            onDragChange: { [weak self] active in self?.setDragging(active); return self?.panel }))
        panel.addChildWindow(shelfPanel, ordered: .below)
        shelfPanel.alphaValue = 0
        if let position = UserDefaults.standard.array(forKey: "pillTopRight") as? [Double], position.count == 2 {
            topRight = NSPoint(x: position[0], y: position[1]); clampAnchor()
        } else { resetPosition() }
        layout(expanded: false)
        panel.orderFrontRegardless()
        reconcileDisplayPills()
        createMenu()
        registerHotKey()
        store.$presentation.map(\.expanded).removeDuplicates().sink { [weak self] expanded in
            self?.showShelf(expanded)
        }.store(in: &subscriptions)
        store.$activeSessionActionsID.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateHover() }
        }.store(in: &subscriptions)
        store.$pillOnEveryDisplay.dropFirst().removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.reconcileDisplayPills() }
        }.store(in: &subscriptions)
        store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateMenuTitle() }
        }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(self, selector: #selector(resetPosition), name: .resetShelf, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
        store.completedReplies.sink { [weak self] sessions in
            guard let self, !self.store.expanded, !self.dragging else { return }
            self.presentReplyBanners(sessions)
        }.store(in: &subscriptions)
        store.$sessions.sink { [weak self] sessions in
            self?.replyBanners.dismissAnswered(in: sessions)
        }.store(in: &subscriptions)
        store.$replyBannersEnabled.dropFirst().filter { !$0 }.sink { [weak self] _ in
            self?.replyBanners.dismissAll()
        }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(self, selector: #selector(previewReplyBanner), name: .previewReplyBanner, object: nil)
        store.start()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { toggle(); return true }
    private func displayID(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return screen.localizedName }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return number.stringValue
    }
    private func screen(at anchor: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSPoint(x: anchor.x - 30, y: anchor.y - 58)) }
    }
    private func makePillPanel() -> ShelfPanel {
        let window = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "Pulse"; window.identifier = NSUserInterfaceItemIdentifier("PulsePanel")
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ShelfPillView(store: store,
            onHover: { [weak self, weak window] inside in
                guard let self, let window else { return }
                if inside { _ = self.activatePill(window) }
                guard self.panel === window else { return }
                self.pillHovered = inside
                self.updateHover()
            },
            onClick: { [weak self, weak window] in
                guard let self, let window else { return }
                self.replyBanners.dismissAll()
                _ = self.activatePill(window)
                guard self.panel === window else { return }
                self.togglePill()
            },
            onDragChange: { [weak self, weak window] active in
                guard let self, let window else { return nil }
                if active {
                    self.store.activeSessionActionsID = nil
                    _ = self.activatePill(window)
                }
                guard self.panel === window else { return nil }
                self.setDragging(active)
                return self.panel
            }))
        return window
    }
    /// All pills share one store and one scanner. Move the existing session panel to the chosen pill.
    @discardableResult private func activatePill(_ window: ShelfPanel) -> Bool {
        guard panel !== window, !dragging, store.activeSessionActionsID == nil else { return false }
        hoverTask?.cancel()
        savePosition()
        animationGeneration += 1
        panel.removeChildWindow(shelfPanel)
        shelfPanel.orderOut(nil)
        panel = window
        topRight = NSPoint(x: window.frame.maxX, y: window.frame.maxY)
        pillHovered = false; shelfHovered = false
        panel.addChildWindow(shelfPanel, ordered: .below)
        layout(expanded: store.expanded)
        if store.expanded { showShelf(true) }
        savePosition()
        return true
    }
    private func reconcileDisplayPills() {
        guard panel != nil, shelfPanel != nil, !dragging,
              let activeScreen = screen(at: topRight) ?? NSScreen.main else { return }
        let activeID = displayID(activeScreen)
        // A drag can cross onto a display that already has a pill. Move that spare back
        // to the source display, keeping exactly one pill on each connected display.
        if let oldID = displayPills.first(where: { $0.value === panel })?.key, oldID != activeID {
            displayPills.removeValue(forKey: oldID)
            if let spare = displayPills.removeValue(forKey: activeID) {
                if store.pillOnEveryDisplay, let oldScreen = NSScreen.screens.first(where: { displayID($0) == oldID }) {
                    let anchor = displayPositions.anchor(displayID: oldID, screen: oldScreen.visibleFrame)
                    spare.setFrame(ShelfPlacement(anchor: anchor, screen: oldScreen.visibleFrame).pillFrame, display: true)
                    displayPills[oldID] = spare
                } else { spare.close() }
            }
        }
        displayPills[activeID] = panel
        let screens = store.pillOnEveryDisplay ? NSScreen.screens : [activeScreen]
        let wanted = Set(screens.map(displayID))
        for id in Array(displayPills.keys) where !wanted.contains(id) {
            displayPills.removeValue(forKey: id)?.close()
        }
        for screen in screens {
            let id = displayID(screen)
            if id == activeID { continue }
            let pill = displayPills[id] ?? makePillPanel()
            let anchor = displayPositions.anchor(displayID: id, screen: screen.visibleFrame)
            pill.setFrame(ShelfPlacement(anchor: anchor, screen: screen.visibleFrame).pillFrame, display: true)
            displayPills[id] = pill
            pill.orderFrontRegardless()
        }
        panel.orderFrontRegardless()
        savePosition()
    }
    private func presentReplyBanners(_ sessions: [Session], preview: Bool = false) {
        if store.replyBannerDuration == .untilClicked { hoverTask?.cancel() }
        let placements = NSScreen.screens.map { screen in
            let id = displayID(screen)
            let pill = displayPills[id]?.frame ?? ShelfPlacement(
                anchor: displayPositions.anchor(displayID: id, screen: screen.visibleFrame),
                screen: screen.visibleFrame).pillFrame
            return ReplyBannerPlacement(pill: pill, screen: screen.visibleFrame)
        }
        replyBanners.enqueue(sessions, placements: placements, duration: store.replyBannerDuration, preview: preview) { [weak self] session in
            guard let self else { return }
            if session.nativeID.hasPrefix("banner-preview") { self.store.presentation.show() }
            else { self.store.open(session) }
        }
    }
    @objc private func previewReplyBanner() {
        guard store.replyBannersEnabled else { return }
        let sample = Session(provider: .codex, nativeID: "banner-preview", title: "Your agent’s reply is ready", project: "Pulse", updatedAt: Date(), state: .ready,
                             lastUserMessage: "Click a reply banner to return to its conversation.")
        store.presentation.dismiss()
        let second = Session(provider: .claude, nativeID: "banner-preview-claude", title: "Another conversation finished", project: "Pulse", updatedAt: Date(), state: .ready,
                             lastUserMessage: "Each chat gets its own banner. New replies update that chat’s card.")
        presentReplyBanners([second, sample], preview: true)
    }
    private func updateHover() {
        hoverTask?.cancel()
        guard !dragging, store.activeSessionActionsID == nil, !replyBanners.holdsUntilClicked else { return }
        let inside = pillHovered || shelfHovered
        store.presentation.pointerChanged(inside: inside)
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(inside ? 160 : 550))
            guard !Task.isCancelled, let self else { return }
            self.store.presentation.applyHover(inside: inside)
        }
    }
    private func layout(expanded: Bool) {
        guard panel != nil, shelfPanel != nil, !dragging else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: topRight.x - 10, y: topRight.y - 10)) } ?? NSScreen.main
        let available = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let placement = ShelfPlacement(anchor: topRight, screen: available)
        shelfRestingFrame = placement.shelfFrame
        resizing = true
        if panel.frame != placement.pillFrame { panel.setFrame(placement.pillFrame, display: true) }
        shelfPanel.setFrame(placement.shelfFrame, display: true)
        resizing = false
    }
    private func showShelf(_ expanded: Bool) {
        guard shelfPanel != nil, !dragging else { return }
        if expanded { replyBanners.dismissAll() }
        if !expanded { store.activeSessionActionsID = nil }
        animationGeneration += 1
        let generation = animationGeneration
        let wasVisible = shelfPanel.isVisible
        if !wasVisible { layout(expanded: expanded) }
        let target = shelfRestingFrame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let offset: CGFloat = reduceMotion ? 0 : (target.midX < panel.frame.midX ? 6 : -6)
        if expanded {
            if !wasVisible {
                shelfPanel.setFrame(target.offsetBy(dx: offset, dy: 0), display: false)
                shelfPanel.alphaValue = 0
            }
            shelfPanel.ignoresMouseEvents = false
            shelfPanel.orderFrontRegardless()
        } else { shelfPanel.ignoresMouseEvents = true }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.10 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            shelfPanel.animator().alphaValue = expanded ? 1 : 0
            shelfPanel.animator().setFrame(expanded ? target : target.offsetBy(dx: offset, dy: 0), display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.animationGeneration == generation else { return }
                if !expanded { self.shelfPanel.orderOut(nil); self.shelfPanel.setFrame(target, display: false) }
            }
        }
    }
    private func clampAnchor() {
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(NSPoint(x: topRight.x - 30, y: topRight.y - 30)) }) else {
            resetPosition(); return
        }
        topRight.x = min(screen.visibleFrame.maxX, max(screen.visibleFrame.minX + ShelfPlacement.pillSize.width, topRight.x))
        topRight.y = min(screen.visibleFrame.maxY, max(screen.visibleFrame.minY + ShelfPlacement.pillSize.height, topRight.y))
    }
    @objc func resetPosition() {
        guard let screen = NSScreen.main else { return }
        topRight = NSPoint(x: screen.visibleFrame.maxX - 18, y: screen.visibleFrame.maxY - 18)
        layout(expanded: store.expanded); savePosition(); reconcileDisplayPills()
    }
    @objc private func screenChanged() {
        replyBanners.dismissAll()
        guard !dragging else { return }
        let currentID = displayPills.first { $0.value === panel }?.key
        if let target = NSScreen.screens.first(where: { displayID($0) == currentID }) ?? NSScreen.main {
            topRight = displayPositions.anchor(displayID: displayID(target), screen: target.visibleFrame)
        }
        clampAnchor(); layout(expanded: store.expanded); reconcileDisplayPills()
    }
    @objc private func wokeUp() {
        store.refresh()
        screenChanged()
        for pill in displayPills.values { pill.orderFrontRegardless() }
    }
    func windowDidMove(_ notification: Notification) {
        guard !resizing, notification.object as? NSWindow === panel else { return }
        guard !dragging else { return }
        topRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        savePosition(); layout(expanded: store.expanded); reconcileDisplayPills()
    }
    private func setDragging(_ active: Bool) {
        hoverTask?.cancel()
        if active {
            replyBanners.dismissAll()
            dragging = true
            panel.followsDragPointer = true
            joinWindowsForDrag()
        } else {
            separateWindowsAfterDrag()
            panel.followsDragPointer = false
            dragging = false
            topRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
            clampAnchor(); layout(expanded: store.expanded); savePosition(); reconcileDisplayPills()
        }
    }
    private func joinWindowsForDrag() {
        guard store.expanded, shelfPanel.isVisible,
              let pillView = panel.contentView, let shelfView = shelfPanel.contentView else { return }
        animationGeneration += 1
        let geometry = ShelfDragLayout(pill: panel.frame, shelf: shelfPanel.frame)
        dragPresentation = DragPresentation(geometry: geometry, pillView: pillView, shelfView: shelfView,
                                           pillAutoresizing: pillView.autoresizingMask, shelfAutoresizing: shelfView.autoresizingMask)
        panel.disableScreenUpdatesUntilFlush()
        shelfPanel.disableScreenUpdatesUntilFlush()
        resizing = true
        panel.removeChildWindow(shelfPanel)
        shelfPanel.orderOut(nil)
        shelfPanel.contentView = nil
        panel.contentView = nil
        panel.setFrame(geometry.windowFrame, display: false)
        let container = NSView(frame: NSRect(origin: .zero, size: geometry.windowFrame.size))
        pillView.autoresizingMask = []; shelfView.autoresizingMask = []
        pillView.frame = geometry.pillInWindow
        shelfView.frame = geometry.shelfInWindow
        container.addSubview(shelfView); container.addSubview(pillView)
        panel.contentView = container
        panel.displayIfNeeded()
        resizing = false
    }
    private func separateWindowsAfterDrag() {
        guard let presentation = dragPresentation else { return }
        let origin = panel.frame.origin
        let pillFrame = presentation.geometry.pillFrame(windowOrigin: origin)
        let shelfFrame = presentation.geometry.shelfFrame(windowOrigin: origin)
        panel.disableScreenUpdatesUntilFlush()
        shelfPanel.disableScreenUpdatesUntilFlush()
        resizing = true
        presentation.pillView.removeFromSuperview(); presentation.shelfView.removeFromSuperview()
        panel.contentView = nil
        panel.setFrame(pillFrame, display: false)
        presentation.pillView.autoresizingMask = presentation.pillAutoresizing
        panel.contentView = presentation.pillView
        shelfPanel.setFrame(shelfFrame, display: false)
        presentation.shelfView.autoresizingMask = presentation.shelfAutoresizing
        shelfPanel.contentView = presentation.shelfView
        shelfRestingFrame = shelfFrame
        panel.addChildWindow(shelfPanel, ordered: .below)
        shelfPanel.alphaValue = store.expanded ? 1 : 0
        if store.expanded { shelfPanel.orderFrontRegardless() }
        dragPresentation = nil
        resizing = false
    }
    private func savePosition() {
        UserDefaults.standard.set([topRight.x, topRight.y], forKey: "pillTopRight")
        if let screen = screen(at: topRight) {
            displayPositions.record(anchor: topRight, displayID: displayID(screen), screen: screen.visibleFrame)
            if let data = try? JSONEncoder().encode(displayPositions) {
                UserDefaults.standard.set(data, forKey: "displayPillPositionsV1")
            }
        }
    }
    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = CometPoseAtlas.image(.ready).copy() as? NSImage {
            image.size = NSSize(width: 20, height: 20)
            statusItem.button?.image = image
        }
        statusItem.button?.toolTip = "Pulse"
        let menu = NSMenu()
        add("Show Pulse", action: #selector(toggle), to: menu)
        add("Connections & setup", action: #selector(connections), to: menu)
        add("Reset pill position", action: #selector(resetPosition), to: menu)
        let sounds = NSMenuItem(title: "Play sound when a reply is ready", action: #selector(toggleSounds(_:)), keyEquivalent: "")
        sounds.target = self; sounds.state = store.soundsEnabled ? .on : .off; menu.addItem(sounds)
        soundMenuItem = sounds
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Launch at login", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off; menu.addItem(login)
        menu.addItem(.separator())
        add("Quit Pulse", action: #selector(quit), to: menu)
        statusItem.menu = menu
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu) { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item) }
    private func updateMenuTitle() {
        soundMenuItem?.state = store.soundsEnabled ? .on : .off
        statusItem.button?.title = store.attentionCount > 0 ? " \(store.attentionCount)" : ""
        statusItem.button?.toolTip = "\(store.runningCount) working · \(store.attentionCount) waiting today · top-level sessions"
    }
    private func togglePill() {
        hoverTask?.cancel()
        store.presentation.clickPill(keepOpen: store.clickPillToKeepOpen)
        panel.orderFrontRegardless()
        if store.expanded { shelfPanel.makeKey() }
    }
    @objc func toggle() {
        replyBanners.dismissAll()
        hoverTask?.cancel()
        if !store.expanded, store.pillOnEveryDisplay,
           let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }),
           let pill = displayPills[displayID(screen)] { activatePill(pill) }
        store.presentation.toggleVisibility()
        panel.orderFrontRegardless()
        if store.expanded { shelfPanel.makeKey() }
    }
    @objc private func connections() { store.showConnections = true; store.presentation.show(); shelfPanel.makeKeyAndOrderFront(nil) }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
    @objc private func toggleSounds(_ item: NSMenuItem) {
        store.toggleSounds()
        item.state = store.soundsEnabled ? .on : .off
    }
    @objc private func toggleLogin(_ item: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        } catch { store.error = "Launch at login: \(error.localizedDescription)"; store.presentation.show() }
    }
    private func registerHotKey() {
        let handler: EventHandlerUPP = { _, _, context in
            guard let context else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { delegate.toggle() }
            return noErr
        }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: 0x41534846, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }
}
