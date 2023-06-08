//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

// This class can be used to:
//
// * Back a preferences class.
// * To persist simple values in our managers.
// * Etc.
@objc
public class SDSKeyValueStore: NSObject {

    // Key-value stores use "collections" to group related keys.
    //
    // * In GRDB, we store each model in a separate table but
    //   all k-v stores are in a single table.
    //   GRDB maintains a mapping between tables and collections.
    //   For the purposes of this mapping only we use dataStoreCollection.
    static let dataStoreCollection = "keyvalue"
    static let tableName = "keyvalue"

    // By default, all reads/writes use this collection.
    @objc
    public let collection: String

    static let collectionColumn = SDSColumnMetadata(columnName: "collection", columnType: .unicodeString, isOptional: false)
    static let keyColumn = SDSColumnMetadata(columnName: "key", columnType: .unicodeString, isOptional: false)
    static let valueColumn = SDSColumnMetadata(columnName: "value", columnType: .blob, isOptional: false)
    // TODO: For now, store all key-value in a single table.
    public static let table = SDSTableMetadata(
        collection: SDSKeyValueStore.dataStoreCollection,
        tableName: SDSKeyValueStore.tableName,
        columns: [
            collectionColumn,
            keyColumn,
            valueColumn
        ]
    )

    @objc
    public required init(collection: String) {
        // TODO: Verify that collection is a valid table name _OR_ convert to valid name.
        self.collection = collection

        super.init()
    }

    @objc
    public class func logCollectionStatistics() {
        Logger.info("SDSKeyValueStore statistics:")
        databaseStorage.read { transaction in
            do {
                let sql = """
                    SELECT \(collectionColumn.columnName), COUNT(*)
                    FROM \(table.tableName)
                    GROUP BY \(collectionColumn.columnName)
                    ORDER BY COUNT(*) DESC
                    """
                let cursor = try Row.fetchCursor(transaction.unwrapGrdbRead.database, sql: sql)
                while let row = try cursor.next() {
                    let collection: String = row[0]
                    let count: UInt = row[1]
                    Logger.info("- \(collection): \(count) items")
                }
            } catch {
                Logger.error("\(error)")
            }
        }
    }

    // MARK: Class Helpers

    @objc
    public class func key(int: Int) -> String {
        return NSNumber(value: int).stringValue
    }

    @objc
    public func hasValue(forKey key: String, transaction: SDSAnyReadTransaction) -> Bool {
        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):
            do {
                let count = try UInt.fetchOne(grdbTransaction.database,
                                              sql: """
                    SELECT
                    COUNT(*)
                    FROM \(SDSKeyValueStore.table.tableName)
                    WHERE \(SDSKeyValueStore.keyColumn.columnName) = ?
                    AND \(SDSKeyValueStore.collectionColumn.columnName) == ?
                    """,
                                              arguments: [key, collection]) ?? 0
                return count > 0
            } catch {
                owsFailDebug("error: \(error)")
                return false
            }
        }
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

    // MARK: - Date

    @objc
    public func getDate(_ key: String, transaction: SDSAnyReadTransaction) -> Date? {
        // Our legacy methods sometimes stored dates as NSNumber and
        // sometimes as NSDate, so we are permissive when decoding.
        guard let object: NSObject = read(key, transaction: transaction) else {
            return nil
        }
        if let date = object as? Date {
            return date
        }
        guard let epochInterval = object as? NSNumber else {
            owsFailDebug("Could not decode value: \(type(of: object)).")
            return nil
        }
        return Date(timeIntervalSince1970: epochInterval.doubleValue)
    }

    @objc
    public func setDate(_ value: Date, key: String, transaction: SDSAnyWriteTransaction) {
        let epochInterval = NSNumber(value: value.timeIntervalSince1970)
        setObject(epochInterval, key: key, transaction: transaction)
    }

    // MARK: - Bool

    public func getBool(_ key: String, transaction: SDSAnyReadTransaction) -> Bool? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.boolValue
    }

    @objc
    public func getBool(_ key: String, defaultValue: Bool, transaction: SDSAnyReadTransaction) -> Bool {
        return getBool(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setBool(_ value: Bool, key: String, transaction: SDSAnyWriteTransaction) {
        write(NSNumber(value: value), forKey: key, transaction: transaction)
    }

    @objc
    public func setBoolIfChanged(_ value: Bool,
                                 defaultValue: Bool,
                                 key: String,
                                 transaction: SDSAnyWriteTransaction) {
        let didChange = value != getBool(key,
                                         defaultValue: defaultValue,
                                         transaction: transaction)
        guard didChange else {
            return
        }
        setBool(value, key: key, transaction: transaction)
    }

    // MARK: - UInt

    public func getUInt(_ key: String, transaction: SDSAnyReadTransaction) -> UInt? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.uintValue
    }

    // TODO: Handle numerics more generally.
    @objc
    public func getUInt(_ key: String, defaultValue: UInt, transaction: SDSAnyReadTransaction) -> UInt {
        return getUInt(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setUInt(_ value: UInt, key: String, transaction: SDSAnyWriteTransaction) {
        write(NSNumber(value: value), forKey: key, transaction: transaction)
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

    // MARK: - Numeric

    @objc
    public func getNSNumber(_ key: String, transaction: SDSAnyReadTransaction) -> NSNumber? {
        let number: NSNumber? = read(key, transaction: transaction)
        return number
    }

    // MARK: - Int

    public func getInt(_ key: String, transaction: SDSAnyReadTransaction) -> Int? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.intValue
    }

    @objc
    public func getInt(_ key: String, defaultValue: Int, transaction: SDSAnyReadTransaction) -> Int {
        return getInt(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setInt(_ value: Int, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - UInt32

    public func getUInt32(_ key: String, transaction: SDSAnyReadTransaction) -> UInt32? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.uint32Value
    }

    @objc
    public func getUInt32(_ key: String, defaultValue: UInt32, transaction: SDSAnyReadTransaction) -> UInt32 {
        return getUInt32(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setUInt32(_ value: UInt32, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - UInt64

    public func getUInt64(_ key: String, transaction: SDSAnyReadTransaction) -> UInt64? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.uint64Value
    }

    @objc
    public func getUInt64(_ key: String, defaultValue: UInt64, transaction: SDSAnyReadTransaction) -> UInt64 {
        return getUInt64(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setUInt64(_ value: UInt64, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - Int64

    public func getInt64(_ key: String, transaction: SDSAnyReadTransaction) -> Int64? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.int64Value
    }

    @objc
    public func getInt64(_ key: String, defaultValue: Int64, transaction: SDSAnyReadTransaction) -> Int64 {
        return getInt64(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setInt64(_ value: Int64, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - Double

    public func getDouble(_ key: String, transaction: SDSAnyReadTransaction) -> Double? {
        guard let number: NSNumber = read(key, transaction: transaction) else {
            return nil
        }
        return number.doubleValue
    }

    @objc
    public func getDouble(_ key: String, defaultValue: Double, transaction: SDSAnyReadTransaction) -> Double {
        return getDouble(key, transaction: transaction) ?? defaultValue
    }

    @objc
    public func setDouble(_ value: Double, key: String, transaction: SDSAnyWriteTransaction) {
        setObject(NSNumber(value: value), key: key, transaction: transaction)
    }

    // MARK: - Object

    @objc
    public func getObject(forKey key: String, transaction: SDSAnyReadTransaction) -> Any? {
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

    // MARK: - 

    @objc
    public func removeValue(forKey key: String, transaction: SDSAnyWriteTransaction) {
        write(nil, forKey: key, transaction: transaction)
    }

    @objc
    public func removeValues(forKeys keys: [String], transaction: SDSAnyWriteTransaction) {
        for key in keys {
            write(nil, forKey: key, transaction: transaction)
        }
    }

    @objc
    public func removeAll(transaction: SDSAnyWriteTransaction) {
        switch transaction.writeTransaction {
        case .grdbWrite(let grdbWrite):
            let sql = """
                DELETE
                FROM \(SDSKeyValueStore.table.tableName)
                WHERE \(SDSKeyValueStore.collectionColumn.columnName) == ?
            """
            grdbWrite.executeAndCacheStatement(sql: sql, arguments: [collection])
        }
    }

    @objc
    public func enumerateKeysAndObjects(transaction: SDSAnyReadTransaction, block: @escaping (String, Any, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            var stop: ObjCBool = false
            // PERF - we could enumerate with a single query rather than
            // fetching keys then fetching objects one by one. In practice
            // the collections that use this are pretty small.
            for key in allKeys(grdbTransaction: grdbRead) {
                guard !stop.boolValue else {
                    return
                }
                guard let value: Any = read(key, transaction: transaction) else {
                    owsFailDebug("value was unexpectedly nil")
                    continue
                }
                block(key, value, &stop)
            }
        }
    }

    @objc
    public func enumerateKeys(transaction: SDSAnyReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            var stop: ObjCBool = false
            for key in allKeys(grdbTransaction: grdbRead) {
                guard !stop.boolValue else {
                    return
                }
                block(key, &stop)
            }
        }
    }

    @objc
    public func allValues(transaction: SDSAnyReadTransaction) -> [Any] {
        return allKeys(transaction: transaction).compactMap { key in
            return self.read(key, transaction: transaction)
        }
    }

    @objc
    public func allDataValues(transaction: SDSAnyReadTransaction) -> [Data] {
        return allKeys(transaction: transaction).compactMap { key in
            return self.getData(key, transaction: transaction)
        }
    }

    private struct PairRecord: Codable, FetchableRecord, PersistableRecord {
        public let key: String?
        public let value: Data?
    }

    private func allPairs(transaction: SDSAnyReadTransaction) -> [PairRecord] {

        switch transaction.readTransaction {
        case .grdbRead(let grdbTransaction):

            let sql = """
            SELECT
                \(SDSKeyValueStore.keyColumn.columnName),
                \(SDSKeyValueStore.valueColumn.columnName)
            FROM \(SDSKeyValueStore.table.tableName)
            WHERE \(SDSKeyValueStore.collectionColumn.columnName) == ?
            """

            do {
                return try PairRecord.fetchAll(grdbTransaction.database,
                                               sql: sql,
                                               arguments: [collection])
            } catch {
                owsFailDebug("Error: \(error)")
                return []
            }
        }
    }

    @objc
    public func allBoolValuesMap(transaction: SDSAnyReadTransaction) -> [String: Bool] {
        let pairs = allPairs(transaction: transaction)
        var result = [String: Bool]()
        for pair in pairs {
            guard let key = pair.key else {
                owsFailDebug("missing key.")
                continue
            }
            guard let value = pair.value else {
                owsFailDebug("missing value.")
                continue
            }
            guard let rawObject = parseArchivedValue(value) else {
                owsFailDebug("Could not parse value.")
                continue
            }
            guard let number: NSNumber = parseValueAs(key: key,
                                                      rawObject: rawObject) else {
                                                        owsFailDebug("Invalid value.")
                                                        continue
            }
            result[key] = number.boolValue
        }
        return result
    }

    @objc
    public func allUIntValuesMap(transaction: SDSAnyReadTransaction) -> [String: UInt] {
        let pairs = allPairs(transaction: transaction)
        var result = [String: UInt]()
        for pair in pairs {
            guard let key = pair.key else {
                owsFailDebug("missing key.")
                continue
            }
            guard let value = pair.value else {
                owsFailDebug("missing value.")
                continue
            }
            guard let rawObject = parseArchivedValue(value) else {
                owsFailDebug("Could not parse value.")
                continue
            }
            guard let number: NSNumber = parseValueAs(key: key,
                                                      rawObject: rawObject) else {
                                                        owsFailDebug("Invalid value.")
                                                        continue
            }
            result[key] = number.uintValue
        }
        return result
    }

    @objc
    public func anyDataValue(transaction: SDSAnyReadTransaction) -> Data? {
        let keys = allKeys(transaction: transaction).shuffled()
        guard let firstKey = keys.first else {
            return nil
        }
        guard let data = self.getData(firstKey, transaction: transaction) else {
            owsFailDebug("Missing data for key: \(firstKey)")
            return nil
        }
        return data
    }

    @objc
    public func allKeys(transaction: SDSAnyReadTransaction) -> [String] {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            return allKeys(grdbTransaction: grdbRead)
        }
    }

    @objc
    public func numberOfKeys(transaction: SDSAnyReadTransaction) -> UInt {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            let sql = """
            SELECT COUNT(*)
            FROM \(SDSKeyValueStore.table.tableName)
            WHERE \(SDSKeyValueStore.collectionColumn.columnName) == ?
            """
            do {
                guard let numberOfKeys = try UInt.fetchOne(grdbRead.database,
                                                           sql: sql,
                                                           arguments: [collection]) else {
                                                            throw OWSAssertionError("numberOfKeys was unexpectedly nil")
                }
                return numberOfKeys
            } catch {
                DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                    userDefaults: CurrentAppContext().appUserDefaults(),
                    error: error
                )
                owsFail("error: \(error)")
            }
        }
    }

    @objc
    public var asObjC: SDSKeyValueStoreObjC {
        return SDSKeyValueStoreObjC(sdsKeyValueStore: self)
    }

    // MARK: -

    @available(*, deprecated, message: "Did you mean removeValue(forKey:transaction:) or setCodable(optional:key:transaction)?")
    public func setCodable<T: Encodable>(_ value: T?, key: String, transaction: SDSAnyWriteTransaction) throws {
        try setCodable(optional: value, key: key, transaction: transaction)
    }

    public func setCodable<T: Encodable>(_ value: T, key: String, transaction: SDSAnyWriteTransaction) throws {
        // The only difference between setCodable(optional:...) and setCodable(_...) is
        // the non-optional variant has a deprecated overload to warn callers of the ambiguity.
        try setCodable(optional: value, key: key, transaction: transaction)
    }

    public func setCodable<T: Encodable>(optional value: T, key: String, transaction: SDSAnyWriteTransaction) throws {
        do {
            let data = try JSONEncoder().encode(value)
            setData(data, key: key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to encode: \(error).")
            throw error
        }
    }

    public func getCodableValue<T: Decodable>(forKey key: String, transaction: SDSAnyReadTransaction) throws -> T? {
        guard let data = getData(key, transaction: transaction) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            owsFailDebug("Failed to decode: \(error).")
            throw error
        }
    }

    public func allCodableValues<T: Decodable>(transaction: SDSAnyReadTransaction) throws -> [T] {
        var result = [T]()
        for data in allDataValues(transaction: transaction) {
            do {
                result.append(try JSONDecoder().decode(T.self, from: data))
            } catch {
                owsFailDebug("Failed to decode: \(error).")
                throw error
            }
        }
        return result
    }

    // MARK: - Internal Methods

    private func read<T>(_ key: String, transaction: SDSAnyReadTransaction) -> T? {
        guard let rawObject = readRawObject(key, transaction: transaction) else {
            return nil
        }
        return parseValueAs(key: key, rawObject: rawObject)
    }

    private func readRawObject(_ key: String, transaction: SDSAnyReadTransaction) -> Any? {
        // GRDB values are serialized to data by this class.
        switch transaction.readTransaction {
        case .grdbRead:
            guard let encoded = readData(key, transaction: transaction) else {
                return nil
            }
            return parseArchivedValue(encoded)
        }
    }

    private func parseArchivedValue(_ encoded: Data) -> Any? {
        do {
            guard let rawObject = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(encoded) else {
                owsFailDebug("Could not decode value.")
                return nil
            }
            return rawObject
        } catch {
            owsFailDebug("Decode failed.")
            return nil
        }
    }

    private func parseValueAs<T>(key: String, rawObject: Any?) -> T? {
        guard let rawObject = rawObject else {
            return nil
        }
        guard let object = rawObject as? T else {
            owsFailDebug("Value for key: \(key) has unexpected type: \(type(of: rawObject)).")
            return nil
        }
        return object
    }

    private func readData(_ key: String, transaction: SDSAnyReadTransaction) -> Data? {
        let collection = self.collection

        switch transaction.readTransaction {
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
            DatabaseCorruptionState.flagDatabaseReadCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            owsFailDebug("error: \(error)")
            return nil
        }
    }

    // TODO: Codable? NSCoding? Other serialization?
    private func write(_ value: NSCoding?, forKey key: String, transaction: SDSAnyWriteTransaction) {
        // GRDB values are serialized to data by this class.
        switch transaction.writeTransaction {
        case .grdbWrite:
            if let value = value {
                let encoded = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false)
                writeData(encoded, forKey: key, transaction: transaction)
            } else {
                writeData(nil, forKey: key, transaction: transaction)
            }
        }
    }

    private func writeData(_ data: Data?, forKey key: String, transaction: SDSAnyWriteTransaction) {

        let collection = self.collection

        switch transaction.writeTransaction {
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
            // See: https://www.sqlite.org/lang_UPSERT.html
            let sql = """
                INSERT INTO \(table.tableName) (
                    \(keyColumn.columnName),
                    \(collectionColumn.columnName),
                    \(valueColumn.columnName)
                ) VALUES (?, ?, ?)
                ON CONFLICT (
                    \(keyColumn.columnName),
                    \(collectionColumn.columnName)
                ) DO UPDATE
                SET \(valueColumn.columnName) = ?
            """
            try update(transaction: transaction, sql: sql, arguments: [ key, collection, encoded, encoded ])
        } else {
            // Setting to nil is a delete.
            let sql = "DELETE FROM \(table.tableName) WHERE \(keyColumn.columnName) == ? AND \(collectionColumn.columnName) == ?"
            try update(transaction: transaction, sql: sql, arguments: [ key, collection ])
        }
    }

    private class func update(
        transaction: GRDBWriteTransaction,
        sql: String,
        arguments: StatementArguments
    ) throws {
        let statement = try transaction.database.cachedStatement(sql: sql)
        try statement.setArguments(arguments)

        do {
            try statement.execute()
        } catch {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(
                userDefaults: CurrentAppContext().appUserDefaults(),
                error: error
            )
            throw error
        }
    }

    private func allKeys(grdbTransaction: GRDBReadTransaction) -> [String] {
        let sql = """
        SELECT \(SDSKeyValueStore.keyColumn.columnName)
        FROM \(SDSKeyValueStore.table.tableName)
        WHERE \(SDSKeyValueStore.collectionColumn.columnName) == ?
        """

        return grdbTransaction.database.strictRead { database in
            try String.fetchAll(database, sql: sql, arguments: [collection])
        }
    }
}
