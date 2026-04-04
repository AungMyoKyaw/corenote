import Foundation
import SQLite3

enum SQLiteParam: Sendable {
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
    case null
}

enum SQLiteError: Error, LocalizedError, Sendable {
    case openFailed(path: String, message: String)
    case executeFailed(sql: String, message: String)
    case queryFailed(sql: String, message: String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let message):
            return "Failed to open database at \(path): \(message)"
        case .executeFailed(let sql, let message):
            return "SQL execute failed (\(sql)): \(message)"
        case .queryFailed(let sql, let message):
            return "SQL query failed (\(sql)): \(message)"
        }
    }
}

final class SQLiteConnection: @unchecked Sendable {
    private var db: OpaquePointer?

    init(path: String) throws {
        let flags: Int32
        if path == ":memory:" {
            flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        } else {
            flags = SQLITE_OPEN_READWRITE
        }

        let result = sqlite3_open_v2(path, &db, flags, nil)
        if result != SQLITE_OK {
            let message = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            db = nil
            throw SQLiteError.openFailed(path: path, message: message)
        }
    }

    func close() {
        if let db = db {
            sqlite3_close(db)
        }
        db = nil
    }

    func execute(_ sql: String, params: [SQLiteParam] = []) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.executeFailed(sql: sql, message: message)
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(stmt: stmt!, params: params)

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE && result != SQLITE_ROW {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.executeFailed(sql: sql, message: message)
        }
    }

    func query(_ sql: String, params: [SQLiteParam] = []) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteError.queryFailed(sql: sql, message: message)
        }
        defer { sqlite3_finalize(stmt) }

        try bindParams(stmt: stmt!, params: params)

        var rows: [[String: Any]] = []
        let columnCount = sqlite3_column_count(stmt)

        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(stmt, i))
                let type = sqlite3_column_type(stmt, i)

                switch type {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB:
                    let bytes = sqlite3_column_blob(stmt, i)
                    let count = sqlite3_column_bytes(stmt, i)
                    if let bytes = bytes {
                        row[name] = Data(bytes: bytes, count: Int(count))
                    } else {
                        row[name] = Data()
                    }
                case SQLITE_NULL:
                    break
                default:
                    break
                }
            }
            rows.append(row)
        }

        return rows
    }

    private func bindParams(stmt: OpaquePointer, params: [SQLiteParam]) throws {
        for (index, param) in params.enumerated() {
            let position = Int32(index + 1)
            var result: Int32

            switch param {
            case .int(let value):
                result = sqlite3_bind_int64(stmt, position, value)
            case .double(let value):
                result = sqlite3_bind_double(stmt, position, value)
            case .text(let value):
                result = sqlite3_bind_text(stmt, position, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .blob(let value):
                result = value.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, position, ptr.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            case .null:
                result = sqlite3_bind_null(stmt, position)
            }

            if result != SQLITE_OK {
                throw SQLiteError.executeFailed(sql: "bind param \(index)", message: "bind failed")
            }
        }
    }

    deinit {
        close()
    }
}
