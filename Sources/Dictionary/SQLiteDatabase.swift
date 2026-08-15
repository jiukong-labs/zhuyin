import Foundation
import SQLite3

enum SQLiteDatabaseError: LocalizedError {
    case open(path: String, message: String)
    case operation(sql: String, message: String)
    case invalidColumn(index: Int32)

    var errorDescription: String? {
        switch self {
        case let .open(path, message):
            return "Could not open SQLite database at \(path): \(message)"
        case let .operation(sql, message):
            return "SQLite operation failed for '\(sql)': \(message)"
        case let .invalidColumn(index):
            return "SQLite returned an invalid text value at column \(index)."
        }
    }
}

enum SQLiteStepResult: Equatable {
    case row
    case done
}

final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL, flags: Int32) throws {
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK, handle != nil else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) }
                ?? "unknown SQLite error"
            if let handle {
                sqlite3_close(handle)
            }
            self.handle = nil
            throw SQLiteDatabaseError.open(path: url.path, message: message)
        }
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func execute(_ sql: String) throws {
        guard let handle else {
            throw SQLiteDatabaseError.operation(
                sql: sql,
                message: "database is closed"
            )
        }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        guard result == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(handle))
            if let errorPointer {
                sqlite3_free(errorPointer)
            }
            throw SQLiteDatabaseError.operation(sql: sql, message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let handle else {
            throw SQLiteDatabaseError.operation(
                sql: sql,
                message: "database is closed"
            )
        }

        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw SQLiteDatabaseError.operation(
                sql: sql,
                message: String(cString: sqlite3_errmsg(handle))
            )
        }

        return SQLiteStatement(
            handle: statement,
            database: self,
            databaseHandle: handle,
            sql: sql
        )
    }
}

final class SQLiteStatement {
    private let handle: OpaquePointer
    private let database: SQLiteDatabase
    private let databaseHandle: OpaquePointer
    private let sql: String

    init(
        handle: OpaquePointer,
        database: SQLiteDatabase,
        databaseHandle: OpaquePointer,
        sql: String
    ) {
        self.handle = handle
        self.database = database
        self.databaseHandle = databaseHandle
        self.sql = sql
    }

    deinit {
        sqlite3_finalize(handle)
    }

    func bind(_ value: String, at index: Int32) throws {
        let byteCount = value.utf8.count
        guard byteCount <= Int(Int32.max) else {
            throw SQLiteDatabaseError.operation(
                sql: sql,
                message: "bound UTF-8 string is too large"
            )
        }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result = value.withCString { bytes in
            sqlite3_bind_text(
                handle,
                index,
                bytes,
                Int32(byteCount),
                transient
            )
        }
        try check(result)
    }

    func bind(_ value: Int64, at index: Int32) throws {
        try check(sqlite3_bind_int64(handle, index, value))
    }

    func bindNull(at index: Int32) throws {
        try check(sqlite3_bind_null(handle, index))
    }

    func step() throws -> SQLiteStepResult {
        switch sqlite3_step(handle) {
        case SQLITE_ROW:
            return .row
        case SQLITE_DONE:
            return .done
        default:
            throw SQLiteDatabaseError.operation(
                sql: sql,
                message: String(cString: sqlite3_errmsg(databaseHandle))
            )
        }
    }

    func text(at index: Int32) throws -> String {
        guard let value = sqlite3_column_text(handle, index) else {
            throw SQLiteDatabaseError.invalidColumn(index: index)
        }

        let byteCount = Int(sqlite3_column_bytes(handle, index))
        let data = Data(bytes: value, count: byteCount)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SQLiteDatabaseError.invalidColumn(index: index)
        }
        return string
    }

    func integer(at index: Int32) -> Int64 {
        sqlite3_column_int64(handle, index)
    }

    func isNull(at index: Int32) -> Bool {
        sqlite3_column_type(handle, index) == SQLITE_NULL
    }

    func reset() throws {
        try check(sqlite3_reset(handle))
        try check(sqlite3_clear_bindings(handle))
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw SQLiteDatabaseError.operation(
                sql: sql,
                message: String(cString: sqlite3_errmsg(databaseHandle))
            )
        }
    }
}
