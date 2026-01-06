//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

public struct RecipientFetcher {
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let searchableNameIndexer: any SearchableNameIndexer

    public init(
        recipientDatabaseTable: RecipientDatabaseTable,
        searchableNameIndexer: any SearchableNameIndexer,
    ) {
        self.recipientDatabaseTable = recipientDatabaseTable
        self.searchableNameIndexer = searchableNameIndexer
    }

    public func fetchOrCreate(serviceId: ServiceId, tx: DBWriteTransaction) -> SignalRecipient {
        return fetchOrCreateImpl(serviceId: serviceId, tx: tx).recipientAfterInsert
    }

    public func fetchOrCreateImpl(serviceId: ServiceId, tx: DBWriteTransaction) -> (inserted: Bool, recipientAfterInsert: SignalRecipient) {
        if let serviceIdRecipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx) {
            return (inserted: false, serviceIdRecipient)
        }
        let newInstance = failIfThrowsDatabaseError { () throws(GRDB.DatabaseError) in
            return try SignalRecipient.insertRecord(aci: serviceId as? Aci, pni: serviceId as? Pni, tx: tx)
        }
        return (inserted: true, newInstance)
    }

    public func fetchOrCreate(phoneNumber: E164, tx: DBWriteTransaction) -> SignalRecipient {
        if let result = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx) {
            return result
        }
        let result = failIfThrowsDatabaseError { () throws(GRDB.DatabaseError) in
            return try SignalRecipient.insertRecord(phoneNumber: phoneNumber, tx: tx)
        }
        searchableNameIndexer.insert(result, tx: tx)
        return result
    }

    public func fetchOrCreate(address: SignalServiceAddress, tx: DBWriteTransaction) -> SignalRecipient? {
        if let serviceId = address.serviceId {
            return fetchOrCreate(serviceId: serviceId, tx: tx)
        }
        if let phoneNumber = address.e164 {
            return fetchOrCreate(phoneNumber: phoneNumber, tx: tx)
        }
        return nil
    }
}
