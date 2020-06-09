//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

private class ModelReadCache<KeyType: AnyObject & Hashable, ValueType: BaseModel> {

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

    class ValueBox {
        let value: ValueType?

        init(value: ValueType?) {
            self.value = value
        }
    }

    // This property should only be accessed on serialQueue.
    //
    // TODO: We could tune the size of this cache.
    //       NSCache's default behavior is opaque.
    //       We're currently only using this to cache
    //       small models, but that could change.
    private let nscache = NSCache<KeyType, ValueBox>()

    typealias ReadBlock = (KeyType, SDSAnyReadTransaction) -> ValueType?
    private let readBlock: ReadBlock

    typealias KeyBlock = (ValueType) -> KeyType
    private let keyBlock: KeyBlock

    typealias CopyBlock = (ValueType) throws -> ValueType
    private let copyBlock: CopyBlock

    init(mode: Mode,
         cacheName: String,
         keyBlock: @escaping KeyBlock,
         readBlock: @escaping ReadBlock,
         copyBlock: @escaping CopyBlock) {
        self.mode = mode
        self.cacheName = cacheName
        self.keyBlock = keyBlock
        self.readBlock = readBlock
        self.copyBlock = copyBlock

        switch mode {
        case .read:
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(didReceiveCrossProcessNotification),
                                                   name: SDSDatabaseStorage.didReceiveCrossProcessNotification,
                                                   object: nil)
        case .uiRead:
            // uiRead caches are evacuated by the cache wrapper, which
            // observes storage changes.
            break
        }
    }

    fileprivate func evacuateCache() {
        nscache.removeAllObjects()
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
        Logger.verbose("---- Reading \(key) in \(logName)")
        if let value = readBlock(key, transaction) {
            if !isExcluded(key: key),
                canUseCache(transaction: transaction) {
                // Update cache.
                nscache.setObject(ValueBox(value: value), forKey: key)
            }
            return value
        }
        if !isExcluded(key: key),
            canUseCache(transaction: transaction) {
            // Update cache.
            nscache.setObject(ValueBox(value: nil), forKey: key)
        }
        return nil
    }

    // This method should only be called within performSync().
    private func cachedValue(for key: KeyType) -> ValueBox? {
        guard !isExcluded(key: key) else {
            // Read excluded.
            return nil
        }
        return nscache.object(forKey: key)
    }

    func getValue(for key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
        // This can be used to verify that cached values exactly
        // align with database contents.
        #if TESTABLE_BUILD
        let shouldCheckValues = false
        let checkValues = { (cachedValue: ValueType?) in
            let databaseValue = self.readValue(for: key, transaction: transaction)
            if cachedValue != databaseValue {
                Logger.verbose("cachedValue: \(cachedValue?.description())")
                Logger.verbose("databaseValue: \(databaseValue?.description())")
                owsFailDebug("cachedValue != databaseValue")
            }
        }
        #endif

        return performSync {
            if let cachedValue = self.cachedValue(for: key) {
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
                return self.readValue(for: key, transaction: transaction)
            }
        }
    }

    private func copyValue(_ value: ValueType) -> ValueType? {
        do {
            // This is a hot code path, so only bench in debug builds.
            let cachedValue: ValueType
            #if TESTABLE_BUILD
            cachedValue = try Bench(title: "Slow copy: \(logName)", logIfLongerThan: 0.001, logInProduction: false) {
                try self.copyBlock(value)
            }
            #else
            cachedValue = try self.copyBlock(value)
            #endif
            return cachedValue
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    func didRemove(value: ValueType, transaction: SDSAnyWriteTransaction) {
        assert(mode == .read)
        let key = keyBlock(value)
        updateCacheForWrite(key: key, value: nil, transaction: transaction)
    }

    func didInsertOrUpdate(value: ValueType, transaction: SDSAnyWriteTransaction) {
        assert(mode == .read)
        let key = keyBlock(value)
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
                nscache.setObject(ValueBox(value: value), forKey: key)
            } else {
                nscache.setObject(ValueBox(value: nil), forKey: key)
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
}

// MARK: -

private class ModelReadCacheWrapper<KeyType: AnyObject & Hashable, ValueType: BaseModel>: SDSDatabaseStorageObserver {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    private let uiReadCache: ModelReadCache<KeyType, ValueType>
    private let readCache: ModelReadCache<KeyType, ValueType>

    typealias ReadBlock = (KeyType, SDSAnyReadTransaction) -> ValueType?
    typealias KeyBlock = (ValueType) -> KeyType
    typealias CopyBlock = (ValueType) throws -> ValueType
    typealias UIReadEvacuationBlock = (SDSDatabaseStorageChange) -> Bool

    private let uiReadEvacuationBlock: UIReadEvacuationBlock

    init(cacheName: String,
         keyBlock: @escaping KeyBlock,
         readBlock: @escaping ReadBlock,
         copyBlock: @escaping CopyBlock,
         uiReadEvacuationBlock: @escaping UIReadEvacuationBlock) {
        uiReadCache = ModelReadCache(mode: .uiRead,
                                     cacheName: cacheName,
                                     keyBlock: keyBlock,
                                     readBlock: readBlock,
                                     copyBlock: copyBlock)
        readCache = ModelReadCache(mode: .read,
                                   cacheName: cacheName,
                                   keyBlock: keyBlock,
                                   readBlock: readBlock,
                                   copyBlock: copyBlock)
        self.uiReadEvacuationBlock = uiReadEvacuationBlock

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.databaseStorage.add(databaseStorageObserver: self)
        }
    }

    func getValue(for key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
        if transaction.isUIRead {
            assert(Thread.isMainThread)
        }
        let cache = (transaction.isUIRead ? uiReadCache : readCache)
        return cache.getValue(for: key, transaction: transaction)
    }

    func didRemove(value: ValueType, transaction: SDSAnyWriteTransaction) {
        // Only update readCache to reflect writes.
        readCache.didRemove(value: value, transaction: transaction)
    }

    func didInsertOrUpdate(value: ValueType, transaction: SDSAnyWriteTransaction) {
        // Only update readCache to reflect writes.
        readCache.didInsertOrUpdate(value: value, transaction: transaction)
    }

    public func databaseStorageDidUpdate(change: SDSDatabaseStorageChange) {
        AssertIsOnMainThread()

        if uiReadEvacuationBlock(change) {
            Logger.verbose("---- Evacuating \(uiReadCache.logName)")
            uiReadCache.evacuateCache()
        }
    }

    public func databaseStorageDidUpdateExternally() {
        AssertIsOnMainThread()

        uiReadCache.evacuateCache()
    }

    public func databaseStorageDidReset() {
        AssertIsOnMainThread()

        uiReadCache.evacuateCache()
    }
}

// MARK: -

@objc
public class UserProfileReadCache: NSObject {
    private let cache: ModelReadCacheWrapper<SignalServiceAddress, OWSUserProfile>

    @objc
    public override init() {
        cache = ModelReadCacheWrapper(cacheName: "UserProfile",
                                      keyBlock: {
            $0.address
        },
            readBlock: { (address, transaction) in
            return OWSUserProfile.getFor(address, transaction: transaction)
        },
            copyBlock: { model in
                // We don't need to use deepCopy() for OWSUserProfile.
                guard let modelCopy = model.copy() as? OWSUserProfile else {
                    throw OWSAssertionError("Copy failed.")
                }
                return modelCopy
        },
            uiReadEvacuationBlock: { storageChange in
                storageChange.didUpdateModel(collection: OWSUserProfile.collection())
        })
    }

    @objc
    public func getUserProfile(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
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
}

// MARK: -

@objc
public class SignalAccountReadCache: NSObject {
    private let cache: ModelReadCacheWrapper<SignalServiceAddress, SignalAccount>

    @objc
    public override init() {
        let accountFinder = AnySignalAccountFinder()
        cache = ModelReadCacheWrapper(cacheName: "SignalAccount",
                                      keyBlock: {
            $0.recipientAddress
        },
                               readBlock: { (address, transaction) in
                                return accountFinder.signalAccount(for: address, transaction: transaction)
        },
                               copyBlock: { model in
                                // We don't need to use deepCopy() for SignalAccount.
                                guard let modelCopy = model.copy() as? SignalAccount else {
                                    throw OWSAssertionError("Copy failed.")
                                }
                                return modelCopy
        },
                               uiReadEvacuationBlock: { storageChange in
                                storageChange.didUpdateModel(collection: SignalAccount.collection())
        })
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
}

// MARK: -

@objc
public class SignalRecipientReadCache: NSObject {
    private let cache: ModelReadCacheWrapper<SignalServiceAddress, SignalRecipient>

    @objc
    public override init() {
        let recipientFinder = AnySignalRecipientFinder()
        cache = ModelReadCacheWrapper(cacheName: "SignalRecipient",
                                      keyBlock: {
            $0.address
        },
                               readBlock: { (address, transaction) in
                                return recipientFinder.signalRecipient(for: address, transaction: transaction)
        },
                               copyBlock: { model in
                                // We don't need to use deepCopy() for SignalRecipient.
                                guard let modelCopy = model.copy() as? SignalRecipient else {
                                    throw OWSAssertionError("Copy failed.")
                                }
                                return modelCopy
        },
                               uiReadEvacuationBlock: { storageChange in
                                storageChange.didUpdateModel(collection: SignalRecipient.collection())
        })
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
}

// MARK: -

@objc
public class ModelReadCaches: NSObject {
    // UserProfileReadCache is only used within the profile manager.

    @objc
    public let signalAccountReadCache = SignalAccountReadCache()
    @objc
    public let signalRecipientReadCache = SignalRecipientReadCache()
}
