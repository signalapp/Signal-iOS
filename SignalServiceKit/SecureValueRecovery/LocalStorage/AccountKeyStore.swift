//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class AccountKeyStore {
    private enum Keys {
        static let masterKey = "masterKey"
        static let aepKeyName = "aep"
        static let mrbkKeyName = "mrbk"
    }

    public enum Constants {
        static let mediaRootBackupKeyLength: UInt = 32 /* bytes */
    }

    private let aepKvStore: KeyValueStore
    private let mrbkKvStore: KeyValueStore
    private let masterKeyKvStore: KeyValueStore

    private let masterKeyGenerator: (() -> MasterKey)
    private let accountEntropyPoolGenerator: (() -> AccountEntropyPool)

    public init(
        masterKeyGenerator: (() -> MasterKey)? = nil,
        accountEntropyPoolGenerator: (() -> AccountEntropyPool)? = nil
    ) {
        self.masterKeyGenerator = masterKeyGenerator ?? { .init() }
        self.accountEntropyPoolGenerator = accountEntropyPoolGenerator ?? { .init() }

        // Collection name must not be changed; matches that historically kept in KeyBackupServiceImpl.
        self.masterKeyKvStore = KeyValueStore(collection: "kOWSKeyBackupService_Keys")
        self.mrbkKvStore = KeyValueStore(collection: "MediaRootBackupKey")
        self.aepKvStore = KeyValueStore(collection: "AccountEntropyPool")
    }

    public func getMasterKey(tx: DBReadTransaction) -> MasterKey? {
        if let aepDerivedKey = getAccountEntropyPool(tx: tx)?.getMasterKey() {
            return aepDerivedKey
        }
        // No AEP? Try fetching from the legacy location
        do {
            return try masterKeyKvStore.getData(Keys.masterKey, transaction: tx).map { try MasterKey(data: $0) }
        } catch {
            owsFailDebug("Failed to instantiate MasterKey")
        }
        return nil
    }

    public func getOrGenerateMasterKey(tx: DBReadTransaction) -> MasterKey {
        return getMasterKey(tx: tx) ?? masterKeyGenerator()
    }

    public func rotateMasterKey(tx: DBWriteTransaction) -> (old: MasterKey?, new: MasterKey) {
        let oldValue = getMasterKey(tx: tx)
        let newValue = masterKeyGenerator()
        setMasterKey(newValue, tx: tx)
        return (oldValue, newValue)
    }

    public func setMasterKey(_ masterKey: MasterKey?, tx: DBWriteTransaction) {
        masterKeyKvStore.setData(masterKey?.rawData, key: Keys.masterKey, transaction: tx)
    }

    /// Manages the "Media Root Backup Key" a.k.a. "MRBK" a.k.a. "Mr Burger King".
    /// This is a key we generate once and use forever that is used to derive encryption keys
    /// for all backed-up media.
    /// The MRBK is _not_ derived from the AccountEntropyPool any of its derivatives;
    /// instead we store the MRBK in the backup proto itself. This avoids needing to rotate
    /// media uploads if the AEP or backup key/id ever changes (at time of writing, it never does);
    /// the MRBK can be left the same and put into the new backup generated with the new backups keys.

    /// Get the already-generated MRBK. Returns nil if none has been set. If you require an MRBK
    /// (e.g. you are creating a backup), use ``getOrGenerateMediaRootBackupKey``.
    public func getMediaRootBackupKey(tx: DBReadTransaction) -> BackupKey? {
        guard let data = mrbkKvStore.getData(Keys.mrbkKeyName, transaction: tx) else {
            return nil
        }
        do {
            return try BackupKey(contents: Array(data))
        } catch {
            owsFailDebug("Failed to instantiate MediaRootBackupKey")
        }
        return nil
    }

    /// Get the already-generated MRBK or, if one has not been generated, generate one.
    /// WARNING: this method should only be called _after_ restoring or choosing not to restore
    /// from an existing backup; calling this generates a new key and invalidates all media backups.
    public func getOrGenerateMediaRootBackupKey(tx: DBWriteTransaction) -> BackupKey {
        if let value = getMediaRootBackupKey(tx: tx) {
            return value
        }
        let newValue = LibSignalClient.BackupKey.generateRandom()
        mrbkKvStore.setData(newValue.serialize().asData, key: Keys.mrbkKeyName, transaction: tx)
        return newValue
    }

    public func wipeMediaRootBackupKeyFromFailedProvisioning(tx: DBWriteTransaction) {
        mrbkKvStore.removeValue(forKey: Keys.mrbkKeyName, transaction: tx)
    }

    public func setMediaRootBackupKey(_ mrbk: BackupKey, tx: DBWriteTransaction) {
        mrbkKvStore.setData(mrbk.serialize().asData, key: Keys.mrbkKeyName, transaction: tx)
    }

    public func getAccountEntropyPool(tx: DBReadTransaction) -> SignalServiceKit.AccountEntropyPool? {
        guard let accountEntropyPool = aepKvStore.getString(Keys.aepKeyName, transaction: tx) else {
            return nil
        }
        do {
            return try AccountEntropyPool(key: accountEntropyPool)
        } catch {
            owsFailDebug("Failed to instantiate AccountEntropyPool")
        }
        return nil
    }

    public func getOrGenerateAccountEntropyPool(tx: DBWriteTransaction) -> AccountEntropyPool {
        return getAccountEntropyPool(tx: tx) ?? accountEntropyPoolGenerator()
    }

    public func setAccountEntropyPool(_ accountEntropyPool: AccountEntropyPool?, tx: DBWriteTransaction) {
        // Clear the old master key when setting the accountEntropyPool
        masterKeyKvStore.removeValue(forKey: Keys.masterKey, transaction: tx)
        if let accountEntropyPool {
            aepKvStore.setString(accountEntropyPool.rawData, key: Keys.aepKeyName, transaction: tx)
        } else {
            aepKvStore.removeValue(forKey: Keys.aepKeyName, transaction: tx)
        }
    }

    public func rotateAccountEntropyPool(tx: DBWriteTransaction) -> (old: AccountEntropyPool?, new: AccountEntropyPool) {
        let oldValue = getAccountEntropyPool(tx: tx)
        let newValue = accountEntropyPoolGenerator()
        setAccountEntropyPool(newValue, tx: tx)
        return (oldValue, newValue)
    }

    public func getMessageRootBackupKey(tx: DBReadTransaction) -> BackupKey? {
        return getAccountEntropyPool(tx: tx)?.getBackupKey()
    }
}
