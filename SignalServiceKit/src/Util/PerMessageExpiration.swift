//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

// Unlike per-conversation expiration, per-message expiration has
// short expiration times and the countdown is manually initiated.
// There should be very few countdowns in flight at a time.
// Therefore we can adopt a much simpler approach to countdown
// logic and use async dispatch for each countdown.
@objc
public class PerMessageExpiration: NSObject {

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

    // MARK: - Constants

    @objc
    public static let kExpirationDurationSeconds: UInt32 = 10

    // MARK: -

    @objc
    public class func startPerMessageExpiration(forMessage message: TSMessage,
                                                transaction: SDSAnyWriteTransaction) {
        AssertIsOnMainThread()

        guard message.hasPerMessageExpiration else {
            owsFailDebug("Message does not have per-message expiration.")
            return
        }

        // Start expiration using "now" as the read time.
        startPerMessageExpiration(forMessage: message,
                                  readTimestamp: nowMs(),
                                  sendSyncMessages: true,
                                  transaction: transaction)
    }

    private class func startPerMessageExpiration(forMessage message: TSMessage,
                                                 readTimestamp: UInt64,
                                                 sendSyncMessages: Bool,
                                                 transaction: SDSAnyWriteTransaction) {

        // Make sure that timestamp is not later than now.
        let timestamp = min(readTimestamp, nowMs())

        if !message.hasPerMessageExpirationStarted {
            // Mark the countdown as begun.
            message.updateWithPerMessageExpireStarted(at: timestamp,
                                                      transaction: transaction)

            if sendSyncMessages {
                sendSyncMessage(forMessage: message, transaction: transaction)
            }
        } else if message.perMessageExpireStartedAt > timestamp {
            // Update the "countdown start" to reflect timestamp,
            // which is earlier than the current value.
            message.updateWithPerMessageExpireStarted(at: timestamp,
                                                      transaction: transaction)
        } else {
            owsFailDebug("Per-message expiration countdown already begun.")
        }

        schedulePerMessageExpiration(forMessage: message,
                                     transaction: transaction)
    }

    private class func schedulePerMessageExpiration(forMessage message: TSMessage,
                                                    transaction: SDSAnyWriteTransaction) {
        guard !hasExpirationCountdownCompleted(message: message) else {
            Logger.verbose("Expiring immediately.")
            // Message has expired; remove it immediately.
            completeExpiration(forMessage: message,
                               transaction: transaction)
            return
        }

        Logger.verbose("Scheduling expiration.")
        let delaySeconds: TimeInterval = Double(message.perMessageExpiresAt - nowMs()) / 1000
        DispatchQueue.global().asyncAfter(wallDeadline: .now() + delaySeconds) {
            databaseStorage.write { (transaction) in
                self.completeExpiration(forMessage: message,
                                        transaction: transaction)
            }
        }
    }

    // MARK: - Events

    private class func nowMs() -> UInt64 {
        return NSDate.ows_millisecondTimeStamp()
    }

    @objc
    public class func appDidBecomeReady() {
        AssertIsOnMainThread()

        DispatchQueue.global().async {
            self.checkForExpiration(shouldResumeNormalExpiration: true)
        }
    }

    // This does two things:
    //
    // * "Resume normal expiration", e.g. expire or schedule expiration
    //   for messages whose "per-message expiration" countdown has begun.
    //   We only need to do this on startup.
    // * "Check for auto-expiration", e.g. expire messages whether or
    //   not they have been read after N days.  We need to repeat this
    //   check periodically while the app is running.
    private class func checkForExpiration(shouldResumeNormalExpiration: Bool) {
        // Find all messages with per-message expiration whose countdown has begun.
        // Cull expired messages & resume countdown for others.
        databaseStorage.write { (transaction) in
            let messages = AnyPerMessageExpirationFinder().allMessagesWithPerMessageExpiration(transaction: transaction)
            for message in messages {
                if shouldMessageAutoExpire(message) {
                    completeExpiration(forMessage: message, transaction: transaction)
                } else if isOutgoingSent(message: message) {
                    completeExpiration(forMessage: message, transaction: transaction)
                } else if message.hasPerMessageExpirationStarted {
                    if shouldResumeNormalExpiration {
                        // If expiration is started, resume countdown.
                        schedulePerMessageExpiration(forMessage: message, transaction: transaction)
                    }
                }
            }
        }

        // We need to "check for auto-expiration" once per day.
        DispatchQueue.global().asyncAfter(wallDeadline: .now() + kDayInterval) {
            self.checkForExpiration(shouldResumeNormalExpiration: false)
        }
    }

    @objc
    public class func expireIfNecessary(message: TSMessage,
                                        transaction: SDSAnyWriteTransaction) {

        guard message.hasPerMessageExpiration else {
            return
        }

        // If message should auto-expire, expire.
        guard !shouldMessageAutoExpire(message) else {
            completeExpiration(forMessage: message, transaction: transaction)
            return
        }

        // If outgoing message and is "sent", expire.
        guard !isOutgoingSent(message: message) else {
            completeExpiration(forMessage: message, transaction: transaction)
            return
        }

        // If countdown has completed, expire.
        guard !hasExpirationCountdownCompleted(message: message) else {
            completeExpiration(forMessage: message, transaction: transaction)
            return
        }
    }

    private class func hasExpirationCountdownCompleted(message: TSMessage) -> Bool {
        return (message.hasPerMessageExpirationStarted &&
                message.perMessageExpiresAt <= nowMs())
    }

    private class func isOutgoingSent(message: TSMessage) -> Bool {
        // If outgoing message and is "sent", expire.
        guard let outgoingMessage = message as? TSOutgoingMessage else {
            return false
        }
        guard outgoingMessage.messageState == .sent else {
            return false
        }
        return true
    }

    // We auto-expire messages after 30 days, even if the user hasn't seen them.
    private class func shouldMessageAutoExpire(_ message: TSMessage) -> Bool {
        let autoExpireDeadlineMs = min(message.timestamp, message.receivedAtTimestamp) + 30 * kDayInMs
        return nowMs() >= autoExpireDeadlineMs
    }

    private class func completeExpiration(forMessage message: TSMessage,
                                          transaction: SDSAnyWriteTransaction) {

        // Start countdown if necessary...
        if !message.hasPerMessageExpirationStarted {
            message.updateWithPerMessageExpireStarted(at: nowMs(),
                                                      transaction: transaction)
        }

        // ...and immediately complete countdown.
        guard !message.perMessageExpirationHasExpired else {
            // Already expired, no need to expire again.
            return
        }
        message.updateWithHasPerMessageExpiredAndRemoveRenderableContent(with: transaction)
    }

    // MARK: - Sync Messages

    private class func sendSyncMessage(forMessage message: TSMessage,
                                       transaction: SDSAnyWriteTransaction) {
        guard let senderId = senderId(forMessage: message) else {
            owsFailDebug("Could not send sync message; no local number.")
            return
        }
        let messageIdTimestamp: UInt64 = message.timestamp
        let readTimestamp: UInt64 = nowMs()

        let syncMessage = OWSPerMessageExpirationReadSyncMessage(senderId: senderId,
                                                                 messageIdTimestamp: messageIdTimestamp,
                                                                 readTimestamp: readTimestamp)
        messageSenderJobQueue.add(message: syncMessage, transaction: transaction)
    }

    @objc
    public class func processIncomingSyncMessage(_ message: SSKProtoSyncMessageMessageTimerRead,
                                                 envelope: SSKProtoEnvelope,
                                                 transaction: SDSAnyWriteTransaction) {

        if tryToApplyIncomingSyncMessage(message,
                                         envelope: envelope,
                                         transaction: transaction) {
            return
        }

        // Unpack and verify the proto & envelope contents.
        let senderId: String = message.sender
        guard senderId.count > 0 else {
            owsFailDebug("Invalid senderId.")
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

        // Persist this "per-message expiration read receipt".
        let key = readReceiptKey(senderId: senderId, messageIdTimestamp: messageIdTimestamp)
        store.setUInt64(readTimestamp, key: key, transaction: transaction)
    }

    // Returns true IFF the read receipt is applied to an existing message.
    private class func tryToApplyIncomingSyncMessage(_ message: SSKProtoSyncMessageMessageTimerRead,
                                                     envelope: SSKProtoEnvelope,
                                                     transaction: SDSAnyWriteTransaction) -> Bool {
        let messageSenderId: String = message.sender
        let messageIdTimestamp: UInt64 = message.timestamp
        let readTimestamp: UInt64 = envelope.timestamp

        let filter = { (interaction: TSInteraction) -> Bool in
            guard interaction.timestamp == messageIdTimestamp else {
                owsFailDebug("Timestamps don't match: \(interaction.timestamp) != \(messageIdTimestamp)")
                return false
            }
            guard let message = interaction as? TSMessage else {
                return false
            }
            guard let senderId = senderId(forMessage: message) else {
                owsFailDebug("Could not process sync message; no local number.")
                return false
            }
            guard senderId == messageSenderId else {
                return false
            }
            guard message.hasPerMessageExpiration else {
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
            // Start expiration using the received read time.
            startPerMessageExpiration(forMessage: message,
                                      readTimestamp: readTimestamp,
                                      sendSyncMessages: false,
                                      transaction: transaction)
        }
        return true
    }

    @objc
    public class func applyEarlyReadReceipts(forIncomingMessage message: TSIncomingMessage,
                                             transaction: SDSAnyWriteTransaction) {
        guard message.hasPerMessageExpiration else {
            return
        }
        guard let senderId = senderId(forMessage: message) else {
            owsFailDebug("Could not apply early read receipts; no local number.")
            return
        }
        let messageIdTimestamp: UInt64 = message.timestamp

        // Check for persisted "per-message expiration read receipt".
        let key = readReceiptKey(senderId: senderId, messageIdTimestamp: messageIdTimestamp)
        guard let readTimestamp = store.getOptionalUInt64(key, transaction: transaction) else {
            // No early read receipt applies, abort.
            return
        }

        // Remove persisted "per-message expiration read receipt".
        store.removeValue(forKey: key, transaction: transaction)

        // Start expiration using the received read time.
        startPerMessageExpiration(forMessage: message,
                                  readTimestamp: readTimestamp,
                                  sendSyncMessages: false,
                                  transaction: transaction)
    }

    private class func senderId(forMessage message: TSMessage) -> String? {

        if let incomingMessage = message as? TSIncomingMessage {
            return incomingMessage.authorAddress.transitional_phoneNumber
        } else if message as? TSOutgoingMessage != nil {
            guard let localNumber = tsAccountManager.localNumber() else {
                owsFailDebug("Could not process sync message; no local number.")
                return nil
            }
            // We also need to send and receive "per-message expiration read" sync
            // messages for outgoing messages, unlike normal read receipts.
            return localNumber
        } else {
            owsFailDebug("Unexpected message type.")
            return nil
        }
    }

    private static let store = SDSKeyValueStore(collection: "perMessageExpiration")

    private class func readReceiptKey(senderId: String,
                                      messageIdTimestamp: UInt64) -> String {
        return "\(senderId).\(messageIdTimestamp)"
    }
}

// MARK: -

public protocol PerMessageExpirationFinder {
    associatedtype ReadTransaction

    typealias EnumerateTSMessageBlock = (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void

    func allMessagesWithPerMessageExpiration(transaction: ReadTransaction) -> [TSMessage]
    func enumerateAllMessagesWithPerMessageExpiration(transaction: ReadTransaction, block: @escaping EnumerateTSMessageBlock)
}

// MARK: -

extension PerMessageExpirationFinder {

    public func allMessagesWithPerMessageExpiration(transaction: ReadTransaction) -> [TSMessage] {
        var result: [TSMessage] = []
        self.enumerateAllMessagesWithPerMessageExpiration(transaction: transaction) { message, _ in
            result.append(message)
        }
        return result
    }
}

// MARK: -

public class AnyPerMessageExpirationFinder {
    lazy var grdbAdapter = GRDBPerMessageExpirationFinder()
    lazy var yapAdapter = YAPDBPerMessageExpirationFinder()
}

// MARK: -

extension AnyPerMessageExpirationFinder: PerMessageExpirationFinder {
    public func enumerateAllMessagesWithPerMessageExpiration(transaction: SDSAnyReadTransaction, block: @escaping EnumerateTSMessageBlock) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            grdbAdapter.enumerateAllMessagesWithPerMessageExpiration(transaction: grdbRead, block: block)
        case .yapRead(let yapRead):
            yapAdapter.enumerateAllMessagesWithPerMessageExpiration(transaction: yapRead, block: block)
        }
    }
}

// MARK: -

class GRDBPerMessageExpirationFinder: PerMessageExpirationFinder {
    func enumerateAllMessagesWithPerMessageExpiration(transaction: GRDBReadTransaction, block: @escaping EnumerateTSMessageBlock) {

        let sql = """
        SELECT * FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .perMessageExpirationDurationSeconds) IS NOT NULL
        AND \(interactionColumn: .perMessageExpirationDurationSeconds) > 0
        AND \(interactionColumn: .perMessageExpirationHasExpired) IS NOT NULL
        AND \(interactionColumn: .perMessageExpirationHasExpired) == FALSE
        """

        let cursor = TSInteraction.grdbFetchCursor(sql: sql,
                                                   arguments: [],
                                                   transaction: transaction)
        var stop: ObjCBool = false
        // GRDB TODO make cursor.next fail hard to remove this `try!`
        while let next = try! cursor.next() {
            guard let message = next as? TSMessage else {
                owsFailDebug("expecting message but found: \(next)")
                return
            }
            guard message.hasPerMessageExpiration,
                !message.perMessageExpirationHasExpired else {
                    owsFailDebug("expecting message with per message expiration but found: \(next)")
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

class YAPDBPerMessageExpirationFinder: PerMessageExpirationFinder {
    public func enumerateAllMessagesWithPerMessageExpiration(transaction: YapDatabaseReadTransaction, block: @escaping EnumerateTSMessageBlock) {
        guard let dbView = TSDatabaseView.perMessageExpirationMessagesDatabaseView(transaction) as? YapDatabaseViewTransaction else {
            owsFailDebug("Couldn't load db view.")
            return
        }

        dbView.enumerateKeysAndObjects(inGroup: TSPerMessageExpirationMessagesGroup) { (_: String, _: String, object: Any, _: UInt, stopPointer: UnsafeMutablePointer<ObjCBool>) in
            guard let message = object as? TSMessage else {
                owsFailDebug("Invalid database entity: \(type(of: object)).")
                return
            }
            guard message.hasPerMessageExpiration,
                !message.perMessageExpirationHasExpired else {
                    owsFailDebug("expecting message with per message expiration but found: \(message)")
                return
            }
            block(message, stopPointer)
        }
    }
}
