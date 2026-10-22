import Foundation

/// The agent provider and the application hosting its UI are separate identities.
public struct SessionRoute: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case iTerm, cursorClaude, cursorTerminal, claudeDesktop, unknown }
    public var kind: Kind
    /// Cursor's actual workspace file or folder, which may differ from the agent's cwd.
    public var workspace: String?
    public var desktopSessionID: String?
    public var ownerPID: Int?
    public var terminalPIDs: [Int]?
    public init(_ kind: Kind, workspace: String? = nil, terminalPIDs: [Int]? = nil, ownerPID: Int? = nil, desktopSessionID: String? = nil) {
        self.desktopSessionID = desktopSessionID
        self.kind = kind; self.workspace = workspace; self.terminalPIDs = terminalPIDs; self.ownerPID = ownerPID
    }

    static func claude(reports: [[String: Any]], entrypoint: String?, cursorWorkspace: String?, desktopSessionID: String? = nil) -> SessionRoute {
        // Reports arrive newest first. Ignore a newer reporter with no host evidence:
        // environment variables such as ITERM_SESSION_ID can be inherited by Cursor.
        if let report = reports.first(where: { !($0["host_bundle_id"] as? String ?? "").isEmpty }) {
            switch report["host_bundle_id"] as? String {
            case "com.todesktop.230313mzl4w4u92":
                let panel = report["host_surface"] as? String == "claudePanel" || entrypoint == "claude-vscode" || cursorWorkspace != nil
                return SessionRoute(panel ? .cursorClaude : .cursorTerminal, workspace: cursorWorkspace ?? report["cwd"] as? String,
                                    terminalPIDs: report["terminal_ancestor_pids"] as? [Int], ownerPID: reports.compactMap { $0["owner_pid"] as? Int }.first)
            case "com.anthropic.claudefordesktop":
                return SessionRoute(.claudeDesktop, desktopSessionID: desktopSessionID)
            case "com.googlecode.iterm2": return SessionRoute(.iTerm)
            default:
                // Older reporters identify Desktop's embedded Code process rather
                // than the enclosing app. Require transcript and saved-ID evidence.
                if entrypoint == "claude-desktop", let desktopSessionID {
                    return SessionRoute(.claudeDesktop, desktopSessionID: desktopSessionID)
                }
                return SessionRoute(.unknown)
            }
        }
        if let desktopSessionID { return SessionRoute(.claudeDesktop, desktopSessionID: desktopSessionID) }
        if let cursorWorkspace { return SessionRoute(.cursorClaude, workspace: cursorWorkspace) }
        if entrypoint == "claude-vscode" { return SessionRoute(.cursorClaude) }
        if reports.contains(where: { !($0["iterm_session_id"] as? String ?? "").isEmpty }) { return SessionRoute(.iTerm) }
        return SessionRoute(.unknown)
    }
}

/// Read only the Claude extension's saved tab IDs, never its credentials or configuration.
enum CursorClaudeWorkspaces {
    static func read(home: URL) -> [String: String] {
        let root = home.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage")
        var result: [String: String] = [:]
        for folder in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("workspace.json")),
                  let metadata = JSON.object(data),
                  let uri = (metadata["workspace"] ?? metadata["folder"]) as? String,
                  let workspace = URL(string: uri), workspace.isFileURL,
                  let db = try? ReadDatabase(folder.appendingPathComponent("state.vscdb").path),
                  let rows = try? db.rows("SELECT json_extract(value,'$.panelTabSessions') AS tabs FROM ItemTable WHERE key='Anthropic.claude-code'"),
                  let text = rows.first?["tabs"],
                  let tabs = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { continue }
            for tab in tabs {
                if let id = tab["sessionId"] as? String { result[id] = workspace.path }
            }
        }
        return result
    }
}
