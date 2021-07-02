//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

public class SDSOrderedKeyValueStore<ValueType: Codable> {

    private let orderedKeysKey = "___orderedKeys"
    private let keyValueStore: SDSKeyValueStore

    public init(collection: String) {
        keyValueStore = .init(collection: collection)
    }

    public func count(transaction: SDSAnyReadTransaction) -> Int {
        max(0, Int(keyValueStore.numberOfKeys(transaction: transaction)) - 1)
    }

    public func orderedKeysAndValues(transaction: SDSAnyReadTransaction) -> OrderedDictionary<String, ValueType> {
        let keys = orderedKeys(transaction: transaction)
        let keysAndValues: [(String, ValueType)] = keys.map {
            guard let value = fetch(key: $0, transaction: transaction) else {
                owsFail("Missing value for key in collection \(keyValueStore.collection)")
            }
            return ($0, value)
        }
        return OrderedDictionary(keyValueMap: Dictionary(uniqueKeysWithValues: keysAndValues), orderedKeys: keys)
    }

    public func orderedKeys(transaction: SDSAnyReadTransaction) -> [String] {
        keyValueStore.getObject(forKey: orderedKeysKey, transaction: transaction) as? [String] ?? []
    }

    public func firstKey(transaction: SDSAnyReadTransaction) -> String? {
        orderedKeys(transaction: transaction).first
    }

    public func lastKey(transaction: SDSAnyReadTransaction) -> String? {
        orderedKeys(transaction: transaction).last
    }

    public func orderedValues(transaction: SDSAnyReadTransaction) -> [ValueType] {
        orderedKeys(transaction: transaction).map {
            guard let value = fetch(key: $0, transaction: transaction) else {
                owsFail("Missing value for key in collection \(keyValueStore.collection)")
            }
            return value
        }
    }

    public func fetch(key: String, transaction: SDSAnyReadTransaction) -> ValueType? {
        do {
            return try keyValueStore.getCodableValue(forKey: key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to decode key")
            return nil
        }
    }

    public func hasValue(forKey key: String, transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.hasValue(forKey: key, transaction: transaction)
    }

    public func insert(key: String, at index: Int, value: ValueType, transaction: SDSAnyWriteTransaction) {
        owsAssert(!hasValue(forKey: key, transaction: transaction), "Key already in dictionary: \(key)")

        var orderedKeys = self.orderedKeys(transaction: transaction)
        owsAssertDebug(!orderedKeys.contains(key), "Unexpected duplicate key in key list: \(key)")

        do {
            try keyValueStore.setCodable(value, key: key, transaction: transaction)
            orderedKeys.insert(key, at: index)
            keyValueStore.setObject(orderedKeys, key: orderedKeysKey, transaction: transaction)
        } catch {
            owsFailDebug("Failed to insert value")
            return
        }

        owsAssertDebug(orderedKeys.count == count(transaction: transaction), "Invalid contents.")
    }

    public func append(key: String, value: ValueType, transaction: SDSAnyWriteTransaction) {
        insert(key: key, at: count(transaction: transaction), value: value, transaction: transaction)
    }

    public func prepend(key: String, value: ValueType, transaction: SDSAnyWriteTransaction) {
        insert(key: key, at: 0, value: value, transaction: transaction)
    }

    @discardableResult
    public func replace(key: String, value: ValueType, transaction: SDSAnyWriteTransaction) -> ValueType {
        guard let oldValue = fetch(key: key, transaction: transaction) else {
            owsFail("Key is not present in OrderedDictionary: \(key)")
        }

        do {
            try keyValueStore.setCodable(value, key: key, transaction: transaction)
        } catch {
            owsFailDebug("Failed to replace value \(error)")
        }

        let orderedKeys = self.orderedKeys(transaction: transaction)
        owsAssertDebug(orderedKeys.contains(key), "Missing key in key list: \(key)")
        owsAssertDebug(orderedKeys.count == count(transaction: transaction), "Invalid contents.")

        return oldValue
    }

    @discardableResult
    public func remove(key: String, transaction: SDSAnyWriteTransaction) -> ValueType? {
        guard let value = fetch(key: key, transaction: transaction) else {
            return nil
        }

        keyValueStore.removeValue(forKey: key, transaction: transaction)

        var orderedKeys = self.orderedKeys(transaction: transaction)
        owsAssertDebug(orderedKeys.contains(key), "Missing key in key list: \(key)")
        orderedKeys.removeAll { $0 == key }
        keyValueStore.setObject(orderedKeys, key: orderedKeysKey, transaction: transaction)

        owsAssertDebug(orderedKeys.count == count(transaction: transaction), "Invalid contents.")
        return value
    }

    public func remove(at index: Int, transaction: SDSAnyWriteTransaction) {
        var orderedKeys = self.orderedKeys(transaction: transaction)

        let key = orderedKeys[index]

        keyValueStore.removeValue(forKey: key, transaction: transaction)
        orderedKeys.remove(at: index)
        keyValueStore.setObject(orderedKeys, key: orderedKeysKey, transaction: transaction)
    }

    public func removeSubrange<R: RangeExpression>(_ range: R, transaction: SDSAnyWriteTransaction) where R.Bound == Int {
        var orderedKeys = self.orderedKeys(transaction: transaction)

        orderedKeys[range].forEach { key in
            keyValueStore.removeValue(forKey: key, transaction: transaction)
        }
        orderedKeys.removeSubrange(range)
        keyValueStore.setObject(orderedKeys, key: orderedKeysKey, transaction: transaction)
    }

    public func removeAll(transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeAll(transaction: transaction)
    }

    public func moveExistingKeyToFirst(_ key: String, transaction: SDSAnyWriteTransaction) {
        var orderedKeys = self.orderedKeys(transaction: transaction)

        guard let index = orderedKeys.firstIndex(of: key) else {
            owsFail("Key not in dictionary: \(key)")
        }

        orderedKeys.remove(at: index)
        orderedKeys.insert(key, at: 0)
        keyValueStore.setObject(orderedKeys, key: orderedKeysKey, transaction: transaction)
    }
}
