//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol RecipientFetcher {
    func fetchOrCreate(serviceId: ServiceId, tx: DBWriteTransaction) -> SignalRecipient
    func fetchOrCreate(phoneNumber: E164, tx: DBWriteTransaction) -> SignalRecipient
}

public class RecipientFetcherImpl: RecipientFetcher {
    private let recipientDatabaseTable: RecipientDatabaseTable

    public init(recipientDatabaseTable: RecipientDatabaseTable) {
        self.recipientDatabaseTable = recipientDatabaseTable
    }

    public func fetchOrCreate(serviceId: ServiceId, tx: DBWriteTransaction) -> SignalRecipient {
        if let serviceIdRecipient = recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx) {
            return serviceIdRecipient
        }
        let newInstance = SignalRecipient(aci: serviceId as? Aci, pni: serviceId as? Pni, phoneNumber: nil)
        recipientDatabaseTable.insertRecipient(newInstance, transaction: tx)
        return newInstance
    }

    public func fetchOrCreate(phoneNumber: E164, tx: DBWriteTransaction) -> SignalRecipient {
        if let result = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx) {
            return result
        }
        let result = SignalRecipient(aci: nil, pni: nil, phoneNumber: phoneNumber)
        recipientDatabaseTable.insertRecipient(result, transaction: tx)
        return result
    }
}
