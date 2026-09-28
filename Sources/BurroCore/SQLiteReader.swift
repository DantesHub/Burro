// Local provider databases are opened read-only; unsupported schemas remain visible as warnings.
import Foundation
import CSystem

final class SQLiteReader {
    private var database: OpaquePointer?
    init(path: String) throws {
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            database = nil
            throw ReaderError.failed("Cannot open Codex metadata")
        }
        sqlite3_busy_timeout(database, 500)
    }
    deinit { sqlite3_close(database) }
    func rows(_ sql: String) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw ReaderError.failed("Codex metadata schema is unsupported") }
        defer { sqlite3_finalize(statement) }
        var result: [[String: String]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw ReaderError.failed("Codex metadata could not be read completely") }
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                if let name = sqlite3_column_name(statement, index), let value = sqlite3_column_text(statement, index) {
                    row[String(cString: name)] = String(cString: value)
                }
            }
            result.append(row)
        }
    }
}
enum ReaderError: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? { switch self { case .failed(let message): message } }
}
