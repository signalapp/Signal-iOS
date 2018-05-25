//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@objc
public class AnyLRUCache: NSObject {

    let backingCache: LRUCache<NSObject, NSObject>

    @objc
    public init(maxSize: Int) {
        backingCache = LRUCache(maxSize: maxSize)
    }

    @objc
    public func get(key: NSObject) -> NSObject? {
        return self.backingCache.get(key: key)
    }

    @objc
    public func set(key: NSObject, value: NSObject) {
        self.backingCache.set(key: key, value: value)
    }
}

// A simple LRU cache bounded by the number of entries.
//
// TODO: We might want to observe memory pressure notifications.
public class LRUCache<KeyType: Hashable & Equatable, ValueType> {

    private var cacheMap: [KeyType: ValueType] = [:]
    private var cacheOrder: [KeyType] = []
    private let maxSize: Int

    public init(maxSize: Int) {
        self.maxSize = maxSize
    }

    public func get(key: KeyType) -> ValueType? {
        guard let value = cacheMap[key] else {
            return nil
        }

        // Update cache order.
        cacheOrder = cacheOrder.filter { $0 != key }
        cacheOrder.append(key)

        return value
    }

    public func set(key: KeyType, value: ValueType) {
        cacheMap[key] = value

        // Update cache order.
        cacheOrder = cacheOrder.filter { $0 != key }
        cacheOrder.append(key)

        while cacheOrder.count > maxSize {
            guard let staleKey = cacheOrder.first else {
                owsFail("Cache ordering unexpectedly empty")
                return
            }
            cacheOrder.removeFirst()
            cacheMap.removeValue(forKey: staleKey)
        }
    }
}
