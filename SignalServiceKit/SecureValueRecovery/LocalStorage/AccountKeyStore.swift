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
    private let mrbkKvStore: NewKeyValueStore
    private let masterKeyKvStore: NewKeyValueStore

    private let backupSettingsStore: BackupSettingsStore

    public init(
        backupSettingsStore: BackupSettingsStore,
    ) {
        // Collection name must not be changed; matches that historically kept in KeyBackupServiceImpl.
        self.masterKeyKvStore = NewKeyValueStore(collection: "kOWSKeyBackupService_Keys")
        self.mrbkKvStore = NewKeyValueStore(collection: "MediaRootBackupKey")
        self.aepKvStore = KeyValueStore(collection: "AccountEntropyPool")
        self.backupSettingsStore = backupSettingsStore
    }

    // MARK: -

    public func getMasterKey(tx: DBReadTransaction) -> MasterKey? {
        if let aepDerivedKey = getAccountEntropyPool(tx: tx)?.getMasterKey() {
            return aepDerivedKey
        }
        // No AEP? Try fetching from the legacy location
        do {
            return try masterKeyKvStore.fetchValue(Data.self, forKey: Keys.masterKey, tx: tx).map { try MasterKey(data: $0) }
        } catch {
            owsFailDebug("Failed to instantiate MasterKey")
        }
        return nil
    }

    public func setMasterKey(_ masterKey: MasterKey?, tx: DBWriteTransaction) {
        masterKeyKvStore.writeValue(masterKey?.rawData, forKey: Keys.masterKey, tx: tx)
    }

    // MARK: -

    /// Manages the "Media Root Backup Key" a.k.a. "MRBK" a.k.a. "Mr Burger King".
    /// This is a key we generate once and use forever that is used to derive encryption keys
    /// for all backed-up media.
    /// The MRBK is _not_ derived from the AccountEntropyPool any of its derivatives;
    /// instead we store the MRBK in the backup proto itself. This avoids needing to rotate
    /// media uploads if the AEP ever changes; the MRBK can be left the same and
    /// put into the new backup generated with the new backups keys.

    /// Get the already-generated MRBK. Returns nil if none has been set. If you require an MRBK
    /// (e.g. you are creating a backup), use ``getOrGenerateMediaRootBackupKey``.
    public func getMediaRootBackupKey(tx: DBReadTransaction) -> MediaRootBackupKey? {
        guard let data = mrbkKvStore.fetchValue(Data.self, forKey: Keys.mrbkKeyName, tx: tx) else {
            return nil
        }
        do {
            return try MediaRootBackupKey(backupKey: BackupKey(contents: data))
        } catch {
            owsFailDebug("Failed to instantiate MediaRootBackupKey")
        }
        return nil
    }

    /// Get the already-generated MRBK or, if one has not been generated, generate one.
    /// WARNING: this method should only be called _after_ restoring or choosing not to restore
    /// from an existing backup; calling this generates a new key and invalidates all media backups.
    public func getOrGenerateMediaRootBackupKey(tx: DBWriteTransaction) -> MediaRootBackupKey {
        if let value = getMediaRootBackupKey(tx: tx) {
            return value
        }
        let newValue = MediaRootBackupKey(backupKey: .generateRandom())
        mrbkKvStore.writeValue(newValue.serialize(), forKey: Keys.mrbkKeyName, tx: tx)
        return newValue
    }

    public func wipeMediaRootBackupKeyFromFailedProvisioning(tx: DBWriteTransaction) {
        mrbkKvStore.removeValue(forKey: Keys.mrbkKeyName, tx: tx)
    }

    public func setMediaRootBackupKey(_ mrbk: MediaRootBackupKey, tx: DBWriteTransaction) {
        mrbkKvStore.writeValue(mrbk.serialize(), forKey: Keys.mrbkKeyName, tx: tx)
    }

    // MARK: -

    public func getMessageRootBackupKey(
        aci: Aci,
        tx: DBReadTransaction,
    ) throws -> MessageRootBackupKey? {
        guard let aep = getAccountEntropyPool(tx: tx) else { return nil }
        return try MessageRootBackupKey(accountEntropyPool: aep, aci: aci)
    }

    // MARK: -

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

    /// Persist the given `AccountEntropyPool`, without side effects.
    ///
    /// - Warning
    /// Rotating the `AccountEntropyPool` has external side-effects. Callers of
    /// this method should be careful that those side-effects have been managed,
    /// either by the caller or something upstream of the caller.
    ///
    /// Callers who are unsure should refer to ``AccountEntropyPoolManager``.
    public func setAccountEntropyPool(_ accountEntropyPool: AccountEntropyPool, tx: DBWriteTransaction) {
        // Clear the old master key when setting the accountEntropyPool
        masterKeyKvStore.removeValue(forKey: Keys.masterKey, tx: tx)

        // Setting the AEP means we need to set our Backup-ID again.
        backupSettingsStore.setHaveSetBackupID(haveSetBackupID: false, tx: tx)

        aepKvStore.setString(accountEntropyPool.rawString, key: Keys.aepKeyName, transaction: tx)
    }
}
