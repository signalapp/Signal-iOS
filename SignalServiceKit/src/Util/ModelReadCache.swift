//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD
protocol ModelCache {
    var logName: String { get }
}

// MARK: -

struct ModelReadCacheStats {
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
    func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
        fatalError("Unimplemented")
    }

    func read(keys: [KeyType], transaction: SDSAnyReadTransaction) -> [ValueType?] {
        return keys.map {
            read(key: $0, transaction: transaction)
        }
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
    let cacheCountLimitNSE: Int

    init(cacheName: String, cacheCountLimit: Int, cacheCountLimitNSE: Int) {
        self.cacheName = cacheName
        self.cacheCountLimit = cacheCountLimit
        self.cacheCountLimitNSE = cacheCountLimitNSE
    }
}

// MARK: -

class ModelReadCache<KeyType: Hashable & Equatable, ValueType>: Dependencies, CacheSizeLeasing {

    enum Mode {
        // * .read caches can be accessed from any thread.
        // * They are eagerly updated to reflect db writes using the
        //   didInsertOrUpdate() and didRemove() hooks.
        // * They use "exclusion" to avoid races between reads and uncommitted
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

    var logName: String {
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

    private let disableCachesInNSE = true

    private var leases = NSHashTable<ModelReadCacheSizeLease>.weakObjects()

    init(mode: Mode, adapter: ModelCacheAdapter<KeyType, ValueType>) {
        self.mode = mode
        self.adapter = adapter
        self.cache = LRUCache(maxSize: adapter.cacheCountLimit,
                              nseMaxSize: disableCachesInNSE ? 0 : adapter.cacheCountLimitNSE)

        switch mode {
        case .read:
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didReceiveCrossProcessNotification),
                name: SDSDatabaseStorage.didReceiveCrossProcessNotificationAlwaysSync,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didReceiveEvacuateCacheNotification),
                name: ModelReadCaches.evacuateAllModelCaches,
                object: nil
            )
        }
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
        assert(mode == .read)
        evacuateCache()
    }

    // This method should only be called within performSync().
    private func readValue(for cacheKey: ModelCacheKey<KeyType>, transaction: SDSAnyReadTransaction) -> ValueType? {
        return readValues(for: AnySequence([cacheKey]), transaction: transaction)[0]
    }

    // This method should only be called within performSync().
    func readValues(for cacheKeys: AnySequence<ModelCacheKey<KeyType>>,
                    transaction: SDSAnyReadTransaction) -> [ValueType?] {
        let maybeValues = adapter.read(keys: cacheKeys.map { $0.key },
                                       transaction: transaction)
        return zip(cacheKeys, maybeValues).map { tuple in
            let (cacheKey, maybeValue) = tuple
            if let value = maybeValue {
                #if TESTABLE_BUILD
                if !CurrentAppContext().isNSE,
                   !isExcluded(cacheKey: cacheKey, transaction: transaction),
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
        return cachedValues(for: [cacheKey], transaction: transaction)[0]
    }

    // This method should only be called within performSync().
    private func cachedValues(for cacheKeys: [ModelCacheKey<KeyType>], transaction: SDSAnyReadTransaction) -> [ModelCacheValueBox<ValueType>?] {
        guard isCacheReady else {
            return Array(repeating: nil, count: cacheKeys.count)
        }
        return Refinery<ModelCacheKey<KeyType>, ModelCacheValueBox<ValueType>>(cacheKeys).refine { cacheKey in
            return !isExcluded(cacheKey: cacheKey, transaction: transaction)
        } then: { cacheKeys -> [ModelCacheValueBox<ValueType>?] in
            return readFromCache(cacheKeys: AnySequence(cacheKeys))
        } otherwise: { cacheKeys -> [ModelCacheValueBox<ValueType>?] in
            // Read excluded.
            return cacheKeys.lazy.map { _ in nil }
        }.values
    }

    func getValue(for cacheKey: ModelCacheKey<KeyType>, transaction: SDSAnyReadTransaction, returnNilOnCacheMiss: Bool = false) -> ValueType? {
        return getValues(for: [cacheKey], transaction: transaction, returnNilOnCacheMiss: returnNilOnCacheMiss)[0]
    }

    func getValues(for cacheKeys: [ModelCacheKey<KeyType>],
                   transaction: SDSAnyReadTransaction,
                   returnNilOnCacheMiss: Bool = false) -> [ValueType?] {
        // This can be used to verify that cached values exactly
        // align with database contents.
        #if TESTABLE_BUILD
        let shouldCheckValues = false
        let checkValues = { (cacheKey: ModelCacheKey<KeyType>, cachedValue: ValueType?) in
            guard !returnNilOnCacheMiss else {
                return
            }
            _ = self.readValue(for: cacheKey, transaction: transaction)
        }
        #endif

        return performSync {
            let maybeValues = self.cachedValues(for: cacheKeys, transaction: transaction)
            let keyValueTuples = Array(zip(cacheKeys, maybeValues))
            typealias KeyValuePair = (ModelCacheKey<KeyType>, ModelCacheValueBox<ValueType>?)
            return Refinery<KeyValuePair, ValueType>(keyValueTuples).refine { (entry: KeyValuePair) -> Bool in
                return entry.1 != nil
            } then: { (entries: AnySequence<KeyValuePair>) -> [ValueType?] in
                //  Have an entry in maybeValues, although it could be nil.
                return entries.map { tuple in
                    let (key, cachedValue) = (tuple.0, tuple.1!)

                    #if TESTABLE_BUILD
                    cacheStats.recordCacheHit(self)
                    #endif

                    if let value = cachedValue.value {
                        // Return a copy of the model.
                        let cachedValue = self.copyValue(value)

                        #if TESTABLE_BUILD
                        if shouldCheckValues {
                            checkValues(key, cachedValue)
                        }
                        #endif

                        return cachedValue
                    }
                    #if TESTABLE_BUILD
                    if shouldCheckValues {
                        checkValues(key, nil)
                    }
                    #endif

                    return nil
                }
            } otherwise: { tuples -> [ValueType?] in
                // Have no cache entry.
                #if TESTABLE_BUILD
                for _ in tuples {
                    cacheStats.recordCacheMiss(self)
                }
                #endif

                guard !returnNilOnCacheMiss else {
                    return tuples.lazy.map { _ in nil }
                }

                let keys = tuples.lazy.map { $0.0 }
                return self.readValues(for: AnySequence(keys), transaction: transaction)
            }.values
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

    func add(lease: ModelReadCacheSizeLease) {
        performSync {
            // It's a bug to add an already-added lease.
            owsAssert(!leases.contains(lease))

            leases.add(lease)
            updateMaxSize()
        }
    }

    func remove(lease: ModelReadCacheSizeLease) {
        performSync {
            leases.remove(lease)
            updateMaxSize()
        }
    }

    private func updateMaxSize() {
        let leasedSize = leases.allObjects.lazy.map { $0.size }.max() ?? 0
        cache.maxSize = leasedSize + cache.regularMaxSize
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
        return false
    }

    var isAppReady: Bool {
        return AppReadiness.isAppReady
    }

    private func canUseCache(cacheKey: ModelCacheKey<KeyType>,
                             transaction: SDSAnyReadTransaction) -> Bool {
        guard isCachable(cacheKey: cacheKey) else {
            return false
        }
        guard isCacheReady else {
            return false
        }
        guard isAppReady else {
            return false
        }
        switch transaction.readTransaction {
        case .grdbRead:
            return true
        }
    }

    // MARK: -

    func writeToCache(cacheKey: ModelCacheKey<KeyType>, value: ValueType?) {
        cache.setObject(ModelCacheValueBox(value: value), forKey: cacheKey.key)
    }

    func readFromCache(cacheKey: ModelCacheKey<KeyType>) -> ModelCacheValueBox<ValueType>? {
        cache.object(forKey: cacheKey.key)
    }

    private func readFromCache(cacheKeys: AnySequence<ModelCacheKey<KeyType>>) -> [ModelCacheValueBox<ValueType>?] {
        return cacheKeys.map { cache.object(forKey: $0.key) }
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
    //   during the "exclusion period" should reflect the old state.
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
    func addExclusion(for cacheKey: ModelCacheKey<KeyType>) {
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

    // Never open a transaction within performSync() to avoid deadlock.
    @discardableResult
    func performSync<T>(_ block: () -> T) -> T {
        switch mode {
        case .read:
            // We can't use a serial queue due to GRDB's scheduling watchdog.
            // Additionally, our locking mechanism needs to be re-entrant.
            objc_sync_enter(self)
            let value = block()
            objc_sync_exit(self)
            return value
        }
    }
}

// MARK: -

#if TESTABLE_BUILD
extension ModelReadCache: ModelCache {}
#endif

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

        override func read(keys: [UserProfileReadCache.KeyType],
                           transaction: SDSAnyReadTransaction) -> [UserProfileReadCache.ValueType?] {
            return OWSUserProfile.getFor(keys: keys, transaction: transaction)
        }
    }

    private let cache: ModelReadCache<KeyType, ValueType>

    private let adapter = Adapter(cacheName: "UserProfile", cacheCountLimit: 32, cacheCountLimitNSE: 16)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(mode: .read, adapter: adapter)
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

    @objc
    public func leaseCacheSize(_ size: Int) -> ModelReadCacheSizeLease {
        return ModelReadCacheSizeLease(size, model: cache)
    }

    public func getUserProfiles(for addresses: AnySequence<SignalServiceAddress>,
                                transaction: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        let cacheKeys = addresses.map { self.adapter.cacheKey(forKey: OWSUserProfile.resolve($0)) }
        return cache.getValues(for: cacheKeys, transaction: transaction)
    }
}

// MARK: -

@objc
public class SignalAccountReadCache: NSObject {
    typealias KeyType = SignalServiceAddress
    typealias ValueType = SignalAccount

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        private let accountFinder = SignalAccountFinder()

        override func read(key: KeyType, transaction tx: SDSAnyReadTransaction) -> ValueType? {
            accountFinder.signalAccount(for: key, tx: tx)
        }

        override func read(keys: [SignalAccountReadCache.KeyType],
                           transaction tx: SDSAnyReadTransaction) -> [SignalAccountReadCache.ValueType?] {
            accountFinder.signalAccounts(for: keys, tx: tx)
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

    private let cache: ModelReadCache<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "SignalAccount", cacheCountLimit: 256, cacheCountLimitNSE: 32)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(mode: .read, adapter: adapter)
    }

    @objc
    public func getSignalAccount(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        let cacheKey = adapter.cacheKey(forKey: address)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    public func getSignalAccounts(addresses: AnySequence<SignalServiceAddress>,
                                  transaction: SDSAnyReadTransaction) -> [SignalAccount?] {
        let cacheKeys = addresses.map { adapter.cacheKey(forKey: $0) }
        return cache.getValues(for: cacheKeys, transaction: transaction)
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

    @objc
    public func leaseCacheSize(_ size: Int) -> ModelReadCacheSizeLease {
        return ModelReadCacheSizeLease(size, model: cache)
    }
}

// MARK: -

@objc
public class SignalRecipientReadCache: NSObject {
    typealias KeyType = SignalServiceAddress
    typealias ValueType = SignalRecipient

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction tx: SDSAnyReadTransaction) -> ValueType? {
            SignalRecipientFinder().signalRecipient(for: key, tx: tx)
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

    private let cache: ModelReadCache<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "SignalRecipient", cacheCountLimit: 256, cacheCountLimitNSE: 32)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(mode: .read, adapter: adapter)
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

    private let cache: ModelReadCache<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "TSThread", cacheCountLimit: 32, cacheCountLimitNSE: 8)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(mode: .read, adapter: adapter)
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

    private let cache: ModelReadCache<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "TSInteraction", cacheCountLimit: 1024, cacheCountLimitNSE: 32)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(mode: .read, adapter: adapter)
    }

    @objc(getInteractionForUniqueId:transaction:)
    public func getInteraction(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSInteraction? {
        let cacheKey = adapter.cacheKey(forKey: uniqueId)
        return cache.getValue(for: cacheKey, transaction: transaction)
    }

    public func getInteractionsIfInCache(for uniqueIds: [String], transaction: SDSAnyReadTransaction) -> [String: TSInteraction] {
        return cache.getValuesIfInCache(for: uniqueIds, transaction: transaction)
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

    private let cache: ModelReadCache<KeyType, ValueType>
    private let adapter = Adapter(cacheName: "TSAttachment", cacheCountLimit: 256, cacheCountLimitNSE: 16)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(mode: .read, adapter: adapter)
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

    private let cache: ModelReadCache<KeyType, ValueType>
    private static var cacheCountLimit: Int {
        if CurrentAppContext().isMainApp {
            // Large enough to hold three pages of max-size stickers.
            return 600
        } else {
            // Large enough to hold the current default 49 stickers with a little room to grow.
            return 64
        }
    }
    private let adapter = Adapter(cacheName: "InstalledSticker",
                                  cacheCountLimit: InstalledStickerCache.cacheCountLimit,
                                  cacheCountLimitNSE: 8)

    @objc
    public init(_ factory: ModelReadCacheFactory) {
        cache = factory.create(mode: .read, adapter: adapter)
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

protocol CacheSizeLeasing: AnyObject {
    func add(lease: ModelReadCacheSizeLease)
    func remove(lease: ModelReadCacheSizeLease)
}

// Use a `ModelReadCacheSizeLease` to temporarily increase the size of a `ModelReadCache`.
@objc
public class ModelReadCacheSizeLease: NSObject {
    fileprivate let size: Int
    private weak var model: CacheSizeLeasing?

    fileprivate init(_ size: Int, model: CacheSizeLeasing) {
        self.size = size
        self.model = model
        super.init()
        model.add(lease: self)
    }

    deinit {
        terminate()
    }

    @objc
    public func terminate() {
        model?.remove(lease: self)
        model = nil
    }
}

// MARK: -

@objc
public class ModelReadCaches: NSObject {
    @objc(initWithModelReadCacheFactory:)
    public init(factory: ModelReadCacheFactory) {
        userProfileReadCache = UserProfileReadCache(factory)
        signalAccountReadCache = SignalAccountReadCache(factory)
        signalRecipientReadCache = SignalRecipientReadCache(factory)
        threadReadCache = ThreadReadCache(factory)
        interactionReadCache = InteractionReadCache(factory)
        attachmentReadCache = AttachmentReadCache(factory)
        installedStickerCache = InstalledStickerCache(factory)

        super.init()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(evacuateAllCaches),
                                               name: SDSDatabaseStorage.storageDidReload,
                                               object: nil)
    }

    @objc
    public let userProfileReadCache: UserProfileReadCache
    @objc
    public let signalAccountReadCache: SignalAccountReadCache
    @objc
    public let signalRecipientReadCache: SignalRecipientReadCache
    @objc
    public let threadReadCache: ThreadReadCache
    @objc
    public let interactionReadCache: InteractionReadCache
    @objc
    public let attachmentReadCache: AttachmentReadCache
    @objc
    public let installedStickerCache: InstalledStickerCache

    @objc
    fileprivate static let evacuateAllModelCaches = Notification.Name("EvacuateAllModelCaches")

    @objc
    func evacuateAllCaches() {
        NotificationCenter.default.post(name: Self.evacuateAllModelCaches, object: nil)
    }
}

class TestableModelReadCache<KeyType: Hashable & Equatable, ValueType>: ModelReadCache<KeyType, ValueType> {
    override var isAppReady: Bool {
        return true
    }
}

@objc
public class ModelReadCacheFactory: NSObject {
    func create<KeyType: Hashable & Equatable, ValueType>(
        mode: ModelReadCache<KeyType, ValueType>.Mode,
        adapter: ModelCacheAdapter<KeyType, ValueType>
    ) -> ModelReadCache<KeyType, ValueType> {
        return ModelReadCache(mode: mode, adapter: adapter)
    }
}

@objc
class TestableModelReadCacheFactory: ModelReadCacheFactory {
    override func create<KeyType: Hashable & Equatable, ValueType>(
        mode: ModelReadCache<KeyType, ValueType>.Mode,
        adapter: ModelCacheAdapter<KeyType, ValueType>
    ) -> ModelReadCache<KeyType, ValueType> {
        return TestableModelReadCache(mode: mode, adapter: adapter)
    }
}
