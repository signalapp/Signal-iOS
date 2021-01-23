//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVMediaCache: NSObject {

    private static func buildMediaCache(countLimit: Int) -> NSCache<NSString, AnyObject> {
        let cache = NSCache<NSString, AnyObject>()
        cache.countLimit = countLimit
        return cache
    }

    private let stillMediaCache = buildMediaCache(countLimit: 16)
    private let animatedMediaCache = buildMediaCache(countLimit: 8)

    private let stillMediaViewCache = MediaInnerCache<String, ReusableMediaView>(maxSize: 12)
    private let animatedMediaViewCache = MediaInnerCache<String, ReusableMediaView>(maxSize: 6)

    @objc
    public required override init() {
        AssertIsOnMainThread()

        super.init()

        // Listen for memory warnings to evacuate the caches
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil)
    }

    @objc
    public func getMedia(_ key: String, isAnimated: Bool) -> AnyObject? {
        let cache = isAnimated ? animatedMediaCache : stillMediaCache
        return cache.object(forKey: key as NSString)
    }

    @objc
    public func setMedia(_ value: AnyObject, forKey key: String, isAnimated: Bool) {
        let cache = isAnimated ? animatedMediaCache : stillMediaCache
        cache.setObject(value, forKey: key as NSString)
    }

    @objc
    public func getMediaView(_ key: String, isAnimated: Bool) -> ReusableMediaView? {
        let cache = isAnimated ? animatedMediaViewCache : stillMediaViewCache
        return cache.get(key)
    }

    @objc
    public func setMediaView(_ value: ReusableMediaView, forKey key: String, isAnimated: Bool) {
        let cache = isAnimated ? animatedMediaViewCache : stillMediaViewCache
        cache.set(value: value, forKey: key)
    }

    @objc
    public func removeAllObjects() {
        AssertIsOnMainThread()

        stillMediaCache.removeAllObjects()
        animatedMediaCache.removeAllObjects()

        stillMediaViewCache.removeAllObjects()
        animatedMediaViewCache.removeAllObjects()
    }

    // MARK: - Events

    @objc
    func didReceiveMemoryWarning() {
        AssertIsOnMainThread()

        Logger.warn("")

        removeAllObjects()
    }
}

// MARK: -

private class MediaInnerCache<KeyType: Hashable, ValueType> {

    private let maxSize: UInt

    private var cache = OrderedDictionary<KeyType, ValueType>()

    @objc
    public required init(maxSize: UInt = 0) {
        AssertIsOnMainThread()

        self.maxSize = maxSize
    }

    // MARK: - API

    func get(_ key: KeyType) -> ValueType? {
        AssertIsOnMainThread()

        guard let value = cache[key] else {
            return nil
        }
        cache.moveExistingKeyToFirst(key)
        return value
    }

    func set(value: ValueType, forKey key: KeyType) {
        AssertIsOnMainThread()

        guard maxSize > 0 else {
            return
        }

        cache.remove(key: key)
        cache.prepend(key: key, value: value)
        if cache.count > maxSize {
            cache.removeSubrange(Int(maxSize)...)
        }
    }

    func removeAllObjects() {
        AssertIsOnMainThread()

        cache.removeAll()
    }
}
