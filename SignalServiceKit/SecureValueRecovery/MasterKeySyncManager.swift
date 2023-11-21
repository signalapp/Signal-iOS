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
        static let hasDistributedMasterKey = "hasSyncedMasterKey"
        static let lastKeysSyncRequestMessageDateKey = "lastKeysSyncRequestMessageDateKey"
    }

    private let logger = PrefixedLogger(prefix: "MKOTSM")

    private let dateProvider: DateProvider
    private let keyValueStore: KeyValueStore
    private let svr: SecureValueRecovery
    private let syncManager: Shims.SyncManager
    private let tsAccountManager: TSAccountManager

    init(
        dateProvider: @escaping DateProvider,
        keyValueStoreFactory: KeyValueStoreFactory,
        svr: SecureValueRecovery,
        syncManager: Shims.SyncManager,
        tsAccountManager: TSAccountManager
    ) {
        self.dateProvider = dateProvider
        self.keyValueStore = keyValueStoreFactory.keyValueStore(collection: StoreConstants.collectionName)
        self.svr = svr
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager
    }

    func runStartupJobs(tx: DBWriteTransaction) {
        switch tsAccountManager.registrationState(tx: tx) {
        case .registered:
            runStartupJobsForPrimaryDevice(tx: tx)
        case .provisioned:
            runStartupJobsForLinkedDevice(tx: tx)
        case .delinked, .deregistered, .unregistered, .transferred,
                .transferringIncoming, .transferringLinkedOutgoing,
                .transferringPrimaryOutgoing,
                .reregistering, .relinking:
            logger.info("Skipping; not registered")
            return
        }
    }

    private func runStartupJobsForPrimaryDevice(tx: DBWriteTransaction) {
        logger.info("")

        guard !keyValueStore.getBool(
            StoreConstants.hasDistributedMasterKey,
            defaultValue: false,
            transaction: tx
        ) else {
            return
        }

        logger.info("Sending one-time keys sync message.")
        syncManager.sendKeysSyncMessage(tx: tx)

        self.keyValueStore.setBool(
            true,
            key: StoreConstants.hasDistributedMasterKey,
            transaction: tx
        )
    }

    private func runStartupJobsForLinkedDevice(tx: DBWriteTransaction) {
        logger.info("")

        if svr.hasMasterKey(transaction: tx) {
            // No need to sync; we have the master key.
            return
        }

        let lastRequestDate = keyValueStore.getDate(
            StoreConstants.lastKeysSyncRequestMessageDateKey,
            transaction: tx
        ) ?? .distantPast

        guard dateProvider().timeIntervalSince(lastRequestDate) >= 60 * 60 * 24 else {
            logger.info("Skipping keys sync request; too soon since last request.")
            return
        }

        logger.info("Requesting keys sync message")
        syncManager.sendKeysSyncRequestMessage(tx: tx)

        keyValueStore.setDate(
            dateProvider(),
            key: StoreConstants.lastKeysSyncRequestMessageDateKey,
            transaction: tx
        )
    }
}

// MARK: - Dependencies

extension MasterKeySyncManagerImpl {
    enum Shims {
        public typealias SyncManager = _MasterKeySyncManagerImpl_SyncManager_Shim
    }

    enum Wrappers {
        public typealias SyncManager = _MasterKeySyncManagerImpl_SyncManager_Wrapper
    }
}

// MARK: SyncManager

protocol _MasterKeySyncManagerImpl_SyncManager_Shim {
    func sendKeysSyncMessage(tx: DBWriteTransaction)
    func sendKeysSyncRequestMessage(tx: DBWriteTransaction)
}

class _MasterKeySyncManagerImpl_SyncManager_Wrapper: _MasterKeySyncManagerImpl_SyncManager_Shim {
    private let syncManager: SyncManagerProtocolSwift

    init(_ syncManager: SyncManagerProtocolSwift) {
        self.syncManager = syncManager
    }

    func sendKeysSyncMessage(tx: DBWriteTransaction) {
        syncManager.sendKeysSyncMessage(tx: SDSDB.shimOnlyBridge(tx))
    }

    func sendKeysSyncRequestMessage(tx: DBWriteTransaction) {
        syncManager.sendKeysSyncRequestMessage(transaction: SDSDB.shimOnlyBridge(tx))
    }
}
