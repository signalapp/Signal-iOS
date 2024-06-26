//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol OWSDeviceManager {

    func warmCaches()

    // MARK: Has received sync message

    func setHasReceivedSyncMessage(
        lastReceivedAt: Date,
        transaction: DBWriteTransaction
    )

    func hasReceivedSyncMessage(inLastSeconds seconds: UInt) -> Bool

    // MARK: May have linked devices

    func setMightHaveUnknownLinkedDevice(
        _ mightHaveUnknownLinkedDevice: Bool,
        transaction: DBWriteTransaction
    )

    func mightHaveUnknownLinkedDevice(transaction: DBReadTransaction) -> Bool
}

extension OWSDeviceManager {
    func setHasReceivedSyncMessage(transaction: DBWriteTransaction) {
        setHasReceivedSyncMessage(lastReceivedAt: Date(), transaction: transaction)
    }
}

class OWSDeviceManagerImpl: OWSDeviceManager {
    private enum Constants {
        static let keyValueStoreCollectionName = "kTSStorageManager_OWSDeviceCollection"
        static let mightHaveUnknownLinkedDeviceKey = "kTSStorageManager_MayHaveLinkedDevices"
        static let lastReceivedSyncMessageKey = "kLastReceivedSyncMessage"
    }

    private let databaseStorage: DB
    private let keyValueStore: KeyValueStore

    private var lastReceivedSyncMessageAt: AtomicOptional<Date> = .init(nil, lock: .init())

    init(
        databaseStorage: DB,
        keyValueStoreFactory: KeyValueStoreFactory
    ) {
        self.databaseStorage = databaseStorage

        keyValueStore = keyValueStoreFactory.keyValueStore(
            collection: Constants.keyValueStoreCollectionName
        )
    }

    func warmCaches() {
        databaseStorage.read { transaction in
            if let lastReceived = keyValueStore.getDate(
                Constants.lastReceivedSyncMessageKey,
                transaction: transaction
            ) {
                _ = lastReceivedSyncMessageAt.tryToSetIfNil(lastReceived)
            }
        }
    }

    // MARK: Has received sync message

    func hasReceivedSyncMessage(inLastSeconds lastSeconds: UInt) -> Bool {
        guard let lastReceivedSyncMessageAt = lastReceivedSyncMessageAt.get() else {
            return false
        }

        let timeIntervalSinceLastReceived = fabs(lastReceivedSyncMessageAt.timeIntervalSinceNow)

        return timeIntervalSinceLastReceived < Double(lastSeconds)
    }

    func setHasReceivedSyncMessage(
        lastReceivedAt: Date,
        transaction: DBWriteTransaction
    ) {
        self.lastReceivedSyncMessageAt.set(lastReceivedAt)

        keyValueStore.setDate(
            lastReceivedAt,
            key: Constants.lastReceivedSyncMessageKey,
            transaction: transaction
        )
    }

    // MARK: May have linked devices

    /// Returns true if there might be an unknown linked device.
    ///
    /// Don't read this value if the local SignalRecipient indicates that there
    /// are linked devices (because you MUST send sync messages to those linked
    /// devices). If the local SignalRecipient indicates that there aren't any
    /// linked devices, you MUST send sync messages iff this value is true (this
    /// will confirm whether or not there are linked devices and update
    /// `mightHaveUnknownLinkedDevice` accordingly).
    ///
    /// This situation may occur after linking a new device on the primary
    /// before we've had a chance to update the local user's SignalRecipient.
    func mightHaveUnknownLinkedDevice(transaction: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(
            Constants.mightHaveUnknownLinkedDeviceKey,
            defaultValue: true,
            transaction: transaction
        )
    }

    func setMightHaveUnknownLinkedDevice(
        _ mightHaveUnknownLinkedDevice: Bool,
        transaction: DBWriteTransaction
    ) {
        keyValueStore.setBool(
            mightHaveUnknownLinkedDevice,
            key: Constants.mightHaveUnknownLinkedDeviceKey,
            transaction: transaction
        )
    }
}
