//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public class OrderedDictionary<KeyType: Hashable, ValueType> {

    private var keyValueMap = [KeyType: ValueType]()

    public var orderedKeys = [KeyType]()

    public init() { }

    // Used to clone copies of instances of this class.
    public init(keyValueMap: [KeyType: ValueType],
                orderedKeys: [KeyType]) {

        self.keyValueMap = keyValueMap
        self.orderedKeys = orderedKeys
    }

    // Since the contents are immutable, we only modify copies
    // made with this method.
    public func clone() -> OrderedDictionary<KeyType, ValueType> {
        return OrderedDictionary(keyValueMap: keyValueMap, orderedKeys: orderedKeys)
    }

    public func value(forKey key: KeyType) -> ValueType? {
        return keyValueMap[key]
    }

    public func hasValue(forKey key: KeyType) -> Bool {
        return keyValueMap[key] != nil
    }

    public func append(key: KeyType, value: ValueType) {
        insert(key: key, value: value, isAppend: true)
    }

    public func prepend(key: KeyType, value: ValueType) {
        insert(key: key, value: value, isAppend: false)
    }

    private func insert(key: KeyType, value: ValueType, isAppend: Bool) {
        if keyValueMap[key] != nil {
            owsFailDebug("Unexpected duplicate key in key map: \(key)")
        }
        keyValueMap[key] = value

        if orderedKeys.contains(key) {
            owsFailDebug("Unexpected duplicate key in key list: \(key)")
        } else {
            if isAppend {
                orderedKeys.append(key)
            } else {
                // Prepend
                orderedKeys = [key ] + orderedKeys
            }
        }

        if orderedKeys.count != keyValueMap.count {
            owsFailDebug("Invalid contents.")
        }
    }

    public func replace(key: KeyType, value: ValueType) {
        if keyValueMap[key] == nil {
            owsFailDebug("Missing key in key map: \(key)")
        }
        keyValueMap[key] = value

        if !orderedKeys.contains(key) {
            owsFailDebug("Missing key in key list: \(key)")
        }

        if orderedKeys.count != keyValueMap.count {
            owsFailDebug("Invalid contents.")
        }
    }

    public func remove(key: KeyType, ignoreMissing: Bool = false) {
        if keyValueMap[key] == nil {
            if ignoreMissing {
                return
            }
            owsFailDebug("Missing key in key map: \(key)")
        } else {
            keyValueMap.removeValue(forKey: key)
        }

        if !orderedKeys.contains(key) {
            owsFailDebug("Missing key in key list: \(key)")
        } else {
            orderedKeys = orderedKeys.filter { $0 != key }
        }

        if orderedKeys.count != keyValueMap.count {
            owsFailDebug("Invalid contents.")
        }
    }

    public var count: Int {
        if orderedKeys.count != keyValueMap.count {
            owsFailDebug("Invalid contents.")
        }
        return orderedKeys.count
    }

    public var orderedValues: [ValueType] {
        var values = [ValueType]()
        for key in orderedKeys {
            guard let value = self.keyValueMap[key] else {
                owsFailDebug("Missing value")
                continue
            }
            values.append(value)
        }
        return values
    }

    public func moveExistingKeyToFirst(_ key: KeyType) {
        guard orderedKeys.contains(key) else {
            owsFailDebug("Key not in dictionary.")
            return
        }

        orderedKeys = [key ] + orderedKeys.filter { $0 != key }
    }

    public var firstKey: KeyType? {
        orderedKeys.first
    }

    public var lastKey: KeyType? {
        orderedKeys.last
    }

    public func removeAll() {
        keyValueMap.removeAll()
        orderedKeys.removeAll()
    }
}

// MARK: -

extension OrderedDictionary: Sequence {
    public typealias Iterator = AnyIterator<(KeyType, ValueType)>

    struct OrderedDictionaryIterator {
        private let keys: [KeyType]
        private let map: [KeyType: ValueType]
        private var index: Int = 0

        fileprivate init(keys: [KeyType], map: [KeyType: ValueType]) {
            self.keys = keys
            self.map = map
        }

        mutating func next() -> (KeyType, ValueType)? {
            guard index < keys.count else {
                return nil
            }
            let key = keys[index]
            index += 1
            guard let value = map[key] else {
                owsFailDebug("Missing value for key.")
                return nil
            }
            return (key, value)
        }
    }

    public func makeIterator() -> Iterator {
        var iterator = OrderedDictionaryIterator(keys: orderedKeys, map: keyValueMap)
        return AnyIterator { iterator.next() }
    }
}
