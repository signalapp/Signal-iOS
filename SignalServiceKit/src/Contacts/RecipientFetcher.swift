//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol RecipientFetcher {
    func fetchOrCreate(serviceId: ServiceId, tx: DBWriteTransaction) -> SignalRecipient
    func fetchOrCreate(phoneNumber: E164, tx: DBWriteTransaction) -> SignalRecipient
}

class RecipientFetcherImpl: RecipientFetcher {
    private let recipientStore: RecipientDataStore

    init(recipientStore: RecipientDataStore) {
        self.recipientStore = recipientStore
    }

    func fetchOrCreate(serviceId: ServiceId, tx: DBWriteTransaction) -> SignalRecipient {
        if let serviceIdRecipient = recipientStore.fetchRecipient(serviceId: serviceId, transaction: tx) {
            return serviceIdRecipient
        }
        let newInstance = SignalRecipient(serviceId: serviceId, phoneNumber: nil)
        recipientStore.insertRecipient(newInstance, transaction: tx)
        return newInstance
    }

    func fetchOrCreate(phoneNumber: E164, tx: DBWriteTransaction) -> SignalRecipient {
        if let result = recipientStore.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx) {
            return result
        }
        let result = SignalRecipient(serviceId: nil, phoneNumber: phoneNumber)
        recipientStore.insertRecipient(result, transaction: tx)
        return result
    }
}
