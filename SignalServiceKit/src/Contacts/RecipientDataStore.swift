//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol RecipientDataStore {
    func fetchRecipient(serviceId: ServiceId, transaction: DBReadTransaction) -> SignalRecipient?
    func fetchRecipient(phoneNumber: String, transaction: DBReadTransaction) -> SignalRecipient?

    func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
    func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
    func removeRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
}

class RecipientDataStoreImpl: RecipientDataStore {
    func fetchRecipient(serviceId: ServiceId, transaction: DBReadTransaction) -> SignalRecipient? {
        AnySignalRecipientFinder()
            .signalRecipientForUUID(serviceId.uuidValue, transaction: SDSDB.shimOnlyBridge(transaction))
    }

    func fetchRecipient(phoneNumber: String, transaction: DBReadTransaction) -> SignalRecipient? {
        AnySignalRecipientFinder()
            .signalRecipientForPhoneNumber(phoneNumber, transaction: SDSDB.shimOnlyBridge(transaction))
    }

    func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        signalRecipient.anyInsert(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        signalRecipient.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(transaction))
    }

    func removeRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction) {
        signalRecipient.anyRemove(transaction: SDSDB.shimOnlyBridge(transaction))
    }
}
