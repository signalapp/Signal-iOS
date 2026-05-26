//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol MasterKeySyncManager {
    /// Runs startup jobs required to sync the master key to linked devices.
    ///
    /// Historically linked devices did not have the master key; now that
    /// we have started including it in the Keys SyncMessage, we have to
    /// do some work to make sure that sync message happens proactively.
    ///
    /// On a primary device, this will trigger a one-time Keys SyncMessage if
    /// we haven't already sent one.
    ///
    /// On a linked device, this will send a sync keys request if we don't have
    /// a master key available locally.
    func runStartupJobs(tx: DBWriteTransaction)
}

class MasterKeySyncManagerImpl: MasterKeySyncManager {
    private enum StoreConstants {
        static let collectionName = "MasterKeyOneTimeSyncManager"
        static let hasDistributedAEP = "hasSyncedAEP"
        static let lastKeysSyncRequestMessageDateKey = "lastKeysSyncRequestMessageDateKey"
    }

    private let logger = PrefixedLogger(prefix: "MKSM")

    private let dateProvider: DateProvider
    private let keyValueStore: KeyValueStore
    private let svr: SecureValueRecovery
    private let syncManager: SyncManagerProtocolSwift
    private let tsAccountManager: TSAccountManager

    init(
        dateProvider: @escaping DateProvider,
        svr: SecureValueRecovery,
        syncManager: SyncManagerProtocolSwift,
        tsAccountManager: TSAccountManager,
    ) {
        self.dateProvider = dateProvider
        self.keyValueStore = KeyValueStore(collection: StoreConstants.collectionName)
        self.svr = svr
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager
    }

    func runStartupJobs(tx: DBWriteTransaction) {
        guard let registeredState = try? tsAccountManager.registeredState(tx: tx) else {
            return
        }
        if registeredState.isPrimary {
            runStartupJobsForPrimaryDevice(tx: tx)
        } else {
            runStartupJobsForLinkedDevice(tx: tx)
        }
    }

    private func runStartupJobsForPrimaryDevice(tx: DBWriteTransaction) {
        let key = StoreConstants.hasDistributedAEP
        guard
            !keyValueStore.getBool(
                key,
                defaultValue: false,
                transaction: tx,
            )
        else {
            return
        }

        logger.info("Sending one-time keys sync message.")
        syncManager.sendKeysSyncMessage(tx: tx)

        self.keyValueStore.setBool(
            true,
            key: key,
            transaction: tx,
        )
    }

    private func runStartupJobsForLinkedDevice(tx: DBWriteTransaction) {
        if svr.hasMasterKey(transaction: tx) {
            // No need to sync; we have the master key.
            return
        }

        let lastRequestDate = keyValueStore.getDate(
            StoreConstants.lastKeysSyncRequestMessageDateKey,
            transaction: tx,
        ) ?? .distantPast

        guard dateProvider().timeIntervalSince(lastRequestDate) >= 60 * 60 * 24 else {
            logger.info("Skipping keys sync request; too soon since last request.")
            return
        }

        logger.info("Requesting keys sync message")
        syncManager.sendKeysSyncRequestMessage(transaction: tx)

        keyValueStore.setDate(
            dateProvider(),
            key: StoreConstants.lastKeysSyncRequestMessageDateKey,
            transaction: tx,
        )
    }
}
