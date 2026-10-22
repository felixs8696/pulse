import Foundation

/// Desktop's session ID is different from the CLI transcript ID. Read only its
/// Code metadata directory, never the browser store, credentials, or chat history.
enum ClaudeDesktopSessions {
    struct Entry {
        let desktopID: String
        let archived: Bool
        let lastActivity: Double
    }
    static func validID(_ id: String) -> Bool {
        id.hasPrefix("local_") && UUID(uuidString: String(id.dropFirst(6))) != nil
    }
    static func read(home: URL) -> [String: Entry] {
        let root = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
        let fm = FileManager.default
        guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return [:] }
        var result: [String: Entry] = [:]
        while let file = files.nextObject() as? URL {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { continue }
            if values.isSymbolicLink == true { files.skipDescendants(); continue }
            guard file.pathExtension == "json", values.isRegularFile == true,
                  (values.fileSize ?? Int.max) <= 2_097_152,
                  let data = try? Data(contentsOf: file), let item = JSON.object(data),
                  let desktopID = item["sessionId"] as? String, validID(desktopID),
                  let cliID = item["cliSessionId"] as? String, UUID(uuidString: cliID) != nil else { continue }
            let entry = Entry(desktopID: desktopID, archived: item["isArchived"] as? Bool ?? false,
                              lastActivity: (item["lastActivityAt"] as? NSNumber)?.doubleValue ?? 0)
            if let previous = result[cliID], previous.lastActivity >= entry.lastActivity { continue }
            result[cliID] = entry
        }
        return result
    }
}
