//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol OWSDeviceManager {
    func setHasReceivedSyncMessage(
        lastReceivedAt: Date,
        transaction: DBWriteTransaction,
    )

    func hasReceivedSyncMessage(
        inLastSeconds seconds: UInt,
        transaction: DBReadTransaction,
    ) -> Bool
}

extension OWSDeviceManager {
    func setHasReceivedSyncMessage(transaction: DBWriteTransaction) {
        setHasReceivedSyncMessage(lastReceivedAt: Date(), transaction: transaction)
    }
}

class OWSDeviceManagerImpl: OWSDeviceManager {
    private enum Constants {
        static let keyValueStoreCollectionName = "kTSStorageManager_OWSDeviceCollection"
        static let lastReceivedSyncMessageKey = "kLastReceivedSyncMessage"
    }

    private let keyValueStore: KeyValueStore

    init() {
        self.keyValueStore = KeyValueStore(
            collection: Constants.keyValueStoreCollectionName,
        )
    }

    // MARK: Has received sync message

    func hasReceivedSyncMessage(inLastSeconds lastSeconds: UInt, transaction tx: DBReadTransaction) -> Bool {
        let lastReceivedSyncMessageAt = keyValueStore.getDate(
            Constants.lastReceivedSyncMessageKey,
            transaction: tx,
        )

        guard let lastReceivedSyncMessageAt else {
            return false
        }

        let timeIntervalSinceLastReceived = fabs(lastReceivedSyncMessageAt.timeIntervalSinceNow)

        return timeIntervalSinceLastReceived < Double(lastSeconds)
    }

    func setHasReceivedSyncMessage(
        lastReceivedAt: Date,
        transaction: DBWriteTransaction,
    ) {
        keyValueStore.setDate(
            lastReceivedAt,
            key: Constants.lastReceivedSyncMessageKey,
            transaction: transaction,
        )
    }
}
