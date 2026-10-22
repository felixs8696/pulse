import AppKit
import SwiftUI
import PulseCore

extension Notification.Name {
    static let previewReplyBanner = Notification.Name("previewReplyBannerScreenshot")
 static let resetShelf = Notification.Name("resetPulseScreenshot") }

// Renders the actual app views with fictional data. No scanner, hooks, or personal
// session storage is used. This entry point exists only in a temporary docs build.
@main
enum ScreenshotMain {
    @MainActor
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let now = Date()
        UserDefaults(suiteName: "PulseDocumentationScreenshots")!.removePersistentDomain(forName: "PulseDocumentationScreenshots")
        let store = SessionStore()
        func session(_ provider: Provider, _ id: String, _ title: String, _ prompt: String,
                     _ state: AgentState, minutes: Double, route: SessionRoute? = nil) -> Session {
            Session(provider: provider, nativeID: id, title: title, project: "/projects/atlas",
                    updatedAt: now.addingTimeInterval(-minutes * 60), state: state,
                    detail: state == .running ? "Turn in progress" : "Finished its latest turn",
                    lastUserMessage: prompt, lastUserMessageAt: now.addingTimeInterval(-minutes * 60), route: route)
        }
        store.sessions = [
            session(.codex, "demo-search", "Make search feel instant",
                    "Add keyboard navigation and keep the results fast.", .running, minutes: 1),
            session(.cursor, "demo-tests", "Give the checkout flow a test run",
                    "Cover the happy path and a declined payment.", .running, minutes: 5),
            session(.claude, "demo-accessibility", "A more accessible command menu",
                    "Check focus order, contrast, and screen reader labels.", .ready, minutes: 8,
                    route: SessionRoute(.cursorClaude, workspace: "/projects/atlas")),
            session(.codex, "demo-release", "Write the release notes",
                    "Summarize what changed in a short, friendly changelog.", .ready, minutes: 12)
        ]
        store.pins = Set([store.sessions[0].id, store.sessions[3].id])
        store.lastScan = now
        // Rendering does not start the store's live scanner or completion sounds.
        store.filter = .all
        try render(store, style: .overview, to: output.appendingPathComponent("overview.png"))
        store.filter = .attention
        try render(store, style: .panel, to: output.appendingPathComponent("waiting.png"))
        store.filter = .pinned
        try render(store, style: .panel, to: output.appendingPathComponent("pinned.png"))
        print("Rendered sample screenshots to \(output.path)")
    }

    enum Style { case overview, panel }

    @MainActor
    static func render(_ store: SessionStore, style: Style, to url: URL) throws {
        let size = NSSize(width: style == .overview ? 664 : 500,
                          height: style == .overview ? 728 : 580)
        let pixels = NSSize(width: size.width * 2, height: size.height * 2)
        let view = NSHostingView(rootView: ScreenshotStage(store: store, overview: style == .overview)
            .frame(width: size.width, height: size.height)
            .scaleEffect(2, anchor: .topLeading)
            .frame(width: pixels.width, height: pixels.height, alignment: .topLeading))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: pixels),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: pixels)
        view.layoutSubtreeIfNeeded()
        // Let SwiftUI resolve lists and bundled SVGs before caching the native view.
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        view.layoutSubtreeIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = pixels
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
        window.contentView = nil
    }
}

private struct ScreenshotStage: View {
    @ObservedObject var store: SessionStore
    let overview: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.91, green: 0.90, blue: 0.96),
                                    Color(red: 0.81, green: 0.80, blue: 0.89)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            ShelfView(store: store, onHover: { _ in }, onDragChange: { _ in nil })
                .frame(width: 436, height: overview ? 664 : 516)
                .shadow(color: .black.opacity(0.17), radius: 16, y: 10)
                .offset(x: overview ? 76 : 32, y: 32)
            if overview {
                ShelfPillView(store: store, onHover: { _ in }, onClick: {}, onDragChange: { _ in nil })
                    .frame(width: 60, height: 116)
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
                    .offset(x: 498, y: 32)
            }
        }
        .clipped()
    }
}
