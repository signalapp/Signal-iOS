//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

@objc
public class ViewOnceMessages: NSObject {

    // MARK: - Dependencies

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private class var messageSenderJobQueue: MessageSenderJobQueue {
        return SSKEnvironment.shared.messageSenderJobQueue
    }

    private class var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: - Events

    private class func nowMs() -> UInt64 {
        return NSDate.ows_millisecondTimeStamp()
    }

    @objc
    public class func appDidBecomeReady() {
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
            let messages = AnyViewOnceMessageFinder().allMessagesWithViewOnceMessage(transaction: transaction)
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
        guard let thread = TSAccountManager.getOrCreateLocalThread(transaction: transaction) else {
            owsFailDebug("Missing thread.")
            return
        }
        let messageIdTimestamp: UInt64 = message.timestamp
        let readTimestamp: UInt64 = nowMs()

        let syncMessage = OWSViewOnceMessageReadSyncMessage(thread: thread,
                                                            senderAddress: senderAddress,
                                                                 messageIdTimestamp: messageIdTimestamp,
                                                                 readTimestamp: readTimestamp)
        messageSenderJobQueue.add(message: syncMessage.asPreparer, transaction: transaction)
    }

    @objc
    public class func processIncomingSyncMessage(_ message: SSKProtoSyncMessageViewOnceOpen,
                                                 envelope: SSKProtoEnvelope,
                                                 transaction: SDSAnyWriteTransaction) {

        if tryToApplyIncomingSyncMessage(message,
                                         envelope: envelope,
                                         transaction: transaction) {
            return
        }

        // Unpack and verify the proto & envelope contents.
        guard let senderAddress = message.senderAddress, senderAddress.isValid else {
            owsFailDebug("Invalid senderAddress.")
            return
        }
        let messageIdTimestamp: UInt64 = message.timestamp
        guard messageIdTimestamp > 0 else {
            owsFailDebug("Invalid messageIdTimestamp.")
            return
        }
        let readTimestamp: UInt64 = envelope.timestamp
        guard readTimestamp > 0 else {
            owsFailDebug("Invalid readTimestamp.")
            return
        }

        // Persist this "view-once read receipt".
        let key = readReceiptKey(senderAddress: senderAddress, messageIdTimestamp: messageIdTimestamp)
        store.setUInt64(readTimestamp, key: key, transaction: transaction)
    }

    // Returns true IFF the read receipt is applied to an existing message.
    private class func tryToApplyIncomingSyncMessage(_ message: SSKProtoSyncMessageViewOnceOpen,
                                                     envelope: SSKProtoEnvelope,
                                                     transaction: SDSAnyWriteTransaction) -> Bool {
        let messageSenderAddress = message.senderAddress
        let messageIdTimestamp: UInt64 = message.timestamp

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
            guard senderAddress == messageSenderAddress else {
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
            return false
        }
        guard interactions.count > 0 else {
            return false
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
        return true
    }

    @objc
    public class func applyEarlyReadReceipts(forIncomingMessage message: TSIncomingMessage,
                                             transaction: SDSAnyWriteTransaction) {
        guard message.isViewOnceMessage else {
            return
        }
        guard let senderAddress = senderAddress(forMessage: message) else {
            owsFailDebug("Could not apply early read receipts; no local number.")
            return
        }
        let messageIdTimestamp: UInt64 = message.timestamp

        // Check for persisted "view-once read receipt".
        let key = readReceiptKey(senderAddress: senderAddress, messageIdTimestamp: messageIdTimestamp)
        guard store.hasValue(forKey: key, transaction: transaction) else {
            // No early read receipt applies, abort.
            return
        }

        // Remove persisted "view-once read receipt".
        store.removeValue(forKey: key, transaction: transaction)

        // Mark as complete.
        markAsComplete(message: message,
                       sendSyncMessages: false,
                       transaction: transaction)
    }

    private class func senderAddress(forMessage message: TSMessage) -> SignalServiceAddress? {

        if let incomingMessage = message as? TSIncomingMessage {
            return incomingMessage.authorAddress
        } else if message as? TSOutgoingMessage != nil {
            guard let localAddress = tsAccountManager.localAddress else {
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

    private static let store = SDSKeyValueStore(collection: "viewOnceMessages")

    private class func readReceiptKey(senderAddress: SignalServiceAddress,
                                      messageIdTimestamp: UInt64) -> String {
        return "\(senderAddress.stringForDisplay).\(messageIdTimestamp)"
    }
}

// MARK: -

public protocol ViewOnceMessageFinder {
    associatedtype ReadTransaction

    typealias EnumerateTSMessageBlock = (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void

    func allMessagesWithViewOnceMessage(transaction: ReadTransaction) -> [TSMessage]
    func enumerateAllIncompleteViewOnceMessages(transaction: ReadTransaction, block: @escaping EnumerateTSMessageBlock)
}

// MARK: -

extension ViewOnceMessageFinder {

    public func allMessagesWithViewOnceMessage(transaction: ReadTransaction) -> [TSMessage] {
        var result: [TSMessage] = []
        self.enumerateAllIncompleteViewOnceMessages(transaction: transaction) { message, _ in
            result.append(message)
        }
        return result
    }
}

// MARK: -

public class AnyViewOnceMessageFinder {
    lazy var grdbAdapter = GRDBViewOnceMessageFinder()
    lazy var yapAdapter = YAPDBViewOnceMessageFinder()
}

// MARK: -

extension AnyViewOnceMessageFinder: ViewOnceMessageFinder {
    public func enumerateAllIncompleteViewOnceMessages(transaction: SDSAnyReadTransaction, block: @escaping EnumerateTSMessageBlock) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            grdbAdapter.enumerateAllIncompleteViewOnceMessages(transaction: grdbRead, block: block)
        case .yapRead(let yapRead):
            yapAdapter.enumerateAllIncompleteViewOnceMessages(transaction: yapRead, block: block)
        }
    }
}

// MARK: -

class GRDBViewOnceMessageFinder: ViewOnceMessageFinder {
    func enumerateAllIncompleteViewOnceMessages(transaction: GRDBReadTransaction, block: @escaping EnumerateTSMessageBlock) {

        let sql = """
        SELECT * FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .isViewOnceMessage) IS NOT NULL
        AND \(interactionColumn: .isViewOnceMessage) == TRUE
        AND \(interactionColumn: .isViewOnceComplete) IS NOT NULL
        AND \(interactionColumn: .isViewOnceComplete) == FALSE
        """

        let cursor = TSInteraction.grdbFetchCursor(sql: sql,
                                                   transaction: transaction)
        var stop: ObjCBool = false
        // GRDB TODO make cursor.next fail hard to remove this `try!`
        while let next = try! cursor.next() {
            guard let message = next as? TSMessage else {
                owsFailDebug("expecting message but found: \(next)")
                return
            }
            guard message.isViewOnceMessage,
                !message.isViewOnceComplete else {
                    owsFailDebug("expecting incomplete view-once message but found: \(message)")
                    return
            }
            block(message, &stop)
            if stop.boolValue {
                return
            }
        }
    }
}

// MARK: -

class YAPDBViewOnceMessageFinder: ViewOnceMessageFinder {
    public func enumerateAllIncompleteViewOnceMessages(transaction: YapDatabaseReadTransaction, block: @escaping EnumerateTSMessageBlock) {
        guard let dbView = TSDatabaseView.incompleteViewOnceMessagesDatabaseView(transaction) as? YapDatabaseViewTransaction else {
            owsFailDebug("Couldn't load db view.")
            return
        }

        dbView.safe_enumerateKeysAndObjects(inGroup: TSIncompleteViewOnceMessagesGroup, extensionName: TSIncompleteViewOnceMessagesDatabaseViewExtensionName) { (_: String, _: String, object: Any, _: UInt, stopPointer: UnsafeMutablePointer<ObjCBool>) in
            guard let message = object as? TSMessage else {
                owsFailDebug("Invalid database entity: \(type(of: object)).")
                return
            }
            guard message.isViewOnceMessage,
                !message.isViewOnceComplete else {
                    owsFailDebug("expecting incomplete view-once message but found: \(message)")
                return
            }
            block(message, stopPointer)
        }
    }
}
