//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MediaViewCache: NSObject {

    private let maxSize: UInt

    public typealias KeyType = String
    // In practice, the values are currently always ReusableMediaView.
    public typealias ValueType = AnyObject

    private let cache = OrderedDictionary<KeyType, ValueType>()

    @objc
    public required init(maxSize: UInt = 0) {
        AssertIsOnMainThread()

        self.maxSize = maxSize

        super.init()

        // Listen for memory warnings to evacuate the caches
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil)
    }

    // MARK: - API

    @objc
    public func get(_ key: KeyType) -> ValueType? {
        AssertIsOnMainThread()

        guard let value = cache.value(forKey: key) else {
            return nil
        }
        cache.moveExistingKeyToFirst(key)
        return value
    }

    @objc
    public func set(value: ValueType, forKey key: KeyType) {
        AssertIsOnMainThread()

        guard maxSize > 0 else {
            return
        }

        cache.remove(key: key, ignoreMissing: true)
        cache.prepend(key: key, value: value)

        while cache.count > maxSize,
            let lastKey = cache.lastKey {
                cache.remove(key: lastKey)
        }
    }

    // MARK: - Events

    @objc
    func didReceiveMemoryWarning() {
        AssertIsOnMainThread()

        Logger.warn("")

        removeAllObjects()
    }

    @objc
    public func removeAllObjects() {
        AssertIsOnMainThread()

        cache.removeAll()
    }
}
