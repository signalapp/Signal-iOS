//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

final public class MessageRequestPendingReceipts: PendingReceiptRecorder {

    public init(appReadiness: AppReadiness) {
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.profileWhitelistDidChange(notification:)),
                                                   name: UserProfileNotifications.profileWhitelistDidChange,
                                                   object: nil)

            DispatchQueue.global().async {
                self.auditPendingReceipts()
            }
        }
    }

    // MARK: - 

    let finder = PendingReceiptFinder()

    // MARK: -

    public func recordPendingReadReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: DBWriteTransaction) {
        do {
            try finder.recordPendingReadReceipt(for: message, thread: thread, transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    public func recordPendingViewedReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: DBWriteTransaction) {
        do {
            try finder.recordPendingViewedReceipt(for: message, thread: thread, transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    // MARK: -

    @objc
    private func profileWhitelistDidChange(notification: Notification) {
        do {
            try SSKEnvironment.shared.databaseStorageRef.grdbStorage.read { transaction in
                guard let thread = notification.affectedThread(transaction: transaction) else {
                    return
                }
                let userProfileWriter = notification.userProfileWriter
                if userProfileWriter == .localUser {
                    try self.sendAnyReadyReceipts(threads: [thread], transaction: transaction)
                } else {
                    try self.removeAnyReadyReceipts(threads: [thread], transaction: transaction)
                }
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    private func auditPendingReceipts() {
        do {
            try SSKEnvironment.shared.databaseStorageRef.grdbStorage.read { transaction in
                let threads = try self.finder.threadsWithPendingReceipts(transaction: transaction)
                try self.sendAnyReadyReceipts(threads: threads, transaction: transaction)
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    private func sendAnyReadyReceipts(threads: [TSThread], transaction: DBReadTransaction) throws {
        let pendingReadReceipts: [PendingReadReceiptRecord] = try threads.flatMap { thread -> [PendingReadReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                return []
            }

            return try self.finder.pendingReadReceipts(thread: thread, transaction: transaction)
        }

        let pendingViewedReceipts: [PendingViewedReceiptRecord] = try threads.flatMap { thread -> [PendingViewedReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                return []
            }

            return try self.finder.pendingViewedReceipts(thread: thread, transaction: transaction)
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

    private func removeAnyReadyReceipts(threads: [TSThread], transaction: DBReadTransaction) throws {
        let pendingReadReceipts: [PendingReadReceiptRecord] = try threads.flatMap { thread -> [PendingReadReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                return []
            }

            return try self.finder.pendingReadReceipts(thread: thread, transaction: transaction)
        }

        let pendingViewedReceipts: [PendingViewedReceiptRecord] = try threads.flatMap { thread -> [PendingViewedReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                return []
            }

            return try self.finder.pendingViewedReceipts(thread: thread, transaction: transaction)
        }

        guard !pendingReadReceipts.isEmpty || !pendingViewedReceipts.isEmpty else {
            return
        }

        SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
            do {
                try self.finder.delete(pendingReadReceipts: pendingReadReceipts, transaction: transaction)
                try self.finder.delete(pendingViewedReceipts: pendingViewedReceipts, transaction: transaction)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    private func enqueue(pendingReadReceipts: [PendingReadReceiptRecord], pendingViewedReceipts: [PendingViewedReceiptRecord], transaction: DBWriteTransaction) throws {
        guard SSKEnvironment.shared.receiptManagerRef.areReadReceiptsEnabled() else {
            Logger.info("Deleting all pending receipts - user has subsequently disabled read receipts.")
            try finder.deleteAllPendingReceipts(transaction: transaction)
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
                tx: transaction
            )
        }
        try finder.delete(pendingReadReceipts: pendingReadReceipts, transaction: transaction)

        for receipt in pendingViewedReceipts {
            guard let authorAci = self.authorAci(aciString: receipt.authorAciString, phoneNumber: receipt.authorPhoneNumber, tx: transaction) else {
                Logger.warn("Address was invalid or missing an ACI.")
                continue
            }
            SSKEnvironment.shared.receiptSenderRef.enqueueViewedReceipt(
                for: authorAci,
                timestamp: UInt64(receipt.messageTimestamp),
                messageUniqueId: receipt.messageUniqueId,
                tx: transaction
            )
        }
        try finder.delete(pendingViewedReceipts: pendingViewedReceipts, transaction: transaction)
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

final public class PendingReceiptFinder {
    public func recordPendingReadReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: DBWriteTransaction) throws {
        guard let threadId = thread.sqliteRowId else {
            throw OWSAssertionError("threadId was unexpectedly nil")
        }

        let record = PendingReadReceiptRecord(
            threadId: threadId,
            messageTimestamp: Int64(message.timestamp),
            messageUniqueId: message.uniqueId,
            authorPhoneNumber: message.authorPhoneNumber,
            authorAci: Aci.parseFrom(aciString: message.authorUUID)
        )

        try record.insert(transaction.database)
    }

    public func recordPendingViewedReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: DBWriteTransaction) throws {
        guard let threadId = thread.sqliteRowId else {
            throw OWSAssertionError("threadId was unexpectedly nil")
        }

        let record = PendingViewedReceiptRecord(
            threadId: threadId,
            messageTimestamp: Int64(message.timestamp),
            messageUniqueId: message.uniqueId,
            authorPhoneNumber: message.authorPhoneNumber,
            authorAci: Aci.parseFrom(aciString: message.authorUUID)
        )

        try record.insert(transaction.database)
    }

    public func pendingReadReceipts(thread: TSThread, transaction: DBReadTransaction) throws -> [PendingReadReceiptRecord] {
        guard let threadId = thread.sqliteRowId else {
            throw OWSAssertionError("threadId was unexpectedly nil")
        }

        let sql = """
            SELECT * FROM pending_read_receipts
            WHERE threadId = \(threadId)
        """
        return try PendingReadReceiptRecord.fetchAll(transaction.database, sql: sql)
    }

    public func pendingViewedReceipts(thread: TSThread, transaction: DBReadTransaction) throws -> [PendingViewedReceiptRecord] {
        guard let threadId = thread.sqliteRowId else {
            throw OWSAssertionError("threadId was unexpectedly nil")
        }

        let sql = """
            SELECT * FROM pending_viewed_receipts
            WHERE threadId = \(threadId)
        """
        return try PendingViewedReceiptRecord.fetchAll(transaction.database, sql: sql)
    }

    public func threadsWithPendingReceipts(transaction: DBReadTransaction) throws -> [TSThread] {
        let readSql = """
            SELECT DISTINCT model_TSThread.* FROM model_TSThread
            INNER JOIN pending_read_receipts
                ON pending_read_receipts.threadId = model_TSThread.id
        """
        let readThreads = try TSThread.grdbFetchCursor(sql: readSql, transaction: transaction).all()

        let viewedSql = """
            SELECT DISTINCT model_TSThread.* FROM model_TSThread
            INNER JOIN pending_viewed_receipts
                ON pending_viewed_receipts.threadId = model_TSThread.id
        """
        let viewedThreads = try TSThread.grdbFetchCursor(sql: viewedSql, transaction: transaction).all()

        return Array(Set(readThreads + viewedThreads))
    }

    public func delete(pendingReadReceipts: [PendingReadReceiptRecord], transaction: DBWriteTransaction) throws {
        try PendingReadReceiptRecord.deleteAll(transaction.database, keys: pendingReadReceipts.compactMap { $0.id })
    }

    public func delete(pendingViewedReceipts: [PendingViewedReceiptRecord], transaction: DBWriteTransaction) throws {
        try PendingViewedReceiptRecord.deleteAll(transaction.database, keys: pendingViewedReceipts.compactMap { $0.id })
    }

    public func deleteAllPendingReceipts(transaction: DBWriteTransaction) throws {
        try PendingReadReceiptRecord.deleteAll(transaction.database)
        try PendingViewedReceiptRecord.deleteAll(transaction.database)
    }
}

// MARK: -

fileprivate extension Notification {
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
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
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
