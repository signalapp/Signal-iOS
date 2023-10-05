//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import SignalCoreKit

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

    var asLinkedDeviceReadReceipt: OWSLinkedDeviceReadReceipt? {
        guard let senderAci = senderAddress.aci else { return nil }
        return OWSLinkedDeviceReadReceipt(
            senderAci: AciObjC(senderAci),
            messageUniqueId: messageUniqueId,
            messageIdTimestamp: messageIdTimestamp,
            readTimestamp: timestamp
        )
    }

    var asLinkedDeviceViewedReceipt: OWSLinkedDeviceViewedReceipt? {
        guard let senderAci = senderAddress.aci else { return nil }
        return OWSLinkedDeviceViewedReceipt(
            senderAci: AciObjC(senderAci),
            messageUniqueId: messageUniqueId,
            messageIdTimestamp: messageIdTimestamp,
            viewedTimestamp: timestamp
        )
    }
}

// MARK: -

public extension OWSReceiptManager {

    private var toLinkedDevicesReadReceiptMapStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "OWSReceiptManager.toLinkedDevicesReadReceiptMapStore")
    }

    private var toLinkedDevicesViewedReceiptMapStore: SDSKeyValueStore {
        return SDSKeyValueStore(collection: "OWSReceiptManager.toLinkedDevicesViewedReceiptMapStore")
    }

    @objc
    func processReceiptsForLinkedDevices(completion: @escaping () -> Void) {
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

            guard let thread = TSContactThread.getOrCreateLocalThread(transaction: transaction) else {
                owsFailDebug("Missing thread.")
                return false
            }

            if !readReceiptsForLinkedDevices.isEmpty {
                let readReceiptsToSend = readReceiptsForLinkedDevices.compactMap { $0.asLinkedDeviceReadReceipt }
                if !readReceiptsToSend.isEmpty {
                    let message = OWSReadReceiptsForLinkedDevicesMessage(thread: thread, readReceipts: readReceiptsToSend, transaction: transaction)
                    self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                }
                self.toLinkedDevicesReadReceiptMapStore.removeAll(transaction: transaction)
            }

            if !viewedReceiptsForLinkedDevices.isEmpty {
                let viewedReceiptsToSend = viewedReceiptsForLinkedDevices.compactMap { $0.asLinkedDeviceViewedReceipt }
                if !viewedReceiptsToSend.isEmpty {
                    let message = OWSViewedReceiptsForLinkedDevicesMessage(thread: thread, viewedReceipts: viewedReceiptsToSend, transaction: transaction)
                    self.sskJobQueues.messageSenderJobQueue.add(message: message.asPreparer, transaction: transaction)
                }
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

    @objc
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

    @objc
    func enqueueLinkedDeviceViewedReceipt(forIncomingMessage message: TSIncomingMessage,
                                          transaction: SDSAnyWriteTransaction) {

        self.enqueueLinkedDeviceViewedReceipt(
            messageAuthorAddress: message.authorAddress,
            messageUniqueId: message.uniqueId,
            messageIdTimestamp: message.timestamp,
            transaction: transaction
        )
    }

    @objc
    func enqueueLinkedDeviceViewedReceipt(forOutgoingMessage message: TSOutgoingMessage,
                                          transaction: SDSAnyWriteTransaction) {

        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aciAddress else {
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

    @objc
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

    @objc
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

    @objc
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
            tx: transaction
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

    private func processReceiptsFromLinkedDevice<T>(
        _ receiptProtos: [T],
        senderAci: KeyPath<T, String?>,
        messageTimestamp: KeyPath<T, UInt64>,
        tx: SDSAnyWriteTransaction,
        markMessage: (TSMessage) -> Void,
        markStoryMessage: (StoryMessage) -> Void
    ) -> [T] {
        var earlyReceiptProtos = [T]()
        for receiptProto in receiptProtos {
            guard let senderAci = Aci.parseFrom(aciString: receiptProto[keyPath: senderAci]) else {
                owsFailDebug("Missing ACI.")
                continue
            }
            let messageTimestamp = receiptProto[keyPath: messageTimestamp]
            guard messageTimestamp > 0, SDS.fitsInInt64(messageTimestamp) else {
                owsFailDebug("Invalid timestamp.")
                continue
            }

            let interactions: [TSInteraction]
            do {
                interactions = try InteractionFinder.interactions(
                    withTimestamp: messageTimestamp,
                    filter: { _ in true },
                    transaction: tx
                )
            } catch {
                owsFailDebug("Error loading interactions: \(error)")
                interactions = []
            }

            let messages = interactions.compactMap({ $0 as? TSMessage }).filter {
                switch $0 {
                case is TSOutgoingMessage:
                    return senderAci == DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)?.aci
                case let incomingMessage as TSIncomingMessage:
                    return senderAci == incomingMessage.authorAddress.serviceId
                default:
                    return false
                }
            }

            Logger.info("Handling receipts from linked device for \(messages.count) messages with timestamp \(messageTimestamp)")

            if !messages.isEmpty {
                messages.forEach { markMessage($0) }
                continue
            }

            let storyMessage = StoryFinder.story(timestamp: messageTimestamp, author: senderAci, transaction: tx)
            if let storyMessage {
                markStoryMessage(storyMessage)
                continue
            }

            earlyReceiptProtos.append(receiptProto)
        }
        return earlyReceiptProtos
    }

    func processReadReceiptsFromLinkedDevice(
        _ readReceiptProtos: [SSKProtoSyncMessageRead],
        readTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) -> [SSKProtoSyncMessageRead] {
        return processReceiptsFromLinkedDevice(
            readReceiptProtos,
            senderAci: \.senderAci,
            messageTimestamp: \.timestamp,
            tx: tx,
            markMessage: {
                markMessageAsReadOnLinkedDevice($0, readTimestamp: readTimestamp, tx: tx)
            },
            markStoryMessage: {
                $0.markAsRead(at: readTimestamp, circumstance: .onLinkedDevice, transaction: tx)
            }
        )
    }

    func processViewedReceiptsFromLinkedDevice(
        _ viewedReceiptProtos: [SSKProtoSyncMessageViewed],
        viewedTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) -> [SSKProtoSyncMessageViewed] {
        return processReceiptsFromLinkedDevice(
            viewedReceiptProtos,
            senderAci: \.senderAci,
            messageTimestamp: \.timestamp,
            tx: tx,
            markMessage: {
                markMessageAsViewedOnLinkedDevice($0, viewedTimestamp: viewedTimestamp, tx: tx)
            },
            markStoryMessage: {
                $0.markAsViewed(at: viewedTimestamp, circumstance: .onLinkedDevice, transaction: tx)
            }
        )
    }

    // MARK: - Mark as read

    func markAsReadLocally(beforeSortId sortId: UInt64,
                           thread: TSThread,
                           hasPendingMessageRequest: Bool,
                           completion: @escaping () -> Void) {
        DispatchQueue.global().async {
            let interactionFinder = InteractionFinder(threadUniqueId: thread.uniqueId)

            let hasMessagesToMarkRead = self.databaseStorage.read { transaction in
                return interactionFinder.hasMessagesToMarkRead(
                    beforeSortId: sortId,
                    transaction: transaction
                )
            }
            guard hasMessagesToMarkRead else {
                // Avoid unnecessary writes.
                DispatchQueue.main.async(execute: completion)
                return
            }

            let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci
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
            Logger.info("Marking received messages and sent messages with reactions as read locally\(logSuffix) (in batches of \(maxBatchSize))")

            var batchQuotaRemaining: Int
            repeat {
                batchQuotaRemaining = maxBatchSize
                self.databaseStorage.write { transaction in
                    var cursor = interactionFinder.fetchUnreadMessages(beforeSortId: sortId,
                                                                       transaction: transaction)
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
                        transaction: transaction)

                    do {
                        while batchQuotaRemaining > 0, let message = try cursor.next() {
                            message.markUnreadReactionsAsRead(transaction: transaction)

                            if let localAci {
                                let receipt = OWSLinkedDeviceReadReceipt(
                                    senderAci: AciObjC(localAci),
                                    messageUniqueId: message.uniqueId,
                                    messageIdTimestamp: message.timestamp,
                                    readTimestamp: readTimestamp
                                )
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
                                                           transaction: transaction)
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

    func markMessageAsReadOnLinkedDevice(
        _ message: TSMessage,
        readTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) {
        switch message {
        case let incomingMessage as TSIncomingMessage:
            guard let thread = message.thread(tx: tx) else {
                break
            }
            let circumstance = linkedDeviceReceiptCircumstance(for: thread, tx: tx)

            // Always re-mark the message as read to ensure any earlier read time is
            // applied to disappearing messages.
            incomingMessage.markAsRead(
                atTimestamp: readTimestamp,
                thread: thread,
                circumstance: circumstance,
                // Do not automatically clear notifications; we will do so below.
                shouldClearNotifications: false,
                transaction: tx
            )

            // Also mark any unread messages appearing earlier in the thread as read.
            let markedAsReadIds = self.markAsRead(
                beforeSortId: incomingMessage.sortId,
                thread: thread,
                readTimestamp: readTimestamp,
                circumstance: circumstance,
                // Do not automatically clear notifications; we will do so below.
                shouldClearNotifications: false,
                transaction: tx
            )

            // Clear notifications for all the now-marked-read messages in one batch.
            notificationPresenter.cancelNotifications(messageIds: [incomingMessage.uniqueId] + markedAsReadIds)
        case let outgoingMessage as TSOutgoingMessage:
            // Outgoing messages are always "read", but if we get a receipt
            // from our linked device about one that indicates that any reactions
            // we received on this message should also be marked read.
            outgoingMessage.markUnreadReactionsAsRead(transaction: tx)
        default:
            owsFailDebug("Message was neither incoming nor outgoing!")
        }
    }

    func markMessageAsViewedOnLinkedDevice(_ message: TSMessage, viewedTimestamp: UInt64, tx: SDSAnyWriteTransaction) {
        if message.giftBadge != nil {
            message.anyUpdateMessage(transaction: tx) { obj in
                switch obj {
                case let incomingMessage as TSIncomingMessage:
                    incomingMessage.giftBadge?.redemptionState = .redeemed
                case let outgoingMessage as TSOutgoingMessage:
                    outgoingMessage.giftBadge?.redemptionState = .opened
                default:
                    owsFailDebug("Unexpected giftBadge message")
                }
            }
            return
        }

        switch message {
        case let incomingMessage as TSIncomingMessage:
            guard let thread = message.thread(tx: tx) else {
                break
            }
            let circumstance = linkedDeviceReceiptCircumstance(for: thread, tx: tx)
            incomingMessage.markAsViewed(
                atTimestamp: viewedTimestamp,
                thread: thread,
                circumstance: circumstance,
                transaction: tx
            )
        default:
            break
        }
    }

    private func linkedDeviceReceiptCircumstance(for thread: TSThread, tx: SDSAnyReadTransaction) -> OWSReceiptCircumstance {
        if thread.hasPendingMessageRequest(transaction: tx) {
            return .onLinkedDeviceWhilePendingMessageRequest
        } else {
            return .onLinkedDevice
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

// MARK: -

extension OWSReceiptManager {
    /// Fetches outgoing messages that need to have incoming receipts applied to them.
    private func outgoingMessages(sentAt timestamp: UInt64, tx: SDSAnyReadTransaction) -> [TSOutgoingMessage] {
        let interactions: [TSInteraction]
        do {
            interactions = try InteractionFinder.interactions(withTimestamp: timestamp, filter: { _ in true }, transaction: tx)
        } catch {
            owsFailDebug("Error loading interactions: \(error)")
            interactions = []
        }

        let result = interactions.compactMap({ $0 as? TSOutgoingMessage })

        if result.count > 1 {
            Logger.error("More than one matching message with timestamp: \(timestamp)")
        }

        return result
    }

    /// Processes a bundle of `sentTimestamps` from a receipt from another user.
    ///
    /// - Returns: A subset of `sentTimestamps` that don't have corresponding
    /// messages. These should be persisted by the caller since the messages
    /// might arrive after the receipts.
    private func processReceiptsForMessages(
        sentAt sentTimestamps: [NSNumber],
        tx: SDSAnyReadTransaction,
        handleTimestampMessages: (UInt64, [TSOutgoingMessage]) -> Bool
    ) -> [NSNumber] {
        return sentTimestamps.filter {
            let sentTimestamp = $0.uint64Value
            let messages = outgoingMessages(sentAt: sentTimestamp, tx: tx)
            return !handleTimestampMessages(sentTimestamp, messages)
        }
    }

    /// Processes a bundle of delivery receipts from another user.
    ///
    /// - Returns: A subset of `sentTimestamps` that don't have corresponding
    /// messages. These should be persisted by the caller since the messages
    /// might arrive after the receipts.
    @objc
    func processDeliveryReceipts(
        from recipientServiceId: ServiceIdObjC,
        recipientDeviceId: UInt32,
        sentTimestamps: [NSNumber],
        deliveryTimestamp: UInt64,
        context: DeliveryReceiptContext,
        tx: SDSAnyWriteTransaction
    ) -> [NSNumber] {
        return processReceiptsForMessages(sentAt: sentTimestamps, tx: tx) { _, messages in
            if !messages.isEmpty {
                for message in messages {
                    message.update(
                        withDeliveredRecipient: SignalServiceAddress(recipientServiceId.wrappedValue),
                        deviceId: recipientDeviceId,
                        deliveryTimestamp: deliveryTimestamp,
                        context: context,
                        tx: tx
                    )
                }
                return true
            }
            return false
        }
    }

    /// Processes a bundle of read receipts from another user.
    ///
    /// - Returns: A subset of `sentTimestamps` that don't have corresponding
    /// messages. These should be persisted by the caller since the messages
    /// might arrive after the receipts.
    @objc
    func processReadReceipts(
        from recipientAci: AciObjC,
        recipientDeviceId: UInt32,
        sentTimestamps: [NSNumber],
        readTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) -> [NSNumber] {
        guard self.areReadReceiptsEnabled() else {
            return []
        }
        return processReceiptsForMessages(sentAt: sentTimestamps, tx: tx) { _, messages in
            if !messages.isEmpty {
                // TODO: We might also need to "mark as read by recipient" any older messages
                // from us in that thread. Or maybe this state should hang on the thread?
                for message in messages {
                    message.update(
                        withReadRecipient: SignalServiceAddress(recipientAci.wrappedValue),
                        deviceId: recipientDeviceId,
                        readTimestamp: readTimestamp,
                        tx: tx
                    )
                }
                return true
            }
            return false
        }
    }

    /// Processes a bundle of viewed receipts from another user.
    ///
    /// - Returns: A subset of `sentTimestamps` that don't have corresponding
    /// messages. These should be persisted by the caller since the messages
    /// might arrive after the receipts.
    @objc
    func processViewedReceipts(
        from recipientAci: AciObjC,
        recipientDeviceId: UInt32,
        sentTimestamps: [NSNumber],
        viewedTimestamp: UInt64,
        tx: SDSAnyWriteTransaction
    ) -> [NSNumber] {
        return processReceiptsForMessages(sentAt: sentTimestamps, tx: tx) { sentTimestamp, messages in
            if !messages.isEmpty {
                if self.areReadReceiptsEnabled() {
                    for message in messages {
                        message.update(
                            withViewedRecipient: SignalServiceAddress(recipientAci.wrappedAciValue),
                            deviceId: recipientDeviceId,
                            viewedTimestamp: viewedTimestamp,
                            tx: tx
                        )
                    }
                } else {
                    Logger.info("Ignoring incoming receipt message as read receipts are disabled.")
                }
                return true
            }
            let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read)!.aci
            let storyMessage = StoryFinder.story(timestamp: sentTimestamp, author: localAci, transaction: tx)
            if let storyMessage {
                if StoryManager.areViewReceiptsEnabled {
                    storyMessage.markAsViewed(
                        at: viewedTimestamp,
                        by: recipientAci.wrappedAciValue,
                        transaction: tx
                    )
                } else {
                    Logger.info("Ignoring incoming story receipt message as view receipts are disabled.")
                }
                return true
            }
            return false
        }
    }
}
