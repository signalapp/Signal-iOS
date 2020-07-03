//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

private class ModelCacheAdapter<KeyType: AnyObject & Hashable, ValueType: BaseModel> {
    func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
        notImplemented()
    }

    func deriveKey(fromValue value: ValueType) -> KeyType {
        notImplemented()
    }

    func copy(value: ValueType) throws -> ValueType {
        notImplemented()
    }

    func uiReadEvacuation(databaseChanges: UIDatabaseChanges,
                          nsCache: NSCache<KeyType, ModelCacheValueBox<ValueType>>) {
        notImplemented()
    }
}

// MARK: -

private class ModelReadCache<KeyType: AnyObject & Hashable, ValueType: BaseModel>: UIDatabaseSnapshotDelegate {

    // MARK: - Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    // MARK: -

    enum Mode {
        // * .uiRead caches are only accessed on the main thread.
        // * They are evacuated whenever the ui database snapshot is updated.
        case uiRead
        // * .read caches can be accessed from any thread.
        // * They are eagerly updated to reflect db writes using the
        //   didInsertOrUpdate() and didRemove() hooks.
        // * They use "exclusion" to avoid races between reads and uncommited
        //   writes.
        // * They need to be evacuated after cross-process writes.
        case read

        public var description: String {
            switch self {
            case .uiRead:
                return ".uiRead"
            case .read:
                return ".read"
            }
        }
    }

    private let mode: Mode

    private let cacheName: String

    fileprivate var logName: String {
        return "\(cacheName) \(mode)"
    }

    #if TESTABLE_BUILD
    let cacheStats = ModelReadCacheStats()
    #endif

    // TODO: We could tune the size of this cache.
    //       NSCache's default behavior is opaque.
    //       We're currently only using this to cache
    //       small models, but that could change.
    fileprivate let nsCache = NSCache<KeyType, ModelCacheValueBox<ValueType>>()

    private let adapter: ModelCacheAdapter<KeyType, ValueType>

    private var isCacheReady: Bool {
        switch mode {
        case .read:
            return true
        case .uiRead:
            AssertIsOnMainThread()
            return isObservingUIDatabaseSnapshots
        }
    }
    private var isObservingUIDatabaseSnapshots = false

    init(mode: Mode, cacheName: String, adapter: ModelCacheAdapter<KeyType, ValueType>) {
        self.mode = mode
        self.cacheName = cacheName
        self.adapter = adapter

        switch mode {
        case .read:
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(didReceiveCrossProcessNotification),
                                                   name: SDSDatabaseStorage.didReceiveCrossProcessNotification,
                                                   object: nil)
        case .uiRead:
            // uiRead caches are evacuated by observing storage changes.
            AppReadiness.runNowOrWhenAppDidBecomeReady {
                AssertIsOnMainThread()

                self.databaseStorage.appendUIDatabaseSnapshotDelegate(self)
                self.isObservingUIDatabaseSnapshots = true
            }
        }
    }

    fileprivate func evacuateCache() {
        nsCache.removeAllObjects()
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
    private func readValue(for key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
        if let value = adapter.read(key: key, transaction: transaction) {
            #if TESTABLE_BUILD
            if !isExcluded(key: key),
                canUseCache(transaction: transaction) {
                // NOTE: We don't to update cache; the SDS model extensions
                // will populate the cache for us.
                assert(nsCache.object(forKey: key) != nil)
            }
            #endif
            return value
        }
        if !isExcluded(key: key),
            canUseCache(transaction: transaction) {
            // Update cache.
            nsCache.setObject(ModelCacheValueBox(value: nil), forKey: key)
        }
        return nil
    }

    func didRead(value: ValueType, transaction: SDSAnyReadTransaction) {
        guard canUseCache(transaction: transaction) else {
            return
        }
        let key = adapter.deriveKey(fromValue: value)
        performSync {
            if !isExcluded(key: key),
                canUseCache(transaction: transaction) {
                // Update cache.
                nsCache.setObject(ModelCacheValueBox(value: value), forKey: key)
            }
        }
    }

    // This method should only be called within performSync().
    private func cachedValue(for key: KeyType) -> ModelCacheValueBox<ValueType>? {
        guard isCacheReady else {
            return nil
        }
        guard !isExcluded(key: key) else {
            // Read excluded.
            return nil
        }
        return nsCache.object(forKey: key)
    }

    func getValue(for key: KeyType, transaction: SDSAnyReadTransaction, returnNilOnCacheMiss: Bool = false) -> ValueType? {
        // This can be used to verify that cached values exactly
        // align with database contents.
        #if TESTABLE_BUILD
        let shouldCheckValues = false
        let checkValues = { (cachedValue: ValueType?) in
            guard !returnNilOnCacheMiss else {
                return
            }
            let databaseValue = self.readValue(for: key, transaction: transaction)
            if cachedValue != databaseValue {
                Logger.verbose("cachedValue: \(cachedValue?.description() ?? "nil")")
                Logger.verbose("databaseValue: \(databaseValue?.description() ?? "nil")")
                owsFailDebug("cachedValue != databaseValue")
            }
        }
        #endif

        return performSync {
            if let cachedValue = self.cachedValue(for: key) {

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

                return self.readValue(for: key, transaction: transaction)
            }
        }
    }

    func getValuesIfInCache(for keys: [KeyType], transaction: SDSAnyReadTransaction) -> [KeyType: ValueType] {
        var result = [KeyType: ValueType]()
        for key in keys {
            if let value = getValue(for: key, transaction: transaction, returnNilOnCacheMiss: true) {
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
        let key = adapter.deriveKey(fromValue: value)
        updateCacheForWrite(key: key, value: nil, transaction: transaction)
    }

    func didInsertOrUpdate(value: ValueType, transaction: SDSAnyWriteTransaction) {
        assert(mode == .read)
        let key = adapter.deriveKey(fromValue: value)
        updateCacheForWrite(key: key, value: value, transaction: transaction)
    }

    private func updateCacheForWrite(key: KeyType, value: ValueType?, transaction: SDSAnyWriteTransaction) {
        guard canUseCache(transaction: transaction) else {
            return
        }

        // Exclude this key from being used in the cache
        // until the write transaction has committed.
        performSync {
            // Update the cache to reflect the new value.
            // The cache won't be used during the exclusion,
            // so we could also update this when we remove
            // the exclusion.
            if let value = value {
                nsCache.setObject(ModelCacheValueBox(value: value), forKey: key)
            } else {
                nsCache.setObject(ModelCacheValueBox(value: nil), forKey: key)
            }

            if self.mode == .read {
                // Protect the cache from being corrupted by reads
                // by excluding the key until the write transaction
                // commits.
                addExclusion(for: key)
            }
        }

        if mode == .read {
            // Once the write transaction has completed, it is safe
            // to use the cache for this key again for .read caches.
            transaction.addSyncCompletion {
                _ = self.performSync {
                    self.removeExclusion(for: key)
                }
            }
        }
    }

    private func canUseCache(transaction: SDSAnyReadTransaction) -> Bool {
        guard isCacheReady else {
            return false
        }
        switch transaction.readTransaction {
        case .yapRead:
            return false
        case .grdbRead:
            return true
        }
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
    private var excludedKeyMap = [KeyType: UInt]()

    // This method should only be called within performSync().
    private func isExcluded(key: KeyType) -> Bool {
        guard mode == .read else {
            return false
        }
        return excludedKeyMap[key] != nil
    }

    // This method should only be called within performSync().
    private func addExclusion(for key: KeyType) {
        assert(mode == .read)

        if let value = excludedKeyMap[key] {
            excludedKeyMap[key] = value + 1
        } else {
            excludedKeyMap[key] = 1
        }
    }

    // This method should only be called within performSync().
    private func removeExclusion(for key: KeyType) {
        assert(mode == .read)

        guard let value = excludedKeyMap[key] else {
            owsFailDebug("Missing exclusion key.")
            return
        }
        guard value > 1 else {
            excludedKeyMap.removeValue(forKey: key)
            return
        }
        excludedKeyMap[key] = value - 1
    }

    // We can't use a serial queue due to GRDB's scheduling watchdog.
    //
    // Never open a transaction within performSync() to avoid deadlock.
    @discardableResult
    private func performSync<T>(_ block: () -> T) -> T {
        switch mode {
        case .uiRead:
            AssertIsOnMainThread()
            // We don't need to bother syncing .uiRead activity since
            // it's all done on the main thread.
            return block()
        case .read:
            objc_sync_enter(self)
            let value = block()
            objc_sync_exit(self)
            return value
        }
    }

    // MARK: - UIDatabaseSnapshotDelegate

    func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
        assert(mode == .uiRead)
    }

    func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()
        assert(mode == .uiRead)

        adapter.uiReadEvacuation(databaseChanges: databaseChanges, nsCache: nsCache)
    }

    func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()
        assert(mode == .uiRead)

        evacuateCache()
    }

    func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()
        assert(mode == .uiRead)

        evacuateCache()
    }
}

// MARK: -

#if TESTABLE_BUILD
extension ModelReadCache: ModelCache {}
#endif

// MARK: -

private class ModelReadCacheWrapper<KeyType: AnyObject & Hashable, ValueType: BaseModel> {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    private let uiReadCache: ModelReadCache<KeyType, ValueType>
    private let readCache: ModelReadCache<KeyType, ValueType>

    init(cacheName: String, adapter: ModelCacheAdapter<KeyType, ValueType>) {
        uiReadCache = ModelReadCache(mode: .uiRead,
                                     cacheName: cacheName,
                                     adapter: adapter)
        readCache = ModelReadCache(mode: .read,
                                   cacheName: cacheName,
                                   adapter: adapter)
    }

    func getValue(for key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
        if transaction.isUIRead {
            assert(Thread.isMainThread)
        }
        let cache = (transaction.isUIRead ? uiReadCache : readCache)
        return cache.getValue(for: key, transaction: transaction)
    }

    func getValuesIfInCache(for keys: [KeyType], transaction: SDSAnyReadTransaction) -> [KeyType: ValueType] {
        if transaction.isUIRead {
            assert(Thread.isMainThread)
        }
        let cache = (transaction.isUIRead ? uiReadCache : readCache)
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
        if transaction.isUIRead {
            uiReadCache.didRead(value: value, transaction: transaction)
        } else {
            // Note that this might not affect the cache due to cache
            // exclusion, etc.
            readCache.didRead(value: value, transaction: transaction)
        }
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

        override func deriveKey(fromValue value: ValueType) -> KeyType {
            OWSUserProfile.resolve(value.address)
        }

        override func copy(value: ValueType) throws -> ValueType {
            // We don't need to use a deepCopy for OWSUserProfile.
            guard let modelCopy = value.copy() as? OWSUserProfile else {
                throw OWSAssertionError("Copy failed.")
            }
            return modelCopy
        }

        override func uiReadEvacuation(databaseChanges: UIDatabaseChanges,
                                       nsCache: NSCache<KeyType, ModelCacheValueBox<ValueType>>) {
            if databaseChanges.didUpdateModel(collection: OWSUserProfile.collection()) {
                nsCache.removeAllObjects()
            }
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(cacheName: "UserProfile", adapter: Adapter())
    }

    @objc
    public func getUserProfile(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        let address = OWSUserProfile.resolve(address)
        return cache.getValue(for: address, transaction: transaction)
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

        override func deriveKey(fromValue value: ValueType) -> KeyType {
            value.recipientAddress
        }

        override func copy(value: ValueType) throws -> ValueType {
            // We don't need to use a deepCopy for SignalAccount.
            guard let modelCopy = value.copy() as? SignalAccount else {
                throw OWSAssertionError("Copy failed.")
            }
            return modelCopy
        }

        override func uiReadEvacuation(databaseChanges: UIDatabaseChanges,
                                       nsCache: NSCache<KeyType, ModelCacheValueBox<ValueType>>) {
            if databaseChanges.didUpdateModel(collection: SignalAccount.collection()) {
                nsCache.removeAllObjects()
            }
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(cacheName: "SignalAccount", adapter: Adapter())
    }

    @objc
    public func getSignalAccount(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        return cache.getValue(for: address, transaction: transaction)
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

        override func deriveKey(fromValue value: ValueType) -> KeyType {
            value.address
        }

        override func copy(value: ValueType) throws -> ValueType {
            // We don't need to use a deepCopy for SignalRecipient.
            guard let modelCopy = value.copy() as? SignalRecipient else {
                throw OWSAssertionError("Copy failed.")
            }
            return modelCopy
        }

        override func uiReadEvacuation(databaseChanges: UIDatabaseChanges,
                                       nsCache: NSCache<KeyType, ModelCacheValueBox<ValueType>>) {
            if databaseChanges.didUpdateModel(collection: SignalRecipient.collection()) {
                nsCache.removeAllObjects()
            }
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(cacheName: "SignalRecipient", adapter: Adapter())
    }

    @objc(getSignalRecipientForAddress:transaction:)
    public func getSignalRecipient(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        return cache.getValue(for: address, transaction: transaction)
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
    typealias KeyType = NSString
    typealias ValueType = TSThread

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            return TSThread.anyFetch(uniqueId: key as String,
                                     transaction: transaction,
                                     ignoreCache: true)
        }

        override func deriveKey(fromValue value: ValueType) -> KeyType {
            value.uniqueId as NSString
        }

        override func copy(value: ValueType) throws -> ValueType {
            return try DeepCopies.deepCopy(value)
        }

        override func uiReadEvacuation(databaseChanges: UIDatabaseChanges,
                                       nsCache: NSCache<KeyType, ModelCacheValueBox<ValueType>>) {
            // Only evacuate modified models.
            for uniqueId: String in databaseChanges.threadUniqueIds {
                nsCache.removeObject(forKey: uniqueId as NSString)
            }
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(cacheName: "TSThread", adapter: Adapter())
    }

    @objc(getThreadForUniqueId:transaction:)
    public func getThread(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSThread? {
        return cache.getValue(for: uniqueId as NSString, transaction: transaction)
    }

    @objc(getThreadsIfInCacheForUniqueIds:transaction:)
    public func getThreadsIfInCache(forUniqueIds uniqueIds: [String], transaction: SDSAnyReadTransaction) -> [String: TSThread] {
        let keys: [NSString] = uniqueIds.map { $0 as NSString }
        let result: [NSString: TSThread] = cache.getValuesIfInCache(for: keys, transaction: transaction)
        return Dictionary(uniqueKeysWithValues: result.map({ (key, value) in
            return (key as String, value)
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
    typealias KeyType = NSString
    typealias ValueType = TSInteraction

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            return TSInteraction.anyFetch(uniqueId: key as String,
                                          transaction: transaction,
                                          ignoreCache: true)
        }

        override func deriveKey(fromValue value: ValueType) -> KeyType {
            value.uniqueId as NSString
        }

        override func copy(value: ValueType) throws -> ValueType {
            return try DeepCopies.deepCopy(value)
        }

        override func uiReadEvacuation(databaseChanges: UIDatabaseChanges,
                                       nsCache: NSCache<KeyType, ModelCacheValueBox<ValueType>>) {
            // Only evacuate modified models.
            for uniqueId: String in databaseChanges.interactionUniqueIds {
                nsCache.removeObject(forKey: uniqueId as NSString)
            }
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(cacheName: "TSInteraction", adapter: Adapter())
    }

    @objc(getInteractionForUniqueId:transaction:)
    public func getInteraction(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSInteraction? {
        return cache.getValue(for: uniqueId as NSString, transaction: transaction)
    }

    @objc(getInteractionsIfInCacheForUniqueIds:transaction:)
    public func getInteractionsIfInCache(forUniqueIds uniqueIds: [String], transaction: SDSAnyReadTransaction) -> [String: TSInteraction] {
        let keys: [NSString] = uniqueIds.map { $0 as NSString }
        let result: [NSString: TSInteraction] = cache.getValuesIfInCache(for: keys, transaction: transaction)
        return Dictionary(uniqueKeysWithValues: result.map({ (key, value) in
            return (key as String, value)
        }))
    }

    @objc(didRemoveInteraction:transaction:)
    public func didRemove(interaction: TSInteraction, transaction: SDSAnyWriteTransaction) {
        cache.didRemove(value: interaction, transaction: transaction)
    }

    @objc(didInsertOrUpdateInteraction:transaction:)
    public func didInsertOrUpdate(interaction: TSInteraction, transaction: SDSAnyWriteTransaction) {
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
    typealias KeyType = NSString
    typealias ValueType = TSAttachment

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            return TSAttachment.anyFetch(uniqueId: key as String,
                                         transaction: transaction,
                                         ignoreCache: true)
        }

        override func deriveKey(fromValue value: ValueType) -> KeyType {
            value.uniqueId as NSString
        }

        override func copy(value: ValueType) throws -> ValueType {
            return try DeepCopies.deepCopy(value)
        }

        override func uiReadEvacuation(databaseChanges: UIDatabaseChanges,
                                       nsCache: NSCache<KeyType, ModelCacheValueBox<ValueType>>) {
            // Only evacuate modified models.
            for uniqueId: String in databaseChanges.attachmentUniqueIds {
                nsCache.removeObject(forKey: uniqueId as NSString)
            }
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(cacheName: "TSAttachment", adapter: Adapter())
    }

    @objc(getAttachmentForUniqueId:transaction:)
    public func getAttachment(uniqueId: String, transaction: SDSAnyReadTransaction) -> TSAttachment? {
        return cache.getValue(for: uniqueId as NSString, transaction: transaction)
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
    typealias KeyType = NSString
    typealias ValueType = InstalledSticker

    private class Adapter: ModelCacheAdapter<KeyType, ValueType> {
        override func read(key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
            return InstalledSticker.anyFetch(uniqueId: key as String,
                                             transaction: transaction,
                                             ignoreCache: true)
        }

        override func deriveKey(fromValue value: ValueType) -> KeyType {
            value.uniqueId as NSString
        }

        override func copy(value: ValueType) throws -> ValueType {
            return try DeepCopies.deepCopy(value)
        }

        override func uiReadEvacuation(databaseChanges: UIDatabaseChanges,
                                       nsCache: NSCache<KeyType, ModelCacheValueBox<ValueType>>) {
            if databaseChanges.didUpdateModel(collection: InstalledSticker.collection()) {
                nsCache.removeAllObjects()
            }
        }
    }

    private let cache: ModelReadCacheWrapper<KeyType, ValueType>

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(cacheName: "InstalledSticker", adapter: Adapter())
    }

    @objc(getInstalledStickerForUniqueId:transaction:)
    public func getInstalledSticker(uniqueId: String, transaction: SDSAnyReadTransaction) -> InstalledSticker? {
        return cache.getValue(for: uniqueId as NSString, transaction: transaction)
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
}
