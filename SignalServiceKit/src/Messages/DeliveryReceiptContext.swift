//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
protocol DeliveryReceiptContext: AnyObject {
    @objc(addUpdateForMessage:transaction:update:)
    func addUpdate(message: TSOutgoingMessage,
                   transaction: SDSAnyWriteTransaction,
                   update: @escaping (TSOutgoingMessage) -> Void)

    @objc(messagesWithTimestamp:transaction:)
    func messages(_ timestamps: UInt64,
                  transaction: SDSAnyReadTransaction) -> [TSOutgoingMessage]
}

private struct Update {
    let message: TSOutgoingMessage
    let update: (TSOutgoingMessage) -> Void
}

fileprivate extension TSOutgoingMessage {
    static func fetch(_ timestamp: UInt64,
                      transaction: SDSAnyReadTransaction) -> [TSOutgoingMessage] {
        var messages = [TSOutgoingMessage]()
        do {
            let fetched = try InteractionFinder.interactions(withTimestamp: timestamp,
                                                             filter: { _ in true },
                                                             transaction: transaction).compactMap { $0 as? TSOutgoingMessage }
            messages.append(contentsOf: fetched)
        } catch {
            owsFailDebug("Error loading interactions: \(error)")
        }
        return messages
    }
}

@objc
public class PassthroughDeliveryReceiptContext: NSObject, DeliveryReceiptContext {
    @objc(addUpdateForMessage:transaction:update:)
    func addUpdate(message: TSOutgoingMessage,
                   transaction: SDSAnyWriteTransaction,
                   update: @escaping (TSOutgoingMessage) -> Void) {
        let deferredUpdate = Update(message: message, update: update)
        message.anyUpdateOutgoingMessage(transaction: transaction) { message in
            deferredUpdate.update(message)
        }
    }

    @objc(messagesWithTimestamp:transaction:)
    func messages(_ timestamp: UInt64,
                  transaction: SDSAnyReadTransaction) -> [TSOutgoingMessage] {
        return TSOutgoingMessage.fetch(timestamp, transaction: transaction)
    }
}

public class BatchingDeliveryReceiptContext: NSObject, DeliveryReceiptContext {
    private var messages = [UInt64: [TSOutgoingMessage]]()
    private var deferredUpdates: [Update] = []

#if TESTABLE_BUILD
    static var didRunDeferredUpdates: ((Int, SDSAnyWriteTransaction) -> Void)?
#endif

    private override init() {
        super.init()
    }

    static func withDeferredUpdates(transaction: SDSAnyWriteTransaction, _ closure: (DeliveryReceiptContext) -> Void) {
        let instance = BatchingDeliveryReceiptContext()
        closure(instance)
        instance.runDeferredUpdates(transaction: transaction)
    }

    // Adds a closure to run that mutates a message. Note that it will be run twice - once for the
    // in-memory instance and a second time for the most up-to-date copy in the database.
    @objc(addUpdateForMessage:transaction:update:)
    func addUpdate(message: TSOutgoingMessage,
                   transaction: SDSAnyWriteTransaction,
                   update: @escaping (TSOutgoingMessage) -> Void) {
        deferredUpdates.append(Update(message: message, update: update))
    }

    @objc(messagesWithTimestamp:transaction:)
    func messages(_ timestamp: UInt64, transaction: SDSAnyReadTransaction) -> [TSOutgoingMessage] {
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

        mutating func addOrExecute(update: Update,
                                   transaction: SDSAnyWriteTransaction) {
            if message?.grdbId != update.message.grdbId {
                execute(transaction: transaction)
                message = update.message
            }
            owsAssertDebug(message != nil)
            closures.append(update.update)
        }

        mutating func execute(transaction: SDSAnyWriteTransaction) {
            guard let message = message else {
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

    private func runDeferredUpdates(transaction: SDSAnyWriteTransaction) {
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
