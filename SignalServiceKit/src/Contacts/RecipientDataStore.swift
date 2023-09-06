//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol RecipientDataStore {
    func fetchRecipient(serviceId: ServiceId, transaction: DBReadTransaction) -> SignalRecipient?
    func fetchRecipient(phoneNumber: String, transaction: DBReadTransaction) -> SignalRecipient?

    func insertRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
    func updateRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
    func removeRecipient(_ signalRecipient: SignalRecipient, transaction: DBWriteTransaction)
}

class RecipientDataStoreImpl: RecipientDataStore {
    func fetchRecipient(serviceId: ServiceId, transaction tx: DBReadTransaction) -> SignalRecipient? {
        SignalRecipientFinder().signalRecipientForServiceId(serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    func fetchRecipient(phoneNumber: String, transaction tx: DBReadTransaction) -> SignalRecipient? {
        SignalRecipientFinder().signalRecipientForPhoneNumber(phoneNumber, tx: SDSDB.shimOnlyBridge(tx))
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
