//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit

struct AvatarDefaultColorStorageServiceMigrator {
    private enum StoreKeys {
        static let hasEnqueuedMigrationKey = "hasEnqueuedMigration"
    }

    private let db: any DB
    private let kvStore: KeyValueStore
    private let logger: PrefixedLogger
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let storageServiceManager: StorageServiceManager
    private let threadStore: ThreadStore

    init(
        db: any DB,
        recipientDatabaseTable: RecipientDatabaseTable,
        storageServiceManager: StorageServiceManager,
        threadStore: ThreadStore,
    ) {
        self.db = db
        self.kvStore = KeyValueStore(collection: "AvatarDefaultColorStorageServiceMigrator")
        self.logger = PrefixedLogger(prefix: "ADCSSMigrator")
        self.recipientDatabaseTable = recipientDatabaseTable
        self.storageServiceManager = storageServiceManager
        self.threadStore = threadStore
    }

    func performMigrationIfNecessary() async throws {
        try await db.awaitableWrite { tx in
            if kvStore.hasValue(StoreKeys.hasEnqueuedMigrationKey, transaction: tx) {
                return
            }

            logger.info("Scheduling migration.")

            var recipientUniqueIds = [RecipientUniqueId]()
            recipientDatabaseTable.enumerateAll(tx: tx) { recipient in
                recipientUniqueIds.append(recipient.uniqueId)
            }

            var groupV2MasterKeys = [GroupMasterKey]()
            try threadStore.enumerateGroupThreads(tx: tx) { groupThread in
                guard
                    let groupModelV2 = groupThread.groupModel as? TSGroupModelV2,
                    let groupMasterKey = try? groupModelV2.masterKey()
                else {
                    return true
                }

                groupV2MasterKeys.append(groupMasterKey)
                return true
            }

            storageServiceManager.recordPendingLocalAccountUpdates()
            storageServiceManager.recordPendingUpdates(updatedRecipientUniqueIds: recipientUniqueIds)
            storageServiceManager.recordPendingUpdates(updatedGroupV2MasterKeys: groupV2MasterKeys)

            kvStore.setBool(true, key: StoreKeys.hasEnqueuedMigrationKey, transaction: tx)
        }
    }
}
