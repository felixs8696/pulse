import AppKit
import PulseCore

enum LaunchError: LocalizedError {
    case failed(String)
    case closedTerminal
    case unavailableDestination
    var errorDescription: String? { switch self {
    case .failed(let s): return s
    case .closedTerminal: return "The original terminal pane has closed."
    case .unavailableDestination: return "The session's original app or destination is unavailable."
    } }
}

@MainActor
enum SessionLauncher {
    static func open(_ session: Session) async throws {
        guard session.hasOpenDestination else { throw LaunchError.unavailableDestination }
        if var url = session.deepLink {
            if let pid = session.route?.ownerPID, pid > 0,
               let windowID = await cursorWindow(containing: pid) {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "windowId", value: String(windowID))]
                url = components.url!
            }
            if session.route?.kind == .cursorClaude || session.route?.kind == .cursorTerminal {
                // The matching window consumes this even when Cursor delays URI dispatch.
                let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/local.pulse-router")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let request: [String: Any] = ["id": session.nativeID,
                    "folder": session.route?.workspace ?? session.project,
                    "kind": session.route?.kind == .cursorTerminal ? "terminal" : "claude",
                    "pids": session.route?.terminalPIDs ?? [], "createdAt": Date().timeIntervalSince1970 * 1000]
                try JSONSerialization.data(withJSONObject: request).write(to: directory.appendingPathComponent("pending-open.json"), options: .atomic)
            }
            NSLog("Pulse opening %@", url.absoluteString)
            guard NSWorkspace.shared.open(url) else { throw LaunchError.unavailableDestination }
            return
        }
        guard session.route?.kind == .iTerm else {
            throw LaunchError.unavailableDestination
        }
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").isEmpty else {
            throw LaunchError.closedTerminal
        }
        if let terminal = session.terminalID, !terminal.isEmpty {
            let id = TerminalPresence.paneID(terminal)
            do {
                try await appleScript(focusScript, arguments: [id]); return
            } catch {
                if error.localizedDescription.contains("-1743") {
                    throw LaunchError.failed("Allow Pulse to control iTerm in System Settings → Privacy & Security → Automation, then try again.")
                }
                if !error.localizedDescription.contains("(404)") { throw error }
            }
        }
        throw LaunchError.closedTerminal
    }
    /// Read pane identities without activating iTerm or starting it if it is closed.
    static func openITermPaneIDs() async -> Set<String>? {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").isEmpty else { return [] }
        guard let output = try? await appleScriptOutput(inventoryScript, arguments: []) else { return nil }
        return Set(output.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty })
    }
    /// Cursor's own process tree identifies the window that owns this exact Claude process.
    static func cursorWindow(containing pid: Int) async -> Int? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/Applications/Cursor.app/Contents/Resources/app/bin/cursor")
            process.arguments = ["--status"]
            let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timeout)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit(); timeout.cancel()
            guard process.terminationStatus == 0 else { return nil }
            var windowID: Int?
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
                guard columns.count >= 4 else { continue }
                let description = String(columns[3])
                if let range = description.range(of: #"window \[(\d+)\]"#, options: .regularExpression) {
                    windowID = Int(description[range].filter(\.isNumber))
                }
                if Int(columns[2].trimmingCharacters(in: .whitespaces)) == pid { return windowID }
            }
            return nil
        }.value
    }
    static func appleScript(_ script: String, arguments: [String]) async throws {
        _ = try await appleScriptOutput(script, arguments: arguments)
    }
    static func appleScriptOutput(_ script: String, arguments: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script, "--"] + arguments
            let output = Pipe(); p.standardOutput = output; p.standardError = output
            try p.run()
            let timeout = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 4, execute: timeout)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit(); timeout.cancel()
            guard p.terminationStatus == 0 else {
                throw LaunchError.failed(String(data: data, encoding: .utf8) ?? "iTerm could not be opened")
            }
            return String(decoding: data, as: UTF8.self)
        }.value
    }
    static let focusScript = """
    on run argv
      set wanted to item 1 of argv
      tell application id "com.googlecode.iterm2"
        repeat with w in windows
          repeat with t in tabs of w
            repeat with s in sessions of t
              if (unique ID of s) is wanted then
                select s
                select t
                select w
                activate
                return
              end if
            end repeat
          end repeat
        end repeat
      end tell
      error "Original iTerm pane is no longer open" number 404
    end run
    """
    static let inventoryScript = """
    on run argv
      set paneIDs to ""
      if application id "com.googlecode.iterm2" is running then
        tell application id "com.googlecode.iterm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                set paneIDs to paneIDs & (unique ID of s) & linefeed
              end repeat
            end repeat
          end repeat
        end tell
      end if
      return paneIDs
    end run
    """
}
