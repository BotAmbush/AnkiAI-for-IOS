import Foundation
import SQLite3

/// Minimal thin wrapper over the system `libsqlite3`, used by the AI database.
///
/// We deliberately depend on the OS-provided SQLite rather than an external
/// Swift package so CI package resolution can never break the build. This wrapper
/// only backs the *separate* `ai_insights.db` — never Anki's `collection.anki2`,
/// which is owned by the Rust backend (milestone 2).
final class SQLiteDatabase {
    enum DBError: Error { case open(String), prepare(String), step(String) }

    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "com.evyatar.ankiai.sqlite")

    /// SQLITE_TRANSIENT tells SQLite to copy bound strings/blobs.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw DBError.open(msg)
        }
    }

    deinit { if let handle { sqlite3_close(handle) } }

    func execute(_ sql: String) throws {
        try queue.sync {
            var err: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? "unknown"
                sqlite3_free(err)
                throw DBError.step(msg)
            }
        }
    }

    /// Run an INSERT/UPDATE/DELETE with positional bindings; returns last row id.
    @discardableResult
    func run(_ sql: String, _ params: [SQLiteValue] = []) throws -> Int64 {
        try queue.sync {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            try bind(params, to: stmt)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw DBError.step(String(cString: sqlite3_errmsg(handle)))
            }
            return sqlite3_last_insert_rowid(handle)
        }
    }

    /// Run a SELECT and map each row.
    func query<T>(_ sql: String, _ params: [SQLiteValue] = [], _ map: (Row) -> T) throws -> [T] {
        try queue.sync {
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }
            try bind(params, to: stmt)
            var results: [T] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(map(Row(stmt: stmt)))
            }
            return results
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DBError.prepare(String(cString: sqlite3_errmsg(handle)))
        }
        return stmt
    }

    private func bind(_ params: [SQLiteValue], to stmt: OpaquePointer) throws {
        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, Self.transient)
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
    }

    struct Row {
        let stmt: OpaquePointer
        func int(_ col: Int32) -> Int64 { sqlite3_column_int64(stmt, col) }
        func double(_ col: Int32) -> Double { sqlite3_column_double(stmt, col) }
        func string(_ col: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, col) else { return "" }
            return String(cString: c)
        }
    }
}

enum SQLiteValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null
}
