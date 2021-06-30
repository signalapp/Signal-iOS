//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

// An @objc wrapper around LRUCache.
@objc
public class AnyLRUCache: NSObject {

    private let backingCache: LRUCache<NSObject, NSObject>

    @objc
    public init(maxSize: Int, nseMaxSize: Int) {
        backingCache = LRUCache(maxSize: maxSize, nseMaxSize: nseMaxSize)
    }

    @objc
    public func get(key: NSObject) -> NSObject? {
        backingCache.get(key: key)
    }

    @objc
    public func set(key: NSObject, value: NSObject) {
        backingCache.set(key: key, value: value)
    }

    @objc
    public func remove(key: NSObject) {
        backingCache.remove(key: key)
    }

    @objc
    public func clear() {
        backingCache.clear()
    }

    // MARK: - NSCache Compatibility

    @objc
    public func setObject(_ value: NSObject, forKey key: NSObject) {
        set(key: key, value: value)
    }

    @objc
    public func object(forKey key: NSObject) -> NSObject? {
        self.get(key: key)
    }

    @objc
    public func removeObject(forKey key: NSObject) {
        remove(key: key)
    }

    @objc
    public func removeAllObjects() {
        clear()
    }
}

// MARK: -

// A simple LRU cache bounded by the number of entries.
public class LRUCache<KeyType: Hashable & Equatable, ValueType> {

    private let cache = NSCache<AnyObject, AnyObject>()
    private let maxSize: Int

    public init(maxSize: Int, nseMaxSize: Int = 0) {
        self.maxSize = CurrentAppContext().isNSE ? nseMaxSize : maxSize
        self.cache.countLimit = maxSize
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func didEnterBackground() {
        AssertIsOnMainThread()

        clear()
    }

    @objc func didReceiveMemoryWarning() {
        AssertIsOnMainThread()

        clear()
    }

    public func get(key: KeyType) -> ValueType? {
        // ValueType might be AnyObject, so we need to check
        // rawValue for nil; value might be NSNull.
        guard let rawValue = cache.object(forKey: key as AnyObject),
              let value = rawValue as? ValueType else {
            return nil
        }
        owsAssertDebug(!(value is NSNull))
        return value
    }

    public func set(key: KeyType, value: ValueType) {
        if value is NSNull {
            owsFailDebug("Nil value.")
            remove(key: key)
            return
        }
        guard maxSize > 0 else {
            Logger.warn("Using disabled cache.")
            return
        }
        cache.setObject(value as AnyObject, forKey: key as AnyObject)
    }

    public func remove(key: KeyType) {
        cache.removeObject(forKey: key as AnyObject)
    }

    @objc
    public func clear() {
        cache.removeAllObjects()
    }

    public subscript(key: KeyType) -> ValueType? {
        get {
            get(key: key)
        }
        set(value) {
            if let value = value {
                set(key: key, value: value)
            } else {
                remove(key: key)
            }
        }
    }

    // MARK: - NSCache Compatibility

    public func setObject(_ value: ValueType, forKey key: KeyType) {
        set(key: key, value: value)
    }

    public func object(forKey key: KeyType) -> ValueType? {
        self.get(key: key)
    }

    public func removeObject(forKey key: KeyType) {
        remove(key: key)
    }

    public func removeAllObjects() {
        clear()
    }
}
