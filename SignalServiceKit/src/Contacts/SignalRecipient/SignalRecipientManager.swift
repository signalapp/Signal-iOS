//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SignalRecipientManager {
    func modifyAndSave(
        _ recipient: SignalRecipient,
        deviceIdsToAdd: [UInt32],
        deviceIdsToRemove: [UInt32],
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction
    )

    func markAsUnregisteredAndSave(
        _ recipient: SignalRecipient,
        unregisteredAt: UnregisteredAt,
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction
    )
}

public enum UnregisteredAt {
    case now
    case specificTimeFromOtherDevice(UInt64)
}

extension SignalRecipientManager {
    public func markAsRegisteredAndSave(
        _ recipient: SignalRecipient,
        deviceId: UInt32 = OWSDevice.primaryDeviceId,
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        modifyAndSave(
            recipient,
            deviceIdsToAdd: [deviceId],
            deviceIdsToRemove: [],
            shouldUpdateStorageService: shouldUpdateStorageService,
            tx: tx
        )
    }

}

public class SignalRecipientManagerImpl: SignalRecipientManager {
    private let recipientDatabaseTable: any RecipientDatabaseTable
    let storageServiceManager: any StorageServiceManager

    public init(
        recipientDatabaseTable: any RecipientDatabaseTable,
        storageServiceManager: any StorageServiceManager
    ) {
        self.recipientDatabaseTable = recipientDatabaseTable
        self.storageServiceManager = storageServiceManager
    }

    public func markAsUnregisteredAndSave(
        _ recipient: SignalRecipient,
        unregisteredAt: UnregisteredAt,
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        if case .specificTimeFromOtherDevice(let timestamp) = unregisteredAt {
            setUnregisteredAtTimestamp(timestamp, for: recipient, shouldUpdateStorageService: shouldUpdateStorageService)
        }
        modifyAndSave(
            recipient,
            deviceIdsToAdd: [],
            deviceIdsToRemove: recipient.deviceIds,
            shouldUpdateStorageService: shouldUpdateStorageService,
            tx: tx
        )
    }

    public func modifyAndSave(
        _ recipient: SignalRecipient,
        deviceIdsToAdd: [UInt32],
        deviceIdsToRemove: [UInt32],
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        var deviceIdsToAdd = deviceIdsToAdd
        // Always add the primary if any other device is registered.
        if !deviceIdsToAdd.isEmpty {
            deviceIdsToAdd.append(OWSDevice.primaryDeviceId)
        }

        let oldDeviceIds = Set(recipient.deviceIds)
        let newDeviceIds = oldDeviceIds.union(deviceIdsToAdd).subtracting(deviceIdsToRemove)

        if oldDeviceIds == newDeviceIds {
            return
        }

        Logger.info("Updating \(recipient.addressComponentsDescription)'s devices. Added \(newDeviceIds.subtracting(oldDeviceIds).sorted()). Removed \(oldDeviceIds.subtracting(newDeviceIds).sorted()).")

        setDeviceIds(newDeviceIds, for: recipient, shouldUpdateStorageService: shouldUpdateStorageService)
        recipientDatabaseTable.updateRecipient(recipient, transaction: tx)
    }
}
