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

    func setMayHaveLinkedDevices(
        _ mayHaveLinkedDevices: Bool,
        transaction: DBWriteTransaction
    )

    func mayHaveLinkedDevices(transaction: DBReadTransaction) -> Bool
}

extension OWSDeviceManager {
    func setHasReceivedSyncMessage(transaction: DBWriteTransaction) {
        setHasReceivedSyncMessage(lastReceivedAt: Date(), transaction: transaction)
    }
}

class OWSDeviceManagerImpl: OWSDeviceManager {
    private enum Constants {
        static let keyValueStoreCollectionName = "kTSStorageManager_OWSDeviceCollection"
        static let mayHaveLinkedDevicesKey = "kTSStorageManager_MayHaveLinkedDevices"
        static let lastReceivedSyncMessageKey = "kLastReceivedSyncMessage"
    }

    private let databaseStorage: DB
    private let keyValueStore: KeyValueStore

    private var lastReceivedSyncMessageAt: AtomicOptional<Date> = .init(nil, lock: AtomicLock())

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

        setMayHaveLinkedDevices(true, transaction: transaction)
    }

    // MARK: May have linked devices

    /// Returns whether or not we may have linked devices.
    ///
    /// By default, returns `true`. If we confirm we have no linked devices,
    /// we should set this flag to `false` via ``setMayHaveLinkedDevices`` so
    /// as to avoid unnecessary sync message sending.
    func mayHaveLinkedDevices(transaction: DBReadTransaction) -> Bool {
        return keyValueStore.getBool(
            Constants.mayHaveLinkedDevicesKey,
            defaultValue: true,
            transaction: transaction
        )
    }

    func setMayHaveLinkedDevices(
        _ mayHaveLinkedDevices: Bool,
        transaction: DBWriteTransaction
    ) {
        keyValueStore.setBool(
            mayHaveLinkedDevices,
            key: Constants.mayHaveLinkedDevicesKey,
            transaction: transaction
        )
    }
}

@objc
class OWSDeviceManagerObjcBridge: NSObject {
    @objc
    static func setHasReceivedSyncMessage(transaction: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.deviceManager.setHasReceivedSyncMessage(
            transaction: transaction.asV2Write
        )
    }
}
