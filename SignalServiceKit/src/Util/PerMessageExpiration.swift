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

    // MARK: -

    @objc
    public class func startPerMessageExpiration(forMessage message: TSMessage,
                                                transaction: SDSAnyWriteTransaction) {
        AssertIsOnMainThread()

        // Start expiration using "now" as the read time.
        startPerMessageExpiration(forMessage: message,
                                  readTimestamp: NSDate.ows_millisecondTimeStamp(),
                                  transaction: transaction)
    }

    private class func startPerMessageExpiration(forMessage message: TSMessage,
                                                 readTimestamp: UInt64,
                                                 transaction: SDSAnyWriteTransaction) {

        // Make sure that timestamp is not later than now.
        let timestamp = min(readTimestamp, NSDate.ows_millisecondTimeStamp())

        if !message.hasPerMessageExpirationStarted {
            // Mark the countdown as begun.
            message.updateWithPerMessageExpireStarted(at: timestamp,
                                                      transaction: transaction)

            sendSyncMessage(forMessage: message, transaction: transaction)
        } else {
            owsFailDebug("Per-message expiration countdown already begun.")
        }

        schedulePerMessageExpiration(forMessage: message,
                                     transaction: transaction)
    }

    private class func schedulePerMessageExpiration(forMessage message: TSMessage,
                                                    transaction: SDSAnyWriteTransaction) {
        let perMessageExpiresAtMS = message.perMessageExpiresAt
        let nowMs = NSDate.ows_millisecondTimeStamp()

        guard perMessageExpiresAtMS > nowMs else {
            // Message has expired; remove it immediately.
            completePerMessageExpiration(forMessage: message,
                                         transaction: transaction)
            return
        }

        let delaySeconds: TimeInterval = Double(perMessageExpiresAtMS - nowMs) / 1000
        DispatchQueue.global().asyncAfter(deadline: .now() + delaySeconds) {
            self.completePerMessageExpiration(forMessage: message)
        }
    }

    private class func completePerMessageExpiration(forMessage message: TSMessage) {
        databaseStorage.write { (transaction) in
            self.completePerMessageExpiration(forMessage: message,
                                              transaction: transaction)
        }
    }

    private class func completePerMessageExpiration(forMessage message: TSMessage,
                                                    transaction: SDSAnyWriteTransaction) {
        message.updateWithHasPerMessageExpiredAndRemoveRenderableContent(with: transaction)
    }

    // MARK: - Events

    @objc
    public class func appDidBecomeReady() {
        AssertIsOnMainThread()

        // Find all messages with per-message expiration whose countdown has begun.
        // Cull expired messages & resume countdown for others.
        databaseStorage.write { (transaction) in
            let messages = AnyPerMessageExpirationFinder().allMessagesWithPerMessageExpiration(transaction: transaction)
            for message in messages {
                schedulePerMessageExpiration(forMessage: message, transaction: transaction)
            }
        }
    }

    // MARK: - Sync Messages

    private class func sendSyncMessage(forMessage message: TSMessage,
                                       transaction: SDSAnyWriteTransaction) {
        guard let senderId = senderId(forMessage: message) else {
            owsFailDebug("Could not send sync message; no local number.")
            return
        }
        let messageIdTimestamp: UInt64 = message.timestamp
        let readTimestamp: UInt64 = NSDate.ows_millisecondTimeStamp()

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
        let fakeThreadUniqueId = ""
        let interactionFinder = InteractionFinder(threadUniqueId: fakeThreadUniqueId)
        let interactions: [TSInteraction]
        do {
            interactions = try interactionFinder.interactions(withTimestamp: messageIdTimestamp, filter: filter, transaction: transaction)
        } catch {
            owsFailDebug("Couldn't find interactions: \(error)")
            return false
        }
        guard interactions.count > 0 else {
            return false
        }
        for interaction in interactions {
            guard let message = interaction as? TSMessage else {
                owsFailDebug("Invalid interaction: \(type(of: interaction))")
                continue
            }
            // Start expiration using the received read time.
            startPerMessageExpiration(forMessage: message,
                                      readTimestamp: readTimestamp,
                                      transaction: transaction)
        }
        return true
    }

    @objc
    public class func applyEarlyReadReceipts(forIncomingMessage message: TSIncomingMessage,
                                             transaction: SDSAnyWriteTransaction) {

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
                                  transaction: transaction)
    }

    private class func senderId(forMessage message: TSMessage) -> String? {

        if let incomingMessage = message as? TSIncomingMessage {
            return incomingMessage.authorId
        } else {
            guard let localNumber = tsAccountManager.localNumber() else {
                owsFailDebug("Could not process sync message; no local number.")
                return nil
            }
            // We also need to send and receive "per-message expiration read" sync
            // messages for outgoing messages, unlike normal read receipts.
            return localNumber
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

    func allMessagesWithPerMessageExpiration(transaction: ReadTransaction) -> [TSMessage]
    func enumerateAllMessagesWithPerMessageExpiration(transaction: ReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void)
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
    public func enumerateAllMessagesWithPerMessageExpiration(transaction: SDSAnyReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {
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
    func enumerateAllMessagesWithPerMessageExpiration(transaction: GRDBReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {

        let sql = """
        SELECT * FROM \(InteractionRecord.databaseTableName)
        WHERE \(interactionColumn: .perMessageExpirationDurationSeconds) IS NOT NULL
        AND \(interactionColumn: .perMessageExpirationDurationSeconds) > 0
        ORDER BY \(interactionColumn: .id)
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
                message.hasPerMessageExpirationStarted,
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
    public func enumerateAllMessagesWithPerMessageExpiration(transaction: YapDatabaseReadTransaction, block: @escaping (TSMessage, UnsafeMutablePointer<ObjCBool>) -> Void) {

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
                message.hasPerMessageExpirationStarted,
                !message.perMessageExpirationHasExpired else {
                return
            }
            block(message, stopPointer)
        }
    }
}
