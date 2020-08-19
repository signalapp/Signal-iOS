//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class MessageRequestReadReceipts: NSObject, PendingReadReceiptRecorder {

    override init() {
        super.init()
        AppReadiness.runNowOrWhenAppDidBecomeReadyPolite {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(self.profileWhitelistDidChange(notification:)),
                                                   name: .profileWhitelistDidChange,
                                                   object: nil)

            DispatchQueue.global().async {
                self.auditPendingReceipts()
            }
        }
    }

    // MARK: - Depenencies

    var databaseStorage: SDSDatabaseStorage {
        return SSKEnvironment.shared.databaseStorage
    }

    var grdbStorage: GRDBDatabaseStorageAdapter {
        return SDSDatabaseStorage.shared.grdbStorage
    }

    var readReceiptsManager: OWSReadReceiptManager {
        return SSKEnvironment.shared.readReceiptManager
    }

    var outgoingReceiptManager: OWSOutgoingReceiptManager {
        return SSKEnvironment.shared.outgoingReceiptManager
    }

    let finder = PendingReadReceiptFinder()

    // MARK: -

    public func recordPendingReadReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: GRDBWriteTransaction) {
        do {
            try finder.recordPendingReadReceipt(for: message, thread: thread, transaction: transaction)
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    // MARK: -

    @objc
    private func profileWhitelistDidChange(notification: Notification) {
        do {
            try grdbStorage.read { transaction in
                guard let thread = notification.affectedThread(transaction: transaction) else {
                    return
                }
                let wasLocallyInitiated = notification.wasLocallyInitiated

                if wasLocallyInitiated {
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
            try grdbStorage.read { transaction in
                let threads = try self.finder.threadsWithPendingReceipts(transaction: transaction)
                try self.sendAnyReadyReceipts(threads: threads, transaction: transaction)
            }
        } catch {
            owsFailDebug("error: \(error)")
        }
    }

    private func sendAnyReadyReceipts(threads: [TSThread], transaction: GRDBReadTransaction) throws {
        let pendingReceipts: [PendingReadReceiptRecord] = try threads.flatMap { thread -> [PendingReadReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                Logger.debug("aborting since there is still a pending message request for thread: \(thread.uniqueId)")
                return []
            }

            return try self.finder.pendingReceipts(thread: thread, transaction: transaction)
        }

        guard !pendingReceipts.isEmpty else {
            Logger.debug("aborting since pendingReceipts is empty for threads: \(threads.count)")
            return
        }

        databaseStorage.asyncWrite { transaction in
            do {
                try self.enqueue(pendingReceipts: pendingReceipts, transaction: transaction.unwrapGrdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    private func removeAnyReadyReceipts(threads: [TSThread], transaction: GRDBReadTransaction) throws {
        let pendingReceipts: [PendingReadReceiptRecord] = try threads.flatMap { thread -> [PendingReadReceiptRecord] in
            guard !thread.hasPendingMessageRequest(transaction: transaction) else {
                Logger.debug("aborting since there is still a pending message request for thread: \(thread.uniqueId)")
                return []
            }

            return try self.finder.pendingReceipts(thread: thread, transaction: transaction)
        }

        guard !pendingReceipts.isEmpty else {
            Logger.debug("aborting since pendingReceipts is empty for threads: \(threads.count)")
            return
        }

        self.databaseStorage.asyncWrite { transaction in
            do {
                try self.finder.delete(pendingReceipts: pendingReceipts, transaction: transaction.unwrapGrdbWrite)
            } catch {
                owsFailDebug("error: \(error)")
            }
        }
    }

    private func enqueue(pendingReceipts: [PendingReadReceiptRecord], transaction: GRDBWriteTransaction) throws {
        guard readReceiptsManager.areReadReceiptsEnabled() else {
            Logger.info("Deleting all pending read receipts - user has subsequently disabled read receipts.")
            try finder.deleteAllPendingReceipts(transaction: transaction)
            return
        }

        Logger.debug("Enqueuing read receipt for sender.")
        for receipt in pendingReceipts {
            let address = SignalServiceAddress(uuidString: receipt.authorUuid, phoneNumber: receipt.authorPhoneNumber)
            guard address.isValid else {
                owsFailDebug("address was invalid")
                continue
            }
            outgoingReceiptManager.enqueueReadReceipt(for: address,
                                                      timestamp: UInt64(receipt.messageTimestamp),
                                                      transaction: transaction.asAnyWrite)
        }

        try finder.delete(pendingReceipts: pendingReceipts, transaction: transaction)
    }
}

// MARK: - Persistence

public class PendingReadReceiptFinder {
    public func recordPendingReadReceipt(for message: TSIncomingMessage, thread: TSThread, transaction: GRDBWriteTransaction) throws {
        guard let threadId = thread.grdbId?.int64Value else {
            throw OWSAssertionError("threadId was unexpectedly nil")
        }

        let record = PendingReadReceiptRecord(threadId: threadId,
                                              messageTimestamp: Int64(message.timestamp),
                                              authorPhoneNumber: message.authorPhoneNumber,
                                              authorUuid: message.authorUUID)

        Logger.debug("pending read receipt: \(record)")
        try record.insert(transaction.database)
    }

    public func pendingReceipts(thread: TSThread, transaction: GRDBReadTransaction) throws -> [PendingReadReceiptRecord] {
        guard let threadId = thread.grdbId?.int64Value else {
            throw OWSAssertionError("threadId was unexpectedly nil")
        }

        let sql = """
            SELECT * FROM pending_read_receipts
            WHERE threadId = \(threadId)
        """
        return try PendingReadReceiptRecord.fetchAll(transaction.database, sql: sql)
    }

    public func threadsWithPendingReceipts(transaction: GRDBReadTransaction) throws -> [TSThread] {
        let sql = """
            SELECT DISTINCT model_TSThread.* FROM model_TSThread
            INNER JOIN pending_read_receipts
                ON pending_read_receipts.threadId = model_TSThread.id
        """
        return try TSThread.grdbFetchCursor(sql: sql, transaction: transaction).all()
    }

    public func delete(pendingReceipts: [PendingReadReceiptRecord], transaction: GRDBWriteTransaction) throws {
        try PendingReadReceiptRecord.deleteAll(transaction.database, keys: pendingReceipts.compactMap { $0.id })
    }

    public func deleteAllPendingReceipts(transaction: GRDBWriteTransaction) throws {
        try PendingReadReceiptRecord.deleteAll(transaction.database)
    }
}

// MARK: -

fileprivate extension Notification {
    var wasLocallyInitiated: Bool {
        guard let wasLocallyInitiatedValue = userInfo?[kNSNotificationKey_WasLocallyInitiated] as? NSNumber else {
            owsFailDebug("wasLocallyInitiatedValue was unexpectedly nil")
            return false
        }
        return wasLocallyInitiatedValue.boolValue
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
