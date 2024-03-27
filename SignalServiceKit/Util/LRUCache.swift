//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

// An @objc wrapper around LRUCache.
@objc
public class AnyLRUCache: NSObject {

    private let backingCache: LRUCache<NSObject, NSObject>

    @objc
    public init(maxSize: Int, nseMaxSize: Int, shouldEvacuateInBackground: Bool) {
        backingCache = LRUCache(maxSize: maxSize,
                                nseMaxSize: nseMaxSize,
                                shouldEvacuateInBackground: shouldEvacuateInBackground)
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
    private let _resetCount = AtomicUInt(0)
    public var resetCount: UInt {
        _resetCount.get()
    }
    public let regularMaxSize: Int
    public var maxSize: Int {
        get {
            return cache.countLimit
        }
        set {
            cache.countLimit = newValue
        }
    }

    public init(maxSize: Int,
                nseMaxSize: Int = 0,
                shouldEvacuateInBackground: Bool = false) {
        regularMaxSize = CurrentAppContext().isNSE ? nseMaxSize : maxSize
        self.cache.countLimit = regularMaxSize

        if CurrentAppContext().isMainApp,
           shouldEvacuateInBackground {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(didEnterBackground),
                                                   name: .OWSApplicationDidEnterBackground,
                                                   object: nil)
        }
    }

    @objc
    private func didEnterBackground() {
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
        guard cache.countLimit > 0 else {
            return
        }
        cache.setObject(value as AnyObject, forKey: key as AnyObject)
    }

    public func remove(key: KeyType) {
        cache.removeObject(forKey: key as AnyObject)
    }

    @objc
    public func clear() {
        _resetCount.increment()

        autoreleasepool {
            cache.removeAllObjects()
        }
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

// MARK: -

// NSCache sometimes evacuates entries off the main thread.
// Some cached entities should only be deallocated on the main thread.
// This handle can be used to ensure that cache entries are released
// on the main thread.
public class ThreadSafeCacheHandle<T: AnyObject> {

    public let value: T

    public init(_ value: T) {
        self.value = value
    }

    deinit {
        guard !Thread.isMainThread else {
            return
        }
        ThreadSafeCacheReleaser.releaseOnMainThread(value)
    }
}

// MARK: -

// Some caches use ThreadSafeCacheHandle to ensure that their
// values are released on the main thread.  If one of these caches
// evacuated a large number of values at the same time off the main
// thread, we wouldn't want to dispatch to the main thread once for
// each value. This class buffers the values and releases them in
// batches.
private class ThreadSafeCacheReleaser {
    private static let unfairLock = UnfairLock()
    private static var valuesToRelease = [AnyObject]()

    fileprivate static func releaseOnMainThread(_ value: AnyObject) {
        unfairLock.withLock {
            let shouldSchedule = valuesToRelease.isEmpty
            valuesToRelease.append(value)
            if shouldSchedule {
                DispatchQueue.main.async {
                    Self.releaseValues()
                }
            }
        }
    }

    private static func releaseValues() {
        AssertIsOnMainThread()

        autoreleasepool {
            var valuesToRelease: [AnyObject] = unfairLock.withLock {
                let valuesToRelease = Self.valuesToRelease
                Self.valuesToRelease = []
                return valuesToRelease
            }
            // To avoid deadlock, we release the values without unfairLock acquired.
            owsAssertDebug(valuesToRelease.count > 0)
            Logger.info("Releasing \(valuesToRelease.count) values.")
            valuesToRelease = []
            owsAssertDebug(valuesToRelease.isEmpty)
        }
    }
}
