import Foundation
import SQLite3

final class SQLiteConnection {
    enum Value {
        case text(String)
        case integer(Int64)
    }

    private var handle: OpaquePointer?

    init(url: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil
        )
        guard result == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open database."
            if let handle { sqlite3_close(handle) }
            throw WordStorageError.sqlite(message)
        }
        self.handle = opened
        guard sqlite3_busy_timeout(opened, 5000) == SQLITE_OK else {
            throw failure()
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    private func failure() -> WordStorageError {
        .sqlite(handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Database is closed.")
    }

    func run(
        _ sql: String, values: [Value] = [],
        row: (OpaquePointer) throws -> Void = { _ in }
    ) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let result: Int32
            switch value {
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, Int32(index + 1), integer)
            case .text(let text):
                // SQLITE_TRANSIENT makes SQLite copy Swift's temporary UTF-8 buffer.
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                let bytes = text.utf8CString
                guard bytes.count - 1 <= Int(Int32.max) else {
                    throw WordStorageError.sqlite("Text exceeds SQLite's supported size.")
                }
                result = bytes.withUnsafeBufferPointer {
                    sqlite3_bind_text(statement, Int32(index + 1), $0.baseAddress, Int32(bytes.count - 1), transient)
                }
            }
            guard result == SQLITE_OK else { throw failure() }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try row(statement)
            case SQLITE_DONE: return
            default: throw failure()
            }
        }
    }

    func scalar(_ sql: String) throws -> Int64 {
        var result: Int64?
        try run(sql) { result = sqlite3_column_int64($0, 0) }
        guard let result else { throw WordStorageError.invalidRow }
        return result
    }

    var insertedID: Int64 { sqlite3_last_insert_rowid(handle) }
    var changes: Int32 { sqlite3_changes(handle) }

    static func text(_ statement: OpaquePointer, column: Int32) throws -> String {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let bytes = sqlite3_column_text(statement, column) else {
            throw WordStorageError.invalidRow
        }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        guard let text = String(data: data, encoding: .utf8) else { throw WordStorageError.invalidRow }
        return text
    }
}
