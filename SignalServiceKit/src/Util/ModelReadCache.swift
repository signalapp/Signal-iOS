//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

#if TESTABLE_BUILD
protocol ModelCache {
    var logName: String { get }
}

// MARK: -

private struct ModelReadCacheStats {
    static let shouldLogCacheStats = false

    let cacheHitCount = AtomicUInt()
    let cacheReadCount = AtomicUInt()

    func recordCacheHit(_ cache: ModelCache) {
        let hitCount = cacheHitCount.increment()
        let totalCount = cacheReadCount.increment()
        logStats(hitCount: hitCount, totalCount: totalCount, cache: cache)
    }

    func recordCacheMiss(_ cache: ModelCache) {
        let hitCount = cacheHitCount.get()
        let totalCount = cacheReadCount.increment()
        logStats(hitCount: hitCount, totalCount: totalCount, cache: cache)
    }

    private func logStats(hitCount: UInt, totalCount: UInt, cache: ModelCache) {
        if Self.shouldLogCacheStats, totalCount > 0, totalCount % 100 == 0 {
            let percentage = 100 * Double(hitCount) / Double(totalCount)
            Logger.verbose("---- \(cache.logName): \(percentage)% \(totalCount)")
        }
    }
}
#endif

// MARK: -

private class ModelCacheValueBox<ValueType: BaseModel> {
    let value: ValueType?

    init(value: ValueType?) {
        self.value = value
    }
}

// MARK: -

private struct ModelCacheKey<KeyType: Hashable & Equatable> {
    let key: KeyType
}

// MARK: -

private class ModelCacheAdapter<KeyType: Hashable & Equatable, ValueType: BaseModel> {
    func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
        notImplemented()
    }

    final func cacheKey(forValue value: ValueType) -> ModelCacheKey<KeyType> {
        cacheKey(forKey: key(forValue: value))
    }

    func key(forValue value: ValueType) -> KeyType {
        notImplemented()
    }

    func cacheKey(forKey key: KeyType) -> ModelCacheKey<KeyType> {
        notImplemented()
    }

    func copy(value: ValueType) throws -> ValueType {
        notImplemented()
    }

    let cacheName: String

    let cacheCountLimit: Int
    let cacheCountLimitNSE: Int

    init(cacheName: String, cacheCountLimit: Int, cacheCountLimitNSE: Int) {
        self.cacheName = cacheName
        self.cacheCountLimit = cacheCountLimit
        self.cacheCountLimitNSE = cacheCountLimitNSE
    }
}

// MARK: -

private class ModelReadCache<KeyType: Hashable & Equatable, ValueType: BaseModel>: Dependencies {

    enum Mode {
        // * .read caches can be accessed from any thread.
        // * They are eagerly updated to reflect db writes using the
        //   didInsertOrUpdate() and didRemove() hooks.
        // * They use "exclusion" to avoid races between reads and uncommited
        //   writes.
        // * They need to be evacuated after cross-process writes.
        case read

        public var description: String {
            switch self {
            case .read:
                return ".read"
            }
        }
    }

    private let mode: Mode

    private var cacheName: String {
        adapter.cacheName
    }

    fileprivate var logName: String {
        return "\(cacheName) \(mode)"
    }

    #if TESTABLE_BUILD
    let cacheStats = ModelReadCacheStats()
    #endif

    fileprivate let cache: LRUCache<KeyType, ModelCacheValueBox<ValueType>>

    private let adapter: ModelCacheAdapter<KeyType, ValueType>

    private var isCacheReady: Bool {
        switch mode {
        case .read:
            return true
        }
    }

    init(mode: Mode, adapter: ModelCacheAdapter<KeyType, ValueType>) {
        self.mode = mode
        self.adapter = adapter
        self.cache = LRUCache(maxSize: adapter.cacheCountLimit,
                              nseMaxSize: adapter.cacheCountLimitNSE)

        switch mode {
        case .read:
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(didReceiveCrossProcessNotification),
                                                   name: SDSDatabaseStorage.didReceiveCrossProcessNotification,
                                                   object: nil)
        }
    }

    fileprivate func evacuateCache() {
        // This may execute on background threads. For now, this is OK
        // because LRUCache is thread safe, but if we ever do more work
        // here we should re-evaluate.
        cache.removeAllObjects()
    }

    @objc
    func didReceiveCrossProcessNotification(_ notification: Notification) {
        AssertIsOnMainThread()
        assert(mode == .read)

        evacuateCache()

        DispatchQueue.global().async {
            self.performSync {
                self.evacuateCache()
            }
        }
    }

    // This method should only be called within performSync().
    private func readValue(for cacheKey: ModelCacheKey<KeyType>, transaction: SDSAnyReadTransaction) -> ValueType? {
        if let value = adapter.read(key: cacheKey.key, transaction: transaction) {
            #if TESTABLE_BUILD
            if !isExcluded(cacheKey: cacheKey, transaction: transaction),
                canUseCache(cacheKey: cacheKey, transaction: transaction) {
                // NOTE: We don't need to update the cache; the SDS
                // model extensions will populate the cache for us.
                if readFromCache(cacheKey: cacheKey)?.value == nil {
                    let cacheKeyForValue = adapter.cacheKey(forValue: value)
                    let canUseCacheForValue = canUseCache(cacheKey: cacheKey, transaction: transaction)
                    Logger.verbose("Missing value in cache: \(cacheKey.key), cacheKeyForValue: \(cacheKeyForValue), canUseCacheForValue: \(canUseCacheForValue), \(logName)")
                }
            }
            #endif
            return value
        }
        if !isExcluded(cacheKey: cacheKey, transaction: transaction),
            canUseCache(cacheKey: cacheKey, transaction: transaction) {
            // Update cache.
            writeToCache(cacheKey: cacheKey, value: nil)
        }
        return nil
    }

    func didRead(value: ValueType, transaction: SDSAnyReadTransaction) {
        let cacheKey = adapter.cacheKey(forValue: value)
        guard canUseCache(cacheKey: cacheKey, transaction: transaction) else {
            return
        }
        performSync {
            if !isExcluded(cacheKey: cacheKey, transaction: transaction),
                canUseCache(cacheKey: cacheKey, transaction: transaction) {
                writeToCache(cacheKey: cacheKey, value: value)
            }
        }
    }

    // This method should only be called within performSync().
    private func cachedValue(for cacheKey: ModelCacheKey<KeyType>, transaction: SDSAnyReadTransaction) -> ModelCacheValueBox<ValueType>? {
        guard isCacheReady else {
            return nil
        }
        guard !isExcluded(cacheKey: cacheKey, transaction: transaction) else {
            // Read excluded.
            return nil
        }
        return readFromCache(cacheKey: cacheKey)
    }

    func getValue(for cacheKey: ModelCacheKey<KeyType>, transaction: SDSAnyReadTransaction, returnNilOnCacheMiss: Bool = false) -> ValueType? {
        // This can be used to verify that cached values exactly
        // align with database contents.
        #if TESTABLE_BUILD
        let shouldCheckValues = false
        let checkValues = { (cachedValue: ValueType?) in
            guard !returnNilOnCacheMiss else {
                return
            }
            let databaseValue = self.readValue(for: cacheKey, transaction: transaction)
            if cachedValue != databaseValue {
                Logger.verbose("cachedValue: \(cachedValue?.description() ?? "nil")")
                Logger.verbose("databaseValue: \(databaseValue?.description() ?? "nil")")
                owsFailDebug("cachedValue != databaseValue")
            }
        }
        #endif

        return performSync {
            if let cachedValue = self.cachedValue(for: cacheKey, transaction: transaction) {

                #if TESTABLE_BUILD
                cacheStats.recordCacheHit(self)
                #endif

                if let value = cachedValue.value {
                    // Return a copy of the model.
                    let cachedValue = self.copyValue(value)

                    #if TESTABLE_BUILD
                    if shouldCheckValues {
                        checkValues(cachedValue)
                    }
                    #endif

                    return cachedValue
                } else {
                    #if TESTABLE_BUILD
                    if shouldCheckValues {
                        checkValues(nil)
                    }
                    #endif

                    return nil
                }
            } else {
                #if TESTABLE_BUILD
                cacheStats.recordCacheMiss(self)
                #endif

                guard !returnNilOnCacheMiss else {
                    return nil
                }

                return self.readValue(for: cacheKey, transaction: transaction)
            }
        }
    }

    func getValuesIfInCache(for keys: [KeyType], transaction: SDSAnyReadTransaction) -> [KeyType: ValueType] {
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
            // This is a hot code path, so only bench in debug builds.
            let cachedValue: ValueType
            #if TESTABLE_BUILD
            cachedValue = try Bench(title: "Slow copy: \(logName)", logIfLongerThan: 0.001, logInProduction: false) {
                try adapter.copy(value: value)
            }
            #else
            cachedValue = try adapter.copy(value: value)
            #endif
            return cachedValue
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func didRemove(value: ValueType, transaction: SDSAnyWriteTransaction) {
        assert(mode == .read)
        let cacheKey = adapter.cacheKey(forValue: value)
        updateCacheForWrite(cacheKey: cacheKey, value: nil, transaction: transaction)
    }

    func didInsertOrUpdate(value: ValueType, transaction: SDSAnyWriteTransaction) {
        assert(mode == .read)
        let cacheKey = adapter.cacheKey(forValue: value)
        updateCacheForWrite(cacheKey: cacheKey, value: value, transaction: transaction)
    }

    private func updateCacheForWrite(cacheKey: ModelCacheKey<KeyType>, value: ValueType?, transaction: SDSAnyWriteTransaction) {
        guard canUseCache(cacheKey: cacheKey, transaction: transaction) else {
            return
        }

        // Exclude this key from being used in the cache
        // until the write transaction has committed.
        performSync {
            // Update the cache to reflect the new value.
            // The cache won't be used during the exclusion,
            // so we could also update this when we remove
            // the exclusion.
            writeToCache(cacheKey: cacheKey, value: value)

            if self.mode == .read {
                // Protect the cache from being corrupted by reads
                // by excluding the key until the write transaction
                // commits.
                addExclusion(for: cacheKey)
            }
        }

        if mode == .read {
            // Once the write transaction has completed, it is safe
            // to use the cache for this key again for .read caches.
            transaction.addSyncCompletion {
                self.performSync {
                    self.removeExclusion(for: cacheKey)
                }
            }
        }
    }

    private func isCachable(cacheKey: ModelCacheKey<KeyType>) -> Bool {
        guard let address = cacheKey.key as? SignalServiceAddress else {
            return true
        }
        if address.uuid != nil {
            return true
        }
        if address.phoneNumber == kLocalProfileInvariantPhoneNumber {
            owsAssertDebug(address.uuid == nil)
            return true
        }
        #if TESTABLE_BUILD
        if !DebugFlags.reduceLogChatter {
            Logger.warn("Skipping cache for: \(address), \(cacheName)")
        }
        #endif
        return false
    }

    private func canUseCache(cacheKey: ModelCacheKey<KeyType>,
                             transaction: SDSAnyReadTransaction) -> Bool {
        guard isCachable(cacheKey: cacheKey) else {
            return false
        }
        guard isCacheReady else {
            return false
        }
        guard AppReadiness.isAppReady else {
            return false
        }
        switch transaction.readTransaction {
        case .grdbRead:
            return true
        }
    }

    // MARK: -

    private func writeToCache(cacheKey: ModelCacheKey<KeyType>, value: ValueType?) {
        cache.setObject(ModelCacheValueBox(value: value), forKey: cacheKey.key)
    }

    private func readFromCache(cacheKey: ModelCacheKey<KeyType>) -> ModelCacheValueBox<ValueType>? {
        cache.object(forKey: cacheKey.key)
    }

    // MARK: - Exclusion

    // Races between reads and writes can corrupt the cache.
    // Therefore gets _for a given key_ should not read from or
    // write to the cache during database writes which affect
    // that key, specifically during the "exclusion period"
    // that begins when the first write query affecting that
    // key completes and that ends when the write transaction
    // has committed.
    //
    // The desired behavior:
    //
    // * During the "exclusion period" (e.g. write query completed
    //   but write transaction hasn't committed) we want
    //   all gets to reflect the current state _for their transaction_.
    // * We might "get" from within the same write
    //   transaction that caused the "exclusion". That should
    //   reflect the _new_ state.
    // * Concurrent gets from read transactions or without a transaction
    //   during the "exclusion period" should refect the old state.
    //
    // We achieve this by having all gets ignore the cache during
    // the "exclusion period."
    //
    // Bear in mind that:
    //
    // * Values might be evacuated from the cache between the
    //   write query and the write transaction being committed.
    //
    // Note that we use a map with counters so that the async
    // completion of one write doesn't interfere with exclusion
    // from a subsequent write to the same entity.
    private var exclusionCountMap = [KeyType: Int]()
    private var exclusionDateMap = [KeyType: Date]()

    // This method should only be called within performSync().
    private func isExcluded(cacheKey: ModelCacheKey<KeyType>, transaction: SDSAnyReadTransaction) -> Bool {
        guard mode == .read else {
            return false
        }

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
    private func addExclusion(for cacheKey: ModelCacheKey<KeyType>) {
        assert(mode == .read)

        let key = cacheKey.key
        if let value = self.exclusionCountMap[key] {
            self.exclusionCountMap[key] = value + 1
        } else {
            self.exclusionCountMap[key] = 1
        }
    }

    // This method should only be called within performSync().
    private func removeExclusion(for cacheKey: ModelCacheKey<KeyType>) {
        assert(mode == .read)

        let key = cacheKey.key

        self.exclusionDateMap[key] = Date()

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

    private let unfairLock = UnfairLock()

    // We can't use a serial queue due to GRDB's scheduling watchdog.
    //
    // Never open a transaction within performSync() to avoid deadlock.
    @discardableResult
    private func performSync<T>(_ block: () -> T) -> T {
        switch mode {
        case .read:
            return unfairLock.withLock {
                block()
            }
        }
    }
}

// MARK: -

#if TESTABLE_BUILD
extension ModelReadCache: ModelCache {}
#endif

// MARK: -

// TODO: Remove?
private class ModelReadCacheWrapper<KeyType: Hashable & Equatable, ValueType: BaseModel> {

    private let readCache: ModelReadCache<KeyType, ValueType>

    init(adapter: ModelCacheAdapter<KeyType, ValueType>) {
        readCache = ModelReadCache(mode: .read, adapter: adapter)
    }

    func getValue(for cacheKey: ModelCacheKey<KeyType>, transaction: SDSAnyReadTransaction) -> ValueType? {
        let cache = readCache
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    func getValuesIfInCache(for keys: [KeyType], transaction: SDSAnyReadTransaction) -> [KeyType: ValueType] {
        let cache = readCache
        return cache.getValuesIfInCache(for: keys, transaction: transaction)
    }

    func didRemove(value: ValueType, transaction: SDSAnyWriteTransaction) {
        // Only update readCache to reflect writes.
        readCache.didRemove(value: value, transaction: transaction)
    }

    func didInsertOrUpdate(value: ValueType, transaction: SDSAnyWriteTransaction) {
        // Only update readCache to reflect writes.
        readCache.didInsertOrUpdate(value: value, transaction: transaction)
    }

    func didRead(value: ValueType, transaction: SDSAnyReadTransaction) {
        // Note that this might not affect the cache due to cache
        // exclusion, etc.
        readCache.didRead(value: value, transaction: transaction)
    }
}

// MARK: -

@objc
public class UserProfileReadCache: NSObject {
    typealias KeyType = SignalServiceAddress
    typealias ValueType = OWSUserProfile

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            OWSUserProfile.getFor(key, transaction: transaction)
        }

        override func key(forValue value: ValueType) -> KeyType {
            OWSUserProfile.resolve(value.address)
        }

        override func cacheKey(forKey key: KeyType) -> ModelCacheKey<KeyType> {
            // Resolve key for local user to the invariant key.
            ModelCacheKey(key: OWSUserProfile.resolve(key))
        }

        override func copy(value: ValueType) throws -> ValueType {
            // We don't need to use a deepCopy for OWSUserProfile.
            guard let modelCopy = value.copy() as? OWSUserProfile else {
                throw OWSAssertionError("Copy failed.")
            }
            return modelCopy
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "UserProfile", cacheCountLimit: 32, cacheCountLimitNSE: 16)

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(adapter: adapter)
    }

    @objc
    public func getUserProfile(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        let address = OWSUserProfile.resolve(address)
        let cacheKey = adapter.cacheKey(forKey: address)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    @objc(didRemoveUserProfile:transaction:)
    public func didRemove(userProfile: OWSUserProfile, transaction: SDSAnyWriteTransaction) {
        cache.didRemove(value: userProfile, transaction: transaction)
    }

    @objc(didInsertOrUpdateUserProfile:transaction:)
    public func didInsertOrUpdate(userProfile: OWSUserProfile, transaction: SDSAnyWriteTransaction) {
        cache.didInsertOrUpdate(value: userProfile, transaction: transaction)
    }

    @objc(didReadUserProfile:transaction:)
    public func didReadUserProfile(_ userProfile: OWSUserProfile, transaction: SDSAnyReadTransaction) {
        cache.didRead(value: userProfile, transaction: transaction)
    }
}

// MARK: -

@objc
public class SignalAccountReadCache: NSObject {
    typealias KeyType = SignalServiceAddress
    typealias ValueType = SignalAccount

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        private let accountFinder = AnySignalAccountFinder()

        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            accountFinder.signalAccount(for: key, transaction: transaction)
        }

        override func key(forValue value: ValueType) -> KeyType {
            value.recipientAddress
        }

        override func cacheKey(forKey key: KeyType) -> ModelCacheKey<KeyType> {
            ModelCacheKey(key: key)
        }

        override func copy(value: ValueType) throws -> ValueType {
            // We don't need to use a deepCopy for SignalAccount.
            guard let modelCopy = value.copy() as? SignalAccount else {
                throw OWSAssertionError("Copy failed.")
            }
            return modelCopy
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "SignalAccount", cacheCountLimit: 256, cacheCountLimitNSE: 32)

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(adapter: adapter)
    }

    @objc
    public func getSignalAccount(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        let cacheKey = adapter.cacheKey(forKey: address)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    @objc(didRemoveSignalAccount:transaction:)
    public func didRemove(signalAccount: SignalAccount, transaction: SDSAnyWriteTransaction) {
        cache.didRemove(value: signalAccount, transaction: transaction)
    }

    @objc(didInsertOrUpdateSignalAccount:transaction:)
    public func didInsertOrUpdate(signalAccount: SignalAccount, transaction: SDSAnyWriteTransaction) {
        cache.didInsertOrUpdate(value: signalAccount, transaction: transaction)
    }

    @objc(didReadSignalAccount:transaction:)
    public func didReadSignalAccount(_ signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) {
        cache.didRead(value: signalAccount, transaction: transaction)
    }
}

// MARK: -

@objc
public class SignalRecipientReadCache: NSObject {
    typealias KeyType = SignalServiceAddress
    typealias ValueType = SignalRecipient

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        private let recipientFinder = AnySignalRecipientFinder()

        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            recipientFinder.signalRecipient(for: key, transaction: transaction)
        }

        override func key(forValue value: ValueType) -> KeyType {
            value.address
        }

        override func cacheKey(forKey key: KeyType) -> ModelCacheKey<KeyType> {
            ModelCacheKey(key: key)
        }

        override func copy(value: ValueType) throws -> ValueType {
            // We don't need to use a deepCopy for SignalRecipient.
            guard let modelCopy = value.copy() as? SignalRecipient else {
                throw OWSAssertionError("Copy failed.")
            }
            return modelCopy
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "SignalRecipient", cacheCountLimit: 256, cacheCountLimitNSE: 32)

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(adapter: adapter)
    }

    @objc(getSignalRecipientForAddress:transaction:)
    public func getSignalRecipient(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        let cacheKey = adapter.cacheKey(forKey: address)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    @objc(didRemoveSignalRecipient:transaction:)
    public func didRemove(signalRecipient: SignalRecipient, transaction: SDSAnyWriteTransaction) {
        cache.didRemove(value: signalRecipient, transaction: transaction)
    }

    @objc(didInsertOrUpdateSignalRecipient:transaction:)
    public func didInsertOrUpdate(signalRecipient: SignalRecipient, transaction: SDSAnyWriteTransaction) {
        cache.didInsertOrUpdate(value: signalRecipient, transaction: transaction)
    }

    @objc(didReadSignalRecipient:transaction:)
    public func didReadSignalRecipient(_ signalRecipient: SignalRecipient, transaction: SDSAnyReadTransaction) {
        cache.didRead(value: signalRecipient, transaction: transaction)
    }
}

// MARK: -

@objc
public class ThreadReadCache: NSObject {
    typealias KeyType = String
    typealias ValueType = TSThread

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            return TSThread.anyFetch(uniqueId: key,
                                     transaction: transaction,
                                     ignoreCache: true)
        }

        override func key(forValue value: ValueType) -> KeyType {
            value.uniqueId
        }

        override func cacheKey(forKey key: KeyType) -> ModelCacheKey<KeyType> {
            return ModelCacheKey(key: key)
        }

        override func copy(value: ValueType) throws -> ValueType {
            return try DeepCopies.deepCopy(value)
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "TSThread", cacheCountLimit: 32, cacheCountLimitNSE: 8)

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(adapter: adapter)
    }

    @objc(getThreadForUniqueId:transaction:)
    public func getThread(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSThread? {
        let cacheKey = adapter.cacheKey(forKey: uniqueId)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    @objc(getThreadsIfInCacheForUniqueIds:transaction:)
    public func getThreadsIfInCache(forUniqueIds uniqueIds: [String], transaction: SDSAnyReadTransaction) -> [String: TSThread] {
        let keys: [String] = uniqueIds.map { $0 }
        let result: [String: TSThread] = cache.getValuesIfInCache(for: keys, transaction: transaction)
        return Dictionary(uniqueKeysWithValues: result.map({ (key, value) in
            return (key, value)
        }))
    }

    @objc(didRemoveThread:transaction:)
    public func didRemove(thread: TSThread, transaction: SDSAnyWriteTransaction) {
        cache.didRemove(value: thread, transaction: transaction)
    }

    @objc(didInsertOrUpdateThread:transaction:)
    public func didInsertOrUpdate(thread: TSThread, transaction: SDSAnyWriteTransaction) {
        cache.didInsertOrUpdate(value: thread, transaction: transaction)
    }

    @objc
    public func didReadThread(_ thread: TSThread, transaction: SDSAnyReadTransaction) {
        cache.didRead(value: thread, transaction: transaction)
    }
}

// MARK: -

@objc
public class InteractionReadCache: NSObject {
    typealias KeyType = String
    typealias ValueType = TSInteraction

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            return TSInteraction.anyFetch(uniqueId: key,
                                          transaction: transaction,
                                          ignoreCache: true)
        }

        override func key(forValue value: ValueType) -> KeyType {
            value.uniqueId
        }

        override func cacheKey(forKey key: KeyType) -> ModelCacheKey<KeyType> {
            return ModelCacheKey(key: key)
        }

        override func copy(value: ValueType) throws -> ValueType {
            return try DeepCopies.deepCopy(value)
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "TSInteraction", cacheCountLimit: 1024, cacheCountLimitNSE: 32)

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(adapter: adapter)
    }

    @objc(getInteractionForUniqueId:transaction:)
    public func getInteraction(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSInteraction? {
        let cacheKey = adapter.cacheKey(forKey: uniqueId)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    @objc(getInteractionsIfInCacheForUniqueIds:transaction:)
    public func getInteractionsIfInCache(forUniqueIds uniqueIds: [String], transaction: SDSAnyReadTransaction) -> [String: TSInteraction] {
        let keys: [String] = uniqueIds.map { $0 }
        let result: [String: TSInteraction] = cache.getValuesIfInCache(for: keys, transaction: transaction)
        return Dictionary(uniqueKeysWithValues: result.map({ (key, value) in
            return (key, value)
        }))
    }

    @objc(didRemoveInteraction:transaction:)
    public func didRemove(interaction: TSInteraction, transaction: SDSAnyWriteTransaction) {
        cache.didRemove(value: interaction, transaction: transaction)
    }

    @objc(didUpdateInteraction:transaction:)
    public func didUpdate(interaction: TSInteraction, transaction: SDSAnyWriteTransaction) {
        guard interaction.sortId > 0 else {
            // Only cache interactions that have been read from the database.
            return
        }
        cache.didInsertOrUpdate(value: interaction, transaction: transaction)
    }

    @objc
    public func didReadInteraction(_ interaction: TSInteraction, transaction: SDSAnyReadTransaction) {
        cache.didRead(value: interaction, transaction: transaction)
    }
}

// MARK: -

@objc
public class AttachmentReadCache: NSObject {
    typealias KeyType = String
    typealias ValueType = TSAttachment

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            return TSAttachment.anyFetch(uniqueId: key,
                                         transaction: transaction,
                                         ignoreCache: true)
        }

        override func key(forValue value: ValueType) -> KeyType {
            value.uniqueId
        }

        override func cacheKey(forKey key: KeyType) -> ModelCacheKey<KeyType> {
            return ModelCacheKey(key: key)
        }

        override func copy(value: ValueType) throws -> ValueType {
            return try DeepCopies.deepCopy(value)
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "TSAttachment", cacheCountLimit: 256, cacheCountLimitNSE: 16)

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(adapter: adapter)
    }

    @objc(getAttachmentForUniqueId:transaction:)
    public func getAttachment(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSAttachment? {
        let cacheKey = adapter.cacheKey(forKey: uniqueId)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    @objc(didRemoveAttachment:transaction:)
    public func didRemove(attachment: TSAttachment, transaction: SDSAnyWriteTransaction) {
        cache.didRemove(value: attachment, transaction: transaction)
    }

    @objc(didInsertOrUpdateAttachment:transaction:)
    public func didInsertOrUpdate(attachment: TSAttachment, transaction: SDSAnyWriteTransaction) {
        cache.didInsertOrUpdate(value: attachment, transaction: transaction)
    }

    @objc
    public func didReadAttachment(_ attachment: TSAttachment, transaction: SDSAnyReadTransaction) {
        cache.didRead(value: attachment, transaction: transaction)
    }
}

// MARK: -

@objc
public class InstalledStickerCache: NSObject {
    typealias KeyType = String
    typealias ValueType = InstalledSticker

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            return InstalledSticker.anyFetch(uniqueId: key,
                                             transaction: transaction,
                                             ignoreCache: true)
        }

        override func key(forValue value: ValueType) -> KeyType {
            value.uniqueId
        }

        override func cacheKey(forKey key: KeyType) -> ModelCacheKey<KeyType> {
            return ModelCacheKey(key: key)
        }

        override func copy(value: ValueType) throws -> ValueType {
            return try DeepCopies.deepCopy(value)
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "InstalledSticker", cacheCountLimit: 32, cacheCountLimitNSE: 8)

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(adapter: adapter)
    }

    @objc(getInstalledStickerForUniqueId:transaction:)
    public func getInstalledSticker(uniqueId: String, transaction: SDSAnyReadTransaction) -> InstalledSticker? {
        let cacheKey = adapter.cacheKey(forKey: uniqueId)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    @objc(didRemoveInstalledSticker:transaction:)
    public func didRemove(installedSticker: InstalledSticker, transaction: SDSAnyWriteTransaction) {
        cache.didRemove(value: installedSticker, transaction: transaction)
    }

    @objc(didInsertOrUpdateInstalledSticker:transaction:)
    public func didInsertOrUpdate(installedSticker: InstalledSticker, transaction: SDSAnyWriteTransaction) {
        cache.didInsertOrUpdate(value: installedSticker, transaction: transaction)
    }

    @objc
    public func didReadInstalledSticker(_ installedSticker: InstalledSticker, transaction: SDSAnyReadTransaction) {
        cache.didRead(value: installedSticker, transaction: transaction)
    }
}

// MARK: -

// MARK: -

@objc
public class ModelReadCaches: NSObject {
    @objc
    public required override init() {
        super.init()

        NotificationCenter.default.addObserver(forName: SDSDatabaseStorage.storageDidReload,
                                               object: nil, queue: nil) { [weak self] _ in
                                                AssertIsOnMainThread()
                                                self?.evacuateAllCaches()
        }
    }

    @objc
    public let userProfileReadCache = UserProfileReadCache()
    @objc
    public let signalAccountReadCache = SignalAccountReadCache()
    @objc
    public let signalRecipientReadCache = SignalRecipientReadCache()
    @objc
    public let threadReadCache = ThreadReadCache()
    @objc
    public let interactionReadCache = InteractionReadCache()
    @objc
    public let attachmentReadCache = AttachmentReadCache()
    @objc
    public let installedStickerCache = InstalledStickerCache()

    @objc
    fileprivate static let evacuateAllModelCaches = Notification.Name("EvacuateAllModelCaches")

    func evacuateAllCaches() {
        NotificationCenter.default.post(name: Self.evacuateAllModelCaches, object: nil)
    }
}
