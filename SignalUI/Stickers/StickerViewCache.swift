//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class StickerViewCache {

    private typealias CacheType = LRUCache<StickerInfo, ThreadSafeCacheHandle<StickerReusableView>>
    private let backingCache: CacheType

    public init(maxSize: Int) {
        // Always use a nseMaxSize of zero.
        backingCache = LRUCache(
            maxSize: maxSize,
            nseMaxSize: 0,
            shouldEvacuateInBackground: true,
        )
    }

    func get(key: StickerInfo) -> StickerReusableView? {
        self.backingCache.get(key: key)?.value
    }

    func set(key: StickerInfo, value: StickerReusableView) {
        self.backingCache.set(key: key, value: ThreadSafeCacheHandle(value))
    }

    func remove(key: StickerInfo) {
        self.backingCache.remove(key: key)
    }

    func clear() {
        self.backingCache.clear()
    }

    // MARK: NSCache Compatibility

    func setObject(_ value: StickerReusableView, forKey key: StickerInfo) {
        set(key: key, value: value)
    }

    func object(forKey key: StickerInfo) -> StickerReusableView? {
        self.get(key: key)
    }

    func removeObject(forKey key: StickerInfo) {
        remove(key: key)
    }

    func removeAllObjects() {
        clear()
    }
}
