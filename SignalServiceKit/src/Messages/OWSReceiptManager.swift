//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

struct ReceiptForLinkedDevice: Codable {
    let senderAddress: SignalServiceAddress
    let messageUniqueId: String?            // Only nil when decoding old values
    let messageIdTimestamp: UInt64
    let timestamp: UInt64

    init(senderAddress: SignalServiceAddress, messageUniqueId: String, messageIdTimestamp: UInt64, timestamp: UInt64) {
        self.senderAddress = senderAddress
        self.messageUniqueId = messageUniqueId
        self.messageIdTimestamp = messageIdTimestamp
        self.timestamp = timestamp
    }

    var asLinkedDeviceReadReceipt: OWSLinkedDeviceReadReceipt {
        return OWSLinkedDeviceReadReceipt(
            senderAddress: senderAddress,
            messageUniqueId: messageUniqueId,
            messageIdTimestamp: messageIdTimestamp,
            readTimestamp: timestamp)
    }

    var asLinkedDeviceViewedReceipt: OWSLinkedDeviceViewedReceipt {
        return OWSLinkedDeviceViewedReceipt(
            senderAddress: senderAddress,
            messageUniqueId: messageUniqueId,
            messageIdTimestamp: messageIdTimestamp,
            viewedTimestamp: timestamp)
    }
}

// MARK: -

@objc
public extension OWSReceiptManager {

    private var toLinkedDevicesReadReceiptMapStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "OWSReceiptManager.toLinkedDevicesReadReceiptMapStore")
    }

    private var toLinkedDevicesViewedReceiptMapStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "OWSReceiptManager.toLinkedDevicesViewedReceiptMapStore")
    }

    func processReceiptsForLinkedDevices(completion: @escaping () -> Void) {
        guard !DebugFlags.suppressBackgroundActivity else {
            // Don't process queues.
            return completion()
        }

        Logger.verbose("Processing receipts for linked devices.")

        let didWork = databaseStorage.write { transaction -> Bool in
            let readReceiptsForLinkedDevices: [ReceiptForLinkedDevice]
            do {
                readReceiptsForLinkedDevices = try self.toLinkedDevicesReadReceiptMapStore.allCodableValues(transaction: transaction)
            } catch {
                owsFailDebug("Error: \(error).")
                return false
            }

            let viewedReceiptsForLinkedDevices: [ReceiptForLinkedDevice]
            do {
                viewedReceiptsForLinkedDevices = try self.toLinkedDevicesViewedReceiptMapStore.allCodableValues(transaction: transaction)
            } catch {
                owsFailDebug("Error: \(error).")
                return false
            }

            guard !readReceiptsForLinkedDevices.isEmpty || !viewedReceiptsForLinkedDevices.isEmpty else {
                return false
            }

            guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
                owsFailDebug("Missing thread.")
                return false
            }

            if !readReceiptsForLinkedDevices.isEmpty {
                let receiptsForMessage = readReceiptsForLinkedDevices.map { $0.asLinkedDeviceReadReceipt }
                let message = OWSReadReceiptsForLinkedDevicesMessage(thread: thread, readReceipts: receiptsForMessage, transaction: transaction)

                self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                self.toLinkedDevicesReadReceiptMapStore.removeAll(transaction: transaction)
            }

            if !viewedReceiptsForLinkedDevices.isEmpty {
                let receiptsForMessage = viewedReceiptsForLinkedDevices.map { $0.asLinkedDeviceViewedReceipt }
                let message = OWSViewedReceiptsForLinkedDevicesMessage(thread: thread, viewedReceipts: receiptsForMessage, transaction: transaction)

                self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                self.toLinkedDevicesViewedReceiptMapStore.removeAll(transaction: transaction)
            }

            return true
        }

        if didWork {
            // Wait N seconds before processing read receipts again.
            // This allows time for a batch to accumulate.
            //
            // We want a value high enough to allow us to effectively de-duplicate,
            // read receipts without being so high that we risk not sending read
            // receipts due to app exit.
            let kProcessingFrequencySeconds: TimeInterval = 3
            DispatchQueue.global().asyncAfter(deadline: .now() + kProcessingFrequencySeconds) {
                self.processReceiptsForLinkedDevices(completion: completion)
            }
        } else {
            completion()
        }
    }

    func enqueueLinkedDeviceReadReceipt(forMessage message: TSIncomingMessage,
                                        transaction: SDSAnyWriteTransaction) {
        let threadUniqueId = message.uniqueThreadId

        let messageAuthorAddress = message.authorAddress
        assert(messageAuthorAddress.isValid)

        let newReadReceipt = ReceiptForLinkedDevice(
            senderAddress: messageAuthorAddress,
            messageUniqueId: message.uniqueId,
            messageIdTimestamp: message.timestamp,
            timestamp: Date.ows_millisecondTimestamp()
        )

        do {
            if let oldReadReceipt: ReceiptForLinkedDevice = try toLinkedDevicesReadReceiptMapStore.getCodableValue(forKey: threadUniqueId, transaction: transaction),
                oldReadReceipt.messageIdTimestamp > newReadReceipt.messageIdTimestamp {
                // If there's an existing "linked device" read receipt for the same thread with
                // a newer timestamp, discard this "linked device" read receipt.
                Logger.verbose("Ignoring redundant read receipt for linked devices.")
            } else {
                Logger.verbose("Enqueuing read receipt for linked devices.")
                try toLinkedDevicesReadReceiptMapStore.setCodable(newReadReceipt, key: threadUniqueId, transaction: transaction)
            }
        } catch {
            owsFailDebug("Error: \(error).")
        }
    }

    func enqueueLinkedDeviceViewedReceipt(forIncomingMessage message: TSIncomingMessage,
                                          transaction: SDSAnyWriteTransaction) {

        self.enqueueLinkedDeviceViewedReceipt(
            messageAuthorAddress: message.authorAddress,
            messageUniqueId: message.uniqueId,
            messageIdTimestamp: message.timestamp,
            transaction: transaction
        )
    }

    func enqueueLinkedDeviceViewedReceipt(forOutgoingMessage message: TSOutgoingMessage,
                                          transaction: SDSAnyWriteTransaction) {

        guard let localAddress = self.tsAccountManager.localAddress(with: transaction) else {
            owsFailDebug("no local address")
            return
        }

        self.enqueueLinkedDeviceViewedReceipt(
            messageAuthorAddress: localAddress,
            messageUniqueId: message.uniqueId,
            messageIdTimestamp: message.timestamp,
            transaction: transaction
        )
    }

    func enqueueLinkedDeviceReadReceipt(
        forStoryMessage message: StoryMessage,
        transaction: SDSAnyWriteTransaction
    ) {
        guard !message.authorAddress.isSystemStoryAddress else {
            Logger.info("Not sending linked device read receipt for system story")
            return
        }

        assert(message.authorAddress.isValid)

        let newReadReceipt = ReceiptForLinkedDevice(
            senderAddress: message.authorAddress,
            messageUniqueId: message.uniqueId,
            messageIdTimestamp: message.timestamp,
            timestamp: Date.ows_millisecondTimestamp()
        )

        // Unlike message read receipts, we send every story message read receipt requested.
        // On the caller side of things, we may choose to only send a read receipt for the latest
        // known message per story context at the time of reading.
        // On the receiving end we keep track of the latest read timestamp per context and should
        // be fine whether we send every read receipt or just the latest; its purely a bandwidth/perf difference.
        do {
            try toLinkedDevicesReadReceiptMapStore.setCodable(newReadReceipt, key: message.uniqueId, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    func enqueueLinkedDeviceViewedReceipt(
        forStoryMessage message: StoryMessage,
        transaction: SDSAnyWriteTransaction
    ) {
        guard !message.authorAddress.isSystemStoryAddress else {
            Logger.info("Not sending linked device viewed receipt for system story")
            return
        }

        self.enqueueLinkedDeviceViewedReceipt(
            messageAuthorAddress: message.authorAddress,
            messageUniqueId: message.uniqueId,
            messageIdTimestamp: message.timestamp,
            transaction: transaction
        )
    }

    func enqueueSenderViewedReceipt(
        forStoryMessage message: StoryMessage,
        transaction: SDSAnyWriteTransaction
    ) {
        guard !message.authorAddress.isSystemStoryAddress else {
            Logger.info("Not sending sender viewed receipt for system story")
            return
        }
        guard !message.authorAddress.isLocalAddress else {
            Logger.info("We don't support incoming messages from self.")
            return
        }

        self.outgoingReceiptManager.enqueueViewedReceipt(
            for: message.authorAddress,
            timestamp: message.timestamp,
            messageUniqueId: message.uniqueId,
            transaction: transaction
        )
    }

    private func enqueueLinkedDeviceViewedReceipt(
        messageAuthorAddress: SignalServiceAddress,
        messageUniqueId: String,
        messageIdTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {

        assert(messageAuthorAddress.isValid)

        let newViewedReceipt = ReceiptForLinkedDevice(
            senderAddress: messageAuthorAddress,
            messageUniqueId: messageUniqueId,
            messageIdTimestamp: messageIdTimestamp,
            timestamp: Date.ows_millisecondTimestamp()
        )

        // Unlike read receipts, we must send *every* viewed receipt, so we use
        // `message.uniqueId` as the key. If you read message N, we can assume that
        // messages [0, N-1] have also been read, and this is reflected in the UI
        // via the unread marker. However, if you view message N (whether it's view
        // once, voice note, etc.), this has no bearing on whether or not you've
        // viewed other messages in the chat.
        do {
            try toLinkedDevicesViewedReceiptMapStore.setCodable(newViewedReceipt, key: messageUniqueId, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
        }
    }

    // MARK: - Mark as read

    func markAsReadLocally(beforeSortId sortId: UInt64,
                           thread: TSThread,
                           hasPendingMessageRequest: Bool,
                           completion: @escaping () -> Void) {
        DispatchQueue.global().async {
            let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)

            let (unreadCount, messagesWithUnreadReactionsCount) = self.databaseStorage.read { transaction in
                (
                    interactionFinder.countUnreadMessages(beforeSortId: sortId,
                                                          transaction: transaction.unwrapGrdbRead),
                    interactionFinder.countMessagesWithUnreadReactions(beforeSortId: sortId,
                                                                       transaction: transaction.unwrapGrdbRead)
                )
            }

            if unreadCount == 0 && messagesWithUnreadReactionsCount == 0 {
                // Avoid unnecessary writes.
                DispatchQueue.main.async(execute: completion)
                return
            }

            let localAddress = self.tsAccountManager.localAddress
            let readTimestamp = Date.ows_millisecondTimestamp()
            let maxBatchSize = 500

            let circumstance: OWSReceiptCircumstance
            let logSuffix: String
            if hasPendingMessageRequest {
                circumstance = .onThisDeviceWhilePendingMessageRequest
                logSuffix = " while pending message request"
            } else {
                circumstance = .onThisDevice
                logSuffix = ""
            }
            Logger.info("Marking \(unreadCount) received messages and \(messagesWithUnreadReactionsCount) sent messages with reactions as read locally\(logSuffix) (in batches of \(maxBatchSize))")

            var batchQuotaRemaining: Int
            repeat {
                batchQuotaRemaining = maxBatchSize
                self.databaseStorage.write { transaction in
                    var cursor = interactionFinder.fetchUnreadMessages(beforeSortId: sortId,
                                                                       transaction: transaction.unwrapGrdbRead)
                    do {
                        while batchQuotaRemaining > 0, let readItem = try cursor.next() {
                            readItem.markAsRead(atTimestamp: readTimestamp,
                                                thread: thread,
                                                circumstance: circumstance,
                                                shouldClearNotifications: true,
                                                transaction: transaction)
                            batchQuotaRemaining -= 1
                        }
                    } catch {
                        owsFailDebug("unexpected failure fetching unread messages: \(error)")
                        // Bail out of the outer loop by leaving the quota > 0;
                        // we're likely to hit the error multiple times.
                    }
                }
                // Continue until we process a batch and have some quota left.
            } while batchQuotaRemaining == 0

            // Mark outgoing messages with unread reactions as well.
            repeat {
                batchQuotaRemaining = maxBatchSize
                self.databaseStorage.write { transaction in
                    var receiptsForMessage: [OWSLinkedDeviceReadReceipt] = []
                    var cursor = interactionFinder.fetchMessagesWithUnreadReactions(
                        beforeSortId: sortId,
                        transaction: transaction.unwrapGrdbRead)

                    do {
                        while batchQuotaRemaining > 0, let message = try cursor.next() {
                            message.markUnreadReactionsAsRead(transaction: transaction)

                            if let localAddress = localAddress {
                                let receipt = OWSLinkedDeviceReadReceipt(senderAddress: localAddress,
                                                                         messageUniqueId: message.uniqueId,
                                                                         messageIdTimestamp: message.timestamp,
                                                                         readTimestamp: readTimestamp)
                                receiptsForMessage.append(receipt)
                            }

                            batchQuotaRemaining -= 1
                        }
                    } catch {
                        owsFailDebug("unexpected failure fetching messages with unread reactions: \(error)")
                        // Bail out of the outer loop by leaving the quota > 0;
                        // we're likely to hit the error multiple times.
                    }

                    if !receiptsForMessage.isEmpty {
                        let message = OWSReadReceiptsForLinkedDevicesMessage(thread: thread,
                                                                             readReceipts: receiptsForMessage,
                                                                             transaction: transaction)
                        self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                    }
                }
                // Continue until we process a batch and have some quota left.
            } while batchQuotaRemaining == 0

            DispatchQueue.main.async(execute: completion)
        }
    }

    func markAsRead(beforeSortId sortId: UInt64,
                    thread: TSThread,
                    readTimestamp: UInt64,
                    circumstance: OWSReceiptCircumstance,
                    shouldClearNotifications: Bool,
                    transaction: SDSAnyWriteTransaction) -> [String] {
        owsAssertDebug(sortId > 0)

        var readUniqueIds = [String]()
        let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)
        var cursor = interactionFinder.fetchUnreadMessages(beforeSortId: sortId,
                                                           transaction: transaction.unwrapGrdbRead)
        do {
            while let readItem = try cursor.next() {
                readItem.markAsRead(atTimestamp: readTimestamp,
                                    thread: thread,
                                    circumstance: circumstance,
                                    shouldClearNotifications: shouldClearNotifications,
                                    transaction: transaction)
                readUniqueIds.append(readItem.uniqueId)
            }
        } catch {
            owsFailDebug("unexpected failure fetching unread messages: \(error)")
            return []
        }

        return readUniqueIds
    }

    func markAsReadOnLinkedDevice(
        _ message: TSMessage,
        thread: TSThread,
        readTimestamp: UInt64,
        transaction: SDSAnyWriteTransaction
    ) {
        if let incomingMessage = message as? TSIncomingMessage {
            let circumstance: OWSReceiptCircumstance
            if thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead) {
                circumstance = .onLinkedDeviceWhilePendingMessageRequest
            } else {
                circumstance = .onLinkedDevice
            }

            // Always re-mark the message as read to ensure any earlier read
            // time is applied to disappearing messages. Also mark any unread
            // messages appearing earlier in the thread as read as well.
            //
            // Do not automatically clear notifications, as we will do so
            // manually below.

            incomingMessage.markAsRead(
                atTimestamp: readTimestamp,
                thread: thread,
                circumstance: circumstance,
                shouldClearNotifications: false,
                transaction: transaction
            )

            let markedAsReadIds = self.markAsRead(
                beforeSortId: incomingMessage.sortId,
                thread: thread,
                readTimestamp: readTimestamp,
                circumstance: circumstance,
                shouldClearNotifications: false,
                transaction: transaction
            )

            // Manually clear notifications for all the now-marked-read messages
            // in one batch.
            notificationPresenter?.cancelNotifications(messageIds: [incomingMessage.uniqueId] + markedAsReadIds)
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            // Outgoing messages are always "read", but if we get a receipt
            // from our linked device about one that indicates that any reactions
            // we received on this message should also be marked read.
            outgoingMessage.markUnreadReactionsAsRead(transaction: transaction)
        } else {
            owsFailDebug("Message was neither incoming nor outgoing!")
        }
    }

    static func markAllCallInteractionsAsReadLocally(
        beforeSQLId sqlId: NSNumber?, /* Clears everything if nil */
        thread: TSThread,
        transaction: SDSAnyWriteTransaction
    ) {
        // At time of writing, the column is always null for call interactions.
        // But lets not rely on that. These queries use an index as long as
        // the where clauses are single value matches and not ORs or anything,
        // so two queries each with an index is better than one non-index query.
        let possibleIsGroupStoryReplyValues: [Bool?] = [nil, false]
        for isGroupStoryReply in possibleIsGroupStoryReplyValues {
            var sql = """
                UPDATE \(InteractionRecord.databaseTableName)
                SET read = 1
                WHERE \(interactionColumn: .read) = 0
                AND \(interactionColumn: .isGroupStoryReply) IS ?
                AND \(interactionColumn: .threadUniqueId) = ?
                AND \(interactionColumn: .recordType) = ?
            """
            var arguments: StatementArguments = [isGroupStoryReply, thread.uniqueId, SDSRecordType.call.rawValue]
            if let sqlId = sqlId {
                sql += " AND \(interactionColumn: .id) <= ?"
                arguments += [sqlId]
            }
            transaction.unwrapGrdbWrite.execute(sql: sql, arguments: arguments)
        }
    }
}
