//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SignalRecipientStore {

    // MARK: - Reads

    func recipient(for address: SignalServiceAddress, tx: DBReadTransaction) -> SignalRecipient?

    func enumerateAll(tx: DBReadTransaction, block: @escaping (SignalRecipient) -> Void)

    // MARK: - Writes

    func insert(_ recipient: SignalRecipient, tx: DBWriteTransaction) throws

    func markAsRegisteredAndSave(_ recipient: SignalRecipient, tx: DBWriteTransaction)

    func markAsUnregisteredAndSave(_ recipient: SignalRecipient, at timestamp: UInt64, tx: DBWriteTransaction)
}

public class SignalRecipientStoreImpl: SignalRecipientStore {

    public init() {}

    // MARK: - Reads

    public func recipient(for address: SignalServiceAddress, tx: DBReadTransaction) -> SignalRecipient? {
        return SignalRecipientFinder().signalRecipient(for: address, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func enumerateAll(tx: DBReadTransaction, block: @escaping (SignalRecipient) -> Void) {
        SignalRecipient.anyEnumerate(
            transaction: SDSDB.shimOnlyBridge(tx),
            block: { recipient, _ in
                block(recipient)
            }
        )
    }

    // MARK: - Writes

    public func insert(_ recipient: SignalRecipient, tx: DBWriteTransaction) throws {
        recipient.anyInsert(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func markAsRegisteredAndSave(_ recipient: SignalRecipient, tx: DBWriteTransaction) {
        recipient.markAsRegisteredAndSave(tx: SDSDB.shimOnlyBridge(tx))
    }

    public func markAsUnregisteredAndSave(_ recipient: SignalRecipient, at timestamp: UInt64, tx: DBWriteTransaction) {
        recipient.markAsUnregisteredAndSave(at: timestamp, tx: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

public class SignalRecipientStoreMock: SignalRecipientStore {

    public init() {}

    public var recipients = [SignalRecipient]()

    // MARK: - Reads

    public func recipient(for address: SignalServiceAddress, tx: DBReadTransaction) -> SignalRecipient? {
        return recipients.first(where: { $0.address.isEqualToAddress(address) })
    }

    public func enumerateAll(tx: DBReadTransaction, block: @escaping (SignalRecipient) -> Void) {
        recipients.forEach(block)
    }

    // MARK: - Writes

    public func insert(_ recipient: SignalRecipient, tx: DBWriteTransaction) throws {
        recipients.append(recipient)
    }

    public func markAsRegisteredAndSave(_ recipient: SignalRecipient, tx: DBWriteTransaction) {
        // Not implemented
    }

    public func markAsUnregisteredAndSave(_ recipient: SignalRecipient, at timestamp: UInt64, tx: DBWriteTransaction) {
        // Not implemented
    }
}

#endif
