//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDBCipher
import SignalCoreKit

// This class can be used to:
//
// * Back a preferences class.
// * To persist simple values in our managers.
// * Etc.
@objc
public class SDSKeyValueStore: NSObject {

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private let collection: String

    private let keyColumn: SDSColumnMetadata
    private let valueColumn: SDSColumnMetadata
    private let tableMetadata: SDSTableMetadata

    @objc
    public init(collection: String) {
        // TODO: Verify that collection is a valid table name _OR_ convert to valid name.
        self.collection = collection

        // TODO:
        keyColumn = SDSColumnMetadata(columnName: "key", columnType: .unicodeString, isOptional: false)
        valueColumn = SDSColumnMetadata(columnName: "value", columnType: .blob, isOptional: false)
        tableMetadata = SDSTableMetadata(tableName: "keyvalue_\(collection)", columns: [
            keyColumn,
            valueColumn
            ])

        super.init()
    }

    // TODO: This method should be invoked on startup, before "database is ready".
    @objc
    public func ensureTableExists() {
        databaseStorage.writeSwallowingErrors { (transaction) in
            transaction.ensureTableExists(self.tableMetadata)
        }
    }

    // MARK: -

    @objc
    public func getString(_ key: String) -> String? {
        return read(key)
    }

    @objc
    public func setString(_ value: String, key: String) {
        write(value as NSString, forKey: key)
    }

    @objc
    public func getBool(_ key: String, defaultValue: Bool = false) -> Bool {
        if let value: NSNumber = read(key) {
            return value.boolValue
        } else {
            return defaultValue
        }
    }

    @objc
    public func setBool(_ value: Bool, key: String) {
        write(NSNumber(booleanLiteral: value), forKey: key)
    }

    // MARK: -

    private func read<T>(_ key: String) -> T? {
        var result: T?

        databaseStorage.readSwallowingErrors { (transaction) in
            guard let database = transaction.transitional_grdbReadTransaction else {
                owsFail("Invalid transaction.")
            }

            var encoded: Data?
            do {
                encoded = try Data.fetchOne(database,
                                            sql: "SELECT \(self.valueColumn.columnName) FROM \(self.tableMetadata.tableName) WHERE \(self.keyColumn.columnName) = ?",
                arguments: [key])
            } catch {
                // This isn't necessarily an error; there may be no matching row.
                //
                // TODO: Should we do a 'SELECT COUNT' first so we can distinguish
                // "not found" from actual errors? Or can we discriminate by error type?
                //
                // owsFailDebug("Read failed.")
                return
            }

            do {
                if let encoded = encoded {
                    guard let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded) as? T else {
                        owsFailDebug("Could not decode value.")
                        return
                    }
                    result = decoded
                }
            } catch {
                owsFailDebug("Read failed.")
            }
        }
        return result
    }

    // TODO: Codable? NSCoding? Other serialization?
    private func write(_ value: NSCoding?, forKey key: String) {
        var encoded: Data?
        if let value = value {
            encoded = NSKeyedArchiver.archivedData(withRootObject: value)
        }

        databaseStorage.writeSwallowingErrors { (transaction) in
            guard let database = transaction.transitional_grdbWriteTransaction else {
                owsFail("Invalid transaction.")
            }
            do {
                try self.write(database: database, key: key, encoded: encoded)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    private func write(database: Database, key: String, encoded: Data?) throws {
        if let encoded = encoded {
            let count = try Int.fetchOne(database,
                                         sql: "SELECT COUNT(*) FROM \(tableMetadata.tableName) WHERE \(keyColumn.columnName) == ?",
                arguments: [
                    key
                ]) ?? 0
            if count > 0 {
                let sql = "UPDATE \(tableMetadata.tableName) SET \(valueColumn.columnName) = ? WHERE \(keyColumn.columnName) = ?"
                try update(database: database, sql: sql, arguments: [ encoded, key ])
            } else {
                let sql = "INSERT INTO \(tableMetadata.tableName) (\(keyColumn.columnName), \(valueColumn.columnName)) VALUES (?, ?)"
                try update(database: database, sql: sql, arguments: [ key, encoded ])
            }
        } else {
            // Setting to nil is a delete.
            let sql = "DELETE FROM \(tableMetadata.tableName) WHERE \(keyColumn.columnName) == ?"
            try update(database: database, sql: sql, arguments: [ key ])
        }
    }

    // In practice, arguments should all be DatabaseValueConvertible,
    // but that protocol is not @objc.
    private func update(database: Database,
                        sql: String,
                        arguments: [Any]) throws {

        let statement = try database.cachedUpdateStatement(sql: sql)
        guard let statementArguments = StatementArguments(arguments) else {
            owsFail("Could not convert values.")
        }
        // TODO: We could use setArgumentsWithValidation for more safety.
        statement.unsafeSetArguments(statementArguments)
        try statement.execute()
    }
}
