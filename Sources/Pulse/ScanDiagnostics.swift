import AppKit
import PulseCore

/// A shareable scan report. Never prints session content, IDs, paths, or raw errors.
enum ScanDiagnostics {
    private final class ReportBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) { lock.lock(); defer { lock.unlock() }; lines.append(line) }
        func text() -> String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") + "\n" }
    }

    static func run() { print(report(), terminator: "") }

    static func report() -> String {
        let buffer = ReportBuffer()
        @Sendable func emit(_ line: String) { buffer.append(line) }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        emit("Pulse \(version) scan health")
        emit("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #if arch(arm64)
        emit("Architecture: Apple Silicon")
        #else
        emit("Architecture: Intel")
        #endif
        for (name, bundle) in [("Codex", "com.openai.codex"), ("Cursor", "com.todesktop.230313mzl4w4u92"), ("iTerm", "com.googlecode.iterm2")] {
            emit("\(name) running: \(!NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty)")
        }
        emit("Window: past 7 days. No chat content included. iTerm automation is not requested.")
        emit("Claude hook setup: \(ClaudeConnection.inspect())")
        let tools = Process()
        tools.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        tools.arguments = ["-p"]
        let output = Pipe()
        tools.standardOutput = output
        tools.standardError = FileHandle.nullDevice
        var pythonAvailable = false
        if (try? tools.run()) != nil {
            let directory = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            tools.waitUntilExit()
            pythonAvailable = tools.terminationStatus == 0 && FileManager.default.isExecutableFile(atPath: directory + "/usr/bin/python3")
        }
        emit("Claude setup Python available: \(pythonAvailable)")
        let lock = NSLock()
        let completed = DispatchGroup()
        let start = Date()
        let coordinator = SessionScanCoordinator()
        for _ in Provider.allCases { completed.enter() }
        coordinator.refresh { event in
            lock.lock(); defer { lock.unlock() }
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(start))
            switch event {
            case .started(let provider): emit("\(provider.label): started")
            case .slow(let provider): emit("\(provider.label): still scanning at \(elapsed)")
            case .finished(let result):
                for source in result.sources {
                    let routed = result.sessions.filter { $0.provider == source.provider && $0.hasOpenDestination }.count
                    emit("\(source.provider.label): \(source.available ? "readable" : "unavailable"), \(source.count) sessions, \(routed) with a known route, \(elapsed)")
                }
                completed.leave()
            }
        }
        if completed.wait(timeout: .now() + 20) == .timedOut {
            emit("Timed out after 20 seconds. Sources without a result are still scanning.")
        } else {
            emit("All source checks finished.")
        }
        return buffer.text()
    }
}
