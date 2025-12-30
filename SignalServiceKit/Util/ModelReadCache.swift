//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: -

class ModelCacheValueBox<ValueType> {
    let value: ValueType?

    init(value: ValueType?) {
        self.value = value
    }
}

// MARK: -

struct ModelCacheKey<KeyType: Hashable & Equatable> {
    let key: KeyType
}

// MARK: -

class ModelCacheAdapter<KeyType: Hashable & Equatable, ValueType> {
    func read(key: KeyType, transaction: DBReadTransaction) -> ValueType? {
        fatalError("Unimplemented")
    }

    final func cacheKey(forValue value: ValueType) -> ModelCacheKey<KeyType> {
        cacheKey(forKey: key(forValue: value))
    }

    func key(forValue value: ValueType) -> KeyType {
        fatalError("Unimplemented")
    }

    func cacheKey(forKey key: KeyType) -> ModelCacheKey<KeyType> {
        fatalError("Unimplemented")
    }

    func copy(value: ValueType) throws -> ValueType {
        fatalError("Unimplemented")
    }

    let cacheName: String

    let cacheCountLimit: Int

    init(cacheName: String, cacheCountLimit: Int) {
        self.cacheName = cacheName
        self.cacheCountLimit = cacheCountLimit
    }
}

// MARK: -

/// * Read caches can be accessed from any thread.
///
/// * They are eagerly updated to reflect db writes using the
/// didInsertOrUpdate() and didRemove() hooks.
///
/// * They use "exclusion" to avoid races between reads and uncommitted
/// writes.
///
/// * They need to be evacuated after cross-process writes.
class ModelReadCache<KeyType: Hashable & Equatable, ValueType> {
    private let appReadiness: AppReadiness

    private var cacheName: String {
        adapter.cacheName
    }

    var logName: String {
        return "\(cacheName)"
    }

    fileprivate let cache: LRUCache<KeyType, ModelCacheValueBox<ValueType>>

    private let adapter: ModelCacheAdapter<KeyType, ValueType>

    init(
        adapter: ModelCacheAdapter<KeyType, ValueType>,
        appReadiness: AppReadiness,
    ) {
        self.appReadiness = appReadiness
        self.adapter = adapter
        self.cache = LRUCache(maxSize: adapter.cacheCountLimit, nseMaxSize: 0)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveCrossProcessNotification),
            name: SDSDatabaseStorage.didReceiveCrossProcessNotificationAlwaysSync,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveEvacuateCacheNotification),
            name: ModelReadCaches.evacuateAllModelCaches,
            object: nil,
        )
    }

    private func evacuateCache() {
        // Right now, we call `cache.removeAllObjects()` on background threads. For
        // now, this is OK because LRUCache is thread safe, but if we ever do more
        // work here we should re-evaluate.

        cache.removeAllObjects()

        DispatchQueue.global().async {
            self.performSync {
                self.cache.removeAllObjects()
            }
        }
    }

    @objc
    private func didReceiveEvacuateCacheNotification(_ notification: Notification) {
        evacuateCache()
    }

    @objc
    private func didReceiveCrossProcessNotification(_ notification: Notification) {
        AssertIsOnMainThread()
        evacuateCache()
    }

    // This method should only be called within performSync().
    private func readValue(for cacheKey: ModelCacheKey<KeyType>, transaction: DBReadTransaction) -> ValueType? {
        let maybeValue = adapter.read(key: cacheKey.key, transaction: transaction)
        if let value = maybeValue {
            return value
        }
        if !isExcluded(cacheKey: cacheKey, transaction: transaction), canUseCache() {
            // Update cache.
            writeToCache(cacheKey: cacheKey, value: nil)
        }
        return nil
    }

    func didRead(value: ValueType, transaction: DBReadTransaction) {
        let cacheKey = adapter.cacheKey(forValue: value)
        guard canUseCache() else {
            return
        }
        performSync {
            if !isExcluded(cacheKey: cacheKey, transaction: transaction), canUseCache() {
                writeToCache(cacheKey: cacheKey, value: value)
            }
        }
    }

    fileprivate func getValue(for cacheKey: ModelCacheKey<KeyType>, transaction: DBReadTransaction, returnNilOnCacheMiss: Bool = false) -> ValueType? {
        return getValues(for: [cacheKey], transaction: transaction, returnNilOnCacheMiss: returnNilOnCacheMiss)[0]
    }

    func getValues(
        for cacheKeys: [ModelCacheKey<KeyType>],
        transaction: DBReadTransaction,
        returnNilOnCacheMiss: Bool = false,
    ) -> [ValueType?] {
        return performSync {
            return cacheKeys.map { cacheKey in
                if
                    !isExcluded(cacheKey: cacheKey, transaction: transaction),
                    let cachedValue = readFromCache(cacheKey: cacheKey)
                {
                    return cachedValue.value.flatMap { self.copyValue($0) }
                }
                if returnNilOnCacheMiss {
                    return nil
                }
                return self.readValue(for: cacheKey, transaction: transaction)
            }
        }
    }

    func getValuesIfInCache(for keys: [KeyType], transaction: DBReadTransaction) -> [KeyType: ValueType] {
        var result = [KeyType: ValueType]()
        for key in keys {
            let cacheKey = adapter.cacheKey(forKey: key)
            if let value = getValue(for: cacheKey, transaction: transaction, returnNilOnCacheMiss: true) {
                result[key] = value
            }
        }
        return result
    }

    private func copyValue(_ value: ValueType) -> ValueType? {
        do {
            return try adapter.copy(value: value)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func didRemove(value: ValueType, transaction: DBWriteTransaction) {
        let cacheKey = adapter.cacheKey(forValue: value)
        updateCacheForWrite(cacheKey: cacheKey, value: nil, transaction: transaction)
    }

    func didInsertOrUpdate(value: ValueType, transaction: DBWriteTransaction) {
        let cacheKey = adapter.cacheKey(forValue: value)
        updateCacheForWrite(cacheKey: cacheKey, value: value, transaction: transaction)
    }

    private func updateCacheForWrite(cacheKey: ModelCacheKey<KeyType>, value: ValueType?, transaction: DBWriteTransaction) {
        guard canUseCache() else {
            return
        }

        // Exclude this key from being used in the cache until the write
        // transaction has committed.
        performSync {
            // Update the cache to reflect the new value. The cache won't be used
            // during the exclusion, so we could also update this when we remove the
            // exclusion.
            writeToCache(cacheKey: cacheKey, value: value)

            // Protect the cache from being corrupted by reads by excluding the key
            // until the write transaction commits.
            addExclusion(for: cacheKey)
        }

        // Once the write transaction has completed, it is safe to use the cache
        // for this key again for .read caches.
        transaction.addSyncCompletion {
            self.performSync {
                self.removeExclusion(for: cacheKey)
            }
        }
    }

    private var isAppReady: Bool {
        return appReadiness.isAppReady
    }

    private func canUseCache() -> Bool { isAppReady }

    // MARK: -

    func writeToCache(cacheKey: ModelCacheKey<KeyType>, value: ValueType?) {
        cache.setObject(ModelCacheValueBox(value: value), forKey: cacheKey.key)
    }

    func readFromCache(cacheKey: ModelCacheKey<KeyType>) -> ModelCacheValueBox<ValueType>? {
        cache.object(forKey: cacheKey.key)
    }

    // MARK: - Exclusion

    /// Races between reads and writes can corrupt the cache. Therefore gets
    /// _for a given key_ should not read from or write to the cache during
    /// database writes which affect that key, specifically during the
    /// "exclusion period" that begins when the first write query affecting that
    /// key completes and that ends when the write transaction has committed.
    ///
    /// The desired behavior:
    ///
    /// * During the "exclusion period" (e.g. write query completed but write
    /// transaction hasn't committed) we want all gets to reflect the current
    /// state _for their transaction_.
    ///
    /// * We might "get" from within the same write transaction that caused the
    /// "exclusion". That should reflect the _new_ state.
    ///
    /// * Concurrent gets from read transactions or without a transaction during
    /// the "exclusion period" should reflect the old state.
    ///
    /// We achieve this by having all gets ignore the cache during the
    /// "exclusion period."
    ///
    /// Bear in mind that:
    ///
    /// * Values might be evacuated from the cache between the write query and
    /// the write transaction being committed.
    ///
    /// Note that we use a map with counters so that the async completion of one
    /// write doesn't interfere with exclusion from a subsequent write to the
    /// same entity.
    private var exclusionCountMap = [KeyType: Int]()
    private var exclusionDateMap = [KeyType: MonotonicDate]()

    // This method should only be called within performSync().
    private func isExcluded(cacheKey: ModelCacheKey<KeyType>, transaction: DBReadTransaction) -> Bool {
        if let exclusionDate = exclusionDateMap[cacheKey.key] {

            if exclusionDate > transaction.startDate {
                return true
            }
        }

        if exclusionCountMap[cacheKey.key] != nil {
            return true
        }
        return false
    }

    // This method should only be called within performSync().
    func addExclusion(for cacheKey: ModelCacheKey<KeyType>) {
        let key = cacheKey.key
        if let value = self.exclusionCountMap[key] {
            self.exclusionCountMap[key] = value + 1
        } else {
            self.exclusionCountMap[key] = 1
        }
    }

    // This method should only be called within performSync().
    private func removeExclusion(for cacheKey: ModelCacheKey<KeyType>) {
        let key = cacheKey.key

        self.exclusionDateMap[key] = MonotonicDate()

        guard let value = self.exclusionCountMap[key] else {
            owsFailDebug("Missing exclusion key.")
            return
        }
        guard value > 1 else {
            self.exclusionCountMap.removeValue(forKey: key)
            return
        }
        self.exclusionCountMap[key] = value - 1
    }

    // Never open a transaction within performSync() to avoid deadlock.
    @discardableResult
    func performSync<T>(_ block: () -> T) -> T {
        // We can't use a serial queue due to GRDB's scheduling watchdog.
        // Additionally, our locking mechanism needs to be re-entrant.
        objc_sync_enter(self)
        let value = block()
        objc_sync_exit(self)
        return value
    }
}

// MARK: -

@objc
public class ThreadReadCache: NSObject {
    private class Adapter: ModelCacheAdapter<String, TSThread> {
        override func read(key: String, transaction: DBReadTransaction) -> TSThread? {
            return TSThread.anyFetch(uniqueId: key, transaction: transaction, ignoreCache: true)
        }

        override func key(forValue value: TSThread) -> String {
            value.uniqueId
        }

        override func cacheKey(forKey key: String) -> ModelCacheKey<String> {
            return ModelCacheKey(key: key)
        }

        override func copy(value: TSThread) throws -> TSThread {
            return try DeepCopies.deepCopy(value)
        }
    }

    private let cache: ModelReadCache<String, TSThread>
    private let adapter = Adapter(cacheName: "TSThread", cacheCountLimit: 32)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(adapter: adapter)
    }

    @objc(getThreadForUniqueId:transaction:)
    public func getThread(uniqueId: String, transaction: DBReadTransaction) -> TSThread? {
        let cacheKey = adapter.cacheKey(forKey: uniqueId)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    @objc(didRemoveThread:transaction:)
    public func didRemove(thread: TSThread, transaction: DBWriteTransaction) {
        cache.didRemove(value: thread, transaction: transaction)
    }

    @objc(didInsertOrUpdateThread:transaction:)
    public func didInsertOrUpdate(thread: TSThread, transaction: DBWriteTransaction) {
        cache.didInsertOrUpdate(value: thread, transaction: transaction)
    }

    @objc
    public func didReadThread(_ thread: TSThread, transaction: DBReadTransaction) {
        cache.didRead(value: thread, transaction: transaction)
    }
}

// MARK: -

@objc
public class InteractionReadCache: NSObject {
    private class Adapter: ModelCacheAdapter<String, TSInteraction> {
        override func read(key: String, transaction: DBReadTransaction) -> TSInteraction? {
            return TSInteraction.anyFetch(uniqueId: key, transaction: transaction, ignoreCache: true)
        }

        override func key(forValue value: TSInteraction) -> String {
            value.uniqueId
        }

        override func cacheKey(forKey key: String) -> ModelCacheKey<String> {
            return ModelCacheKey(key: key)
        }

        override func copy(value: TSInteraction) throws -> TSInteraction {
            return try DeepCopies.deepCopy(value)
        }
    }

    private let cache: ModelReadCache<String, TSInteraction>
    private let adapter = Adapter(cacheName: "TSInteraction", cacheCountLimit: 1024)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(adapter: adapter)
    }

    @objc(getInteractionForUniqueId:transaction:)
    public func getInteraction(uniqueId: String, transaction: DBReadTransaction) -> TSInteraction? {
        let cacheKey = adapter.cacheKey(forKey: uniqueId)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    public func getInteractionsIfInCache(for uniqueIds: [String], transaction: DBReadTransaction) -> [String: TSInteraction] {
        return cache.getValuesIfInCache(for: uniqueIds, transaction: transaction)
    }

    @objc(didRemoveInteraction:transaction:)
    public func didRemove(interaction: TSInteraction, transaction: DBWriteTransaction) {
        cache.didRemove(value: interaction, transaction: transaction)
    }

    @objc(didUpdateInteraction:transaction:)
    public func didUpdate(interaction: TSInteraction, transaction: DBWriteTransaction) {
        guard interaction.sortId > 0 else {
            // Only cache interactions that have been read from the database.
            return
        }
        cache.didInsertOrUpdate(value: interaction, transaction: transaction)
    }

    @objc
    public func didReadInteraction(_ interaction: TSInteraction, transaction: DBReadTransaction) {
        cache.didRead(value: interaction, transaction: transaction)
    }
}

// MARK: -

@objc
public class InstalledStickerCache: NSObject {
    private class Adapter: ModelCacheAdapter<String, InstalledSticker> {
        override func read(key: String, transaction: DBReadTransaction) -> InstalledSticker? {
            return InstalledSticker.anyFetch(uniqueId: key, transaction: transaction, ignoreCache: true)
        }

        override func key(forValue value: InstalledSticker) -> String {
            value.uniqueId
        }

        override func cacheKey(forKey key: String) -> ModelCacheKey<String> {
            return ModelCacheKey(key: key)
        }

        override func copy(value: InstalledSticker) throws -> InstalledSticker {
            return try DeepCopies.deepCopy(value)
        }
    }

    private let cache: ModelReadCache<String, InstalledSticker>
    private static var cacheCountLimit: Int {
        if CurrentAppContext().isMainApp {
            // Large enough to hold three pages of max-size stickers.
            return 600
        } else {
            // Large enough to hold the current default 49 stickers with a little room to grow.
            return 64
        }
    }

    private let adapter = Adapter(cacheName: "InstalledSticker", cacheCountLimit: InstalledStickerCache.cacheCountLimit)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(adapter: adapter)
    }

    @objc(getInstalledStickerForUniqueId:transaction:)
    public func getInstalledSticker(uniqueId: String, transaction: DBReadTransaction) -> InstalledSticker? {
        let cacheKey = adapter.cacheKey(forKey: uniqueId)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    @objc(didRemoveInstalledSticker:transaction:)
    public func didRemove(installedSticker: InstalledSticker, transaction: DBWriteTransaction) {
        cache.didRemove(value: installedSticker, transaction: transaction)
    }

    @objc(didInsertOrUpdateInstalledSticker:transaction:)
    public func didInsertOrUpdate(installedSticker: InstalledSticker, transaction: DBWriteTransaction) {
        cache.didInsertOrUpdate(value: installedSticker, transaction: transaction)
    }

    @objc
    public func didReadInstalledSticker(_ installedSticker: InstalledSticker, transaction: DBReadTransaction) {
        cache.didRead(value: installedSticker, transaction: transaction)
    }
}

// MARK: -

@objc
public class ModelReadCaches: NSObject {
    @objc(initWithModelReadCacheFactory:)
    public init(factory: ModelReadCacheFactory) {
        threadReadCache = ThreadReadCache(factory)
        interactionReadCache = InteractionReadCache(factory)
        installedStickerCache = InstalledStickerCache(factory)
    }

    @objc
    public let threadReadCache: ThreadReadCache
    @objc
    public let interactionReadCache: InteractionReadCache
    @objc
    public let installedStickerCache: InstalledStickerCache

    @objc
    fileprivate static let evacuateAllModelCaches = Notification.Name("EvacuateAllModelCaches")

    @objc
    public func evacuateAllCaches() {
        NotificationCenter.default.post(name: Self.evacuateAllModelCaches, object: nil)
    }
}

public class ModelReadCacheFactory: NSObject {

    fileprivate let appReadiness: AppReadiness

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
    }

    func create<KeyType: Hashable & Equatable, ValueType>(
        adapter: ModelCacheAdapter<KeyType, ValueType>,
    ) -> ModelReadCache<KeyType, ValueType> {
        return ModelReadCache(adapter: adapter, appReadiness: appReadiness)
    }
}
