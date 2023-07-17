//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

/// Produces instances of `InMemoryKeyValueStore`.
public class InMemoryKeyValueStoreFactory: KeyValueStoreFactory {

    public var stores = [String: InMemoryKeyValueStore]()

    public init() {}

    public func keyValueStore(collection: String) -> SignalServiceKit.KeyValueStore {
        if let store = stores[collection] {
            return store
        }
        let store = InMemoryKeyValueStore(collection: collection)
        stores[collection] = store
        return store
    }
}

/// In memory implementation of a KeyValueStore, requiring no database setup.
/// Should only be used in test environments to simplify testing while replicating "real" storage.
public class InMemoryKeyValueStore: KeyValueStore {

    private var dict = [String: Any]()

    public required init(collection: String) {}

    private func read<T>(_ key: String) -> T? {
        guard let value = dict[key] else {
            return nil
        }
        let val = value as! T
        return val
    }

    private func read<T>(_ key: String, defaultValue: T) -> T {
        guard let value = dict[key] else {
            return defaultValue
        }
        let val = value as! T
        return val
    }

    public func hasValue(_ key: String, transaction: DBReadTransaction) -> Bool {
        return dict[key] != nil
    }

    public func getString(_ key: String, transaction: DBReadTransaction) -> String? {
        return read(key)
    }

    public func setString(_ value: String?, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getDate(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> Date? {
        return read(key)
    }

    public func setDate(_ value: Date, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getBool(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> Bool? {
        return read(key)
    }

    public func getBool(_ key: String, defaultValue: Bool, transaction: SignalServiceKit.DBReadTransaction) -> Bool {
        return read(key, defaultValue: defaultValue)
    }

    public func setBool(_ value: Bool, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func setBoolIfChanged(_ value: Bool, defaultValue: Bool, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getUInt(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> UInt? {
        return read(key)
    }

    public func getUInt(_ key: String, defaultValue: UInt, transaction: SignalServiceKit.DBReadTransaction) -> UInt {
        return read(key, defaultValue: defaultValue)
    }

    public func setUInt(_ value: UInt, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getData(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> Data? {
        return read(key)
    }

    public func setData(_ value: Data?, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getNSNumber(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> NSNumber? {
        return read(key)
    }

    public func getInt(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> Int? {
        return read(key)
    }

    public func getInt(_ key: String, defaultValue: Int, transaction: SignalServiceKit.DBReadTransaction) -> Int {
        return read(key, defaultValue: defaultValue)
    }

    public func setInt(_ value: Int, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getUInt32(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> UInt32? {
        return read(key)
    }

    public func getUInt32(_ key: String, defaultValue: UInt32, transaction: SignalServiceKit.DBReadTransaction) -> UInt32 {
        return read(key, defaultValue: defaultValue)
    }

    public func setUInt32(_ value: UInt32, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getUInt64(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> UInt64? {
        return read(key)
    }

    public func getUInt64(_ key: String, defaultValue: UInt64, transaction: SignalServiceKit.DBReadTransaction) -> UInt64 {
        return read(key, defaultValue: defaultValue)
    }

    public func setUInt64(_ value: UInt64, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getInt64(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> Int64? {
        return read(key)
    }

    public func getInt64(_ key: String, defaultValue: Int64, transaction: SignalServiceKit.DBReadTransaction) -> Int64 {
        return read(key, defaultValue: defaultValue)
    }

    public func setInt64(_ value: Int64, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getDouble(_ key: String, transaction: SignalServiceKit.DBReadTransaction) -> Double? {
        return read(key)
    }

    public func getDouble(_ key: String, defaultValue: Double, transaction: SignalServiceKit.DBReadTransaction) -> Double {
        return read(key, defaultValue: defaultValue)
    }

    public func setDouble(_ value: Double, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = value
    }

    public func getObject(forKey key: String, transaction: SignalServiceKit.DBReadTransaction) -> Any? {
        return read(key)
    }

    public func setObject(_ anyValue: Any?, key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = anyValue
    }

    public func removeValue(forKey key: String, transaction: SignalServiceKit.DBWriteTransaction) {
        dict[key] = nil
    }

    public func removeValues(forKeys keys: [String], transaction: SignalServiceKit.DBWriteTransaction) {
        keys.forEach {
            removeValue(forKey: $0, transaction: transaction)
        }
    }

    public func removeAll(transaction: SignalServiceKit.DBWriteTransaction) {
        dict = [:]
    }

    public func enumerateKeysAndObjects(transaction: SignalServiceKit.DBReadTransaction, block: (String, Any, UnsafeMutablePointer<ObjCBool>) -> Void) {
        for key in dict.keys {
            var bool: ObjCBool = .init(booleanLiteral: false)
            block(key, dict[key]!, &bool)
            if bool.boolValue {
                return
            }
        }
    }

    public func enumerateKeys(transaction: SignalServiceKit.DBReadTransaction, block: (String, UnsafeMutablePointer<ObjCBool>) -> Void) {
        enumerateKeysAndObjects(transaction: transaction, block: { key, _, stop in
            block(key, stop)
        })
    }

    public func allValues(transaction: SignalServiceKit.DBReadTransaction) -> [Any] {
        return Array(dict.values)
    }

    public func allDataValues(transaction: SignalServiceKit.DBReadTransaction) -> [Data] {
        return allValues(transaction: transaction).compactMap { $0 as? Data }
    }

    public func allBoolValuesMap(transaction: SignalServiceKit.DBReadTransaction) -> [String: Bool] {
        return dict.compactMapValues { $0 as? Bool }
    }

    public func allUIntValuesMap(transaction: SignalServiceKit.DBReadTransaction) -> [String: UInt] {
        return dict.compactMapValues { $0 as? UInt }
    }

    public func anyDataValue(transaction: SignalServiceKit.DBReadTransaction) -> Data? {
        return allDataValues(transaction: transaction).randomElement()
    }

    public func allKeys(transaction: SignalServiceKit.DBReadTransaction) -> [String] {
        return Array(dict.keys)
    }

    public func numberOfKeys(transaction: SignalServiceKit.DBReadTransaction) -> UInt {
        return UInt(dict.count)
    }

    public func setCodable<T>(_ value: T, key: String, transaction: SignalServiceKit.DBWriteTransaction) throws where T: Encodable {
        let encoded = try JSONEncoder().encode(value)
        setData(encoded, key: key, transaction: transaction)
    }

    public func setCodable<T>(optional value: T, key: String, transaction: SignalServiceKit.DBWriteTransaction) throws where T: Encodable {
        let encoded = try JSONEncoder().encode(value)
        setData(encoded, key: key, transaction: transaction)
    }

    public func getCodableValue<T>(forKey key: String, transaction: SignalServiceKit.DBReadTransaction) throws -> T? where T: Decodable {
        guard let raw = dict[key] else {
            return nil
        }
        let data = raw as! Data
        let decoded = try JSONDecoder().decode(T.self, from: data)
        return decoded
    }

    public func allCodableValues<T>(transaction: SignalServiceKit.DBReadTransaction) throws -> [T] where T: Decodable {
        let decoder = JSONDecoder()
        return dict.values.compactMap { raw in
            guard
                let data = raw as? Data,
                let decoded = try? decoder.decode(T.self, from: data)
            else {
                return nil
            }
            return decoded
        }
    }
}

#endif
