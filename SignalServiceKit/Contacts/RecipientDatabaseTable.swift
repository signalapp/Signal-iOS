//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol RecipientDatabaseTable {
    func fetchRecipient(rowId: Int64, tx: DBReadTransaction) -> SignalRecipient?
    func fetchRecipient(serviceId: ServiceId, transaction: DBReadTransaction) -> SignalRecipient?
    func fetchRecipient(phoneNumber: String, transaction: DBReadTransaction) -> SignalRecipient?

    func enumerateAll(tx: DBReadTransaction, block: (SignalRecipient) -> Void)

    func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
    func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
    func removeRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
}

extension RecipientDatabaseTable {
    func fetchRecipient(contactThread: TSContactThread, tx: DBReadTransaction) -> SignalRecipient? {
        return fetchServiceIdAndRecipient(contactThread: contactThread, tx: tx)
            .flatMap { (_, recipient) in recipient }
    }

    func fetchServiceId(contactThread: TSContactThread, tx: DBReadTransaction) -> ServiceId? {
        return fetchServiceIdAndRecipient(contactThread: contactThread, tx: tx)
            .map { (serviceId, _) in serviceId }
    }

    /// Fetch the `ServiceId` for the owner of this contact thread, and its
    /// corresponding `SignalRecipient` if one exists.
    private func fetchServiceIdAndRecipient(
        contactThread: TSContactThread,
        tx: DBReadTransaction
    ) -> (ServiceId, SignalRecipient?)? {
        let threadServiceId = contactThread.contactUUID.flatMap { try? ServiceId.parseFrom(serviceIdString: $0) }

        // If there's an ACI, it's *definitely* correct, and it's definitely the
        // owner, so we can return early without issuing any queries.
        if let aci = threadServiceId as? Aci {
            let ownedByRecipient = fetchRecipient(serviceId: aci, transaction: tx)

            return (aci, ownedByRecipient)
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
            let ownedByServiceId = ownedByRecipient?.aci ?? ownedByRecipient?.pni

            return ownedByServiceId.map { ($0, ownedByRecipient) }
        }

        if let pni = threadServiceId as? Pni {
            let ownedByRecipient = fetchRecipient(serviceId: pni, transaction: tx)
            let ownedByServiceId = ownedByRecipient?.aci ?? ownedByRecipient?.pni ?? pni

            return (ownedByServiceId, ownedByRecipient)
        }

        return nil
    }

    // MARK: -

    public func fetchRecipient(address: SignalServiceAddress, tx: DBReadTransaction) -> SignalRecipient? {
        return (
            address.serviceId.flatMap({ fetchRecipient(serviceId: $0, transaction: tx) })
            ?? address.phoneNumber.flatMap({ fetchRecipient(phoneNumber: $0, transaction: tx) })
        )
    }

    public func fetchAuthorRecipient(incomingMessage: TSIncomingMessage, tx: DBReadTransaction) -> SignalRecipient? {
        return fetchRecipient(address: incomingMessage.authorAddress, tx: tx)
    }
}

public class RecipientDatabaseTableImpl: RecipientDatabaseTable {
    public init() {}

    public func fetchRecipient(rowId: Int64, tx: DBReadTransaction) -> SignalRecipient? {
        return SDSCodableModelDatabaseInterfaceImpl().fetchModel(modelType: SignalRecipient.self, rowId: rowId, tx: tx)
    }

    public func fetchRecipient(serviceId: ServiceId, transaction tx: DBReadTransaction) -> SignalRecipient? {
        let serviceIdColumn: SignalRecipient.CodingKeys = {
            switch serviceId.kind {
            case .aci: return .aciString
            case .pni: return .pni
            }
        }()
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: serviceIdColumn) = ?"
        return SignalRecipient.anyFetch(sql: sql, arguments: [serviceId.serviceIdUppercaseString], transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchRecipient(phoneNumber: String, transaction tx: DBReadTransaction) -> SignalRecipient? {
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: .phoneNumber) = ?"
        return SignalRecipient.anyFetch(sql: sql, arguments: [phoneNumber], transaction: SDSDB.shimOnlyBridge(tx))
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
    var nextRowId: Int64 = 1
    var recipientTable: [Int64: SignalRecipient] = [:]

    func fetchRecipient(rowId: Int64, tx: DBReadTransaction) -> SignalRecipient? {
        return recipientTable[rowId]
    }

    func fetchRecipient(serviceId: ServiceId, transaction: DBReadTransaction) -> SignalRecipient? {
        return recipientTable.values.first(where: { $0.aci == serviceId || $0.pni == serviceId })?.copyRecipient() ?? nil
    }

    func fetchRecipient(phoneNumber: String, transaction: DBReadTransaction) -> SignalRecipient? {
        return recipientTable.values.first(where: { $0.phoneNumber?.stringValue == phoneNumber })?.copyRecipient() ?? nil
    }

    func enumerateAll(tx: DBReadTransaction, block: (SignalRecipient) -> Void) {
        recipientTable.forEach({ block($0.value) })
    }

    func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        precondition(rowId(for: signalRecipient) == nil)
        signalRecipient.id = nextRowId
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

    private func rowId(for signalRecipient: SignalRecipient) -> Int64? {
        for (rowId, value) in recipientTable {
            if value.uniqueId == signalRecipient.uniqueId {
                return rowId
            }
        }
        return nil
    }
}

#endif
