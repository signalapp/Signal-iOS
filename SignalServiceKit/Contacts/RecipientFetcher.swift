//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol RecipientFetcher {
    func fetchOrCreateImpl(serviceId: ServiceId, tx: DBWriteTransaction) -> (inserted: Bool, recipientAfterInsert: SignalRecipient)
    func fetchOrCreate(phoneNumber: E164, tx: DBWriteTransaction) -> SignalRecipient
}

extension RecipientFetcher {
    public func fetchOrCreate(serviceId: ServiceId, tx: DBWriteTransaction) -> SignalRecipient {
        return fetchOrCreateImpl(serviceId: serviceId, tx: tx).recipientAfterInsert
    }
}

final public class RecipientFetcherImpl: RecipientFetcher {
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let searchableNameIndexer: any SearchableNameIndexer

    public init(
        recipientDatabaseTable: RecipientDatabaseTable,
        searchableNameIndexer: any SearchableNameIndexer,
    ) {
        self.recipientDatabaseTable = recipientDatabaseTable
        self.searchableNameIndexer = searchableNameIndexer
    }

    public func fetchOrCreateImpl(serviceId: ServiceId, tx: DBWriteTransaction) -> (inserted: Bool, recipientAfterInsert: SignalRecipient) {
        if let serviceIdRecipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx) {
            return (inserted: false, serviceIdRecipient)
        }
        let newInstance = SignalRecipient(aci: serviceId as? Aci, pni: serviceId as? Pni, phoneNumber: nil)
        recipientDatabaseTable.insertRecipient(newInstance, transaction: tx)
        return (inserted: true, newInstance)
    }

    public func fetchOrCreate(phoneNumber: E164, tx: DBWriteTransaction) -> SignalRecipient {
        if let result = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx) {
            return result
        }
        let result = SignalRecipient(aci: nil, pni: nil, phoneNumber: phoneNumber)
        recipientDatabaseTable.insertRecipient(result, transaction: tx)
        searchableNameIndexer.insert(result, tx: tx)
        return result
    }
}
