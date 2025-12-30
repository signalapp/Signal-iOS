//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB

/// An efficient-on-disk Key-Value Store.
///
/// This type is capable of storing boolean, integer, double, string, and
/// data values. They are stored in SQLite-native representations. It is not
/// natively capable of storing "complex" objects encoded via JSONEncoder or
/// NSKeyedArchiver; callers should convert these to Data themselves.
///
/// This type is not backwards compatible with `KeyValueStore` (except for
/// `Data` values), though `KeyValueStoreMigrator` can migrate values to the
/// new representation.
public struct NewKeyValueStore {
    enum TableMetadata {
        enum Columns {
            static let collection = "collection"
            static let key = "key"
            static let value = "value"
        }

        static let tableName = "keyvalue"
    }

    static var tableName: String { TableMetadata.tableName }
    static var collectionColumnName: String { TableMetadata.Columns.collection }

    private let collection: String

    public init(collection: String) {
        self.collection = collection
    }

    /// Remove all values or crash if an error occurs.
    public func removeAll(tx: DBWriteTransaction) {
        failIfThrowsDatabaseError { () throws(GRDB.DatabaseError) in
            try self.removeAllOrThrow(tx: tx)
        }
    }

    /// Remove all values or throw the error that occurs.
    public func removeAllOrThrow(tx: DBWriteTransaction) throws(GRDB.DatabaseError) {
        return try withDatabaseError { try self._removeAllOrThrow(tx: tx) }
    }

    /// Fetch all the keys or crash if an error occurs.
    public func fetchKeys(tx: DBReadTransaction) -> [String] {
        return failIfThrowsDatabaseError { () throws(GRDB.DatabaseError) in
            return try self.fetchKeysOrThrow(tx: tx)
        }
    }

    /// Fetch all the keys or throw the error that occurs.
    public func fetchKeysOrThrow(tx: DBReadTransaction) throws(GRDB.DatabaseError) -> [String] {
        return try withDatabaseError { try self._getKeysOrThrow(tx: tx) }
    }

    /// Fetch a value (or nil if it doesn't exist) or crash if an error occurs.
    public func fetchValue<T: KeyValueStoreValue>(_ type: T.Type, forKey key: String, tx: DBReadTransaction) -> T? {
        return failIfThrowsDatabaseError { () throws(GRDB.DatabaseError) in
            return try fetchValueOrThrow(T.self, forKey: key, tx: tx)
        }
    }

    /// Fetch a value (or nil if it doesn't exist) or throw the error that occurs.
    public func fetchValueOrThrow<T: KeyValueStoreValue>(_ type: T.Type, forKey key: String, tx: DBReadTransaction) throws(GRDB.DatabaseError) -> T? {
        return try withDatabaseError {
            return try self._getValueOrThrow(T.DatabaseType.self, key: key, tx: tx).map(T.init(keyValueStoreValue:))
        }
    }

    /// Write/clear a value or crash if an error occurs.
    public func writeValue<T: KeyValueStoreValue>(_ value: T?, forKey key: String, tx: DBWriteTransaction) {
        failIfThrowsDatabaseError { () throws(GRDB.DatabaseError) in
            try writeValueOrThrow(value, forKey: key, tx: tx)
        }
    }

    /// Write/clear a value or throw the error that occurs.
    public func writeValueOrThrow<T: KeyValueStoreValue>(_ value: T?, forKey key: String, tx: DBWriteTransaction) throws(GRDB.DatabaseError) {
        try withDatabaseError { try self._setValueOrThrow(value?.keyValueStoreValue, key: key, tx: tx) }
    }

    /// Clear a value or crash if an error occurs.
    public func removeValue(forKey key: String, tx: DBWriteTransaction) {
        failIfThrowsDatabaseError { () throws(GRDB.DatabaseError) in
            try self.removeValueOrThrow(forKey: key, tx: tx)
        }
    }

    /// Clear a value or throw the error that occurs.
    public func removeValueOrThrow(forKey key: String, tx: DBWriteTransaction) throws(GRDB.DatabaseError) {
        try self.writeValueOrThrow(nil as Data?, forKey: key, tx: tx)
    }

    private func withDatabaseError<T>(_ block: () throws -> T) throws(GRDB.DatabaseError) -> T {
        do {
            return try block()
        } catch {
            throw error.forceCastToDatabaseError()
        }
    }

    public static func logCollectionStatistics(tx: DBReadTransaction) {
        Logger.info("KeyValueStore statistics:")
        do {
            let sql = """
            SELECT \(TableMetadata.Columns.collection), COUNT(*)
            FROM \(TableMetadata.tableName)
            GROUP BY \(TableMetadata.Columns.collection)
            ORDER BY COUNT(*) DESC
            LIMIT 10
            """
            let cursor = try Row.fetchCursor(tx.database, sql: sql)
            while let row = try cursor.next() {
                let collection: String = row[0]
                let count: Int64 = row[1]
                Logger.info("- \(collection): \(count) items")
            }
        } catch {
            Logger.warn("\(error.grdbErrorForLogging)")
        }
    }

    // MARK: - CRUD Methods

    private func _getValueOrThrow<T: DatabaseValueConvertible>(_ type: T.Type, key: String, tx: DBReadTransaction) throws -> T? {
        return try T.fetchOne(
            tx.database,
            sql: """
            SELECT \(TableMetadata.Columns.value)
            FROM \(TableMetadata.tableName)
            WHERE
                \(TableMetadata.Columns.key) = ?
                AND \(TableMetadata.Columns.collection) == ?
            """,
            arguments: [key, collection],
        )
    }

    private func _getKeysOrThrow(tx: DBReadTransaction) throws -> [String] {
        return try String.fetchAll(
            tx.database,
            sql: """
            SELECT \(TableMetadata.Columns.key)
            FROM \(TableMetadata.tableName)
            WHERE \(TableMetadata.Columns.collection) == ?
            """,
            arguments: [collection],
        )
    }

    private func _setValueOrThrow<T: DatabaseValueConvertible>(_ value: T?, key: String, tx: DBWriteTransaction) throws {
        let sql: String
        let arguments: StatementArguments
        if let value {
            // See: https://www.sqlite.org/lang_UPSERT.html
            sql = """
            INSERT INTO \(TableMetadata.tableName) (
                \(TableMetadata.Columns.key),
                \(TableMetadata.Columns.collection),
                \(TableMetadata.Columns.value)
            ) VALUES (?, ?, ?)
            ON CONFLICT (
                \(TableMetadata.Columns.key),
                \(TableMetadata.Columns.collection)
            ) DO UPDATE
            SET \(TableMetadata.Columns.value) = ?
            """
            arguments = [key, collection, value, value]
        } else {
            // Setting to nil is a delete.
            sql = """
            DELETE FROM \(TableMetadata.tableName)
            WHERE
                \(TableMetadata.Columns.key) == ?
                AND \(TableMetadata.Columns.collection) == ?
            """
            arguments = [key, collection]
        }

        let statement = try tx.database.cachedStatement(sql: sql)
        try statement.setArguments(arguments)
        try statement.execute()
    }

    private func _removeAllOrThrow(tx: DBWriteTransaction) throws {
        try tx.database.execute(
            sql: """
            DELETE
            FROM \(TableMetadata.tableName)
            WHERE \(TableMetadata.Columns.collection) == ?
            """,
            arguments: [collection],
        )
    }
}

// MARK: -

// These "implement" the on-disk representation for primitives supported by
// NewKeyValueStore. They are typically "put the value directly in SQLite",
// though there are two exceptions for things that (1) can be represented
// in both SQLite & Swift, (2) have a non-failable path between those
// representations, and (3) aren't bridged automatically. (A UInt64 can be
// stored in the database, but we need to pass it to SQLite as an Int64,
// and we need to read it back as an Int64.)

public protocol KeyValueStoreValue<DatabaseType> {
    associatedtype DatabaseType where DatabaseType: DatabaseValueConvertible
    var keyValueStoreValue: DatabaseType { get }
    init(keyValueStoreValue: DatabaseType)
}

extension Data: KeyValueStoreValue {
    public var keyValueStoreValue: Data { self }
    public init(keyValueStoreValue: Data) { self = keyValueStoreValue }
}

extension String: KeyValueStoreValue {
    public var keyValueStoreValue: String { self }
    public init(keyValueStoreValue: String) { self = keyValueStoreValue }
}

extension Bool: KeyValueStoreValue {
    public var keyValueStoreValue: Bool { self }
    public init(keyValueStoreValue: Bool) { self = keyValueStoreValue }
}

extension Double: KeyValueStoreValue {
    public var keyValueStoreValue: Double { self }
    public init(keyValueStoreValue: Double) { self = keyValueStoreValue }
}

extension Int64: KeyValueStoreValue {
    public var keyValueStoreValue: Int64 { self }
    public init(keyValueStoreValue: Int64) { self = keyValueStoreValue }
}

extension UInt64: KeyValueStoreValue {
    public var keyValueStoreValue: Int64 { Int64(bitPattern: self) }
    public init(keyValueStoreValue: Int64) { self.init(bitPattern: keyValueStoreValue) }
}

extension Date: KeyValueStoreValue {
    public var keyValueStoreValue: Double { self.timeIntervalSince1970 }
    public init(keyValueStoreValue: Double) { self.init(timeIntervalSince1970: keyValueStoreValue) }
}

// MARK: -

struct KeyValueStoreMigrator {
    private let collection: String

    init(collection: String) {
        self.collection = collection
    }

    /// Migrate a single NSKeyedArchiver-encoded value.
    ///
    /// If an error occurs fetching from/writing to the database, that error is rethrown.
    ///
    /// If an error occurs when parsing an NSKeyedArchiver-encoded value, that
    /// error is not thrown, and the value is deleted. This maintains the old
    /// behavior where decoding errors behave as if the value isn't set.
    func migrateKey<V1Type: NSObject & NSSecureCoding, V2Type: DatabaseValueConvertible>(
        _ key: String,
        withValueOfType oldType: V1Type.Type,
        toNewValue migrateValue: (V1Type) -> V2Type,
        tx: DBWriteTransaction,
    ) throws {
        let dataValue = try Data.fetchOne(
            tx.database,
            sql: "SELECT value FROM keyvalue WHERE collection = ? AND key = ?",
            arguments: [collection, key],
        )
        guard let dataValue else {
            // The representation of `nil` doesn't change.
            return
        }
        // Dates may have been stored as NSDates or NSNumbers; this method handles
        // both representations.
        let isDateValue = V1Type.self == NSDate.self
        let oldTypes = isDateValue ? [V1Type.self, NSNumber.self] : [oldType]
        let oldValue: V1Type
        switch try? NSKeyedUnarchiver.unarchivedObject(ofClasses: oldTypes, from: dataValue) {
        case let _oldValue as V1Type:
            oldValue = _oldValue
        case let numberValue as NSNumber where isDateValue:
            oldValue = NSDate(timeIntervalSince1970: numberValue.doubleValue) as! V1Type
        default:
            // The old KeyValueStore silently ignores malformed values. Do the same here.
            Logger.error("Couldn't migrate '\(key)' in '\(collection)' because it was malformed.")
            try tx.database.execute(
                sql: "DELETE FROM keyvalue WHERE collection = ? AND key = ?",
                arguments: [collection, key],
            )
            return
        }
        let newValue = migrateValue(oldValue)
        try tx.database.execute(
            sql: "UPDATE keyvalue SET value = ? WHERE collection = ? AND key = ?",
            arguments: [newValue, collection, key],
        )
    }

    func migrateString(_ key: String, tx: DBWriteTransaction) throws {
        return try migrateKey(key, withValueOfType: NSString.self, toNewValue: { $0 as String }, tx: tx)
    }

    func migrateDate(_ key: String, tx: DBWriteTransaction) throws {
        return try migrateKey(key, withValueOfType: NSDate.self, toNewValue: \.timeIntervalSince1970, tx: tx)
    }

    func migrateUInt32(_ key: String, tx: DBWriteTransaction) throws {
        return try migrateKey(key, withValueOfType: NSNumber.self, toNewValue: { Int64($0.uint32Value) }, tx: tx)
    }

    func migrateBool(_ key: String, tx: DBWriteTransaction) throws {
        return try migrateKey(key, withValueOfType: NSNumber.self, toNewValue: \.boolValue, tx: tx)
    }
}
