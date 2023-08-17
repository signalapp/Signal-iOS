//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit

public class MessageRequestPendingReceipts: Dependencies, PendingReceiptRecorder {

    public init() {
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.profileWhitelistDidChange(notification:)),
                                                   name: .profileWhitelistDidChange,
                                                   object: nil)

            DispatchQueue.global().async {
                self.auditPendingReceipts()
            }
        }
    }

    // MARK: - 

    let finder = PendingReceiptFinder()

    // MARK: -

    public func recordPendingReadReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: GRDBWriteTransaction) {
        do {
            try finder.recordPendingReadReceipt(for: message, thread: thread, transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    public func recordPendingViewedReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: GRDBWriteTransaction) {
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
            try grdbStorageAdapter.read { transaction in
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
            try grdbStorageAdapter.read { transaction in
                let threads = try self.finder.threadsWithPendingReceipts(transaction: transaction)
                try self.sendAnyReadyReceipts(threads: threads, transaction: transaction)
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    private func sendAnyReadyReceipts(threads: [TSThread], transaction: GRDBReadTransaction) throws {
        let pendingReadReceipts: [PendingReadReceiptRecord] = try threads.flatMap { thread -> [PendingReadReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                Logger.debug("aborting since there is still a pending message request for thread: \(thread.uniqueId)")
                return []
            }

            return try self.finder.pendingReadReceipts(thread: thread, transaction: transaction)
        }

        let pendingViewedReceipts: [PendingViewedReceiptRecord] = try threads.flatMap { thread -> [PendingViewedReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                Logger.debug("aborting since there is still a pending message request for thread: \(thread.uniqueId)")
                return []
            }

            return try self.finder.pendingViewedReceipts(thread: thread, transaction: transaction)
        }

        guard !pendingReadReceipts.isEmpty || !pendingViewedReceipts.isEmpty else {
            Logger.debug("aborting since pendingReceipts is empty for threads: \(threads.count)")
            return
        }

        databaseStorage.asyncWrite { transaction in
            do {
                try self.enqueue(pendingReadReceipts: pendingReadReceipts, pendingViewedReceipts: pendingViewedReceipts, transaction: transaction.unwrapGrdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    private func removeAnyReadyReceipts(threads: [TSThread], transaction: GRDBReadTransaction) throws {
        let pendingReadReceipts: [PendingReadReceiptRecord] = try threads.flatMap { thread -> [PendingReadReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                Logger.debug("aborting since there is still a pending message request for thread: \(thread.uniqueId)")
                return []
            }

            return try self.finder.pendingReadReceipts(thread: thread, transaction: transaction)
        }

        let pendingViewedReceipts: [PendingViewedReceiptRecord] = try threads.flatMap { thread -> [PendingViewedReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                Logger.debug("aborting since there is still a pending message request for thread: \(thread.uniqueId)")
                return []
            }

            return try self.finder.pendingViewedReceipts(thread: thread, transaction: transaction)
        }

        guard !pendingReadReceipts.isEmpty || !pendingViewedReceipts.isEmpty else {
            Logger.debug("aborting since pendingReceipts is empty for threads: \(threads.count)")
            return
        }

        self.databaseStorage.asyncWrite { transaction in
            do {
                try self.finder.delete(pendingReadReceipts: pendingReadReceipts, transaction: transaction.unwrapGrdbWrite)
                try self.finder.delete(pendingViewedReceipts: pendingViewedReceipts, transaction: transaction.unwrapGrdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    private func enqueue(pendingReadReceipts: [PendingReadReceiptRecord], pendingViewedReceipts: [PendingViewedReceiptRecord], transaction: GRDBWriteTransaction) throws {
        guard receiptManager.areReadReceiptsEnabled() else {
            Logger.info("Deleting all pending receipts - user has subsequently disabled read receipts.")
            try finder.deleteAllPendingReceipts(transaction: transaction)
            return
        }

        Logger.debug("Enqueuing read receipt for sender.")
        for receipt in pendingReadReceipts {
            let address = SignalServiceAddress(aciString: receipt.authorAciString, phoneNumber: receipt.authorPhoneNumber)
            guard address.isValid else {
                owsFailDebug("address was invalid")
                continue
            }
            outgoingReceiptManager.enqueueReadReceipt(
                for: address,
                timestamp: UInt64(receipt.messageTimestamp),
                messageUniqueId: receipt.messageUniqueId,
                tx: transaction.asAnyWrite
            )
        }
        try finder.delete(pendingReadReceipts: pendingReadReceipts, transaction: transaction)

        Logger.debug("Enqueuing viewed receipt for sender.")
        for receipt in pendingViewedReceipts {
            let address = SignalServiceAddress(aciString: receipt.authorAciString, phoneNumber: receipt.authorPhoneNumber)
            guard address.isValid else {
                owsFailDebug("address was invalid")
                continue
            }
            outgoingReceiptManager.enqueueViewedReceipt(
                for: address,
                timestamp: UInt64(receipt.messageTimestamp),
                messageUniqueId: receipt.messageUniqueId,
                tx: transaction.asAnyWrite
            )
        }
        try finder.delete(pendingViewedReceipts: pendingViewedReceipts, transaction: transaction)
    }
}

// MARK: - Persistence

public class PendingReceiptFinder {
    public func recordPendingReadReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: GRDBWriteTransaction) throws {
        guard let threadId = thread.grdbId?.int64Value else {
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

    public func recordPendingViewedReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: GRDBWriteTransaction) throws {
        guard let threadId = thread.grdbId?.int64Value else {
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

    public func pendingReadReceipts(thread: TSThread, transaction: GRDBReadTransaction) throws -> [PendingReadReceiptRecord] {
        guard let threadId = thread.grdbId?.int64Value else {
            throw OWSAssertionError("threadId was unexpectedly nil")
        }

        let sql = """
            SELECT * FROM pending_read_receipts
            WHERE threadId = \(threadId)
        """
        return try PendingReadReceiptRecord.fetchAll(transaction.database, sql: sql)
    }

    public func pendingViewedReceipts(thread: TSThread, transaction: GRDBReadTransaction) throws -> [PendingViewedReceiptRecord] {
        guard let threadId = thread.grdbId?.int64Value else {
            throw OWSAssertionError("threadId was unexpectedly nil")
        }

        let sql = """
            SELECT * FROM pending_viewed_receipts
            WHERE threadId = \(threadId)
        """
        return try PendingViewedReceiptRecord.fetchAll(transaction.database, sql: sql)
    }

    public func threadsWithPendingReceipts(transaction: GRDBReadTransaction) throws -> [TSThread] {
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

    public func delete(pendingReadReceipts: [PendingReadReceiptRecord], transaction: GRDBWriteTransaction) throws {
        try PendingReadReceiptRecord.deleteAll(transaction.database, keys: pendingReadReceipts.compactMap { $0.id })
    }

    public func delete(pendingViewedReceipts: [PendingViewedReceiptRecord], transaction: GRDBWriteTransaction) throws {
        try PendingViewedReceiptRecord.deleteAll(transaction.database, keys: pendingViewedReceipts.compactMap { $0.id })
    }

    public func deleteAllPendingReceipts(transaction: GRDBWriteTransaction) throws {
        try PendingReadReceiptRecord.deleteAll(transaction.database)
        try PendingViewedReceiptRecord.deleteAll(transaction.database)
    }
}

// MARK: -

fileprivate extension Notification {
    var userProfileWriter: UserProfileWriter {
        guard let userProfileWriterValue = userInfo?[kNSNotificationKey_UserProfileWriter] as? NSNumber else {
            owsFailDebug("userProfileWriterValue was unexpectedly nil")
            return .unknown
        }
        guard let userProfileWriter = UserProfileWriter(rawValue: UInt(userProfileWriterValue.intValue)) else {
            owsFailDebug("Invalid userProfileWriterValue")
            return .unknown
        }
        return userProfileWriter
    }

    func affectedThread(transaction: GRDBReadTransaction) -> TSThread? {
        if let address = userInfo?[kNSNotificationKey_ProfileAddress] as? SignalServiceAddress {
            guard let contactThread = TSContactThread.getWithContactAddress(address, transaction: transaction.asAnyRead) else {
                Logger.debug("No existing contact thread for address: \(address)")
                return nil
            }
            return contactThread
        } else {
            assert(userInfo?[kNSNotificationKey_ProfileAddress] == nil)
        }

        if let groupId = userInfo?[kNSNotificationKey_ProfileGroupId] as? Data {
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction.asAnyRead) else {
                Logger.debug("No existing group thread for groupId: \(groupId)")
                return nil
            }
            return groupThread
        } else {
            assert(userInfo?[kNSNotificationKey_ProfileGroupId] == nil)
        }

        owsFailDebug("no thread details in notification")
        return nil
    }
}
