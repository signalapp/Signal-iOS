//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public class MessageRequestPendingReceipts: PendingReceiptRecorder {

    public init(appReadiness: AppReadiness) {
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.profileWhitelistDidChange(notification:)),
                name: UserProfileNotifications.profileWhitelistDidChange,
                object: nil,
            )

            DispatchQueue.global().async {
                self.auditPendingReceipts()
            }
        }
    }

    // MARK: -

    private let finder = PendingReceiptFinder()

    // MARK: -

    public func recordPendingReadReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: DBWriteTransaction) {
        guard let threadId = thread.sqliteRowId else {
            owsFail("can't record pending receipt without thread id")
        }
        finder.recordPendingReadReceipt(for: message, threadId: threadId, transaction: transaction)
    }

    public func recordPendingViewedReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: DBWriteTransaction) {
        guard let threadId = thread.sqliteRowId else {
            owsFail("can't record pending receipt without thread id")
        }
        finder.recordPendingViewedReceipt(for: message, threadId: threadId, transaction: transaction)
    }

    // MARK: -

    @objc
    private func profileWhitelistDidChange(notification: Notification) {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            guard let threadId = notification.affectedThread(transaction: transaction)?.sqliteRowId else {
                return
            }
            let userProfileWriter = notification.userProfileWriter
            if userProfileWriter == .localUser {
                self.sendAnyReadyReceipts(threadIds: [threadId], transaction: transaction)
            } else {
                self.removeAnyReadyReceipts(threadIds: [threadId], transaction: transaction)
            }
        }
    }

    private func auditPendingReceipts() {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            let threadIds = self.finder.threadIdsWithPendingReceipts(transaction: transaction)
            self.sendAnyReadyReceipts(threadIds: threadIds, transaction: transaction)
        }
    }

    private func sendAnyReadyReceipts(threadIds: some Sequence<TSThread.RowId>, transaction: DBReadTransaction) {
        var pendingReadReceipts = [PendingReadReceiptRecord]()
        var pendingViewedReceipts = [PendingViewedReceiptRecord]()

        for threadId in threadIds {
            guard let thread = ThreadFinder().fetch(rowId: threadId, tx: transaction) else {
                // The thread may be missing because there's no foreign key relationship.
                continue
            }
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                continue
            }

            pendingReadReceipts.append(contentsOf: self.finder.pendingReadReceipts(threadId: threadId, transaction: transaction))
            pendingViewedReceipts.append(contentsOf: self.finder.pendingViewedReceipts(threadId: threadId, transaction: transaction))
        }

        guard !pendingReadReceipts.isEmpty || !pendingViewedReceipts.isEmpty else {
            return
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            do {
                try self.enqueue(pendingReadReceipts: pendingReadReceipts, pendingViewedReceipts: pendingViewedReceipts, transaction: transaction)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    private func removeAnyReadyReceipts(threadIds: some Sequence<TSThread.RowId>, transaction: DBReadTransaction) {
        var pendingReadReceipts = [PendingReadReceiptRecord]()
        var pendingViewedReceipts = [PendingViewedReceiptRecord]()

        for threadId in threadIds {
            guard let thread = ThreadFinder().fetch(rowId: threadId, tx: transaction) else {
                // The thread may be missing because there's no foreign key relationship.
                continue
            }
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                continue
            }

            pendingReadReceipts.append(contentsOf: self.finder.pendingReadReceipts(threadId: threadId, transaction: transaction))
            pendingViewedReceipts.append(contentsOf: self.finder.pendingViewedReceipts(threadId: threadId, transaction: transaction))
        }

        guard !pendingReadReceipts.isEmpty || !pendingViewedReceipts.isEmpty else {
            return
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            self.finder.delete(pendingReadReceipts: pendingReadReceipts, transaction: transaction)
            self.finder.delete(pendingViewedReceipts: pendingViewedReceipts, transaction: transaction)
        }
    }

    private func enqueue(pendingReadReceipts: [PendingReadReceiptRecord], pendingViewedReceipts: [PendingViewedReceiptRecord], transaction: DBWriteTransaction) throws {
        guard OWSReceiptManager.areReadReceiptsEnabled(transaction: transaction) else {
            Logger.info("Deleting all pending receipts - user has subsequently disabled read receipts.")
            finder.deleteAllPendingReceipts(transaction: transaction)
            return
        }

        for receipt in pendingReadReceipts {
            guard let authorAci = self.authorAci(aciString: receipt.authorAciString, phoneNumber: receipt.authorPhoneNumber, tx: transaction) else {
                Logger.warn("Address was invalid or missing an ACI.")
                continue
            }
            SSKEnvironment.shared.receiptSenderRef.enqueueReadReceipt(
                for: authorAci,
                timestamp: UInt64(receipt.messageTimestamp),
                messageUniqueId: receipt.messageUniqueId,
                tx: transaction,
            )
        }
        finder.delete(pendingReadReceipts: pendingReadReceipts, transaction: transaction)

        for receipt in pendingViewedReceipts {
            guard let authorAci = self.authorAci(aciString: receipt.authorAciString, phoneNumber: receipt.authorPhoneNumber, tx: transaction) else {
                Logger.warn("Address was invalid or missing an ACI.")
                continue
            }
            SSKEnvironment.shared.receiptSenderRef.enqueueViewedReceipt(
                for: authorAci,
                timestamp: UInt64(receipt.messageTimestamp),
                messageUniqueId: receipt.messageUniqueId,
                tx: transaction,
            )
        }
        finder.delete(pendingViewedReceipts: pendingViewedReceipts, transaction: transaction)
    }

    private func authorAci(aciString: String?, phoneNumber: String?, tx: DBReadTransaction) -> Aci? {
        if let aciString, let aci = Aci.parseFrom(aciString: aciString) {
            return aci
        }
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        if let phoneNumber, let aci = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber, transaction: tx)?.aci {
            return aci
        }
        return nil
    }
}

// MARK: - Persistence

private class PendingReceiptFinder {
    func recordPendingReadReceipt(for message: TSIncomingMessage, threadId: TSThread.RowId, transaction: DBWriteTransaction) {
        var record = PendingReadReceiptRecord(
            threadId: threadId,
            messageTimestamp: Int64(message.timestamp),
            messageUniqueId: message.uniqueId,
            authorPhoneNumber: message.authorPhoneNumber,
            authorAci: Aci.parseFrom(aciString: message.authorUUID),
        )

        failIfThrows {
            try record.insert(transaction.database)
        }
    }

    func recordPendingViewedReceipt(for message: TSIncomingMessage, threadId: TSThread.RowId, transaction: DBWriteTransaction) {
        var record = PendingViewedReceiptRecord(
            threadId: threadId,
            messageTimestamp: Int64(message.timestamp),
            messageUniqueId: message.uniqueId,
            authorPhoneNumber: message.authorPhoneNumber,
            authorAci: Aci.parseFrom(aciString: message.authorUUID),
        )

        failIfThrows {
            try record.insert(transaction.database)
        }
    }

    func pendingReadReceipts(threadId: TSThread.RowId, transaction: DBReadTransaction) -> [PendingReadReceiptRecord] {
        let sql = """
            SELECT * FROM \(PendingReadReceiptRecord.databaseTableName) WHERE threadId = ?
        """
        return failIfThrows {
            return try PendingReadReceiptRecord.fetchAll(transaction.database, sql: sql, arguments: [threadId])
        }
    }

    func pendingViewedReceipts(threadId: TSThread.RowId, transaction: DBReadTransaction) -> [PendingViewedReceiptRecord] {
        let sql = """
            SELECT * FROM \(PendingViewedReceiptRecord.databaseTableName) WHERE threadId = ?
        """
        return failIfThrows {
            return try PendingViewedReceiptRecord.fetchAll(transaction.database, sql: sql, arguments: [threadId])
        }
    }

    func threadIdsWithPendingReceipts(transaction: DBReadTransaction) -> Set<TSThread.RowId> {
        let readSql = """
            SELECT DISTINCT threadId FROM \(PendingReadReceiptRecord.databaseTableName)
        """
        let readThreadIds = failIfThrows {
            return try Int64.fetchAll(transaction.database, sql: readSql)
        }

        let viewedSql = """
            SELECT DISTINCT threadId FROM \(PendingViewedReceiptRecord.databaseTableName)
        """
        let viewedThreadIds = failIfThrows {
            return try Int64.fetchAll(transaction.database, sql: viewedSql)
        }

        return Set(readThreadIds + viewedThreadIds)
    }

    func delete(pendingReadReceipts: [PendingReadReceiptRecord], transaction: DBWriteTransaction) {
        failIfThrows {
            try PendingReadReceiptRecord.deleteAll(transaction.database, keys: pendingReadReceipts.compactMap { $0.id })
        }
    }

    func delete(pendingViewedReceipts: [PendingViewedReceiptRecord], transaction: DBWriteTransaction) {
        failIfThrows {
            try PendingViewedReceiptRecord.deleteAll(transaction.database, keys: pendingViewedReceipts.compactMap { $0.id })
        }
    }

    func deleteAllPendingReceipts(transaction: DBWriteTransaction) {
        failIfThrows {
            try PendingReadReceiptRecord.deleteAll(transaction.database)
            try PendingViewedReceiptRecord.deleteAll(transaction.database)
        }
    }
}

// MARK: -

private extension Notification {
    var userProfileWriter: UserProfileWriter {
        guard let userProfileWriterValue = userInfo?[OWSProfileManager.notificationKeyUserProfileWriter] as? NSNumber else {
            owsFailDebug("userProfileWriterValue was unexpectedly nil")
            return .unknown
        }
        guard let userProfileWriter = UserProfileWriter(rawValue: UInt(userProfileWriterValue.intValue)) else {
            owsFailDebug("Invalid userProfileWriterValue")
            return .unknown
        }
        return userProfileWriter
    }

    func affectedThread(transaction: DBReadTransaction) -> TSThread? {
        if let address = userInfo?[UserProfileNotifications.profileAddressKey] as? SignalServiceAddress {
            guard let contactThread = TSContactThread.getWithContactAddress(address, transaction: transaction) else {
                return nil
            }
            return contactThread
        } else {
            assert(userInfo?[UserProfileNotifications.profileAddressKey] == nil)
        }

        if let groupId = userInfo?[UserProfileNotifications.profileGroupIdKey] as? Data {
            guard let groupThread = TSGroupThread.fetchThread(forGroupIdData: groupId, tx: transaction) else {
                return nil
            }
            return groupThread
        } else {
            assert(userInfo?[UserProfileNotifications.profileGroupIdKey] == nil)
        }

        owsFailDebug("no thread details in notification")
        return nil
    }
}
