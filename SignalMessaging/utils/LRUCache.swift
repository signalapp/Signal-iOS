//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@objc
public protocol AnyLRUCacheDelegate: class {
    func lruCache(_ cache: AnyLRUCache, didDeleteItem item: NSObject)
}

@objc
public class AnyLRUCache: NSObject, LRUCacheDelegate {

    let backingCache: LRUCache<NSObject, NSObject>
    public weak var delegate: AnyLRUCacheDelegate?
    
    public init(maxSize: Int) {
        backingCache = LRUCache(maxSize: maxSize)
        backingCache.delegate = self
    }

    public func get(key: NSObject) -> NSObject? {
        return self.backingCache.get(key: key)
    }

    public func set(key: NSObject, value: NSObject) {
        self.backingCache.set(key: key, value: value)
    }
    
    // MARK: LRUCacheDelegate
    internal func lruCache<K, V>(_ cache: LRUCache<K, V>, didDeleteItem item: V) where K : Hashable {
        <#code#>
    }
    
    public func lruCache(_ cache: LRUCache<NSObject, NSObject>, didDeleteItem item: NSObject) {
        delegate?.lruCache(self, didDeleteItem: item)
    }
}

// A simple LRU cache bounded by the number of entries.
//
// TODO: We might want to observe memory pressure notifications.
internal protocol LRUCacheDelegate: class {
    func lruCache<K, V>(_ cache: LRUCache<K, V>, didDeleteItem item: V)
}

public class LRUCache<KeyType: Hashable, ValueType> {

    private var cacheMap: [KeyType: ValueType] = [:]
    private var cacheOrder: [KeyType] = []
    private let maxSize: Int
    internal weak var delegate: LRUCacheDelegate?

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
                owsFail("In \(#function) staleKey was unexpectedly nil")
                return
            }
            cacheOrder.removeFirst()
            
            guard let deletedItem = cacheMap.removeValue(forKey: staleKey) else {
                owsFail("In \(#function) deletedItem was unexpectedly nil")
                return
            }
            
            self.delegate?.lruCache(self, didDeleteItem: deletedItem)
        }
    }
}
