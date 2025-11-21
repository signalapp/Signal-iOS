//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

@objc
public class ViewOnceMessages: NSObject {

    private override init() {
        super.init()
    }

    // MARK: - Events

    private class func nowMs() -> UInt64 {
        return NSDate.ows_millisecondTimeStamp()
    }

    // "Check for auto-completion", e.g. complete messages whether or
    // not they have been read after N days.  Also complete outgoing
    // sent messages.
    public static func expireIfNecessary() async throws(CancellationError) {
        // Find all view-once messages which are not yet complete.
        // Complete messages if necessary.
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        var afterRowId: Int64?
        repeat {
            if Task.isCancelled {
                throw CancellationError()
            }
            await databaseStorage.awaitableWrite { tx in
                let messages: [TSMessage]
                (messages, afterRowId) = ViewOnceMessageFinder().fetchSomeIncompleteViewOnceMessages(after: afterRowId, limit: 100, tx: tx)
                if !messages.isEmpty {
                    Logger.info("Checking \(messages.count) view once message(s) for auto-expiration.")
                }
                for message in messages {
                    completeIfNecessary(message: message, transaction: tx)
                }
            }
        } while afterRowId != nil
    }

    @objc
    public class func completeIfNecessary(message: TSMessage,
                                          transaction: DBWriteTransaction) {

        guard message.isViewOnceMessage,
            !message.isViewOnceComplete else {
            return
        }

        // If message should auto-complete, complete.
        guard !shouldMessageAutoComplete(message) else {
            markAsComplete(message: message,
                           sendSyncMessages: true,
                           transaction: transaction)
            return
        }

        // If outgoing message and is "sent", complete.
        guard !isOutgoingSent(message: message) else {
            markAsComplete(message: message,
                           sendSyncMessages: true,
                           transaction: transaction)
            return
        }

        // Message should not yet complete.
    }

    private class func isOutgoingSent(message: TSMessage) -> Bool {
        guard message.isViewOnceMessage else {
            owsFailDebug("Unexpected message.")
            return false
        }
        // If outgoing message and is "sent", complete.
        guard let outgoingMessage = message as? TSOutgoingMessage else {
            return false
        }
        guard outgoingMessage.messageState == .sent else {
            return false
        }
        return true
    }

    // We auto-complete messages after N days, even if the user hasn't seen them.
    private class func shouldMessageAutoComplete(_ message: TSMessage) -> Bool {
        let autoCompleteDeadlineMs = min(message.timestamp, message.receivedAtTimestamp) + RemoteConfig.current.messageQueueTimeMs
        return nowMs() >= autoCompleteDeadlineMs
    }

    @objc
    public class func markAsComplete(message: TSMessage,
                                     sendSyncMessages: Bool,
                                     transaction: DBWriteTransaction) {
        guard message.isViewOnceMessage else {
            owsFailDebug("Not a view-once message.")
            return
        }
        guard !message.isViewOnceComplete else {
            // Already completed, no need to complete again.
            return
        }
        message.updateWithViewOnceCompleteAndRemoveRenderableContent(with: transaction)

        if sendSyncMessages {
            sendSyncMessage(forMessage: message, transaction: transaction)
        }
    }

    // MARK: - Sync Messages

    private class func sendSyncMessage(forMessage message: TSMessage, transaction: DBWriteTransaction) {
        guard let senderAci = senderAci(forMessage: message, tx: transaction) else {
            return
        }
        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing thread.")
            return
        }
        let readTimestamp: UInt64 = nowMs()

        let syncMessage = OWSViewOnceMessageReadSyncMessage(
            localThread: thread,
            senderAci: AciObjC(senderAci),
            message: message,
            readTimestamp: readTimestamp,
            transaction: transaction
        )
        // this is the sync that we viewed; it doesn't have the attachment on it.
        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: syncMessage
        )
        SSKEnvironment.shared.messageSenderJobQueueRef.add(message: preparedMessage, transaction: transaction)

        if let incomingMessage = message as? TSIncomingMessage {
            let circumstance: OWSReceiptCircumstance =
                thread.hasPendingMessageRequest(transaction: transaction)
                ? .onThisDeviceWhilePendingMessageRequest
                : .onThisDevice
            incomingMessage.markAsViewed(
                atTimestamp: readTimestamp,
                thread: thread,
                circumstance: circumstance,
                transaction: transaction
            )
        }
    }

    public enum ViewOnceSyncMessageProcessingResult {
        case associatedMessageMissing(senderAci: Aci, associatedMessageTimestamp: UInt64)
        case invalidSyncMessage
        case success
    }

    public class func processIncomingSyncMessage(
        _ message: SSKProtoSyncMessageViewOnceOpen,
        envelope: SSKProtoEnvelope,
        transaction: DBWriteTransaction
    ) -> ViewOnceSyncMessageProcessingResult {
        guard let messageSender = Aci.parseFrom(
            serviceIdBinary: message.senderAciBinary,
            serviceIdString: message.senderAci,
        ) else {
            owsFailDebug("Invalid messageSender.")
            return .invalidSyncMessage
        }
        let messageIdTimestamp: UInt64 = message.timestamp
        guard messageIdTimestamp > 0, SDS.fitsInInt64(messageIdTimestamp) else {
            owsFailDebug("Invalid messageIdTimestamp.")
            return .invalidSyncMessage
        }

        let filter = { (interaction: TSInteraction) -> TSMessage? in
            guard let message = interaction as? TSMessage else {
                return nil
            }
            guard let senderAci = senderAci(forMessage: message, tx: transaction) else {
                return nil
            }
            guard senderAci == messageSender else {
                return nil
            }
            guard message.isViewOnceMessage else {
                return nil
            }
            return message
        }
        let messages: [TSMessage]
        do {
            messages = try InteractionFinder.fetchInteractions(
                timestamp: messageIdTimestamp,
                transaction: transaction
            ).compactMap(filter)
        } catch {
            owsFailDebug("Couldn't find interactions: \(error)")
            return .invalidSyncMessage
        }
        guard messages.count > 0 else {
            return .associatedMessageMissing(senderAci: messageSender, associatedMessageTimestamp: messageIdTimestamp)
        }
        if messages.count > 1 {
            owsFailDebug("More than one message from the same sender with the same timestamp found.")
        }
        for message in messages {
            // Mark as complete.
            markAsComplete(message: message,
                           sendSyncMessages: false,
                           transaction: transaction)
        }
        return .success
    }

    private static func senderAci(forMessage message: TSMessage, tx: DBReadTransaction) -> Aci? {
        if let incomingMessage = message as? TSIncomingMessage {
            return incomingMessage.authorAddress.aci
        } else if message is TSOutgoingMessage {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                owsFailDebug("Could not process sync message; no local number.")
                return nil
            }
            // We also need to send and receive "per-message expiration read" sync
            // messages for outgoing messages, unlike normal read receipts.
            return localIdentifiers.aci
        } else {
            owsFailDebug("Unexpected message type.")
            return nil
        }
    }
}

// MARK: -

private class ViewOnceMessageFinder {
    func fetchSomeIncompleteViewOnceMessages(after rowId: Int64?, limit: Int, tx: DBReadTransaction) -> ([TSMessage], mightHaveMoreAfter: Int64?) {
        var results: [TSMessage] = []

        let cursor: TSInteractionCursor
        if let rowId {
            cursor = TSInteraction.grdbFetchCursor(
                sql: """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                \(DEBUG_INDEXED_BY("Interaction_incompleteViewOnce_partial"))
                WHERE \(interactionColumn: .isViewOnceMessage) = 1
                AND \(interactionColumn: .isViewOnceComplete) = 0
                AND \(interactionColumn: .id) > ?
                ORDER BY \(interactionColumn: .id)
                """,
                arguments: [rowId],
                transaction: tx
            )
        } else {
            cursor = TSInteraction.grdbFetchCursor(
                sql: """
                SELECT *
                FROM \(InteractionRecord.databaseTableName)
                \(DEBUG_INDEXED_BY("Interaction_incompleteViewOnce_partial"))
                WHERE \(interactionColumn: .isViewOnceMessage) = 1
                AND \(interactionColumn: .isViewOnceComplete) = 0
                ORDER BY \(interactionColumn: .id)
                """,
                transaction: tx
            )
        }

        while let next = try! cursor.next() {
            guard let message = next as? TSMessage else {
                owsFailDebug("expecting message but found: \(next)")
                continue
            }
            results.append(message)
            if results.count >= limit {
                return (results, mightHaveMoreAfter: message.sqliteRowId!)
            }
        }
        return (results, mightHaveMoreAfter: nil)
    }
}
