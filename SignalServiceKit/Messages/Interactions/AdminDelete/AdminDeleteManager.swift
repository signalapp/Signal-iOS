//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
import GRDB

public struct RemoteDeleteAuthor: Equatable {
    public enum AuthorType: Equatable {
        case admin(aci: Aci)
        case regular
    }

    public let displayName: String
    public let authorType: AuthorType
}

public class AdminDeleteManager {
    let recipientDatabaseTable: RecipientDatabaseTable
    let tsAccountManager: TSAccountManager

    private let logger = PrefixedLogger(prefix: "AdminDelete")

    init(
        recipientDatabaseTable: RecipientDatabaseTable,
        tsAccountManager: TSAccountManager,
    ) {
        self.recipientDatabaseTable = recipientDatabaseTable
        self.tsAccountManager = tsAccountManager
    }

    private func insertAdminDelete(
        groupThread: TSGroupThread,
        interactionId: Int64,
        deleteAuthor: Aci,
        tx: DBWriteTransaction,
    ) throws(TSMessage.RemoteDeleteError) {
        guard
            let groupModel = groupThread.groupModel as? TSGroupModelV2,
            groupModel.membership.isFullMemberAndAdministrator(deleteAuthor)
        else {
            logger.error("Failed to process admin delete for non-admin")
            throw .invalidDelete
        }

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
}
