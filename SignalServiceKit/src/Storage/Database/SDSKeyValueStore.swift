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

    // By default, all reads/writes use this collection.
    public let collection: String

    private static let collectionColumn = SDSColumnMetadata(columnName: "collection", columnType: .unicodeString, isOptional: false)
    private static let keyColumn = SDSColumnMetadata(columnName: "key", columnType: .unicodeString, isOptional: false)
    private static let valueColumn = SDSColumnMetadata(columnName: "value", columnType: .blob, isOptional: false)
    // TODO: For now, store all key-value in a single table.
    public static let table = SDSTableMetadata(tableName: "keyvalue", columns: [
        collectionColumn,
        keyColumn,
        valueColumn
        ])

    @objc
    public init(collection: String) {
        // TODO: Verify that collection is a valid table name _OR_ convert to valid name.
        self.collection = collection

        super.init()
    }

    // MARK: - String

    @objc
    public func getString(_ key: String, transaction: SDSAnyReadTransaction) -> String? {
        return read(key, transaction: transaction)
    }

    @objc
    public func setString(_ value: String?, key: String, transaction: SDSAnyWriteTransaction) {
        guard let value = value else {
            write(nil, forKey: key, transaction: transaction)
            return
        }
        write(value as NSString, forKey: key, transaction: transaction)
    }

    // MARK: - Bool

    @objc
    public func getBool(_ key: String, defaultValue: Bool = false, transaction: SDSAnyReadTransaction) -> Bool {
        if let value: NSNumber = read(key, transaction: transaction) {
            return value.boolValue
        } else {
            return defaultValue
        }
    }

    @objc
    public func setBool(_ value: Bool, key: String, transaction: SDSAnyWriteTransaction) {
        write(NSNumber(booleanLiteral: value), forKey: key, transaction: transaction)
    }

    // MARK: - Data

    @objc
    public func getData(_ key: String, transaction: SDSAnyReadTransaction) -> Data? {
        return readData(key, transaction: transaction)
    }

    @objc
    public func setData(_ value: Data?, key: String, transaction: SDSAnyWriteTransaction) {
        writeData(value, forKey: key, transaction: transaction)
    }

    // MARK: - Object

    @objc
    public func getObject(_ key: String, transaction: SDSAnyReadTransaction) -> Any? {
        return read(key, transaction: transaction)
    }

    @objc
    public func setObject(_ anyValue: Any?, key: String, transaction: SDSAnyWriteTransaction) {
        guard let anyValue = anyValue else {
            write(nil, forKey: key, transaction: transaction)
            return
        }
        guard let codingValue = anyValue as? NSCoding else {
            owsFailDebug("Invalid value.")
            write(nil, forKey: key, transaction: transaction)
            return
        }
        write(codingValue, forKey: key, transaction: transaction)
    }

    // MARK: - Debugging

    @objc
    public func allKeys(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            return ydbTransaction.allKeys(inCollection: collection)
        case .grdbRead(let grdbRead):
            let sql = """
            SELECT \(SDSKeyValueStore.keyColumn.columnName)
            FROM \(SDSKeyValueStore.table.tableName)
            WHERE \(SDSKeyValueStore.collectionColumn.columnName) == ?
            """
            return try! String.fetchAll(grdbRead.database,
                                        sql: sql,
                                        arguments: [collection])
        }
    }

    // MARK: - Internal Methods

    private func read<T>(_ key: String, transaction: SDSAnyReadTransaction) -> T? {
        // YDB values are serialized by YDB.
        // GRDB values are serialized to data by this class.
        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            guard let rawObject = ydbTransaction.object(forKey: key, inCollection: collection) else {
                return nil
            }
            guard let object = rawObject as? T else {
                owsFailDebug("Value has unexpected type: \(type(of: rawObject)).")
                return nil
            }
            return object
        case .grdbRead:
            guard let encoded = readData(key, transaction: transaction) else {
                return nil
            }

            do {
                guard let decoded = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded) as? T else {
                    owsFailDebug("Could not decode value.")
                    return nil
                }
                return decoded
            } catch {
                owsFailDebug("Decode failed.")
                return nil
            }
        }
    }

    private func readData(_ key: String, transaction: SDSAnyReadTransaction) -> Data? {
        let collection = self.collection

        switch transaction.readTransaction {
        case .yapRead(let ydbTransaction):
            guard let rawObject = ydbTransaction.object(forKey: key, inCollection: collection) else {
                return nil
            }
            guard let object = rawObject as? Data else {
                owsFailDebug("Value has unexpected type: \(type(of: rawObject)).")
                return nil
            }
            return object
        case .grdbRead(let grdbTransaction):
            return SDSKeyValueStore.readData(transaction: grdbTransaction, key: key, collection: collection)
        }
    }

    private class func readData(transaction: GRDBReadTransaction, key: String, collection: String) -> Data? {
        do {
            return try Data.fetchOne(transaction.database,
                                     sql: "SELECT \(self.valueColumn.columnName) FROM \(self.table.tableName) WHERE \(self.keyColumn.columnName) = ? AND \(collectionColumn.columnName) == ?",
                arguments: [key, collection])
        } catch {
            owsFailDebug("Read failed.")
            return nil
        }
    }

    // TODO: Codable? NSCoding? Other serialization?
    private func write(_ value: NSCoding?, forKey key: String, transaction: SDSAnyWriteTransaction) {
        // YDB values are serialized by YDB.
        // GRDB values are serialized to data by this class.
        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            if let value = value {
                ydbTransaction.setObject(value, forKey: key, inCollection: collection)
            } else {
                ydbTransaction.removeObject(forKey: key, inCollection: collection)
            }
        case .grdbWrite:
            if let value = value {
                let encoded = NSKeyedArchiver.archivedData(withRootObject: value)
                writeData(encoded, forKey: key, transaction: transaction)
            } else {
                writeData(nil, forKey: key, transaction: transaction)
            }
        }
    }

    private func writeData(_ data: Data?, forKey key: String, transaction: SDSAnyWriteTransaction) {

        let collection = self.collection

        switch transaction.writeTransaction {
        case .yapWrite(let ydbTransaction):
            if let data = data {
                ydbTransaction.setObject(data, forKey: key, inCollection: collection)
            } else {
                ydbTransaction.removeObject(forKey: key, inCollection: collection)
            }
        case .grdbWrite(let grdbTransaction):
            do {
                try SDSKeyValueStore.write(transaction: grdbTransaction, key: key, collection: collection, encoded: data)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    private class func write(transaction: GRDBWriteTransaction, key: String, collection: String, encoded: Data?) throws {
        if let encoded = encoded {
            let count = try Int.fetchOne(transaction.database,
                                         sql: "SELECT COUNT(*) FROM \(table.tableName) WHERE \(keyColumn.columnName) == ? AND \(collectionColumn.columnName) == ?",
                arguments: [
                    key, collection
                ]) ?? 0
            if count > 0 {
                let sql = "UPDATE \(table.tableName) SET \(valueColumn.columnName) = ? WHERE \(keyColumn.columnName) = ? AND \(collectionColumn.columnName) == ?"
                try update(transaction: transaction, sql: sql, arguments: [ encoded, key, collection ])
            } else {
                let sql = "INSERT INTO \(table.tableName) ( \(keyColumn.columnName), \(collectionColumn.columnName), \(valueColumn.columnName) ) VALUES (?, ?, ?)"
                try update(transaction: transaction, sql: sql, arguments: [ key, collection, encoded ])
            }
        } else {
            // Setting to nil is a delete.
            let sql = "DELETE FROM \(table.tableName) WHERE \(keyColumn.columnName) == ? AND  \(collectionColumn.columnName) == ?"
            try update(transaction: transaction, sql: sql, arguments: [ key, collection ])
        }
    }

    private class func update(transaction: GRDBWriteTransaction,
                        sql: String,
                        arguments: [DatabaseValueConvertible]) throws {

        let statement = try transaction.database.cachedUpdateStatement(sql: sql)
        guard let statementArguments = StatementArguments(arguments) else {
            owsFailDebug("Could not convert values.")
            return
        }
        // TODO: We could use setArgumentsWithValidation for more safety.
        statement.unsafeSetArguments(statementArguments)
        try statement.execute()
    }
}
