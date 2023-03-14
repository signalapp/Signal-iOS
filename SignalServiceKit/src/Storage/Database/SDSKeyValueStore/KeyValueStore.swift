//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Abstract protocol for storing values by key.
/// In production, typically backed by `SDSKeyValueStore`, which uses the GRDB
/// database to persist keys and values to disk.
/// In test code, typically backed by `InMemoryKeyValueStore`, which just keeps
/// everything in memory to avoid setting up an entire db schema on every test case run.
///
/// Instances of `KeyValueStore` should be created using a `KeyValueStoreFactory`.
///
/// Methods are identical to those on `SDSKeyValueStore`.
public protocol KeyValueStore {

    init(collection: String)

    // MARK: - Existence

    func hasValue(_ key: String, transaction: DBReadTransaction) -> Bool

    // MARK: - String

    func getString(_ key: String, transaction: DBReadTransaction) -> String?

    func setString(_ value: String?, key: String, transaction: DBWriteTransaction)

    // MARK: - Date

    func getDate(_ key: String, transaction: DBReadTransaction) -> Date?

    func setDate(_ value: Date, key: String, transaction: DBWriteTransaction)

    // MARK: - Bool

    func getBool(_ key: String, transaction: DBReadTransaction) -> Bool?

    func getBool(_ key: String, defaultValue: Bool, transaction: DBReadTransaction) -> Bool

    func setBool(_ value: Bool, key: String, transaction: DBWriteTransaction)

    func setBoolIfChanged(
        _ value: Bool,
        defaultValue: Bool,
        key: String,
        transaction: DBWriteTransaction
    )

    // MARK: - UInt

    func getUInt(_ key: String, transaction: DBReadTransaction) -> UInt?

    // TODO: Handle numerics more generally.
    func getUInt(_ key: String, defaultValue: UInt, transaction: DBReadTransaction) -> UInt

    func setUInt(_ value: UInt, key: String, transaction: DBWriteTransaction)

    // MARK: - Data

    func getData(_ key: String, transaction: DBReadTransaction) -> Data?

    func setData(_ value: Data?, key: String, transaction: DBWriteTransaction)

    // MARK: - Numeric

    func getNSNumber(_ key: String, transaction: DBReadTransaction) -> NSNumber?

    // MARK: - Int

    func getInt(_ key: String, transaction: DBReadTransaction) -> Int?

    func getInt(_ key: String, defaultValue: Int, transaction: DBReadTransaction) -> Int

    func setInt(_ value: Int, key: String, transaction: DBWriteTransaction)

    // MARK: - UInt32

    func getUInt32(_ key: String, transaction: DBReadTransaction) -> UInt32?

    func getUInt32(_ key: String, defaultValue: UInt32, transaction: DBReadTransaction) -> UInt32

    func setUInt32(_ value: UInt32, key: String, transaction: DBWriteTransaction)

    // MARK: - UInt64

    func getUInt64(_ key: String, transaction: DBReadTransaction) -> UInt64?

    func getUInt64(_ key: String, defaultValue: UInt64, transaction: DBReadTransaction) -> UInt64

    func setUInt64(_ value: UInt64, key: String, transaction: DBWriteTransaction)

    // MARK: - Int64

    func getInt64(_ key: String, transaction: DBReadTransaction) -> Int64?

    func getInt64(_ key: String, defaultValue: Int64, transaction: DBReadTransaction) -> Int64

    func setInt64(_ value: Int64, key: String, transaction: DBWriteTransaction)

    // MARK: - Double

    func getDouble(_ key: String, transaction: DBReadTransaction) -> Double?

    func getDouble(_ key: String, defaultValue: Double, transaction: DBReadTransaction) -> Double

    func setDouble(_ value: Double, key: String, transaction: DBWriteTransaction)

    // MARK: - Object

    func getObject(forKey key: String, transaction: DBReadTransaction) -> Any?

    func setObject(_ anyValue: Any?, key: String, transaction: DBWriteTransaction)

    // MARK: -

    func removeValue(forKey key: String, transaction: DBWriteTransaction)

    func removeValues(forKeys keys: [String], transaction: DBWriteTransaction)

    func removeAll(transaction: DBWriteTransaction)

    func enumerateKeysAndObjects(transaction: DBReadTransaction, block: @escaping (String, Any, UnsafeMutablePointer<ObjCBool>) -> Void)

    func enumerateKeys(transaction: DBReadTransaction, block: @escaping (String, UnsafeMutablePointer<ObjCBool>) -> Void)

    func allValues(transaction: DBReadTransaction) -> [Any]

    func allDataValues(transaction: DBReadTransaction) -> [Data]

    func allBoolValuesMap(transaction: DBReadTransaction) -> [String: Bool]

    func allUIntValuesMap(transaction: DBReadTransaction) -> [String: UInt]

    func anyDataValue(transaction: DBReadTransaction) -> Data?

    func allKeys(transaction: DBReadTransaction) -> [String]

    func numberOfKeys(transaction: DBReadTransaction) -> UInt

    // MARK: -

    func setCodable<T: Encodable>(_ value: T, key: String, transaction: DBWriteTransaction) throws

    func setCodable<T: Encodable>(optional value: T, key: String, transaction: DBWriteTransaction) throws

    func getCodableValue<T: Decodable>(forKey key: String, transaction: DBReadTransaction) throws -> T?

    func allCodableValues<T: Decodable>(transaction: DBReadTransaction) throws -> [T]
}
