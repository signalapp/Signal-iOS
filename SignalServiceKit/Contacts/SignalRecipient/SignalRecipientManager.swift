//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol SignalRecipientManager {
    func fetchRecipientIfPhoneNumberVisible(
        _ phoneNumber: String,
        tx: DBReadTransaction
    ) -> SignalRecipient?

    func modifyAndSave(
        _ recipient: SignalRecipient,
        deviceIdsToAdd: [DeviceId],
        deviceIdsToRemove: [DeviceId],
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
        deviceId: DeviceId = .primary,
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

final public class SignalRecipientManagerImpl: SignalRecipientManager {
    private let phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher
    private let recipientDatabaseTable: RecipientDatabaseTable
    let storageServiceManager: any StorageServiceManager

    public init(
        phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher,
        recipientDatabaseTable: RecipientDatabaseTable,
        storageServiceManager: any StorageServiceManager
    ) {
        self.phoneNumberVisibilityFetcher = phoneNumberVisibilityFetcher
        self.recipientDatabaseTable = recipientDatabaseTable
        self.storageServiceManager = storageServiceManager
    }

    public func fetchRecipientIfPhoneNumberVisible(_ phoneNumber: String, tx: DBReadTransaction) -> SignalRecipient? {
        let recipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber, transaction: tx)
        guard let recipient else {
            return nil
        }
        guard phoneNumberVisibilityFetcher.isPhoneNumberVisible(for: recipient, tx: tx) else {
            return nil
        }
        return recipient
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
        deviceIdsToAdd: [DeviceId],
        deviceIdsToRemove: [DeviceId],
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        var deviceIdsToAdd = deviceIdsToAdd
        // Always add the primary if any other device is registered.
        if !deviceIdsToAdd.isEmpty {
            deviceIdsToAdd.append(.primary)
        }

        let oldDeviceIds: Set<DeviceId> = Set(recipient.deviceIds)
        let newDeviceIds: Set<DeviceId> = oldDeviceIds.union(deviceIdsToAdd).subtracting(deviceIdsToRemove)

        if oldDeviceIds == newDeviceIds {
            return
        }

        Logger.info("Updating \(recipient.aci?.logString ?? recipient.pni?.logString ?? "<>")'s devices. Added \(newDeviceIds.subtracting(oldDeviceIds).sorted()). Removed \(oldDeviceIds.subtracting(newDeviceIds).sorted()).")

        setDeviceIds(newDeviceIds, for: recipient, shouldUpdateStorageService: shouldUpdateStorageService)
        recipientDatabaseTable.updateRecipient(recipient, transaction: tx)
    }
}
