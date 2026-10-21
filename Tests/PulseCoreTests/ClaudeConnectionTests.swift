import Foundation
import Testing
@testable import PulseCore

struct ClaudeConnectionTests {
    @Test func detectsMissingPartialAndInstalledHooksWithoutChangingSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(ClaudeConnection.inspect(home: root) == .missing)
        let settings = root.appendingPathComponent(".claude/settings.json")
        let hook = root.appendingPathComponent(".local/share/pulse/claude-hook.py")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: hook)
        var hooks: [String: Any] = [:]
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"] {
            hooks[event] = [["hooks": [["type": "command", "command": "/usr/bin/python3 '\(hook.path)'"]]]]
        }
        let data = try JSONSerialization.data(withJSONObject: ["hooks": hooks, "model": "keep"])
        try data.write(to: settings)
        #expect(ClaudeConnection.inspect(home: root) == .installed)
        #expect(!ClaudeConnection.needsRepair(home: root, bundledHook: Data()))
        #expect(ClaudeConnection.needsRepair(home: root, bundledHook: Data("new version".utf8)))
        #expect(try Data(contentsOf: settings) == data)
        hooks.removeValue(forKey: "Stop")
        try JSONSerialization.data(withJSONObject: ["hooks": hooks]).write(to: settings)
        #expect(ClaudeConnection.inspect(home: root) == .missing)
        try data.write(to: settings)
        try FileManager.default.removeItem(at: hook)
        #expect(ClaudeConnection.inspect(home: root) == .missing)
    }

    @Test func disabledAndInvalidSettingsAreReportedWithoutRepairingThem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"disableAllHooks":true}"#.utf8).write(to: settings)
        #expect(ClaudeConnection.inspect(home: root) == .disabled)
        #expect(!ClaudeConnection.needsRepair(home: root, bundledHook: Data()))
        let broken = Data("{broken".utf8)
        try broken.write(to: settings)
        #expect(ClaudeConnection.inspect(home: root) == .invalidSettings)
        #expect(!ClaudeConnection.needsRepair(home: root, bundledHook: Data()))
        #expect(try Data(contentsOf: settings) == broken)
    }
}
