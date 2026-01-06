//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

public struct RecipientDatabaseTable {
    public init() {}

    func fetchRecipient(contactThread: TSContactThread, tx: DBReadTransaction) -> SignalRecipient? {
        return fetchServiceIdAndRecipient(contactThread: contactThread, tx: tx)
            .flatMap { _, recipient in recipient }
    }

    func fetchServiceId(contactThread: TSContactThread, tx: DBReadTransaction) -> ServiceId? {
        return fetchServiceIdAndRecipient(contactThread: contactThread, tx: tx)
            .map { serviceId, _ in serviceId }
    }

    /// Fetch the `ServiceId` for the owner of this contact thread, and its
    /// corresponding `SignalRecipient` if one exists.
    private func fetchServiceIdAndRecipient(
        contactThread: TSContactThread,
        tx: DBReadTransaction,
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
        return
            address.serviceId.flatMap({ fetchRecipient(serviceId: $0, transaction: tx) })
                ?? address.phoneNumber.flatMap({ fetchRecipient(phoneNumber: $0, transaction: tx) })

    }

    public func fetchAuthorRecipient(incomingMessage: TSIncomingMessage, tx: DBReadTransaction) -> SignalRecipient? {
        return fetchRecipient(address: incomingMessage.authorAddress, tx: tx)
    }

    public func fetchRecipient(rowId: Int64, tx: DBReadTransaction) -> SignalRecipient? {
        return failIfThrows {
            return try SignalRecipient.fetchOne(tx.database, key: rowId)
        }
    }

    public func fetchRecipient(uniqueId: String, tx: DBReadTransaction) -> SignalRecipient? {
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: .uniqueId) = ?"
        return failIfThrows {
            return try SignalRecipient.fetchOne(tx.database, sql: sql, arguments: [uniqueId])
        }
    }

    public func fetchRecipient(serviceId: ServiceId, transaction tx: DBReadTransaction) -> SignalRecipient? {
        let serviceIdColumn: SignalRecipient.CodingKeys = {
            switch serviceId.kind {
            case .aci: return .aciString
            case .pni: return .pni
            }
        }()
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: serviceIdColumn) = ?"
        return failIfThrows {
            return try SignalRecipient.fetchOne(tx.database, sql: sql, arguments: [serviceId.serviceIdUppercaseString])
        }
    }

    public func fetchRecipient(phoneNumber: String, transaction tx: DBReadTransaction) -> SignalRecipient? {
        let sql = "SELECT * FROM \(SignalRecipient.databaseTableName) WHERE \(signalRecipientColumn: .phoneNumber) = ?"
        return failIfThrows {
            return try SignalRecipient.fetchOne(tx.database, sql: sql, arguments: [phoneNumber])
        }
    }

    public func enumerateAll(tx: DBReadTransaction, block: (SignalRecipient) -> Void) {
        failIfThrows {
            let cursor = try SignalRecipient.fetchCursor(tx.database)
            var hasMore = true
            while hasMore {
                try autoreleasepool {
                    guard let recipient = try cursor.next() else {
                        hasMore = false
                        return
                    }
                    block(recipient)
                }
            }
        }
    }

    public func fetchWhitelistedRecipients(tx: DBReadTransaction) -> [SignalRecipient] {
        let fetchRequest = SignalRecipient.filter(
            Column(SignalRecipient.CodingKeys.status.rawValue) == SignalRecipient.Status.whitelisted.rawValue,
        )
        return failIfThrows { try fetchRequest.fetchAll(tx.database) }
    }

    public func fetchAllPhoneNumbers(tx: DBReadTransaction) -> [String: Bool] {
        var result = [String: Bool]()
        enumerateAll(tx: tx) { signalRecipient in
            guard let phoneNumber = signalRecipient.phoneNumber?.stringValue else {
                return
            }
            result[phoneNumber] = signalRecipient.isRegistered
        }
        return result
    }

    public func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        failIfThrows {
            try signalRecipient.update(transaction.database)
        }
    }

    public func removeRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        failIfThrows {
            try signalRecipient.delete(transaction.database)
        }
    }
}
