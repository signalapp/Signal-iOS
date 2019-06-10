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

    // MARK: -

    @objc
    public class func startPerMessageExpiration(forMessage message: TSMessage,
                                                transaction: SDSAnyWriteTransaction) {
        AssertIsOnMainThread()

        if message.perMessageExpireStartedAt < 1 {
            // Mark the countdown as begun.
            message.updateWithPerMessageExpireStarted(at: NSDate.ows_millisecondTimeStamp(),
                                                      transaction: transaction)
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

    // MARK: -

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
