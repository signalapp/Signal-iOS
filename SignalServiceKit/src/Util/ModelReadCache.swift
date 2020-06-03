//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

private class ModelReadCache<KeyType: AnyObject & Hashable, ValueType: AnyObject> {

    // MARK: - Dependencies

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    // MARK: -

    // This property should only be accessed on serialQueue.
    //
    // TODO: We could tune the size of this cache.
    //       NSCache's default behavior is opaque.
    //       We're currently only using this to cache
    //       small models, but that could change.
    private let nscache = NSCache<KeyType, ValueType>()

    typealias ReadBlock = (KeyType, SDSAnyReadTransaction) -> ValueType?
    private let readBlock: ReadBlock

    typealias KeyBlock = (ValueType) -> KeyType
    private let keyBlock: KeyBlock

    init(keyBlock: @escaping KeyBlock, readBlock: @escaping ReadBlock) {
        self.keyBlock = keyBlock
        self.readBlock = readBlock

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didReceiveCrossProcessNotification),
                                               name: SDSDatabaseStorage.didReceiveCrossProcessNotification,
                                               object: nil)
    }

    @objc
    func didReceiveCrossProcessNotification(_ notification: Notification) {
        AssertIsOnMainThread()

        DispatchQueue.global().async {
            self.performSync {
                self.nscache.removeAllObjects()
            }
        }
    }

    // This method should only be called within performSync().
    private func readValue(for key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
        if let value = readBlock(key, transaction) {
            if !isExcluded(key: key),
                canUseCache(transaction: transaction) {
                // Update cache.
                nscache.setObject(value, forKey: key)
            }
            return value
        }
        return nil
    }

    // This method should only be called within performSync().
    private func cachedValue(for key: KeyType) -> ValueType? {
        guard !isExcluded(key: key) else {
            // Read excluded.
            return nil
        }
        return nscache.object(forKey: key)
    }

    func getValue(for key: KeyType, transaction: SDSAnyReadTransaction) -> ValueType? {
        return performSync {
            if let cachedValue = self.cachedValue(for: key) {
                return cachedValue
            }
            return self.readValue(for: key, transaction: transaction)
        }
    }

    func getValueWithSneakyTransaction(for key: KeyType) -> ValueType? {
        // We avoid opening a read transaction if possible.
        let cachedValue = performSync {
            return self.cachedValue(for: key)
        }
        if let value = cachedValue {
            return value
        }

        // We avoid opening a transaction within performSync() to avoid deadlock.
        return self.databaseStorage.read { transaction in
            return self.performSync {
                return self.readValue(for: key, transaction: transaction)
            }
        }
    }

    func didRemove(value: ValueType, transaction: SDSAnyWriteTransaction) {
        let key = keyBlock(value)
        updateCacheForWrite(key: key, value: nil, transaction: transaction)
    }

    func didInsertOrUpdate(value: ValueType, transaction: SDSAnyWriteTransaction) {
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
                nscache.setObject(value, forKey: key)
            } else {
                nscache.removeObject(forKey: key)
            }
            // Protect the cache from being corrupted by reads
            // by excluding the key until the write transaction
            // commits.
            addExclusion(for: key)
        }
        // Once the write transaction has completed, it is safe
        // to use the cache for this key again.
        transaction.addSyncCompletion {
            _ = self.performSync {
                self.removeExclusion(for: key)
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
        return excludedKeyMap[key] != nil
    }

    // This method should only be called within performSync().
    private func addExclusion(for key: KeyType) {
        if let value = excludedKeyMap[key] {
            excludedKeyMap[key] = value + 1
        } else {
            excludedKeyMap[key] = 1
        }
    }

    // This method should only be called within performSync().
    private func removeExclusion(for key: KeyType) {
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
        objc_sync_enter(self)
        let value = block()
        objc_sync_exit(self)
        return value
    }
}

// MARK: -

@objc
public class UserProfileReadCache: NSObject {
    private let cache: ModelReadCache<SignalServiceAddress, OWSUserProfile>

    @objc
    public override init() {
        cache = ModelReadCache(keyBlock: {
            $0.address
        },
            readBlock: { (address, transaction) in
            return OWSUserProfile.getFor(address, transaction: transaction)
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
    private let cache: ModelReadCache<SignalServiceAddress, SignalAccount>

    @objc
    public override init() {
        let accountFinder = AnySignalAccountFinder()
        cache = ModelReadCache(keyBlock: {
            $0.recipientAddress
        },
            readBlock: { (address, transaction) in
            return accountFinder.signalAccount(for: address, transaction: transaction)
        })
    }

    @objc
    public func getSignalAccount(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        return cache.getValue(for: address, transaction: transaction)
    }

    @objc
    public func getSignalAccountWithSneakyTransaction(address: SignalServiceAddress) -> SignalAccount? {
        return cache.getValueWithSneakyTransaction(for: address)
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
