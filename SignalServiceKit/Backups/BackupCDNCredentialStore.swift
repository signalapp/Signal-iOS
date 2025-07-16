//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

struct BackupCDNCredentialStore {
    private enum Constants {
        static let cdnMetadataLifetime: TimeInterval = BackupCDNReadCredential.lifetime
    }

    private let kvStore: KeyValueStore

    init() {
        self.kvStore = KeyValueStore(collection: "BackupCDNCredentialStore")
    }

    // MARK: -

    func wipe(tx: DBWriteTransaction) {
        kvStore.removeAll(transaction: tx)
    }

    // MARK: -

    private static func backupCDNAuthCredentialKey(
        cdnNumber: Int32,
        authType: BackupAuthCredentialType,
    ) -> String {
        return "BackupCDN\(cdnNumber):\(authType.rawValue)"
    }

    func backupCDNReadCredential(
        cdnNumber: Int32,
        authType: BackupAuthCredentialType,
        now: Date,
        tx: DBReadTransaction,
    ) -> BackupCDNReadCredential? {
        do {
            let cachedCredential: BackupCDNReadCredential? = try kvStore.getCodableValue(
                forKey: Self.backupCDNAuthCredentialKey(cdnNumber: cdnNumber, authType: authType),
                transaction: tx
            )

            if
                let cachedCredential,
                !cachedCredential.isExpired(now: now)
            {
                return cachedCredential
            }
        } catch {
            Logger.warn("Failed to deserialize BackupCDNReadCredential!")
        }

        return nil
    }

    func setBackupCDNReadCredential(
        _ backupCDNReadCredential: BackupCDNReadCredential,
        cdnNumber: Int32,
        authType: BackupAuthCredentialType,
        currentBackupPlan: BackupPlan,
        tx: DBWriteTransaction,
    ) {
        switch currentBackupPlan {
        case .disabled:
            owsFailDebug("Attempting to set BackupCDNReadCredential while Backups is disabled!")
            return
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        do {
            try kvStore.setCodable(
                backupCDNReadCredential,
                key: Self.backupCDNAuthCredentialKey(cdnNumber: cdnNumber, authType: authType),
                transaction: tx
            )
        } catch {
            Logger.warn("Failed to serialize BackupCDNReadCredential! \(error)")
        }
    }

    // MARK: -

    private static func backupCDNMetadataKeys(authType: BackupAuthCredentialType) -> (
        metadata: String,
        metadataSavedDate: String
    ) {
        return (
            "BackupCDNMetadata:\(authType.rawValue)",
            "BackupCDNMetadataSavedDate:\(authType.rawValue)",
        )
    }

    func backupCDNMetadata(
        authType: BackupAuthCredentialType,
        now: Date,
        tx: DBReadTransaction,
    ) -> BackupCDNMetadata? {
        let (metadataKey, metadataSavedDateKey) = Self.backupCDNMetadataKeys(authType: authType)

        if
            let metadataSavedDate = kvStore.getDate(metadataSavedDateKey, transaction: tx),
            now > metadataSavedDate.addingTimeInterval(Constants.cdnMetadataLifetime)
        {
            // It's been long enough that we should skip the cached value.
            return nil
        }

        do {
            if let metadata: BackupCDNMetadata = try kvStore.getCodableValue(forKey: metadataKey, transaction: tx) {
                return metadata
            }
        } catch {
            Logger.warn("Failed to deserialize BackupCDNMetadata! \(error)")
        }

        return nil
    }

    func setBackupCDNMetadata(
        _ backupCDNMetadata: BackupCDNMetadata,
        authType: BackupAuthCredentialType,
        now: Date,
        currentBackupPlan: BackupPlan,
        tx: DBWriteTransaction,
    ) {
        switch currentBackupPlan {
        case .disabled:
            owsFailDebug("Attempting to set BackupCDNMetadata while Backups is disabled!")
            return
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        let (metadataKey, metadataSavedDateKey) = Self.backupCDNMetadataKeys(authType: authType)

        do {
            try kvStore.setCodable(backupCDNMetadata, key: metadataKey, transaction: tx)
            kvStore.setDate(now, key: metadataSavedDateKey, transaction: tx)
        } catch {
            Logger.warn("Failed to serialize BackupCDNMetadata! \(error)")
        }
    }
}
