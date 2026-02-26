//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
import GRDB

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

    public enum AdminDeleteProcessingResult: Error {
        case deletedMessageMissing
        case invalidDelete
        case success
    }

    private func insertAdminDelete(
        groupThread: TSGroupThread,
        interactionId: Int64,
        deleteAuthor: Aci,
        tx: DBWriteTransaction,
    ) -> AdminDeleteProcessingResult {
        guard
            let groupModel = groupThread.groupModel as? TSGroupModelV2,
            groupModel.membership.isFullMemberAndAdministrator(deleteAuthor)
        else {
            logger.error("Failed to process admin delete for non-admin")
            return .invalidDelete
        }

        guard
            let deleteAuthorId = recipientDatabaseTable.fetchRecipient(
                serviceId: deleteAuthor,
                transaction: tx,
            )?.id
        else {
            logger.error("Failed to process admin delete for missing signal recipient")
            return .invalidDelete
        }

        failIfThrows {
            try AdminDeleteRecord.insertRecord(
                interactionId: interactionId,
                deleteAuthorId: deleteAuthorId,
                tx: tx,
            )
        }
        return .success
    }

    public func tryToAdminDeleteMessage(
        originalMessageAuthorAci: Aci,
        deleteAuthorAci: Aci,
        sentAtTimestamp: UInt64,
        groupThread: TSGroupThread,
        threadUniqueId: String?,
        serverTimestamp: UInt64,
        transaction: DBWriteTransaction,
    ) -> AdminDeleteProcessingResult {
        guard SDS.fitsInInt64(sentAtTimestamp) else {
            owsFailDebug("Unable to delete a message with invalid sentAtTimestamp: \(sentAtTimestamp)")
            return .invalidDelete
        }

        if
            let threadUniqueId, let messageToDelete = InteractionFinder.findMessage(
                withTimestamp: sentAtTimestamp,
                threadId: threadUniqueId,
                author: SignalServiceAddress(originalMessageAuthorAci),
                transaction: transaction,
            )
        {
            let success = TSMessage.remotelyDeleteMessage(
                messageToDelete,
                authorAci: originalMessageAuthorAci,
                isAdminDelete: true,
                serverTimestamp: serverTimestamp,
                transaction: transaction,
            )

            guard success else {
                return .invalidDelete
            }

            return insertAdminDelete(
                groupThread: groupThread,
                interactionId: messageToDelete.sqliteRowId!,
                deleteAuthor: deleteAuthorAci,
                tx: transaction,
            )
        } else {
            return .deletedMessageMissing
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
            try AdminDeleteRecord.insertRecord(
                interactionId: interactionId,
                deleteAuthorId: recipientId,
                tx: tx,
            )
        }
    }
}
