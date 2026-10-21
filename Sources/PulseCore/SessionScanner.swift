import Foundation
import Darwin

/// Own on a single background queue. Source databases are always opened read-only.
public final class SessionScanner: @unchecked Sendable {
    private let home: URL
    private let fm = FileManager.default
    private var cache: [String: (Date, Int, Session)] = [:]
    private var claudeFiles: [URL] = []
    private var cursorClaudeWorkspaces: [String: String] = [:]
    private var lastDiscovery = Date.distantPast
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }
    private func path(_ relative: String) -> String { home.appendingPathComponent(relative).path }

    public func scan() -> ScanResult {
        var sessions: [Session] = []
        var health: [SourceHealth] = []
        for provider in Provider.allCases {
            do {
                let result: [Session]
                switch provider { case .codex: result = try codex(); case .claude: result = try claude(); case .cursor: result = try cursor() }
                let topLevel = result.filter { !$0.isSubagent }
                sessions += topLevel
                health.append(SourceHealth(provider, count: topLevel.count, message: "Reading local sessions", available: true))
            } catch {
                health.append(SourceHealth(provider, count: 0, message: error.localizedDescription, available: false))
            }
        }
        sessions = sessions.map { original in
            var session = original
            if session.state == .running && Date().timeIntervalSince(session.updatedAt) > 21_600 {
                session.state = .unknown; session.detail = "No recent activity; open to check"
            }
            return session
        }
        return ScanResult(sessions: sessions, sources: health)
    }

    private func codex() throws -> [Session] {
        let root = home.appendingPathComponent(".codex")
        let dbs = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        guard let file = dbs.first else { throw DatabaseError.unavailable("No Codex session database found") }
        let db = try ReadDatabase(file.path)
        let history = try? ReadDatabase(path(".codex/thread_history_1.sqlite"))
        let columns = try db.columns("threads")
        let optional = ["updated_at_ms", "recency_at_ms", "agent_nickname", "agent_role", "originator", "preview", "name"]
            .filter { columns.contains($0) }.map { ", \($0)" }.joined()
        let rows = try db.rows("SELECT id, title, cwd, updated_at, rollout_path, source\(optional) FROM threads WHERE archived = 0 ORDER BY updated_at DESC")
        return rows.map { row in
            let id = row["id"] ?? ""
            let log = row["rollout_path"] ?? ""
            let metadataDate = Date(timeIntervalSince1970: Double(row["updated_at_ms"] ?? "").map { $0 / 1000 } ?? Double(row["updated_at"] ?? "0") ?? 0)
            let modified = fileSignature(log)
            let userItem = (try? history?.rows("SELECT item_json, created_at_ms FROM thread_items WHERE thread_id=? AND item_type='userMessage' ORDER BY rollout_ordinal DESC LIMIT 5", bindings: [id]))?
                .first { JSON.object($0["item_json"] ?? "").flatMap(MessagePreview.codexItem) != nil }
            let message = userItem.flatMap { JSON.object($0["item_json"] ?? "").flatMap(MessagePreview.codexItem) }
            let historyDate = userItem?["created_at_ms"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
            if let cached = cache["codex:" + id], cached.0 == modified.0, cached.1 == modified.1 {
                var session = cached.2
                if let message { session.lastUserMessage = message }
                if session.lastUserMessageAt == nil { session.lastUserMessageAt = historyDate }
                return session
            }
            let slice = TranscriptSlice(path: log)
            let status = StatusParser.codex(slice.tail)
            let nickname = row["agent_nickname"] ?? ""
            let transcriptMessageDate = userMessageDate(log, provider: .codex, tail: slice.tail, signature: modified, cacheKey: "codex:" + id)
            let s = Session(provider: .codex, nativeID: id,
                            title: JSON.title(row["name"] ?? row["title"] ?? "", fallback: nickname.isEmpty ? "Codex session" : nickname),
                            project: row["cwd"] ?? "", updatedAt: status.1 ?? metadataDate,
                            state: status.0, detail: status.2, transcript: log,
                            isSubagent: !nickname.isEmpty || (row["source"] ?? "").contains("subagent"),
                            lastUserMessage: message ?? MessagePreview.codex(slice.tail) ?? cache["codex:" + id]?.2.lastUserMessage ?? MessagePreview.codex(slice.head),
                            lastUserMessageAt: transcriptMessageDate ?? historyDate,
                            replayedAt: StatusParser.codexReplayDate(slice.tail))
            var cachedSession = s
            cachedSession.lastUserMessageAt = transcriptMessageDate
            cache["codex:" + id] = (modified.0, modified.1, cachedSession)
            return s
        }
    }

    private func userMessageDate(_ path: String, provider: Provider, tail: [[String: Any]], signature: (Date, Int), cacheKey: String) -> Date? {
        if let date = MessagePreview.lastUserMessageDate(tail, provider: provider) { return date }
        let previous = cache[cacheKey]
        let canReuse = previous != nil && signature.1 >= previous!.1 && previous!.2.lastUserMessageAt != nil
        return TranscriptSlice.lastUserMessageDate(path: path, provider: provider, sinceOffset: canReuse ? previous!.1 : 0)
            ?? (canReuse ? previous!.2.lastUserMessageAt : nil)
    }

    private func fileSignature(_ path: String) -> (Date, Int) {
        let a = try? fm.attributesOfItem(atPath: path)
        return (a?[.modificationDate] as? Date ?? .distantPast, a?[.size] as? Int ?? 0)
    }

    private func claude() throws -> [Session] {
        let root = home.appendingPathComponent(".claude/projects")
        guard fm.fileExists(atPath: root.path) else { throw DatabaseError.unavailable("No Claude Code session folder found") }
        if Date().timeIntervalSince(lastDiscovery) > 15 {
            let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            claudeFiles = (enumerator?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "jsonl" }
            cursorClaudeWorkspaces = CursorClaudeWorkspaces.read(home: home)
            lastDiscovery = Date()
        }
        let managed = statusFiles(path(".claude/agent-manager/sessions"))
        let own = statusFiles(path(".local/share/pulse/events"))
        var history: [String: [String: Any]] = [:]
        var latestPrompts: [String: String] = [:]
        var latestPromptDates: [String: Date] = [:]
        if let data = fm.contents(atPath: path(".claude/history.jsonl")) {
            for item in TranscriptSlice.parse(data, dropFirst: false) {
                guard let id = item["sessionId"] as? String,
                      let display = item["display"] as? String, !display.isEmpty else { continue }
                if history[id] == nil && !display.hasPrefix("/") { history[id] = item }
                if let text = MessagePreview.clean(display) {
                    latestPrompts[id] = text
                    if let date = JSON.date(item["timestamp"]) { latestPromptDates[id] = max(latestPromptDates[id] ?? .distantPast, date) }
                }
            }
        }
        var result: [Session] = []
        for file in claudeFiles {
            let id = file.deletingPathExtension().lastPathComponent
            let sig = fileSignature(file.path)
            var s: Session
            if let cached = cache["claude:" + file.path], cached.0 == sig.0, cached.1 == sig.1 { s = cached.2 }
            else {
                let slice = TranscriptSlice(path: file.path)
                let combined = slice.head + slice.tail
                let metadata = combined.last { $0["cwd"] is String }
                let firstUser = slice.head.first { $0["type"] as? String == "user" && ($0["message"] as? [String: Any])?["role"] as? String == "user" }
                let message = firstUser?["message"] as? [String: Any] ?? [:]
                let custom = combined.last { $0["type"] as? String == "custom-title" }?["customTitle"] as? String
                let summary = combined.last { $0["type"] as? String == "summary" }?["summary"] as? String
                let status = StatusParser.claude(slice.tail)
                let project = metadata?["cwd"] as? String ?? ""
                let userTitle = history[id]?["display"] as? String ?? JSON.text(message["content"])
                let title = JSON.title(custom ?? summary ?? userTitle, fallback: URL(fileURLWithPath: project).lastPathComponent + " session")
                s = Session(provider: .claude, nativeID: id, title: title, project: project,
                            updatedAt: status.1 ?? sig.0, state: status.0, detail: status.2,
                            transcript: file.path, isSubagent: file.path.contains("/subagents/"),
                            lastUserMessage: latestPrompts[id] ?? MessagePreview.claude(slice.tail) ?? cache["claude:" + file.path]?.2.lastUserMessage ?? MessagePreview.claude(slice.head),
                            lastUserMessageAt: userMessageDate(file.path, provider: .claude, tail: slice.tail, signature: sig, cacheKey: "claude:" + file.path),
                            entrypoint: combined.last { $0["entrypoint"] is String }?["entrypoint"] as? String)
                cache["claude:" + file.path] = (sig.0, sig.1, s)
            }
            if let latest = latestPrompts[id] { s.lastUserMessage = latest }
            if let date = latestPromptDates[id] { s.lastUserMessageAt = max(s.lastUserMessageAt ?? .distantPast, date) }
            // Multiple reporters may exist. Prefer the newest event, never a stale hook file.
            let reports = [managed[id], own[id]].compactMap { $0 }.sorted {
                (JSON.date($0["updated_at"]) ?? .distantPast) > (JSON.date($1["updated_at"]) ?? .distantPast)
            }
            if let report = reports.first {
                let date = JSON.date(report["updated_at"]) ?? .distantPast
                s.terminalID = report["iterm_session_id"] as? String
                if let project = report["cwd"] as? String, !project.isEmpty { s.project = project }
                if s.title.hasSuffix(" session"), let label = report["label"] as? String, !label.isEmpty { s.title = label }
                if date >= s.updatedAt.addingTimeInterval(-2) {
                    let raw = report["state"] as? String ?? ""
                    switch raw {
                    case "processing", "running": s.state = .running; s.detail = "Turn in progress"
                    case "waiting", "attention", "permission", "input": s.state = .waiting; s.detail = "Waiting for your input or approval"
                    case "done", "ready", "stopped": s.state = .ready; s.detail = "Finished its latest turn"
                    case "ended", "idle":
                        // Closing a completed agent does not mean the user handled its reply.
                        if s.state != .ready && s.state != .waiting { s.state = .idle; s.detail = "Session ended" }
                    default: break
                    }
                    if report["main_waiting"] as? Bool == true || !(report["agent_input_pending_ids"] as? [String] ?? []).isEmpty {
                        s.state = .waiting; s.detail = "Waiting for your input or approval"
                    }
                    // Reporter heartbeats must not make an old conversation jump to the top.
                    if let since = JSON.date(report["state_since"]) { s.updatedAt = max(s.updatedAt, since) }
                    let pid = (report["owner_pid"] as? NSNumber)?.int32Value ?? 0
                    if s.state == .running, pid > 0, kill(pid, 0) != 0, errno == ESRCH {
                        s.state = .unknown; s.detail = "Agent process has exited"
                    } else if s.state == .running && Date().timeIntervalSince(date) > 21_600 {
                        s.state = .unknown; s.detail = "Status report is stale"
                    }
                }
            }
            s.route = SessionRoute.claude(reports: reports, entrypoint: s.entrypoint, cursorWorkspace: cursorClaudeWorkspaces[id])
            if s.route?.kind != .iTerm { s.terminalID = nil }
            // Internal helper logs can have colliding agent IDs; nativeID includes their parent.
            if s.isSubagent {
                let parent = file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
                s.nativeID = parent + "/" + id
            }
            result.append(s)
        }
        return result
    }

    private func statusFiles(_ directory: String) -> [String: [String: Any]] {
        var result: [String: [String: Any]] = [:]
        for file in (try? fm.contentsOfDirectory(atPath: directory)) ?? [] where file.hasSuffix(".json") {
            if let data = fm.contents(atPath: directory + "/" + file), let obj = JSON.object(data) {
                let id = obj["session_id"] as? String ?? String(file.dropLast(5)); result[id] = obj
            }
        }
        return result
    }

    private func cursor() throws -> [Session] {
        let db = try ReadDatabase(path("Library/Application Support/Cursor/User/globalStorage/state.vscdb"))
        // Current Cursor versions index headers. Older versions store full headers in workspace databases.
        var rows: [[String: String]]
        do {
            rows = try db.rows("SELECT composerId, recency, value FROM composerHeaders WHERE COALESCE(isArchived,0)=0 ORDER BY recency DESC")
        } catch {
            rows = try db.rows("SELECT substr(key,14) AS composerId, value FROM cursorDiskKV WHERE key LIKE 'composerData:%'")
        }
        var result: [Session] = []
        for row in rows {
            guard let id = row["composerId"], id != "empty-state-draft", let header = JSON.object(row["value"] ?? "") else { continue }
            guard header["isDraft"] as? Bool != true, header["isArchived"] as? Bool != true else { continue }
            // Project out metadata inside SQLite so encrypted contexts and transcript bodies aren't loaded.
            let fields = ["name", "subtitle", "status", "lastUpdatedAt", "createdAt", "hasUnreadMessages", "hasBlockingPendingActions", "hasPendingPlan", "isContinuationInProgress", "generatingBubbleIds", "workspaceIdentifier", "fullConversationHeadersOnly", "subagentInfo"]
            let projection = fields.map { "json_extract(value,'$.\($0)') AS \($0)" }.joined(separator: ",")
            let meta = try db.rows("SELECT \(projection) FROM cursorDiskKV WHERE key=?", bindings: ["composerData:" + id]).first ?? [:]
            let conversations = meta["fullConversationHeadersOnly"].flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [[String: Any]] } ?? []
            guard !conversations.isEmpty || !(meta["name"] ?? header["name"] as? String ?? "").isEmpty else { continue }
            let workspace = JSON.object(meta["workspaceIdentifier"] ?? "") ?? header["workspaceIdentifier"] as? [String: Any] ?? [:]
            let uri = workspace["uri"] as? [String: Any] ?? [:]
            let project = uri["fsPath"] as? String ?? uri["path"] as? String ?? ""
            let raw = meta["status"] ?? header["status"] as? String ?? "none"
            var state: AgentState = .unknown
            var detail = "Cursor does not expose a current execution state"
            if ["generating", "running", "streaming"].contains(raw) || meta["isContinuationInProgress"] == "1" || (meta["generatingBubbleIds"] ?? "[]") != "[]" {
                state = .running; detail = "Agent is generating"
            } else if ["completed", "done"].contains(raw) || meta["hasUnreadMessages"] == "1" {
                state = .ready; detail = "Reply ready"
            } else if ["aborted", "cancelled"].contains(raw) {
                state = .idle; detail = "Agent stopped"
            }
            if meta["hasBlockingPendingActions"] == "1" || meta["hasPendingPlan"] == "1" || header["hasBlockingPendingActions"] as? Bool == true {
                state = .waiting; detail = "Waiting for approval or plan review"
            }
            let conversationDate = conversations.compactMap { JSON.date($0["createdAt"]) }.max()
            let metadataDate = Double(meta["lastUpdatedAt"] ?? row["recency"] ?? meta["createdAt"] ?? "0").map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
            let date = conversationDate ?? metadataDate
            let lastUserMessageAt = conversations.filter { $0["type"] as? Int == 1 }.compactMap { JSON.date($0["createdAt"]) }.max()
            var lastUserMessage: String?
            for bubble in conversations.reversed() where bubble["type"] as? Int == 1 {
                guard let bubbleID = bubble["bubbleId"] as? String else { continue }
                let text = try db.rows("SELECT json_extract(value,'$.text') AS text FROM cursorDiskKV WHERE key=?", bindings: ["bubbleId:\(id):\(bubbleID)"]).first?["text"] ?? ""
                if let preview = MessagePreview.clean(text) { lastUserMessage = preview; break }
            }
            if state == .running, Date().timeIntervalSince(max(date, metadataDate)) > 21_600 {
                state = .unknown; detail = "No recent activity; open to check"
            }
            result.append(Session(provider: .cursor, nativeID: id,
                                  title: JSON.title(meta["name"] ?? header["name"] as? String ?? "", fallback: "Cursor agent"),
                                  project: project, updatedAt: date, state: state, detail: detail,
                                  isSubagent: meta["subagentInfo"] != nil || id.hasPrefix("task-"), lastUserMessage: lastUserMessage, lastUserMessageAt: lastUserMessageAt))
        }
        return result
    }
}
