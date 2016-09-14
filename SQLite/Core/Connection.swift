//
// SQLite.swift
// https://github.com/stephencelis/SQLite.swift
// Copyright © 2014-2015 Stephen Celis.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Dispatch
#if SQLITE_SWIFT_STANDALONE
import sqlite3
#else
import CSQLite
#endif

/// A connection to SQLite.
public final class Connection {

    /// The location of a SQLite database.
    public enum Location {

        /// An in-memory database (equivalent to `.URI(":memory:")`).
        ///
        /// See: <https://www.sqlite.org/inmemorydb.html#sharedmemdb>
        case inMemory

        /// A temporary, file-backed database (equivalent to `.URI("")`).
        ///
        /// See: <https://www.sqlite.org/inmemorydb.html#temp_db>
        case temporary

        /// A database located at the given URI filename (or path).
        ///
        /// See: <https://www.sqlite.org/uri.html>
        ///
        /// - Parameter filename: A URI filename
        case uri(String)
    }

    public var handle: OpaquePointer { return _handle! }

    fileprivate var _handle: OpaquePointer? = nil

    /// Initializes a new SQLite connection.
    ///
    /// - Parameters:
    ///
    ///   - location: The location of the database. Creates a new database if it
    ///     doesn’t already exist (unless in read-only mode).
    ///
    ///     Default: `.InMemory`.
    ///
    ///   - readonly: Whether or not to open the database in a read-only state.
    ///
    ///     Default: `false`.
    ///
    /// - Returns: A new database connection.
    public init(_ location: Location = .inMemory, readonly: Bool = false) throws {
        let flags = readonly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
        try check(sqlite3_open_v2(location.description, &_handle, flags | SQLITE_OPEN_FULLMUTEX, nil))
        queue.setSpecific(key: Connection.queueKey, value: ())
    }

    /// Initializes a new connection to a database.
    ///
    /// - Parameters:
    ///
    ///   - filename: The location of the database. Creates a new database if
    ///     it doesn’t already exist (unless in read-only mode).
    ///
    ///   - readonly: Whether or not to open the database in a read-only state.
    ///
    ///     Default: `false`.
    ///
    /// - Throws: `Result.Error` iff a connection cannot be established.
    ///
    /// - Returns: A new database connection.
    public convenience init(_ filename: String, readonly: Bool = false) throws {
        try self.init(.uri(filename), readonly: readonly)
    }

    deinit {
        sqlite3_close(handle)
    }

    // MARK: -

    /// Whether or not the database was opened in a read-only state.
    public var readonly: Bool { return sqlite3_db_readonly(handle, nil) == 1 }

    /// The last rowid inserted into the database via this connection.
    public var lastInsertRowid: Int64? {
        let rowid = sqlite3_last_insert_rowid(handle)
        return rowid != 0 ? rowid : nil
    }

    /// The last number of changes (inserts, updates, or deletes) made to the
    /// database via this connection.
    public var changes: Int {
        return Int(sqlite3_changes(handle))
    }

    /// The total number of changes (inserts, updates, or deletes) made to the
    /// database via this connection.
    public var totalChanges: Int {
        return Int(sqlite3_total_changes(handle))
    }

    // MARK: - Execute

    /// Executes a batch of SQL statements.
    ///
    /// - Parameter SQL: A batch of zero or more semicolon-separated SQL
    ///   statements.
    ///
    /// - Throws: `Result.Error` if query execution fails.
    public func execute(_ SQL: String) throws {
        try sync { try self.check(sqlite3_exec(self.handle, SQL, nil, nil, nil)) }
    }

    // MARK: - Prepare

    /// Prepares a single SQL statement (with optional parameter bindings).
    ///
    /// - Parameters:
    ///
    ///   - statement: A single SQL statement.
    ///
    ///   - bindings: A list of parameters to bind to the statement.
    ///
    /// - Returns: A prepared statement.
    public func prepare(_ statement: String, _ bindings: Binding?...) throws -> Statement {
        if !bindings.isEmpty { return try prepare(statement, bindings) }
        return try Statement(self, statement)
    }

    /// Prepares a single SQL statement and binds parameters to it.
    ///
    /// - Parameters:
    ///
    ///   - statement: A single SQL statement.
    ///
    ///   - bindings: A list of parameters to bind to the statement.
    ///
    /// - Returns: A prepared statement.
    public func prepare(_ statement: String, _ bindings: [Binding?]) throws -> Statement {
        return try prepare(statement).bind(bindings)
    }

    /// Prepares a single SQL statement and binds parameters to it.
    ///
    /// - Parameters:
    ///
    ///   - statement: A single SQL statement.
    ///
    ///   - bindings: A dictionary of named parameters to bind to the statement.
    ///
    /// - Returns: A prepared statement.
    public func prepare(_ statement: String, _ bindings: [String: Binding?]) throws -> Statement {
        return try prepare(statement).bind(bindings)
    }

    // MARK: - Run

    /// Runs a single SQL statement (with optional parameter bindings).
    ///
    /// - Parameters:
    ///
    ///   - statement: A single SQL statement.
    ///
    ///   - bindings: A list of parameters to bind to the statement.
    ///
    /// - Throws: `Result.Error` if query execution fails.
    ///
    /// - Returns: The statement.
    @discardableResult
    public func run(_ statement: String, _ bindings: Binding?...) throws -> Statement {
        return try run(statement, bindings)
    }

    /// Prepares, binds, and runs a single SQL statement.
    ///
    /// - Parameters:
    ///
    ///   - statement: A single SQL statement.
    ///
    ///   - bindings: A list of parameters to bind to the statement.
    ///
    /// - Throws: `Result.Error` if query execution fails.
    ///
    /// - Returns: The statement.
    @discardableResult
    public func run(_ statement: String, _ bindings: [Binding?]) throws -> Statement {
        return try prepare(statement).run(bindings)
    }

    /// Prepares, binds, and runs a single SQL statement.
    ///
    /// - Parameters:
    ///
    ///   - statement: A single SQL statement.
    ///
    ///   - bindings: A dictionary of named parameters to bind to the statement.
    ///
    /// - Throws: `Result.Error` if query execution fails.
    ///
    /// - Returns: The statement.
    @discardableResult
    public func run(_ statement: String, _ bindings: [String: Binding?]) throws -> Statement {
        return try prepare(statement).run(bindings)
    }

    // MARK: - Scalar

    /// Runs a single SQL statement (with optional parameter bindings),
    /// returning the first value of the first row.
    ///
    /// - Parameters:
    ///
    ///   - statement: A single SQL statement.
    ///
    ///   - bindings: A list of parameters to bind to the statement.
    ///
    /// - Returns: The first value of the first row returned.
    public func scalar(_ statement: String, _ bindings: Binding?...) -> Binding? {
        return scalar(statement, bindings)
    }

    /// Runs a single SQL statement (with optional parameter bindings),
    /// returning the first value of the first row.
    ///
    /// - Parameters:
    ///
    ///   - statement: A single SQL statement.
    ///
    ///   - bindings: A list of parameters to bind to the statement.
    ///
    /// - Returns: The first value of the first row returned.
    public func scalar(_ statement: String, _ bindings: [Binding?]) -> Binding? {
        return try! prepare(statement).scalar(bindings)
    }

    /// Runs a single SQL statement (with optional parameter bindings),
    /// returning the first value of the first row.
    ///
    /// - Parameters:
    ///
    ///   - statement: A single SQL statement.
    ///
    ///   - bindings: A dictionary of named parameters to bind to the statement.
    ///
    /// - Returns: The first value of the first row returned.
    public func scalar(_ statement: String, _ bindings: [String: Binding?]) -> Binding? {
        return try! prepare(statement).scalar(bindings)
    }

    // MARK: - Transactions

    /// The mode in which a transaction acquires a lock.
    public enum TransactionMode : String {

        /// Defers locking the database till the first read/write executes.
        case Deferred = "DEFERRED"

        /// Immediately acquires a reserved lock on the database.
        case Immediate = "IMMEDIATE"

        /// Immediately acquires an exclusive lock on all databases.
        case Exclusive = "EXCLUSIVE"

    }

    // TODO: Consider not requiring a throw to roll back?
    /// Runs a transaction with the given mode.
    ///
    /// - Note: Transactions cannot be nested. To nest transactions, see
    ///   `savepoint()`, instead.
    ///
    /// - Parameters:
    ///
    ///   - mode: The mode in which a transaction acquires a lock.
    ///
    ///     Default: `.Deferred`
    ///
    ///   - block: A closure to run SQL statements within the transaction.
    ///     The transaction will be committed when the block returns. The block
    ///     must throw to roll the transaction back.
    ///
    /// - Throws: `Result.Error`, and rethrows.
    public func transaction(_ mode: TransactionMode = .Deferred, block: @escaping () throws -> Void) throws {
        try transaction("BEGIN \(mode.rawValue) TRANSACTION", block, "COMMIT TRANSACTION", or: "ROLLBACK TRANSACTION")
    }

    // TODO: Consider not requiring a throw to roll back?
    // TODO: Consider removing ability to set a name?
    /// Runs a transaction with the given savepoint name (if omitted, it will
    /// generate a UUID).
    ///
    /// - SeeAlso: `transaction()`.
    ///
    /// - Parameters:
    ///
    ///   - savepointName: A unique identifier for the savepoint (optional).
    ///
    ///   - block: A closure to run SQL statements within the transaction.
    ///     The savepoint will be released (committed) when the block returns.
    ///     The block must throw to roll the savepoint back.
    ///
    /// - Throws: `SQLite.Result.Error`, and rethrows.
    public func savepoint(_ name: String = UUID().uuidString, block: @escaping () throws -> Void) throws {
        let name = name.quote("'")
        let savepoint = "SAVEPOINT \(name)"

        try transaction(savepoint, block, "RELEASE \(savepoint)", or: "ROLLBACK TO \(savepoint)")
    }

    fileprivate func transaction(_ begin: String, _ block: @escaping () throws -> Void, _ commit: String, or rollback: String) throws {
        return try sync {
            try self.run(begin)
            do {
                try block()
            } catch {
                try self.run(rollback)
                throw error
            }
            try self.run(commit)
        }
    }

    /// Interrupts any long-running queries.
    public func interrupt() {
        sqlite3_interrupt(handle)
    }

    // MARK: - Handlers

    /// The number of seconds a connection will attempt to retry a statement
    /// after encountering a busy signal (lock).
    public var busyTimeout: Double = 0 {
        didSet {
            sqlite3_busy_timeout(handle, Int32(busyTimeout * 1_000))
        }
    }

    /// Sets a handler to call after encountering a busy signal (lock).
    ///
    /// - Parameter callback: This block is executed during a lock in which a
    ///   busy error would otherwise be returned. It’s passed the number of
    ///   times it’s been called for this lock. If it returns `true`, it will
    ///   try again. If it returns `false`, no further attempts will be made.
    public func busyHandler(_ callback: ((_ tries: Int) -> Bool)?) {
        guard let callback = callback else {
            sqlite3_busy_handler(handle, nil, nil)
            busyHandler = nil
            return
        }

        let box: BusyHandler = { callback(Int($0)) ? 1 : 0 }
        sqlite3_busy_handler(handle, { callback, tries in
            unsafeBitCast(callback, to: BusyHandler.self)(tries)
        }, unsafeBitCast(box, to: UnsafeMutableRawPointer.self))
        busyHandler = box
    }
    fileprivate typealias BusyHandler = @convention(block) (Int32) -> Int32
    fileprivate var busyHandler: BusyHandler?

    /// Sets a handler to call when a statement is executed with the compiled
    /// SQL.
    ///
    /// - Parameter callback: This block is invoked when a statement is executed
    ///   with the compiled SQL as its argument.
    ///
    ///       db.trace { SQL in print(SQL) }
    public func trace(_ callback: ((String) -> Void)?) {
        guard let callback = callback else {
            sqlite3_trace(handle, nil, nil)
            trace = nil
            return
        }

        let box: Trace = { callback(String(validatingUTF8: $0)!) }
        sqlite3_trace(handle, { callback, SQL in
            unsafeBitCast(callback, to: Trace.self)(SQL!)
        }, unsafeBitCast(box, to: UnsafeMutableRawPointer.self))
        trace = box
    }
    fileprivate typealias Trace = @convention(block) (UnsafePointer<Int8>) -> Void
    fileprivate var trace: Trace?

    /// Registers a callback to be invoked whenever a row is inserted, updated,
    /// or deleted in a rowid table.
    ///
    /// - Parameter callback: A callback invoked with the `Operation` (one of
    ///   `.Insert`, `.Update`, or `.Delete`), database name, table name, and
    ///   rowid.
    public func updateHook(_ callback: ((_ operation: Operation, _ db: String, _ table: String, _ rowid: Int64) -> Void)?) {
        guard let callback = callback else {
            sqlite3_update_hook(handle, nil, nil)
            updateHook = nil
            return
        }

        let box: UpdateHook = {
            callback(
                Operation(rawValue: $0),
                String(validatingUTF8: $1)!,
                String(validatingUTF8: $2)!,
                $3
            )
        }
        sqlite3_update_hook(handle, { callback, operation, db, table, rowid in
            unsafeBitCast(callback, to: UpdateHook.self)(operation, db!, table!, rowid)
        }, unsafeBitCast(box, to: UnsafeMutableRawPointer.self))
        updateHook = box
    }
    fileprivate typealias UpdateHook = @convention(block) (Int32, UnsafePointer<Int8>, UnsafePointer<Int8>, Int64) -> Void
    fileprivate var updateHook: UpdateHook?

    /// Registers a callback to be invoked whenever a transaction is committed.
    ///
    /// - Parameter callback: A callback invoked whenever a transaction is
    ///   committed. If this callback throws, the transaction will be rolled
    ///   back.
    public func commitHook(_ callback: (() throws -> Void)?) {
        guard let callback = callback else {
            sqlite3_commit_hook(handle, nil, nil)
            commitHook = nil
            return
        }

        let box: CommitHook = {
            do {
                try callback()
            } catch {
                return 1
            }
            return 0
        }
        sqlite3_commit_hook(handle, { callback in
            unsafeBitCast(callback, to: CommitHook.self)()
        }, unsafeBitCast(box, to: UnsafeMutableRawPointer.self))
        commitHook = box
    }
    fileprivate typealias CommitHook = @convention(block) () -> Int32
    fileprivate var commitHook: CommitHook?

    /// Registers a callback to be invoked whenever a transaction rolls back.
    ///
    /// - Parameter callback: A callback invoked when a transaction is rolled
    ///   back.
    public func rollbackHook(_ callback: (() -> Void)?) {
        guard let callback = callback else {
            sqlite3_rollback_hook(handle, nil, nil)
            rollbackHook = nil
            return
        }

        let box: RollbackHook = { callback() }
        sqlite3_rollback_hook(handle, { callback in
            unsafeBitCast(callback, to: RollbackHook.self)()
        }, unsafeBitCast(box, to: UnsafeMutableRawPointer.self))
        rollbackHook = box
    }
    fileprivate typealias RollbackHook = @convention(block) () -> Void
    fileprivate var rollbackHook: RollbackHook?

    /// Creates or redefines a custom SQL function.
    ///
    /// - Parameters:
    ///
    ///   - function: The name of the function to create or redefine.
    ///
    ///   - argumentCount: The number of arguments that the function takes. If
    ///     `nil`, the function may take any number of arguments.
    ///
    ///     Default: `nil`
    ///
    ///   - deterministic: Whether or not the function is deterministic (_i.e._
    ///     the function always returns the same result for a given input).
    ///
    ///     Default: `false`
    ///
    ///   - block: A block of code to run when the function is called. The block
    ///     is called with an array of raw SQL values mapped to the function’s
    ///     parameters and should return a raw SQL value (or nil).
    public func createFunction(_ function: String, argumentCount: UInt? = nil, deterministic: Bool = false, _ block: @escaping (_ args: [Binding?]) -> Binding?) {
        let argc = argumentCount.map { Int($0) } ?? -1
        let box: Function = { context, argc, argv in
            let arguments: [Binding?] = (0..<Int(argc)).map { idx in
                let value = argv[idx]
                switch sqlite3_value_type(value) {
                case SQLITE_BLOB:
                    return Blob(bytes: sqlite3_value_blob(value), length: Int(sqlite3_value_bytes(value)))
                case SQLITE_FLOAT:
                    return sqlite3_value_double(value)
                case SQLITE_INTEGER:
                    return sqlite3_value_int64(value)
                case SQLITE_NULL:
                    return nil
                case SQLITE_TEXT:
                    return String(validatingUTF8: UnsafePointer(sqlite3_value_text(value)))!
                case let type:
                    fatalError("unsupported value type: \(type)")
                }
            }
            let result = block(arguments)
            if let result = result as? Blob {
                sqlite3_result_blob(context, result.bytes, Int32(result.bytes.count), nil)
            } else if let result = result as? Double {
                sqlite3_result_double(context, result)
            } else if let result = result as? Int64 {
                sqlite3_result_int64(context, result)
            } else if let result = result as? String {
                sqlite3_result_text(context, result, Int32(result.characters.count), SQLITE_TRANSIENT)
            } else if result == nil {
                sqlite3_result_null(context)
            } else {
                fatalError("unsupported result type: \(result)")
            }
        }
        var flags = SQLITE_UTF8
        if deterministic {
            flags |= SQLITE_DETERMINISTIC
        }
        sqlite3_create_function_v2(handle, function, Int32(argc), flags, unsafeBitCast(box, to: UnsafeMutableRawPointer.self), { context, argc, value in
            unsafeBitCast(sqlite3_user_data(context), to: Function.self)(context, argc, value)
        }, nil, nil, nil)
        if functions[function] == nil { self.functions[function] = [:] }
        functions[function]?[argc] = box
    }
    fileprivate typealias Function = @convention(block) (OpaquePointer, Int32, UnsafeMutablePointer<OpaquePointer>) -> Void
    fileprivate var functions = [String: [Int: Function]]()

    /// Defines a new collating sequence.
    ///
    /// - Parameters:
    ///
    ///   - collation: The name of the collation added.
    ///
    ///   - block: A collation function that takes two strings and returns the
    ///     comparison result.
    public func createCollation(_ collation: String, _ block: @escaping (_ lhs: String, _ rhs: String) -> ComparisonResult) {
        let box: Collation = { lhs, rhs in
            Int32(block(String(validatingUTF8: UnsafePointer<Int8>(lhs))!, String(validatingUTF8: UnsafePointer<Int8>(rhs))!).rawValue)
        }
        try! check(sqlite3_create_collation_v2(handle, collation, SQLITE_UTF8, unsafeBitCast(box, to: UnsafeMutableRawPointer.self), { callback, _, lhs, _, rhs in
            unsafeBitCast(callback, to: Collation.self)(lhs!, rhs!)
        }, nil))
        collations[collation] = box
    }
    fileprivate typealias Collation = @convention(block) (UnsafeRawPointer, UnsafeRawPointer) -> Int32
    fileprivate var collations = [String: Collation]()

    // MARK: - Error Handling

    @discardableResult
    func sync<T>(_ block: @escaping () throws -> T) rethrows -> T {
        var success: T?
        var failure: Error?

        let box: () -> Void = {
            do {
                success = try block()
            } catch {
                failure = error
            }
        }

        if DispatchQueue.getSpecific(key: Connection.queueKey) == queueContext {
            box()
        } else {
            (queue).sync(execute: box) // FIXME: rdar://problem/21389236
        }

        if let failure = failure {
            try { () -> Void in throw failure }()
        }

        return success!
    }

    @discardableResult
    func check(_ resultCode: Int32, statement: Statement? = nil) throws -> Int32 {
        guard let error = Result(errorCode: resultCode, connection: self, statement: statement) else {
            return resultCode
        }

        throw error
    }

    fileprivate var queue = DispatchQueue(label: "SQLite.Database", attributes: .serial)

    fileprivate static let queueKey = DispatchSpecificKey<()>()
//    private static let queueKey = unsafeBitCast(Connection.self, to: UnsafePointer<Void>.self)

    fileprivate lazy var queueContext: UnsafeMutableRawPointer = unsafeBitCast(self, to: UnsafeMutableRawPointer.self)

}

extension Connection : CustomStringConvertible {

    public var description: String {
        return String(validatingUTF8: sqlite3_db_filename(handle, nil))!
    }

}

extension Connection.Location : CustomStringConvertible {

    public var description: String {
        switch self {
        case .inMemory:
            return ":memory:"
        case .temporary:
            return ""
        case .uri(let URI):
            return URI
        }
    }

}

/// An SQL operation passed to update callbacks.
public enum Operation {

    /// An INSERT operation.
    case insert

    /// An UPDATE operation.
    case update

    /// A DELETE operation.
    case delete

    fileprivate init(rawValue: Int32) {
        switch rawValue {
        case SQLITE_INSERT:
            self = .insert
        case SQLITE_UPDATE:
            self = .update
        case SQLITE_DELETE:
            self = .delete
        default:
            fatalError("unhandled operation code: \(rawValue)")
        }
    }

}

public enum Result : Error {

    fileprivate static let successCodes: Set = [SQLITE_OK, SQLITE_ROW, SQLITE_DONE]

    case error(message: String, code: Int32, statement: Statement?)

    init?(errorCode: Int32, connection: Connection, statement: Statement? = nil) {
        guard !Result.successCodes.contains(errorCode) else { return nil }

        let message = String(validatingUTF8: sqlite3_errmsg(connection.handle))!
        self = Error(message: message, code: errorCode, statement: statement)
    }

}

extension Result : CustomStringConvertible {

    public var description: String {
        switch self {
        case let .error(message, _, statement):
            guard let statement = statement else { return message }

            return "\(message) (\(statement))"
        }
    }

}
