import AppKit
import SwiftUI
import Combine
import Carbon
import QuartzCore
import ServiceManagement
import PulseCore

extension Notification.Name { static let resetShelf = Notification.Name("resetPulse") }

@main
enum PulseMain {
    static func main() {
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

final class ShelfPanel: NSPanel {
    var followsDragPointer = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // The combined window can cross a screen edge while its pill remains onscreen.
        // AppKit's vertical window constraints must not fight the pointer during a drag.
        followsDragPointer ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = SessionStore()
    private var panel: ShelfPanel!
    private var shelfPanel: ShelfPanel!
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
        panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Keep native controls in the same appearance when focus or drag tracking changes.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.title = "Pulse"; panel.identifier = NSUserInterfaceItemIdentifier("PulsePanel")
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: ShelfPillView(store: store,
            onHover: { [weak self] inside in self?.pillHovered = inside; self?.updateHover() },
            onClick: { [weak self] in self?.togglePill() },
            onDragChange: { [weak self] active in self?.setDragging(active); return self?.panel }))
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
        createMenu()
        registerHotKey()
        store.$presentation.map(\.expanded).removeDuplicates().sink { [weak self] expanded in
            self?.showShelf(expanded)
        }.store(in: &subscriptions)
        store.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateMenuTitle() }
        }.store(in: &subscriptions)
        NotificationCenter.default.addObserver(self, selector: #selector(resetPosition), name: .resetShelf, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
        store.start()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { toggle(); return true }
    private func updateHover() {
        hoverTask?.cancel()
        guard !dragging else { return }
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
        layout(expanded: store.expanded); savePosition()
    }
    @objc private func screenChanged() {
        guard !dragging else { return }
        clampAnchor(); layout(expanded: store.expanded)
    }
    @objc private func wokeUp() { store.refresh(); panel.orderFrontRegardless() }
    func windowDidMove(_ notification: Notification) {
        guard !resizing, notification.object as? NSWindow === panel else { return }
        guard !dragging else { return }
        topRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
        savePosition(); layout(expanded: store.expanded)
    }
    private func setDragging(_ active: Bool) {
        hoverTask?.cancel()
        if active {
            dragging = true
            panel.followsDragPointer = true
            joinWindowsForDrag()
        } else {
            separateWindowsAfterDrag()
            panel.followsDragPointer = false
            dragging = false
            topRight = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY)
            clampAnchor(); layout(expanded: store.expanded); savePosition()
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
    private func savePosition() { UserDefaults.standard.set([topRight.x, topRight.y], forKey: "pillTopRight") }
    private func createMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = BrandArtwork.image("pulse-mark")?.copy() as? NSImage {
            image.size = NSSize(width: 22, height: 15)
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
        store.presentation.clickPill()
        panel.orderFrontRegardless()
        if store.expanded { shelfPanel.makeKey() }
    }
    @objc func toggle() {
        hoverTask?.cancel()
        store.presentation.toggleVisibility()
        panel.orderFrontRegardless()
        if store.expanded { shelfPanel.makeKey() }
    }
    @objc private func connections() { store.showConnections = true; store.presentation.holdOpen(); shelfPanel.makeKeyAndOrderFront(nil) }
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
        } catch { store.error = "Launch at login: \(error.localizedDescription)"; store.presentation.holdOpen() }
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
