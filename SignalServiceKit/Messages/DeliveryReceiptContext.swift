//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol DeliveryReceiptContext: AnyObject {
    func addUpdate(
        message: TSOutgoingMessage,
        transaction: DBWriteTransaction,
        update: @escaping (TSOutgoingMessage) -> Void,
    )

    func messages(_ timestamps: UInt64, transaction: DBReadTransaction) -> [TSOutgoingMessage]
}

private struct Update {
    let message: TSOutgoingMessage
    let update: (TSOutgoingMessage) -> Void
}

private extension TSOutgoingMessage {
    static func fetch(_ timestamp: UInt64, transaction: DBReadTransaction) -> [TSOutgoingMessage] {
        do {
            return try InteractionFinder.fetchInteractions(
                timestamp: timestamp,
                transaction: transaction,
            ).compactMap { $0 as? TSOutgoingMessage }
        } catch {
            owsFailDebug("Error loading interactions: \(error)")
            return []
        }
    }
}

public class PassthroughDeliveryReceiptContext: DeliveryReceiptContext {
    public init() {}

    public func addUpdate(
        message: TSOutgoingMessage,
        transaction: DBWriteTransaction,
        update: @escaping (TSOutgoingMessage) -> Void,
    ) {
        let deferredUpdate = Update(message: message, update: update)
        message.anyUpdateOutgoingMessage(transaction: transaction) { message in
            deferredUpdate.update(message)
        }
    }

    public func messages(_ timestamp: UInt64, transaction: DBReadTransaction) -> [TSOutgoingMessage] {
        return TSOutgoingMessage.fetch(timestamp, transaction: transaction)
    }
}

public class BatchingDeliveryReceiptContext: DeliveryReceiptContext {
    private var messages = [UInt64: [TSOutgoingMessage]]()
    private var deferredUpdates: [Update] = []

#if TESTABLE_BUILD
    static var didRunDeferredUpdates: ((Int, DBWriteTransaction) -> Void)?
#endif

    static func withDeferredUpdates(transaction: DBWriteTransaction, _ closure: (DeliveryReceiptContext) -> Void) {
        let instance = BatchingDeliveryReceiptContext()
        closure(instance)
        instance.runDeferredUpdates(transaction: transaction)
    }

    // Adds a closure to run that mutates a message. Note that it will be run twice - once for the
    // in-memory instance and a second time for the most up-to-date copy in the database.
    public func addUpdate(
        message: TSOutgoingMessage,
        transaction: DBWriteTransaction,
        update: @escaping (TSOutgoingMessage) -> Void,
    ) {
        deferredUpdates.append(Update(message: message, update: update))
    }

    public func messages(_ timestamp: UInt64, transaction: DBReadTransaction) -> [TSOutgoingMessage] {
        if let result = messages[timestamp] {
            return result
        }
        let fetched = TSOutgoingMessage.fetch(timestamp, transaction: transaction)
        messages[timestamp] = fetched
        return fetched
    }

    private struct UpdateCollection {
        private var message: TSOutgoingMessage?
        private var closures = [(TSOutgoingMessage) -> Void]()

        mutating func addOrExecute(
            update: Update,
            transaction: DBWriteTransaction,
        ) {
            if message?.grdbId != update.message.grdbId {
                execute(transaction: transaction)
                message = update.message
            }
            owsAssertDebug(message != nil)
            closures.append(update.update)
        }

        mutating func execute(transaction: DBWriteTransaction) {
            guard let message else {
                owsAssertDebug(closures.isEmpty)
                return
            }
            message.anyUpdateOutgoingMessage(transaction: transaction) { messageToUpdate in
                for closure in closures {
                    closure(messageToUpdate)
                }
            }
            self.message = nil
            closures = []
        }
    }

    private func runDeferredUpdates(transaction: DBWriteTransaction) {
        var updateCollection = UpdateCollection()
#if TESTABLE_BUILD
        let count = deferredUpdates.count
#endif
        while let update = deferredUpdates.first {
            deferredUpdates.removeFirst()
            updateCollection.addOrExecute(update: update, transaction: transaction)
        }
        updateCollection.execute(transaction: transaction)
#if TESTABLE_BUILD
        let closure = Self.didRunDeferredUpdates
        Self.didRunDeferredUpdates = nil
        closure?(count, transaction)
#endif
    }

}
