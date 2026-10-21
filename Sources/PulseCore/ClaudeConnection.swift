import Foundation

public enum ClaudeConnection: Sendable, Equatable {
    case missing, installed, disabled, invalidSettings

    public static func inspect(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                               directory: String = "pulse") -> ClaudeConnection {
        let settings = home.appendingPathComponent(".claude/settings.json")
        guard FileManager.default.fileExists(atPath: settings.path) else { return .missing }
        guard let data = try? Data(contentsOf: settings),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .invalidSettings }
        if root["disableAllHooks"] as? Bool == true { return .disabled }
        guard let hooks = root["hooks"] as? [String: Any],
              FileManager.default.fileExists(atPath: home.appendingPathComponent(".local/share/\(directory)/claude-hook.py").path) else { return .missing }
        for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "PermissionRequest"] {
            let groups = hooks[event] as? [[String: Any]] ?? []
            let handlers = groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            guard handlers.contains(where: {
                $0["type"] as? String == "command" && ($0["command"] as? String ?? "").contains("\(directory)/claude-hook.py")
            }) else { return .missing }
        }
        return .installed
    }
}
