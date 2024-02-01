//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol RecipientDatabaseTable {
    func fetchRecipient(serviceId: ServiceId, transaction: DBReadTransaction) -> SignalRecipient?
    func fetchRecipient(phoneNumber: String, transaction: DBReadTransaction) -> SignalRecipient?

    func enumerateAll(tx: DBReadTransaction, block: (SignalRecipient) -> Void)

    func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
    func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
    func removeRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
}

extension RecipientDatabaseTable {
    func fetchServiceId(for contactThread: TSContactThread, tx: DBReadTransaction) -> ServiceId? {
        let serviceId = contactThread.contactUUID.flatMap { try? ServiceId.parseFrom(serviceIdString: $0) }
        // If there's an ACI, it's *definitely* correct, and it's definitely the
        // owner, so we can return early without issuing any queries.
        if let aci = serviceId as? Aci {
            return aci
        }
        // Otherwise, we need to figure out which recipient "owns" this thread. If
        // the thread has a phone number but there's no SignalRecipient with that
        // phone number, we'll return nil (even if the thread has a PNI). This is
        // intentional. In this case, the phone number takes precedence, and this
        // PNI definitely isn’t associated with this phone number. This situation
        // should be impossible because ThreadMerger should keep these values in
        // sync. (It's pre-ThreadMerger threads that might be wrong, and PNIs were
        // introduced after ThreadMerger.)
        if let phoneNumber = contactThread.contactPhoneNumber {
            let ownedByRecipient = fetchRecipient(phoneNumber: phoneNumber, transaction: tx)
            return ownedByRecipient?.aci ?? ownedByRecipient?.pni
        }
        if let pni = serviceId as? Pni {
            let ownedByRecipient = fetchRecipient(serviceId: pni, transaction: tx)
            return ownedByRecipient?.aci ?? ownedByRecipient?.pni ?? pni
        }
        return nil
    }

    func fetchRecipient(address: SignalServiceAddress, tx: DBReadTransaction) -> SignalRecipient? {
        return (
            address.serviceId.flatMap({ fetchRecipient(serviceId: $0, transaction: tx) })
            ?? address.phoneNumber.flatMap({ fetchRecipient(phoneNumber: $0, transaction: tx) })
        )
    }
}

public class RecipientDatabaseTableImpl: RecipientDatabaseTable {
    public init() {}

    public func fetchRecipient(serviceId: ServiceId, transaction tx: DBReadTransaction) -> SignalRecipient? {
        SignalRecipientFinder().signalRecipientForServiceId(serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchRecipient(phoneNumber: String, transaction tx: DBReadTransaction) -> SignalRecipient? {
        SignalRecipientFinder().signalRecipientForPhoneNumber(phoneNumber, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func enumerateAll(tx: DBReadTransaction, block: (SignalRecipient) -> Void) {
        SignalRecipient.anyEnumerate(transaction: SDSDB.shimOnlyBridge(tx), block: { recipient, _ in block(recipient) })
    }

    public func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        signalRecipient.anyInsert(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    public func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        signalRecipient.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    public func removeRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        signalRecipient.anyRemove(transaction: SDSDB.shimOnlyBridge(transaction))
    }
}

#if TESTABLE_BUILD

class MockRecipientDatabaseTable: RecipientDatabaseTable {
    var nextRowId = 1
    var recipientTable: [Int: SignalRecipient] = [:]

    func fetchRecipient(serviceId: ServiceId, transaction: DBReadTransaction) -> SignalRecipient? {
        return recipientTable.values.first(where: { $0.aci == serviceId || $0.pni == serviceId })?.copyRecipient() ?? nil
    }

    func fetchRecipient(phoneNumber: String, transaction: DBReadTransaction) -> SignalRecipient? {
        return recipientTable.values.first(where: { $0.phoneNumber == phoneNumber })?.copyRecipient() ?? nil
    }

    func enumerateAll(tx: DBReadTransaction, block: (SignalRecipient) -> Void) {
        recipientTable.forEach({ block($0.value) })
    }

    func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        precondition(rowId(for: signalRecipient) == nil)
        recipientTable[nextRowId] = signalRecipient.copyRecipient()
        nextRowId += 1
    }

    func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        let rowId = rowId(for: signalRecipient)!
        recipientTable[rowId] = signalRecipient.copyRecipient()
    }

    func removeRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        let rowId = rowId(for: signalRecipient)!
        recipientTable[rowId] = nil
    }

    private func rowId(for signalRecipient: SignalRecipient) -> Int? {
        for (rowId, value) in recipientTable {
            if value.uniqueId == signalRecipient.uniqueId {
                return rowId
            }
        }
        return nil
    }
}

#endif
