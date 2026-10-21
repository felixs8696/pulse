import Foundation
import CSQLite

enum DatabaseError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? { switch self { case .unavailable(let s): return s } }
}

/// Never creates or writes the source database. WAL is read normally, without immutable=1.
final class ReadDatabase {
    private var handle: OpaquePointer?
    init(_ path: String) throws {
        let code = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open database"
            sqlite3_close(handle); handle = nil
            throw DatabaseError.unavailable(message)
        }
        sqlite3_busy_timeout(handle, 120)
    }
    deinit { sqlite3_close(handle) }
    func rows(_ sql: String, bindings: [String] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError.unavailable(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            _ = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        }
        var result: [[String: String]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw DatabaseError.unavailable(String(cString: sqlite3_errmsg(handle))) }
            var row: [String: String] = [:]
            for i in 0..<sqlite3_column_count(statement) {
                if let bytes = sqlite3_column_text(statement, i) {
                    row[String(cString: sqlite3_column_name(statement, i))] = String(cString: bytes)
                }
            }
            result.append(row)
        }
        return result
    }
    func columns(_ table: String) throws -> Set<String> {
        Set(try rows("PRAGMA table_info(\(table))").compactMap { $0["name"] })
    }
}
