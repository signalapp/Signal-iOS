//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
import GRDB

public enum RemoteDeleteAuthor: Equatable {
    case admin(aci: Aci, displayName: String)
    case regular(displayName: String)
    case localUser
}

public class AdminDeleteManager {
    public struct DeleteType: OptionSet {
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public let rawValue: Int

        public static let admin = DeleteType(rawValue: 1 << 1)
        public static let regular = DeleteType(rawValue: 1 << 2)
    }

    private let recipientDatabaseTable: RecipientDatabaseTable
    private let tsAccountManager: TSAccountManager
    private let kvStore: NewKeyValueStore
    private let storageServiceManager: StorageServiceManager

    private static let kvStoreAdminDeleteEducationReadKey = "adminDeleteEducationRead"

    private let logger = PrefixedLogger(prefix: "AdminDelete")

    init(
        recipientDatabaseTable: RecipientDatabaseTable,
        tsAccountManager: TSAccountManager,
        storageServiceManager: StorageServiceManager,
    ) {
        self.recipientDatabaseTable = recipientDatabaseTable
        self.tsAccountManager = tsAccountManager
        self.kvStore = NewKeyValueStore(collection: "AdminDeleteManager")
        self.storageServiceManager = storageServiceManager
    }

    private func insertAdminDelete(
        groupThread: TSGroupThread,
        interactionId: Int64,
        deleteAuthor: Aci,
        tx: DBWriteTransaction,
    ) throws(TSMessage.RemoteDeleteError) {
        guard
            let deleteAuthorId = recipientDatabaseTable.fetchRecipient(
                serviceId: deleteAuthor,
                transaction: tx,
            )?.id
        else {
            logger.error("Failed to process admin delete for missing signal recipient")
            throw .invalidDelete
        }

        failIfThrows {
            var adminDeleteRecord = AdminDeleteRecord(
                interactionId: interactionId,
                deleteAuthorId: deleteAuthorId,
            )
            try adminDeleteRecord.insert(tx.database)
        }
    }

    public func tryToAdminDeleteMessage(
        originalMessageAuthorAci: Aci,
        deleteAuthorAci: Aci,
        sentAtTimestamp: UInt64,
        groupThread: TSGroupThread,
        threadUniqueId: String?,
        serverTimestamp: UInt64,
        transaction: DBWriteTransaction,
    ) throws(TSMessage.RemoteDeleteError) {
        guard SDS.fitsInInt64(sentAtTimestamp) else {
            owsFailDebug("Unable to delete a message with invalid sentAtTimestamp: \(sentAtTimestamp)")
            throw .invalidDelete
        }

        guard
            let groupModel = groupThread.groupModel as? TSGroupModelV2,
            groupModel.membership.isFullMemberAndAdministrator(deleteAuthorAci)
        else {
            logger.error("Failed to process admin delete for non-admin")
            throw .invalidDelete
        }

        if
            let threadUniqueId, let messageToDelete = InteractionFinder.findMessage(
                withTimestamp: sentAtTimestamp,
                threadId: threadUniqueId,
                author: SignalServiceAddress(originalMessageAuthorAci),
                transaction: transaction,
            )
        {
            let allowDeleteTimeframe = RemoteConfig.current.adminDeleteMaxAgeInSeconds + .day
            let latestMessage = try TSMessage.remotelyDeleteMessage(
                messageToDelete,
                deleteAuthorAci: deleteAuthorAci,
                allowedDeleteTimeframeSeconds: allowDeleteTimeframe,
                serverTimestamp: serverTimestamp,
                transaction: transaction,
            )

            return try insertAdminDelete(
                groupThread: groupThread,
                interactionId: latestMessage.sqliteRowId!,
                deleteAuthor: deleteAuthorAci,
                tx: transaction,
            )
        } else {
            throw .deletedMessageMissing
        }
    }

    public func adminDeleteAuthor(interactionId: Int64, tx: DBReadTransaction) -> Aci? {
        guard BuildFlags.AdminDelete.receive else {
            return nil
        }

        return failIfThrows {
            guard
                let adminDeleteRecord = try AdminDeleteRecord
                    .filter(AdminDeleteRecord.Columns.interactionId == interactionId)
                    .fetchOne(tx.database)
            else {
                return nil
            }

            let signalRecipient = recipientDatabaseTable.fetchRecipient(
                rowId: adminDeleteRecord.deleteAuthorId,
                tx: tx,
            )
            return signalRecipient?.aci
        }
    }

    public func canAdminDeleteMessage(
        message: TSMessage,
        thread: TSThread,
        tx: DBReadTransaction,
    ) -> Bool {
        guard BuildFlags.AdminDelete.send else {
            return false
        }

        guard let groupThread = thread as? TSGroupThread else {
            return false
        }

        guard let localAci = tsAccountManager.localIdentifiers(tx: tx)?.aci else {
            return false
        }

        guard groupThread.groupModel.groupMembership.isFullMemberAndAdministrator(localAci) else {
            return false
        }

        guard message.canBeRemotelyDeletedByAdmin else {
            return false
        }

        return true
    }

    public func insertAdminDeleteForSignalRecipient(
        _ recipientId: SignalRecipient.RowId,
        interactionId: Int64,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            var adminDeleteRecord = AdminDeleteRecord(
                interactionId: interactionId,
                deleteAuthorId: recipientId,
            )
            try adminDeleteRecord.insert(tx.database)
        }
    }

    public func adminDeleteEducationReadStatus(tx: DBReadTransaction) -> Bool {
        return kvStore.fetchValue(Bool.self, forKey: Self.kvStoreAdminDeleteEducationReadKey, tx: tx) ?? false
    }

    public func setAdminDeleteEducationRead(tx: DBWriteTransaction, updateStorageService: Bool) {
        guard !adminDeleteEducationReadStatus(tx: tx) else {
            return
        }
        kvStore.writeValue(true, forKey: Self.kvStoreAdminDeleteEducationReadKey, tx: tx)
        if updateStorageService {
            storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }
}
