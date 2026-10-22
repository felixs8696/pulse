import SwiftUI
import PulseCore

private enum Ink {
    static let text = Color(red: 238/255, green: 239/255, blue: 244/255)
    static let muted = Color(red: 152/255, green: 155/255, blue: 169/255)
    static let accent = Color(red: 187/255, green: 166/255, blue: 244/255)
    static let surface = Color(red: 20/255, green: 21/255, blue: 26/255)
    static let raised = Color(red: 36/255, green: 38/255, blue: 46/255)
    // Lavender signals activity; soft white signals attention.
    static let working = accent
    static let workingSubtle = accent.opacity(0.13)
    static let success = Color(red: 146/255, green: 207/255, blue: 176/255)
    static let successSubtle = success.opacity(0.12)
    static let waiting = text
    static let waitingSubtle = text.opacity(0.07)
    static let neutral = Color(white: 0.60)
    static let neutralSubtle = neutral.opacity(0.12)
    static let rule = Color.white.opacity(0.08)
}

extension Provider {
    var tint: Color { switch self { case .claude: return Color(red: 0.86, green: 0.66, blue: 0.52); case .codex: return Color(red: 0.57, green: 0.72, blue: 0.96); case .cursor: return Color(red: 0.76, green: 0.70, blue: 0.92) } }
}

/// Brand artwork is bundled offline; monochrome marks select the supplied contrast variant.
private struct ProviderLogo: View {
    let provider: Provider
    var size: CGFloat = 20
    @Environment(\.colorScheme) private var colorScheme
    private var asset: String {
        let mode = colorScheme == .dark ? "dark" : "light"
        switch provider {
        case .claude: return "claude"
        case .cursor: return "cursor-" + mode
        case .codex: return "openai-" + mode
        }
    }
    var body: some View {
        Group {
            if let artwork = BrandArtwork.image(asset) {
                Image(nsImage: artwork).resizable().renderingMode(.original).scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(provider == .codex ? "OpenAI" : provider.label)
    }
}

private struct SessionLogo: View {
    let session: Session
    let workingBrightness: Double

    private var isClaudeInCursor: Bool {
        session.provider == .claude && (session.route?.kind == .cursorClaude || session.route?.kind == .cursorTerminal)
    }

    var body: some View {
        ProviderLogo(provider: isClaudeInCursor ? .cursor : session.provider)
            .frame(width: 30, height: 30)
            .background((isClaudeInCursor ? Provider.cursor : session.provider).tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            .overlay(alignment: .bottomTrailing) {
                if isClaudeInCursor {
                    ProviderLogo(provider: .claude, size: 10)
                        .frame(width: 15, height: 15)
                        .background(Ink.raised, in: Circle())
                        .overlay(Circle().strokeBorder(Ink.rule, lineWidth: 0.7))
                        .offset(x: 3, y: 3)
                }
            }
            .opacity(session.state == .running ? workingBrightness : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isClaudeInCursor ? "Claude Code in Cursor" : (session.provider == .codex ? "OpenAI" : session.provider.label))
    }
}
extension AgentState {
    var tint: Color {
        switch self { case .running: return Ink.working; case .waiting: return Ink.waiting; case .ready: return Ink.success; case .idle, .unknown: return Ink.neutral }
    }
    var badgeBackground: Color {
        switch self {
        case .running: return Ink.workingSubtle
        case .waiting: return Ink.waitingSubtle
        case .ready: return Ink.successSubtle
        case .idle, .unknown: return Ink.neutralSubtle
        }
    }
    var compactLabel: String {
        switch self {
        case .running: return "Working"
        case .waiting: return "Waiting"
        case .ready: return "Ready"
        case .idle: return "Idle"
        case .unknown: return "Unknown"
        }
    }
}

/// Compact semantic labels for tabs that mix session states.
private struct SessionStatusBadge: View {
    let session: Session
    var body: some View {
        Text(session.state.compactLabel.uppercased())
            .font(.system(size: 9, weight: .semibold)).tracking(0.4)
            .foregroundStyle(session.state.tint)
            .frame(width: 62, height: 18)
            .background(session.state.badgeBackground, in: RoundedRectangle(cornerRadius: 4))
            .help(session.state.label + " · " + session.detail)
            .accessibilityLabel(session.state.label)
    }
}

private struct ShelfIconButton: View {
    let symbol: String
    let label: String
    var selected = false
    var subdued = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? Ink.accent : Ink.muted)
                .opacity(subdued && !hovered ? 0.5 : 1)
                .frame(width: 12, height: 12)
                .frame(width: 26, height: 26)
                .background(.white.opacity(hovered ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
        .onHover { hovered = $0 }
    }
}

private struct SoundToggleButton: View {
    @ObservedObject var store: SessionStore
    var body: some View {
        Button { store.toggleSounds() } label: {
            Image(systemName: store.soundsEnabled ? "speaker.wave.2" : "speaker.slash")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.soundsEnabled ? Ink.text.opacity(0.75) : Ink.muted)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(store.soundsEnabled ? "Mute completion sounds" : "Turn on completion sounds · plays a preview")
        .accessibilityLabel("Completion sounds")
        .accessibilityValue(store.soundsEnabled ? "On" : "Muted")
    }
}

struct ShelfView: View {
    @ObservedObject var store: SessionStore
    var onHover: (Bool) -> Void
    var onDragChange: (Bool) -> NSWindow?
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            header
            if store.showConnections { connections }
            else if store.needsClaudeConnection { claudeConnectionCard }
            search
            filters
            Divider().overlay(Ink.rule).padding(.top, 14)
            ShelfSessionList(store: store, onDragChange: onDragChange)
                // Navigation replaces the list immediately. Only live changes within
                // the same scope participate in departure/reordering animations.
                .id([store.filter.rawValue, store.provider?.rawValue ?? "", store.query])
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DragHandle(onClick: {}, onDragChange: onDragChange))
        .background {
            RoundedRectangle(cornerRadius: 22).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22).fill(Ink.surface.opacity(0.96)))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.12), lineWidth: 0.7))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .foregroundStyle(Ink.text)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .onHover(perform: onHover)
        .onExitCommand { store.presentation.dismiss() }
        .alert("Couldn’t open session", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 12) {
                PulseLogo().frame(width: 28, height: 21)
                Text("Pulse").font(BrandArtwork.titleFont(size: 21))
                    .tracking(-0.4).foregroundStyle(Ink.muted).fixedSize()
                Spacer()
            }
            .overlay(DragHandle(onClick: {}, onDragChange: onDragChange))
            SoundToggleButton(store: store)
            Menu {
                Button(store.showConnections ? "Hide connections" : "Connections & setup") { store.showConnections.toggle(); store.presentation.show() }
                Button(store.claudeConnection == .installed ? "Repair Claude connection" : "Connect Claude Code") { store.connectClaude() }
                    .disabled(store.connectingClaude || store.claudeConnection == .disabled)
                Toggle("Automatically connect Claude Code", isOn: $store.automaticClaudeSetup)
                Button("Mark displayed replies read") { store.markDisplayedRead() }
                Button("Refresh now") { store.refresh() }
                Divider()
                Toggle("Show reply banners", isOn: $store.replyBannersEnabled)
                if store.replyBannersEnabled {
                    Picker("Banner duration", selection: $store.replyBannerDuration) {
                        ForEach(ReplyBannerDuration.allCases, id: \.self) { duration in
                            Text(duration.label).tag(duration)
                        }
                    }.pickerStyle(.menu)
                    Button("Preview reply banner") { NotificationCenter.default.post(name: .previewReplyBanner, object: nil) }
                }
                Toggle("Click pill to keep panel open", isOn: $store.clickPillToKeepOpen)
                Toggle("Show pill on every display", isOn: $store.pillOnEveryDisplay)
                Button("Reset pill position") { NotificationCenter.default.post(name: .resetShelf, object: nil) }
                Button("Quit Pulse", role: .destructive) { NSApplication.shared.terminate(nil) }
            } label: { Image(systemName: "ellipsis").foregroundStyle(Ink.muted).frame(width: 26, height: 26) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        }
        .buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 17)
    }
    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Ink.muted)
            TextField("Find a session or project…", text: $store.query).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
            if !store.query.isEmpty { Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.muted) }.buttonStyle(.plain) }
            Menu {
                Button("All apps") { store.provider = nil }
                ForEach(Provider.allCases, id: \.self) { provider in Button(provider.label) { store.provider = provider } }
            } label: { Text(store.provider?.label ?? "All apps").font(.system(size: 10)).foregroundStyle(Ink.muted) }
                .menuStyle(.borderlessButton).fixedSize()
        }.padding(.horizontal, 11).padding(.vertical, 10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 18)
    }
    private var filters: some View {
        HStack(spacing: 5) {
            ForEach(ShelfFilter.allCases, id: \.self) { filter in
                if filter == .all { Spacer(minLength: 0) }
                Button { store.filter = filter } label: {
                    HStack(spacing: 4) {
                        Text(filter.rawValue)
                        if filter == .pinned { Text("\(store.matchingPinnedCount)").foregroundStyle(Ink.accent).monospacedDigit() }
                        if filter == .attention { Text("\(store.matchingAttentionCount)").foregroundStyle(Ink.waiting).monospacedDigit() }
                        if filter == .running && store.matchingRunningCount > 0 {
                            Text("\(store.matchingRunningCount)").foregroundStyle(Ink.working).monospacedDigit()
                        }
                    }.font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 7)
                        .background(store.filter == filter ? Color.white.opacity(0.09) : .clear, in: Capsule())
                        .foregroundStyle(store.filter == filter ? Ink.text : Ink.muted)
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 18).padding(.top, 12)
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Text("⌃ Space").font(.system(size: 10, weight: .medium, design: .monospaced))
            Text("to show or hide").font(.system(size: 10))
            Spacer()
        }.font(.system(size: 10)).foregroundStyle(Ink.muted).padding(.horizontal, 20).padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(Ink.rule).frame(height: 1) }
    }
    private var connections: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.sources, id: \.provider) { source in
                VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ProviderLogo(provider: source.provider, size: 14).frame(width: 16)
                    Text(source.provider.label)
                    Spacer()
                    Text(source.available ? "\(source.count) sessions" : "Unavailable").foregroundStyle(source.available ? Ink.muted : Ink.waiting)
                }.font(.system(size: 11)).help(source.message)
                    if !source.available { Text(source.message).font(.system(size: 10)).foregroundStyle(Ink.waiting).fixedSize(horizontal: false, vertical: true) }
                }
            }
            claudeConnectionContent
        }.padding(12).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 18).padding(.bottom, 12)
    }
    private var claudeConnectionCard: some View {
        claudeConnectionContent.padding(12)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 18).padding(.bottom, 12)
    }
    private var claudeConnectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.claudeConnection == .installed && store.claudeConnectionError == nil {
                Text(store.claudeConnectionHint ?? "Claude hooks installed. Keep using your current chats to connect their live panes.")
                    .font(.system(size: 11)).foregroundStyle(Ink.muted)
            } else if store.claudeConnection == .disabled {
                Text("Claude hooks are disabled in your Claude settings. Enable them in Claude to connect your live chats.")
                    .font(.system(size: 11)).foregroundStyle(Ink.muted)
            } else {
                HStack(spacing: 8) {
                    Text("Connect your Claude chats").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 4)
                    Button(store.connectingClaude ? "Connecting…" : "Connect Claude Code") { store.connectClaude() }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.bordered).tint(Ink.accent).disabled(store.connectingClaude)
                }
                Text("Adds local hooks for live panes and reply alerts. Backs up your Claude settings and keeps existing hooks. Your chats stay open.")
                    .font(.system(size: 10)).foregroundStyle(Ink.muted)
            }
            if let error = store.claudeConnectionError {
                Text(error).font(.system(size: 10)).foregroundStyle(Ink.waiting)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

private struct ShelfSessionList: View {
    @ObservedObject var store: SessionStore
    let onDragChange: (Bool) -> NSWindow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var rowMotion
    @State private var listPresentation: SessionListPresentation

    init(store: SessionStore, onDragChange: @escaping (Bool) -> NSWindow?) {
        self.store = store
        self.onDragChange = onDragChange
        var presentation = SessionListPresentation()
        presentation.reset(to: store.filtered)
        _listPresentation = State(initialValue: presentation)
    }

    var body: some View {
        let targetSessions = store.filtered
        let sessions = listPresentation.rows
        let animateWorking = store.expanded && !reduceMotion && sessions.contains { $0.state == .running }
        return GeometryReader { viewport in
            ScrollView {
                // One render timeline owns the entire list. Logos never update their
                // placement on independent timelines while hooks reorder their rows.
                TimelineView(.animation(minimumInterval: 1 / 30, paused: !animateWorking)) { timeline in
                    let phase = timeline.date.timeIntervalSinceReferenceDate / 2.6 * 2 * Double.pi
                    let brightness = animateWorking ? 0.38 + 0.62 * (0.5 + 0.5 * cos(phase)) : 1
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if store.filter == .attention && store.hasScope {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(store.matchingAttentionCount) matching · \(store.attentionCount) total today")
                                    .font(.system(size: 11)).foregroundStyle(Ink.muted)
                                Button("Show all \(store.attentionCount) sessions needing you") { store.showAllNeedsYou() }
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.accent).buttonStyle(.plain)
                            }.padding(.horizontal, 10).padding(.top, 14).padding(.bottom, 4)
                        }
                        if !sessions.isEmpty {
                            ForEach(sessions) { session in
                                if store.filter != .running,
                                   session.id == sessions.first?.id ||
                                    (store.isRead(session) && session.id == sessions.first(where: { store.isRead($0) })?.id) {
                                    Text(store.isRead(session) ? "Read" : "Unread")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Ink.muted)
                                        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 3)
                                }
                                SessionRow(session: session, store: store, workingBrightness: brightness)
                                    // Animate the whole row outside its content transaction,
                                    // keeping the icon pulse from animating text or controls.
                                    .matchedGeometryEffect(id: session.id, in: rowMotion, properties: .position)
                                    .opacity(listPresentation.exitingIDs.contains(session.id) ? 0 : 1)
                                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2),
                                               value: listPresentation.exitingIDs.contains(session.id))
                                    .allowsHitTesting(!listPresentation.exitingIDs.contains(session.id))
                                    .accessibilityHidden(listPresentation.exitingIDs.contains(session.id))
                                    .transition(reduceMotion ? .identity : .asymmetric(insertion: .opacity, removal: .identity))
                            }
                        }
                        if sessions.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: store.filter == .attention && !store.hasScope ? "checkmark.circle" : "magnifyingglass").font(.system(size: 27, weight: .ultraLight)).foregroundStyle(Ink.accent)
                                Text(emptyStateTitle).font(.system(size: 13, weight: .medium))
                                Text(emptyStateHint).font(.system(size: 11)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(.vertical, 72)
                        }
                    }
                    .animation(reduceMotion ? nil : .smooth(duration: 0.36, extraBounce: 0), value: sessions.map(\.id))
                    .frame(maxWidth: .infinity, minHeight: max(0, viewport.size.height - 16), alignment: .top)
                    .background(DragHandle(onClick: {}, onDragChange: onDragChange))
                    .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 10)
                }
            }
        }.frame(minHeight: 100, maxHeight: .infinity)
        .onChange(of: targetSessions) { _, next in
            if reduceMotion || !store.expanded { listPresentation.reset(to: next) }
            else { listPresentation.stage(next) }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { listPresentation.reset(to: store.filtered) }
        }
        .task(id: listPresentation.exitingIDs.sorted()) {
            guard !listPresentation.exitingIDs.isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            listPresentation.finishRemovals()
        }
    }
    private var emptyStateTitle: String {
        if !store.slowProviders.isEmpty && store.visibleBase.isEmpty { return "Some apps are taking longer" }
        if store.lastScan == nil { return "Finding your chats…" }
        if store.hasScope { return "No matching chats" }
        switch store.filter {
        case .attention: return "Nothing waiting on you right now"
        case .running: return "No agents working right now"
        case .pinned: return "Nothing pinned yet"
        case .older: return "No older chats yet"
        case .all: return "No chats here yet"
        }
    }
    private var emptyStateHint: String {
        if !store.slowProviders.isEmpty && store.visibleBase.isEmpty { return "Open Connections & setup in the top-right menu for details." }
        if store.lastScan == nil { return "Connecting to your agent apps." }
        if store.hasScope { return "Try another search or clear your filters." }
        switch store.filter {
        case .pinned: return "Pin a chat to keep it close."
        case .older: return "Past chats will appear here."
        case .attention, .running, .all: return "Start a chat with an agent to track it here."
        }
    }
}

private struct SessionRow: View {
    let session: Session
    @ObservedObject var store: SessionStore
    let workingBrightness: Double
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button { store.open(session) } label: {
                HStack(alignment: .top, spacing: 11) {
                    SessionLogo(session: session, workingBrightness: workingBrightness).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(session.title)
                                .font(.system(size: 12, weight: store.isRead(session) ? .regular : .semibold))
                                .opacity(store.isRead(session) && session.state != .running ? 0.72 : 1)
                                .lineLimit(2).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            TimelineView(.periodic(from: .now, by: 30)) { context in
                                Text(relative(session.updatedAt, now: context.date))
                                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Ink.muted.opacity(0.8))
                            }.fixedSize()
                        }
                        Text(session.lastUserMessage ?? "No user message available")
                            .font(.system(size: 11)).foregroundStyle(Ink.muted)
                            .opacity(store.isRead(session) && session.state != .running ? 0.75 : 1)
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            HStack(spacing: 8) {
                if store.filter != .running && store.filter != .attention {
                    SessionStatusBadge(session: session)
                }
                Button { store.open(session) } label: {
                    Text(session.hostLabel + " · " + session.projectName)
                        .font(.system(size: 9)).foregroundStyle(Ink.muted.opacity(0.8))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button {
                    store.activeSessionActionsID = store.activeSessionActionsID == session.id ? nil : session.id
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Ink.muted)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Session options")
                .accessibilityLabel("Options for \(session.title)")
                .popover(isPresented: Binding(
                    get: { store.activeSessionActionsID == session.id },
                    set: { if !$0 && store.activeSessionActionsID == session.id { store.activeSessionActionsID = nil } }
                ), arrowEdge: .bottom) {
                    SessionActions(session: session, store: store)
                }
                .padding(.trailing, -7)
            }.padding(.leading, 41)
        }
        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 8)
        .background(hover ? Color.white.opacity(0.035) : .clear, in: RoundedRectangle(cornerRadius: 12))
        .compositingGroup()
        .transaction { $0.animation = nil }
        .onHover { hover = $0 }
        .onDisappear {
            if store.activeSessionActionsID == session.id { store.activeSessionActionsID = nil }
        }
        .help("\(session.hostLabel) · \(session.project)\n\(session.lastUserMessage ?? "")\n\(session.detail)\n\(session.updatedAt.formatted(date: .abbreviated, time: .standard))")
        .contextMenu {
            Button("Open session") { store.open(session) }
            Button("Preview session sound") { store.previewSound(session) }
            Button("Change tone…") { store.activeSessionActionsID = session.id }
            Button(store.pins.contains(session.id) ? "Unpin" : "Pin") { store.togglePin(session) }
            if session.state.needsAttention {
                Button(store.isRead(session) ? "Mark unread" : "Mark read") { store.toggleRead(session) }
            }
            Button("Copy session ID") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(session.nativeID, forType: .string) }
            if let log = session.transcript { Button("Reveal session log") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: log)]) } }
        }
    }
    private func relative(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        if seconds < 86400 * 7 { return "\(seconds / 86400)d" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

private struct SessionActions: View {
    let session: Session
    @ObservedObject var store: SessionStore
    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button {
            perform()
            store.activeSessionActionsID = nil
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12))
            .foregroundStyle(Ink.text)
            .padding(.horizontal, 8).padding(.vertical, 7)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            action(store.pins.contains(session.id) ? "Unpin session" : "Pin session",
                   symbol: store.pins.contains(session.id) ? "pin.slash" : "pin") { store.togglePin(session) }
            if session.state.needsAttention {
                action(store.isRead(session) ? "Mark unread" : "Mark read",
                       symbol: store.isRead(session) ? "envelope" : "envelope.open") { store.toggleRead(session) }
            }
            Divider().padding(.vertical, 7)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Completion tone").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(store.tone(for: session))").monospacedDigit()
                        .font(.system(size: 12)).foregroundStyle(Ink.accent)
                }
                Slider(value: Binding(
                    get: { Double(store.tone(for: session)) },
                    set: { store.setTone(Int($0), for: session) }
                ), in: 1...100, step: 1, onEditingChanged: { editing in
                    if !editing { store.previewSound(session) }
                }) { Text("Completion tone") }
                .labelsHidden()
                .tint(Ink.accent)
                .accessibilityValue("\(store.tone(for: session)) out of 100")
                HStack {
                    Text("1 · Low")
                    Spacer()
                    Text("High · 100")
                }.font(.system(size: 10)).foregroundStyle(Ink.muted)
                HStack {
                    Button { store.previewSound(session) } label: {
                        Label("Preview", systemImage: "play.fill")
                    }
                    Spacer()
                    Button("Reset") {
                        store.setTone(nil, for: session)
                        store.previewSound(session)
                    }.disabled(!store.hasCustomTone(session))
                }.font(.system(size: 11)).buttonStyle(.borderless)
                Text(store.hasCustomTone(session) ? "Saved for this session" : "Automatic session tone")
                    .font(.system(size: 10)).foregroundStyle(Ink.muted)
            }.padding(.horizontal, 8).padding(.bottom, 5)
        }
        .padding(10).frame(width: 248)
        .foregroundStyle(Ink.text)
        .preferredColorScheme(.dark)
    }
}

struct ShelfPillView: View {
    @ObservedObject var store: SessionStore
    var onHover: (Bool) -> Void
    var onClick: () -> Void
    var onDragChange: (Bool) -> NSWindow?
    var body: some View {
        pillContent
            .contentShape(Capsule())
            .help("\(store.runningCount) working · \(store.attentionCount) waiting today. Hover to open; \(store.clickPillToKeepOpen ? "click to keep open or collapse" : "move away to collapse"); drag to move.")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pulse. \(store.runningCount) working, \(store.attentionCount) waiting today")
            .accessibilityValue(store.presentation.heldOpen ? "Kept open" : store.expanded ? "Hover preview" : "Collapsed")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onClick() }
            .overlay(DragHandle(onClick: onClick, onDragChange: onDragChange))
        .padding(12)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(Ink.text)
        .onHover(perform: onHover)
    }
    private var pillContent: some View {
        VStack(spacing: 9) {
            PulseLogo().frame(width: 21, height: 15)
            VStack(spacing: 3) {
                Text("\(store.runningCount)").foregroundStyle(Ink.working)
                Rectangle().fill(.white.opacity(0.14)).frame(width: 12, height: 1)
                Text("\(store.attentionCount)").foregroundStyle(store.attentionCount > 0 ? Ink.waiting : Ink.muted)
            }.font(.system(size: 11, weight: .medium, design: .monospaced)).monospacedDigit()
        }
        .frame(width: 36, height: 92)
        .background(Capsule().fill(.ultraThinMaterial).overlay(Capsule().fill(Ink.surface.opacity(0.96))))
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.7))
        .overlay(ActivityOrbit(sessionIDs: store.visibleBase.filter { $0.state == .running }.map(\.id).sorted()))
    }
}

struct DragHandle: NSViewRepresentable {
    var onClick: () -> Void
    var onDragChange: (Bool) -> NSWindow?
    func makeNSView(context: Context) -> Handle {
        let view = Handle(); view.onClick = onClick; view.onDragChange = onDragChange; return view
    }
    func updateNSView(_ view: Handle, context: Context) {
        view.onClick = onClick; view.onDragChange = onDragChange
    }
    final class Handle: NSView {
        var onClick: (() -> Void)?
        var onDragChange: ((Bool) -> NSWindow?)?
        private var startPointer = NSPoint.zero
        private var didDrag = false
        private var pointerDrag: ShelfPointerDrag?
        private var dragWindow: NSWindow?
        private func screenPointer(for event: NSEvent) -> NSPoint {
            // Sample the event itself, not the live cursor which can already be ahead
            // of queued input. Quartz uses the primary screen's top-left as its origin.
            if let point = event.cgEvent?.location, let primary = NSScreen.screens.first {
                return NSPoint(x: point.x, y: primary.frame.maxY - point.y)
            }
            return NSEvent.mouseLocation
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {
            startPointer = screenPointer(for: event)
            didDrag = false
            pointerDrag = nil
            dragWindow = nil
            // Joining the hosting views changes AppKit's mouse target. Keep ownership
            // of this gesture through mouse-up so release always separates the windows.
            while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                              until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if next.type == .leftMouseUp {
                    mouseUp(with: next)
                    return
                }
                mouseDragged(with: next)
            }
            if didDrag { pointerDrag = nil; _ = onDragChange?(false); dragWindow = nil }
        }
        override func mouseDragged(with event: NSEvent) {
            let point = screenPointer(for: event)
            let dx = point.x - startPointer.x, dy = point.y - startPointer.y
            guard didDrag || hypot(dx, dy) > 4 else { return }
            guard didDrag || window != nil else { return }
            if !didDrag {
                didDrag = true
                // Reparenting a hosting view can recreate its background handle.
                // Retain the controller's shared window for the entire gesture.
                dragWindow = onDragChange?(true) ?? window
                guard let dragWindow else { return }
                pointerDrag = ShelfPointerDrag(windowOrigin: dragWindow.frame.origin, pointer: startPointer)
            }
            // Use absolute screen coordinates on both axes. Native performDrag applies
            // vertical screen-edge behavior to the much taller combined window.
            if let pointerDrag { dragWindow?.setFrameOrigin(pointerDrag.windowOrigin(at: point)) }
        }
        override func mouseUp(with event: NSEvent) {
            if didDrag {
                if let pointerDrag { dragWindow?.setFrameOrigin(pointerDrag.windowOrigin(at: screenPointer(for: event))) }
                pointerDrag = nil
                _ = onDragChange?(false)
                dragWindow = nil
            } else { onClick?() }
        }
    }
}

/// A completion is an invitation to return to a conversation, not an acknowledgment.
struct ReplyBannerView: View {
    let session: Session
    let open: () -> Void
    let dismiss: () -> Void
    let hover: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 12) {
                    SessionLogo(session: session, workingBrightness: 1).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Reply ready").font(.system(size: 10, weight: .medium))
                            Spacer(minLength: 8)
                            Text(session.hostLabel).font(.system(size: 10)).lineLimit(1)
                        }.foregroundStyle(Ink.muted)
                        Text(session.title).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Ink.text).lineLimit(1)
                        Text(session.lastUserMessage ?? "Click to open the conversation")
                            .font(.system(size: 11)).foregroundStyle(Ink.muted).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Open reply: " + session.title)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Ink.muted).frame(width: 22, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Dismiss banner").accessibilityLabel("Dismiss banner")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18).fill(Ink.surface.opacity(0.94)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.13), lineWidth: 0.7))
        }
        .padding(12)
        .preferredColorScheme(.dark)
        .onHover(perform: hover)
    }
}
