import Foundation

enum ClaudeConnectionInstaller {
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    static func install() async throws {
        guard let script = Bundle.main.url(forResource: "setup-claude", withExtension: "py") else {
            throw Failure(errorDescription: "The Claude setup files are missing. Reinstall Pulse from the latest download.")
        }
        try await Task.detached(priority: .userInitiated) {
            // /usr/bin/python3 can be an installer stub on a fresh Mac. Check the
            // selected developer tools first so background repair never opens it.
            let tools = Process()
            tools.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            tools.arguments = ["-p"]
            let output = Pipe()
            tools.standardOutput = output
            tools.standardError = FileHandle.nullDevice
            try tools.run()
            let directory = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            tools.waitUntilExit()
            guard tools.terminationStatus == 0,
                  FileManager.default.isExecutableFile(atPath: directory + "/usr/bin/python3") else {
                throw Failure(errorDescription: "Claude connection needs Python 3 from Apple’s Command Line Tools. Install the tools, then choose Repair Claude connection. Your settings were left unchanged.")
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script.path]
            // Setup output can contain local settings paths. Keep it out of app logs.
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch {
                throw Failure(errorDescription: "Claude setup needs Python 3 from Apple’s Command Line Tools. Install the tools, then try connecting again.")
            }
            let timeout = DispatchWorkItem {
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeout)
            process.waitUntilExit()
            timeout.cancel()
            guard process.terminationStatus == 0 else {
                throw Failure(errorDescription: "Couldn’t install the Claude hooks. Check that Python 3 is available and ~/.claude/settings.json contains valid JSON and is writable, then try again.")
            }
        }.value
    }
}
