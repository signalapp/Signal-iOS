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

    private let unfairLock = UnfairLock()
    private var cacheMap: [KeyType: ValueType] = [:]
    private var cacheOrder: [KeyType] = []
    private let maxSize: Int

    public init(maxSize: Int, nseMaxSize: Int = 0) {
        self.maxSize = CurrentAppContext().isNSE ? nseMaxSize : maxSize

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveMemoryWarning),
                                               name: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didEnterBackground),
                                               name: .OWSApplicationDidEnterBackground,
                                               object: nil)
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

    private func markKeyAsFirst(key: KeyType) {
        cacheOrder = cacheOrder.filter { $0 != key }
        cacheOrder.append(key)
    }

    public func get(key: KeyType) -> ValueType? {
        unfairLock.withLock {
            guard let value = cacheMap[key] else {
                // Miss
                return nil
            }

            // Hit
            markKeyAsFirst(key: key)

            return value
        }
    }

    public func set(key: KeyType, value: ValueType) {
        unfairLock.withLock {
            guard maxSize > 0 else {
                Logger.warn("Using disabled cache.")
                return
            }

            cacheMap[key] = value

            markKeyAsFirst(key: key)

            while cacheOrder.count > maxSize {
                guard let staleKey = cacheOrder.first else {
                    owsFailDebug("Cache ordering unexpectedly empty")
                    return
                }
                cacheOrder.removeFirst()
                cacheMap.removeValue(forKey: staleKey)
            }
        }
    }

    public func remove(key: KeyType) {
        unfairLock.withLock {
            guard maxSize > 0 else {
                Logger.warn("Using disabled cache.")
                return
            }

            cacheMap.removeValue(forKey: key)

            cacheOrder = cacheOrder.filter { $0 != key }
        }
    }

    @objc
    public func clear() {
        unfairLock.withLock {
            cacheMap.removeAll()
            cacheOrder.removeAll()
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
