//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct BackupCDNCredentialStore {
    private enum Constants {
        static let cdnMetadataLifetime: TimeInterval = BackupCDNReadCredential.lifetime
    }

    private let kvStore: NewKeyValueStore

    public init() {
        self.kvStore = NewKeyValueStore(collection: "BackupCDNCredentialStore")
    }

    // MARK: -

    public func wipe(tx: DBWriteTransaction) {
        kvStore.removeAll(tx: tx)
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
        let cachedCredential: BackupCDNReadCredential?
        do {
            cachedCredential = try kvStore.fetchJSONAsValue(
                BackupCDNReadCredential.self,
                forKey: Self.backupCDNAuthCredentialKey(cdnNumber: cdnNumber, authType: authType),
                tx: tx,
            )
        } catch {
            Logger.warn("Failed to deserialize BackupCDNReadCredential!")
            return nil
        }
        guard let cachedCredential, !cachedCredential.isExpired(now: now) else {
            return nil
        }
        return cachedCredential
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
            // This can happen during registration when fetching backup info to download the backup
            return
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        kvStore.writeValueAsJSON(
            backupCDNReadCredential,
            forKey: Self.backupCDNAuthCredentialKey(cdnNumber: cdnNumber, authType: authType),
            tx: tx,
        )
    }

    // MARK: -

    private static func backupCDNMetadataKeys(authType: BackupAuthCredentialType) -> (
        metadata: String,
        metadataSavedDate: String,
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
            let metadataSavedDate = kvStore.fetchValue(Date.self, forKey: metadataSavedDateKey, tx: tx),
            now > metadataSavedDate.addingTimeInterval(Constants.cdnMetadataLifetime)
        {
            // It's been long enough that we should skip the cached value.
            return nil
        }

        do {
            return try kvStore.fetchJSONAsValue(BackupCDNMetadata.self, forKey: metadataKey, tx: tx)
        } catch {
            Logger.warn("Failed to deserialize BackupCDNMetadata! \(error)")
            return nil
        }
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
            // This can happen during registration when fetching backup info to download the backup
            return
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        let (metadataKey, metadataSavedDateKey) = Self.backupCDNMetadataKeys(authType: authType)

        kvStore.writeValueAsJSON(backupCDNMetadata, forKey: metadataKey, tx: tx)
        kvStore.writeValue(now, forKey: metadataSavedDateKey, tx: tx)
    }
}
