//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import Lottie

public class CVMediaCache: NSObject {

    private let stillMediaCache = LRUCache<String, AnyObject>(maxSize: 16,
                                                              shouldEvacuateInBackground: true)
    private let animatedMediaCache = LRUCache<String, AnyObject>(maxSize: 8,
                                                                 shouldEvacuateInBackground: true)

    private let stillMediaViewCache = MediaInnerCache<String, ReusableMediaView>(maxSize: 12)
    private let animatedMediaViewCache = MediaInnerCache<String, ReusableMediaView>(maxSize: 6)

    private let lottieAnimationCache = LRUCache<String, Lottie.Animation>(maxSize: 8,
                                                                          shouldEvacuateInBackground: true)
    private let lottieImageProvider = BundleImageProvider(bundle: .main, searchPath: nil)

    public required override init() {
        AssertIsOnMainThread()

        super.init()
    }

    public func getMedia(_ key: String, isAnimated: Bool) -> AnyObject? {
        let cache = isAnimated ? animatedMediaCache : stillMediaCache
        return cache.get(key: key)
    }

    public func setMedia(_ value: AnyObject, forKey key: String, isAnimated: Bool) {
        let cache = isAnimated ? animatedMediaCache : stillMediaCache
        cache.set(key: key, value: value)
    }

    public func getMediaView(_ key: String, isAnimated: Bool) -> ReusableMediaView? {
        let cache = isAnimated ? animatedMediaViewCache : stillMediaViewCache
        return cache.get(key)
    }

    public func setMediaView(_ value: ReusableMediaView, forKey key: String, isAnimated: Bool) {
        let cache = isAnimated ? animatedMediaViewCache : stillMediaViewCache
        cache.set(value: value, forKey: key)
    }

    public func getLottieAnimation(name: String) -> Lottie.Animation? {
        AssertIsOnMainThread()

        if let value = lottieAnimationCache.get(key: name) {
            return value
        }
        guard let value = Lottie.Animation.named(name) else {
            owsFailDebug("Invalid Lottie animation: \(name).")
            return nil
        }
        lottieAnimationCache.set(key: name, value: value)
        return value
    }

    public func buildLottieAnimationView(name: String) -> Lottie.AnimationView {
        AssertIsOnMainThread()

        // Don't use Lottie.AnimationCacheProvider; LRUCache is better.
        let animation: Lottie.Animation? = getLottieAnimation(name: name)
        // Don't specify textProvider.
        let animationView = Lottie.AnimationView(animation: animation, imageProvider: lottieImageProvider)
        return animationView
    }

    public func removeAllObjects() {
        AssertIsOnMainThread()

        stillMediaCache.removeAllObjects()
        animatedMediaCache.removeAllObjects()

        stillMediaViewCache.removeAllObjects()
        animatedMediaViewCache.removeAllObjects()

        lottieAnimationCache.removeAllObjects()
    }
}

// MARK: -

private class MediaInnerCache<KeyType: Hashable, ValueType> {

    private var cache: LRUCache<KeyType, ValueType>

    public required init(maxSize: Int = 0) {
        AssertIsOnMainThread()

        cache = LRUCache<KeyType, ValueType>(maxSize: maxSize,
                                             shouldEvacuateInBackground: true)
    }

    // MARK: - API

    func get(_ key: KeyType) -> ValueType? {
        AssertIsOnMainThread()

        return cache.get(key: key)
    }

    func set(value: ValueType, forKey key: KeyType) {
        AssertIsOnMainThread()

        cache.set(key: key, value: value)
    }

    func removeAllObjects() {
        AssertIsOnMainThread()

        cache.clear()
    }
}
