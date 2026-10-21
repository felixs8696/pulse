import AppKit
import PulseCore

/// A shareable scan report. Never prints session content, IDs, paths, or raw errors.
enum ScanDiagnostics {
    static func run() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        print("Pulse \(version) scan health")
        print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #if arch(arm64)
        print("Architecture: Apple Silicon")
        #else
        print("Architecture: Intel")
        #endif
        for (name, bundle) in [("Codex", "com.openai.codex"), ("Cursor", "com.todesktop.230313mzl4w4u92"), ("iTerm", "com.googlecode.iterm2")] {
            print("\(name) running: \(!NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty)")
        }
        print("Window: past 7 days. No chat content included. iTerm automation is not requested.")
        print("Claude hook setup: \(ClaudeConnection.inspect())")
        let lock = NSLock()
        let completed = DispatchGroup()
        let start = Date()
        let coordinator = SessionScanCoordinator()
        for _ in Provider.allCases { completed.enter() }
        coordinator.refresh { event in
            lock.lock(); defer { lock.unlock() }
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
            switch event {
            case .started(let provider): print("\(provider.label): started")
            case .slow(let provider): print("\(provider.label): still scanning at \(elapsed)")
            case .finished(let result):
                for source in result.sources {
                    let routed = result.sessions.filter { $0.provider == source.provider && $0.hasOpenDestination }.count
                    print("\(source.provider.label): \(source.available ? "readable" : "unavailable"), \(source.count) sessions, \(routed) with a known route, \(elapsed)")
                }
                completed.leave()
            }
        }
        if completed.wait(timeout: .now() + 20) == .timedOut {
            print("Timed out after 20 seconds. Sources without a result are still scanning.")
        } else {
            print("All source checks finished.")
        }
    }
}
