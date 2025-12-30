//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol AccountEntropyPoolManager {
    func generateIfMissing() async

    func setAccountEntropyPool(
        newAccountEntropyPool: AccountEntropyPool,
        disablePIN: Bool,
        tx: DBWriteTransaction,
    )
}

// MARK: -

class AccountEntropyPoolManagerImpl: AccountEntropyPoolManager {
    private let accountAttributesUpdater: AccountAttributesUpdater
    private let accountKeyStore: AccountKeyStore
    private let appContext: AppContext
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let logger: PrefixedLogger
    private let storageServiceManager: StorageServiceManager
    private let svr: SecureValueRecovery
    private let syncManager: SyncManagerProtocol
    private let tsAccountManager: TSAccountManager

    init(
        accountAttributesUpdater: AccountAttributesUpdater,
        accountKeyStore: AccountKeyStore,
        appContext: AppContext,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        storageServiceManager: StorageServiceManager,
        svr: SecureValueRecovery,
        syncManager: SyncManagerProtocol,
        tsAccountManager: TSAccountManager,
    ) {
        self.accountAttributesUpdater = accountAttributesUpdater
        self.accountKeyStore = accountKeyStore
        self.appContext = appContext
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.storageServiceManager = storageServiceManager
        self.svr = svr
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    func generateIfMissing() async {
        await db.awaitableWrite { tx in
            _generateIfMissing(tx: tx)
        }
    }

    func _generateIfMissing(tx: DBWriteTransaction) {
        guard
            appContext.isMainApp,
            tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice
        else {
            owsFailDebug("Attempting to generate AEP, but not registered primary && main app!")
            return
        }

        guard accountKeyStore.getAccountEntropyPool(tx: tx) == nil else {
            return
        }

        logger.info("Generating new AEP for registered primary missing one.")

        setAccountEntropyPool(
            newAccountEntropyPool: AccountEntropyPool(),
            disablePIN: false,
            tx: tx,
        )
    }

    // MARK: -

    func setAccountEntropyPool(
        newAccountEntropyPool: AccountEntropyPool,
        disablePIN: Bool,
        tx: DBWriteTransaction,
    ) {
        logger.warn("Setting new AEP!")

        // Eventually, we may support rotating the AEP without rotating related-
        // but-non-derived keys such as the MRBK and the Storage Service
        // recordIkm. For now, though, "rotating the AEP" should also rotate all
        // our keys.
        let rotateRelatedNonDerivedKeys = true

        switch backupSettingsStore.backupPlan(tx: tx) {
        case .disabled:
            break
        case .disabling, .free, .paid, .paidExpiringSoon, .paidAsTester:
            owsFail("Attempting to set AEP while Backups are not disabled.")
        }

        let isRegisteredPrimaryDevice = tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice

        if !isRegisteredPrimaryDevice {
            logger.warn("Setting AEP, but not a registered primary device.")
        }

        if rotateRelatedNonDerivedKeys {
            accountKeyStore.setMediaRootBackupKey(
                MediaRootBackupKey(backupKey: .generateRandom()),
                tx: tx,
            )
        }

        accountKeyStore.setAccountEntropyPool(newAccountEntropyPool, tx: tx)

        svr.handleMasterKeyUpdated(
            newMasterKey: newAccountEntropyPool.getMasterKey(),
            disablePIN: disablePIN,
            tx: tx,
        )

        // Skip the steps below if we're not yet registered. This check matters
        // because one of our big callers is registration itself.
        guard isRegisteredPrimaryDevice else {
            return
        }

        // Schedule an account attributes update, since we need to update the
        // reglock and reg recovery password downstream of the master key
        // changing.
        accountAttributesUpdater.scheduleAccountAttributesUpdate(
            authedAccount: .implicit(),
            tx: tx,
        )

        // Proactively rotate our Storage Service manifest, since the master key
        // has changed and the Storage Service manifest key is derived from the
        // master key.
        //
        // It's okay if this doesn't succeed; we'll get decryption errors the
        // next time we do a Storage Service operation, from which we'll recover
        // by creating a new manifest anyway.
        Task {
            try? await storageServiceManager.rotateManifest(
                mode: rotateRelatedNonDerivedKeys ? .alsoRotatingRecords : .preservingRecordsIfPossible,
                authedDevice: .implicit,
            )

            // Sync our new keys with linked devices, but wait until the storage
            // service restore is done. Otherwise, linked devices might get the
            // new keys and try and restore Storage Service before we've updated
            // it, in which case they'd ask us for the keys again.
            //
            // Regardless, things should eventually recover regardless of what
            // succeeds and in what order.
            syncManager.sendKeysSyncMessage()
        }
    }
}

// MARK: -

#if TESTABLE_BUILD

class MockAccountEntropyPoolManager: AccountEntropyPoolManager {
    func generateIfMissing() async {}

    var setAccountEntropyPoolMock: (() -> Void)?
    func setAccountEntropyPool(newAccountEntropyPool: AccountEntropyPool, disablePIN: Bool, tx: DBWriteTransaction) {
        setAccountEntropyPoolMock?()
    }
}

#endif
