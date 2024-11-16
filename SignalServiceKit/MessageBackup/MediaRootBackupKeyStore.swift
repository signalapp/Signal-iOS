//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Manages the "Media Root Backup Key" a.k.a. "MRBK" a.k.a. "Mr Burger King".
/// This is a key we generate once and use forever that is used to derive encryption keys
/// for all backed-up media.
/// The MRBK is _not_ derived from the AccountEntropyPool any of its derivatives;
/// instead we store the MRBK in the backup proto itself. This avoids needing to rotate
/// media uploads if the AEP or backup key/id ever changes (at time of writing, it never does);
/// the MRBK can be left the same and put into the new backup generated with the new backups keys.
public class MediaRootBackupKeyStore {

    public static let mediaRootBackupKeyLength: UInt = 32 /* bytes */

    private let kvStore: KeyValueStore

    public init() {
        self.kvStore = KeyValueStore(collection: "MediaRootBackupKey")
    }

    /// Get the already-generated MRBK. Returns nil if none has been set. If you require an MRBK
    /// (e.g. you are creating a backup), use ``getOrGenerateMediaRootBackupKey``.
    public func getMediaRootBackupKey(tx: DBReadTransaction) -> Data? {
        kvStore.getData(Self.keyName, transaction: tx)
    }

    /// Get the already-generated MRBK or, if one has not been generated, generate one.
    /// WARNING: this method should only be called _after_ restoring or choosing not to restore
    /// from an existing backup; calling this generates a new key and invalidates all media backups.
    public func getOrGenerateMediaRootBackupKey(tx: DBWriteTransaction) -> Data {
        if let value = getMediaRootBackupKey(tx: tx) {
            return value
        }
        let newValue = Randomness.generateRandomBytes(Self.mediaRootBackupKeyLength)
        kvStore.setData(newValue, key: Self.keyName, transaction: tx)
        return newValue
    }

    /// Set the MRBK found in a backup at restore time.
    public func setMediaRootBackupKey(
        fromRestoredBackup backupProto: BackupProto_BackupInfo,
        tx: DBWriteTransaction
    ) throws {
        guard let mrbk = backupProto.mediaRootBackupKey.nilIfEmpty else {
            // TODO: [Backups] fail if MRBK unset
            return
        }
        try setMediaRootBackupKey(mrbk, tx: tx)
    }

    /// Set the MRBK found in a provisioning message.
    public func setMediaRootBackupKey(
        fromProvisioningMessage provisioningMessage: ProvisionMessage,
        tx: DBWriteTransaction
    ) throws {
        guard let mrbk = provisioningMessage.mrbk else { return }
        try setMediaRootBackupKey(mrbk, tx: tx)
    }

    public func setMediaRootBackupKey(
        fromKeysSyncMessage syncMessage: SSKProtoSyncMessageKeys,
        tx: DBWriteTransaction
    ) throws {
        guard let mrbk = syncMessage.mediaRootBackupKey?.nilIfEmpty else {
            return
        }
        try setMediaRootBackupKey(mrbk, tx: tx)
    }

    private func setMediaRootBackupKey(
        _ mrbk: Data,
        tx: DBWriteTransaction
    ) throws {
        guard mrbk.byteLength == Self.mediaRootBackupKeyLength else {
            throw OWSAssertionError("Invalid MRBK length!")
        }
        kvStore.setData(mrbk, key: Self.keyName, transaction: tx)
    }

    private static let keyName = "mrbk"
}
