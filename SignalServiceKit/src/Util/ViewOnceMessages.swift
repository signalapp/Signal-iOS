//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

@objc
public class ViewOnceMessages: NSObject {

    @objc
    public required override init() {
        super.init()

        if CurrentAppContext().isMainApp {
            AppReadiness.runNowOrWhenAppDidBecomeReadySync {
                Self.appDidBecomeReady()
            }
        }
    }

    // MARK: - Events

    private class func nowMs() -> UInt64 {
        return NSDate.ows_millisecondTimeStamp()
    }

    private class func appDidBecomeReady() {
        AssertIsOnMainThread()

        DispatchQueue.global().async {
            self.checkForAutoCompletion()
        }
    }

    // "Check for auto-completion", e.g. complete messages whether or
    // not they have been read after N days.  Also complete outgoing
    // sent messages. We need to repeat this check periodically while
    // the app is running.
    private class func checkForAutoCompletion() {
        // Find all view-once messages which are not yet complete.
        // Complete messages if necessary.
        databaseStorage.write { (transaction) in
            let messages = ViewOnceMessageFinder()
                .allMessagesWithViewOnceMessage(transaction: transaction)
            for message in messages {
                completeIfNecessary(message: message, transaction: transaction)
            }
        }

        // We need to "check for auto-completion" once per day.
        DispatchQueue.global().asyncAfter(wallDeadline: .now() + kDayInterval) {
            self.checkForAutoCompletion()
        }
    }

    @objc
    public class func completeIfNecessary(message: TSMessage,
                                          transaction: SDSAnyWriteTransaction) {

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

    // We auto-complete messages after 30 days, even if the user hasn't seen them.
    private class func shouldMessageAutoComplete(_ message: TSMessage) -> Bool {
        let autoCompleteDeadlineMs = min(message.timestamp, message.receivedAtTimestamp) + 30 * kDayInMs
        return nowMs() >= autoCompleteDeadlineMs
    }

    @objc
    public class func markAsComplete(message: TSMessage,
                                     sendSyncMessages: Bool,
                                     transaction: SDSAnyWriteTransaction) {
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

    private class func sendSyncMessage(forMessage message: TSMessage,
                                       transaction: SDSAnyWriteTransaction) {
        guard let senderAddress = senderAddress(forMessage: message) else {
            owsFailDebug("Could not send sync message; no local number.")
            return
        }
        guard let thread = TSContactThread.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing thread.")
            return
        }
        let readTimestamp: UInt64 = nowMs()

        let syncMessage = OWSViewOnceMessageReadSyncMessage(thread: thread,
                                                            senderAddress: senderAddress,
                                                            message: message,
                                                            readTimestamp: readTimestamp,
                                                            transaction: transaction)
        sskJobQueues.messageSenderJobQueue.add(message: syncMessage.asPreparer, transaction: transaction)

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
        transaction: SDSAnyWriteTransaction
    ) -> ViewOnceSyncMessageProcessingResult {
        guard let messageSender = Aci.parseFrom(aciString: message.senderAci) else {
            owsFailDebug("Invalid messageSender.")
            return .invalidSyncMessage
        }
        let messageIdTimestamp: UInt64 = message.timestamp
        guard messageIdTimestamp > 0, SDS.fitsInInt64(messageIdTimestamp) else {
            owsFailDebug("Invalid messageIdTimestamp.")
            return .invalidSyncMessage
        }

        let filter = { (interaction: TSInteraction) -> Bool in
            guard interaction.timestamp == messageIdTimestamp else {
                owsFailDebug("Timestamps don't match: \(interaction.timestamp) != \(messageIdTimestamp)")
                return false
            }
            guard let message = interaction as? TSMessage else {
                return false
            }
            guard let senderAddress = senderAddress(forMessage: message) else {
                owsFailDebug("Could not process sync message; no local number.")
                return false
            }
            guard senderAddress.serviceId == messageSender else {
                return false
            }
            guard message.isViewOnceMessage else {
                return false
            }
            return true
        }
        let interactions: [TSInteraction]
        do {
            interactions = try InteractionFinder.interactions(withTimestamp: messageIdTimestamp, filter: filter, transaction: transaction)
        } catch {
            owsFailDebug("Couldn't find interactions: \(error)")
            return .invalidSyncMessage
        }
        guard interactions.count > 0 else {
            return .associatedMessageMissing(senderAci: messageSender, associatedMessageTimestamp: messageIdTimestamp)
        }
        if interactions.count > 1 {
            owsFailDebug("More than one message from the same sender with the same timestamp found.")
        }
        for interaction in interactions {
            guard let message = interaction as? TSMessage else {
                owsFailDebug("Invalid interaction: \(type(of: interaction))")
                continue
            }
            // Mark as complete.
            markAsComplete(message: message,
                           sendSyncMessages: false,
                           transaction: transaction)
        }
        return .success
    }

    private class func senderAddress(forMessage message: TSMessage) -> SignalServiceAddress? {

        if let incomingMessage = message as? TSIncomingMessage {
            return incomingMessage.authorAddress
        } else if message as? TSOutgoingMessage != nil {
            guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress else {
                owsFailDebug("Could not process sync message; no local number.")
                return nil
            }
            // We also need to send and receive "per-message expiration read" sync
            // messages for outgoing messages, unlike normal read receipts.
            return localAddress
        } else {
            owsFailDebug("Unexpected message type.")
            return nil
        }
    }
}

// MARK: -

private class ViewOnceMessageFinder {
    public func allMessagesWithViewOnceMessage(transaction: SDSAnyReadTransaction) -> [TSMessage] {
        var result: [TSMessage] = []
        self.enumerateAllIncompleteViewOnceMessages(transaction: transaction) { message in
            result.append(message)
        }
        return result
    }

    private func enumerateAllIncompleteViewOnceMessages(
        transaction: SDSAnyReadTransaction,
        block: (TSMessage) -> Void
    ) {
        let sql = """
            SELECT *
            FROM \(InteractionRecord.databaseTableName)
            WHERE \(interactionColumn: .isViewOnceMessage) IS NOT NULL
            AND \(interactionColumn: .isViewOnceMessage) == TRUE
            AND \(interactionColumn: .isViewOnceComplete) IS NOT NULL
            AND \(interactionColumn: .isViewOnceComplete) == FALSE
        """
        let cursor = TSInteraction.grdbFetchCursor(
            sql: sql,
            transaction: transaction.unwrapGrdbRead
        )

        // GRDB TODO make cursor.next fail hard to remove this `try!`
        while let next = try! cursor.next() {
            guard let message = next as? TSMessage else {
                owsFailDebug("expecting message but found: \(next)")
                return
            }

            guard
                message.isViewOnceMessage,
                !message.isViewOnceComplete
            else {
                owsFailDebug("expecting incomplete view-once message but found: \(message)")
                return
            }

            block(message)
        }
    }
}
