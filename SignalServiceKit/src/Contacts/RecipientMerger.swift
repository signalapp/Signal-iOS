//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol RecipientMerger {
    func merge(
        trustLevel: SignalRecipientTrustLevel,
        serviceId: ServiceId?,
        phoneNumber: String?,
        transaction: DBWriteTransaction
    ) -> SignalRecipient?
}

protocol RecipientMergerTemporaryShims {
    func clearMappings(phoneNumber: String, transaction: DBWriteTransaction)
    func clearMappings(serviceId: ServiceId, transaction: DBWriteTransaction)
    func didUpdatePhoneNumber(
        oldServiceIdString: String?,
        oldPhoneNumber: String?,
        newServiceIdString: String?,
        newPhoneNumber: String?,
        transaction: DBWriteTransaction
    )
    func mergeUserProfilesIfNecessary(serviceId: ServiceId, phoneNumber: String, transaction: DBWriteTransaction)
    func hasActiveSignalProtocolSession(recipientId: String, deviceId: Int32, transaction: DBWriteTransaction) -> Bool
}

class RecipientMergerImpl: RecipientMerger {
    private let dataStore: RecipientDataStore
    private let temporaryShims: RecipientMergerTemporaryShims
    private let storageServiceManager: StorageServiceManager

    init(
        temporaryShims: RecipientMergerTemporaryShims,
        dataStore: RecipientDataStore,
        storageServiceManager: StorageServiceManager
    ) {
        self.temporaryShims = temporaryShims
        self.dataStore = dataStore
        self.storageServiceManager = storageServiceManager
    }

    func merge(
        trustLevel: SignalRecipientTrustLevel,
        serviceId: ServiceId?,
        phoneNumber: String?,
        transaction: DBWriteTransaction
    ) -> SignalRecipient? {
        guard serviceId != nil || phoneNumber != nil else {
            return nil
        }
        switch trustLevel {
        case .low:
            return mergeLowTrust(serviceId: serviceId, phoneNumber: phoneNumber, transaction: transaction)
        case .high:
            return mergeHighTrust(serviceId: serviceId, phoneNumber: phoneNumber, transaction: transaction)
        }
    }

    /// Fetches (or creates) a low-trust recipient.
    ///
    /// Low trust fetches don't indicate any relation between `serviceId` and
    /// `phoneNumber`. They might be the same account, but they also may refer
    /// to different accounts.
    ///
    /// In this method, we first try to fetch based on `serviceId`. If there's a
    /// recipient for `serviceId`, we return it as-is, even if its phone number
    /// doesn't match `phoneNumber`. If there's no recipient for `serviceId`
    /// (but `serviceId` is nonnil), we'll create a ServiceId-only recipient
    /// (i.e., we ignore `phoneNumber`).
    ///
    /// Otherwise, we try to fetch based on `phoneNumber`. If there's a
    /// recipient for the phone number, we return it as-is (even if it already
    /// has a different ServiceId specified). If there's not a recipient, we'll
    /// create a phone number-only recipient (b/c `serviceId` is nil).
    private func mergeLowTrust(serviceId: ServiceId?, phoneNumber: String?, transaction: DBWriteTransaction) -> SignalRecipient? {
        if let serviceId {
            if let serviceIdRecipient = dataStore.fetchRecipient(serviceId: serviceId, transaction: transaction) {
                return serviceIdRecipient
            }
            let newInstance = SignalRecipient(serviceId: ServiceIdObjC(serviceId), phoneNumber: nil)
            dataStore.insertRecipient(newInstance, transaction: transaction)
            return newInstance
        }
        if let phoneNumber {
            if let phoneNumberRecipient = dataStore.fetchRecipient(phoneNumber: phoneNumber, transaction: transaction) {
                return phoneNumberRecipient
            }
            let newInstance = SignalRecipient(serviceId: nil, phoneNumber: phoneNumber)
            dataStore.insertRecipient(newInstance, transaction: transaction)
            return newInstance
        }
        return nil
    }

    /// Fetches (or creates) a high-trust recipient.
    ///
    /// High trust fetches indicate that `serviceId` & `phoneNumber` refer to
    /// the same account. As part of the fetch, the database will be updated to
    /// reflect that relationship.
    ///
    /// In general, the rules we follow when applying changes are:
    ///
    /// * ACIs are immutable and representative of an account. We never change
    /// the ACI of a ``SignalRecipient`` from one ACI to another; instead we
    /// create a new ``SignalRecipient``. (However, the ACI *may* change from a
    /// nil value to a nonnil value.)
    ///
    /// * Phone numbers are transient and can move freely between ACIs. When
    /// they do, we must backfill the database to reflect the change.
    private func mergeHighTrust(serviceId: ServiceId?, phoneNumber: String?, transaction: DBWriteTransaction) -> SignalRecipient? {
        var shouldUpdate = false

        let serviceIdRecipient = serviceId.flatMap { dataStore.fetchRecipient(serviceId: $0, transaction: transaction) }
        let phoneNumberRecipient = phoneNumber.flatMap { dataStore.fetchRecipient(phoneNumber: $0, transaction: transaction) }
        let existingRecipient: SignalRecipient?

        if let serviceId, let serviceIdRecipient, let phoneNumber, let phoneNumberRecipient {
            if serviceIdRecipient.uniqueId == phoneNumberRecipient.uniqueId {
                // These are the same and both fully complete; we have no extra work to do.
                existingRecipient = phoneNumberRecipient

            } else if phoneNumberRecipient.recipientUUID == nil && serviceIdRecipient.recipientPhoneNumber == nil {
                // These are the same, but not fully complete; we need to merge them.
                shouldUpdate = true
                existingRecipient = mergeRecipients(
                    serviceId: serviceId,
                    serviceIdRecipient: serviceIdRecipient,
                    phoneNumber: phoneNumber,
                    phoneNumberRecipient: phoneNumberRecipient,
                    transaction: transaction
                )

            } else {
                // The UUID differs between the two records; we need to migrate the phone
                // number to the UUID instance.
                Logger.warn("Learned phoneNumber (\(phoneNumber))) now belongs to serviceId (\(serviceId)")

                // Ordering is critical here. We must remove the phone number from the old
                // recipient *before* we assign the phone number to the new recipient in
                // case there are any legacy phone number-only records in the database.

                shouldUpdate = true

                updateRecipient(phoneNumberRecipient, phoneNumber: nil, transaction: transaction)
                dataStore.updateRecipient(phoneNumberRecipient, transaction: transaction)

                // We've already used phoneNumberInstance.changePhoneNumber() above to
                // ensure that phoneNumberInstance does not use address.phoneNumber.
                //
                // However, phoneNumberInstance.changePhoneNumber() will only update
                // mappings in other database tables that exactly match the address
                // components of phoneNumberInstance.
                //
                // The mappings in other tables might not exactly match the mappings in the
                // SignalRecipient table. Therefore, to avoid crashes and other mapping
                // problems, we need to ensure that no other db tables have a mapping that
                // uses address.phoneNumber _before_ we use
                // uuidInstance.changePhoneNumber() with address.phoneNumber.

                temporaryShims.clearMappings(phoneNumber: phoneNumber, transaction: transaction)
                updateRecipient(serviceIdRecipient, phoneNumber: phoneNumber, transaction: transaction)

                existingRecipient = serviceIdRecipient
            }
        } else if let phoneNumber, let phoneNumberRecipient {
            if let serviceId {
                // There is no instance of SignalRecipient for the new uuid, but other db
                // tables might have mappings for the new uuid. We need to clear that out.
                temporaryShims.clearMappings(serviceId: serviceId, transaction: transaction)

                if phoneNumberRecipient.recipientUUID != nil {
                    Logger.warn("Learned phoneNumber \(phoneNumber) now belongs to serviceId \(serviceId)")

                    // The UUID associated with this phone number has changed, we must clear
                    // the phone number from this instance and create a new instance.
                    updateRecipient(phoneNumberRecipient, phoneNumber: nil, transaction: transaction)
                    dataStore.updateRecipient(phoneNumberRecipient, transaction: transaction)
                    // phoneNumberInstance is no longer associated with the phone number. We
                    // will create a "newInstance" for the new (uuid, phone number) below.
                    existingRecipient = nil
                } else {
                    Logger.info("Learned serviceId \(serviceId) is associated with phoneNumber \(phoneNumber)")

                    shouldUpdate = true
                    phoneNumberRecipient.recipientUUID = serviceId.uuidValue.uuidString
                    existingRecipient = phoneNumberRecipient
                }
            } else {
                existingRecipient = phoneNumberRecipient
            }
        } else if let serviceId, let serviceIdRecipient {
            if let phoneNumber {
                // We need to update the phone number on uuidInstance.

                // There is no instance of SignalRecipient for the new phone number, but
                // other db tables might have mappings for the new phone number. We need to
                // clear that out.
                temporaryShims.clearMappings(phoneNumber: phoneNumber, transaction: transaction)

                if let oldPhoneNumber = serviceIdRecipient.recipientPhoneNumber {
                    Logger.info("Learned serviceId \(serviceId) changed from old phoneNumber \(oldPhoneNumber) to new phoneNumber \(phoneNumber)")
                } else {
                    Logger.info("Learned serviceId \(serviceId) is associated with phoneNumber \(phoneNumber)")
                }

                shouldUpdate = true

                updateRecipient(serviceIdRecipient, phoneNumber: phoneNumber, transaction: transaction)
            } else {
                // No work is necessary.
            }

            existingRecipient = serviceIdRecipient
        } else {
            existingRecipient = nil
        }

        guard let existingRecipient else {
            Logger.debug("creating new high trust recipient: \(String(describing: serviceId)), \(String(describing: phoneNumber))")
            let newInstance = SignalRecipient(serviceId: serviceId.map { ServiceIdObjC($0) }, phoneNumber: phoneNumber)
            dataStore.insertRecipient(newInstance, transaction: transaction)
            return newInstance
        }

        // Record the updated contact in the social graph
        if shouldUpdate {
            dataStore.updateRecipient(existingRecipient, transaction: transaction)
            storageServiceManager.recordPendingUpdates(
                updatedAccountIds: [existingRecipient.accountId],
                authedAccount: .implicit()
            )
        }

        return existingRecipient
    }

    private func updateRecipient(
        _ recipient: SignalRecipient,
        phoneNumber: String?,
        transaction: DBWriteTransaction
    ) {
        let oldPhoneNumber = recipient.recipientPhoneNumber?.nilIfEmpty
        let oldServiceIdString = recipient.recipientUUID

        recipient.recipientPhoneNumber = phoneNumber?.nilIfEmpty

        if recipient.recipientPhoneNumber == nil && oldServiceIdString == nil {
            Logger.warn("Clearing out the phone number on a recipient with no serviceId; old phone number: \(String(describing: oldPhoneNumber))")
            // Fill in a random UUID, so we can complete the change and maintain a common
            // association for all the records and not leave them dangling. This should
            // in general never happen.
            recipient.recipientUUID = UUID().uuidString
        } else {
            Logger.info("Changing the phone number on a recipient; serviceId: \(oldServiceIdString ?? "nil"), phoneNumber: \(oldPhoneNumber ?? "nil") -> \(recipient.recipientPhoneNumber ?? "nil")")
        }

        temporaryShims.didUpdatePhoneNumber(
            oldServiceIdString: oldServiceIdString,
            oldPhoneNumber: oldPhoneNumber,
            newServiceIdString: recipient.recipientUUID,
            newPhoneNumber: recipient.recipientPhoneNumber,
            transaction: transaction
        )
    }

    private func mergeRecipients(
        serviceId: ServiceId,
        serviceIdRecipient: SignalRecipient,
        phoneNumber: String,
        phoneNumberRecipient: SignalRecipient,
        transaction: DBWriteTransaction
    ) -> SignalRecipient {
        owsAssertDebug(
            serviceIdRecipient.recipientPhoneNumber == nil
            || serviceIdRecipient.recipientPhoneNumber == phoneNumber
        )
        owsAssertDebug(
            phoneNumberRecipient.recipientUUID == nil
            || phoneNumberRecipient.recipientUUID == serviceId.uuidValue.uuidString
        )

        // We have separate recipients in the db for the uuid and phone number.
        // There isn't an ideal way to do this, but we need to converge on one
        // recipient and discard the other.

        // We try to preserve the recipient that has a session.
        // (Note that we don't check for PNI sessions; we always prefer the ACI session there.)
        let hasSessionForServiceId = temporaryShims.hasActiveSignalProtocolSession(
            recipientId: serviceIdRecipient.accountId,
            deviceId: Int32(OWSDevicePrimaryDeviceId),
            transaction: transaction
        )
        let hasSessionForPhoneNumber = temporaryShims.hasActiveSignalProtocolSession(
            recipientId: phoneNumberRecipient.accountId,
            deviceId: Int32(OWSDevicePrimaryDeviceId),
            transaction: transaction
        )

        let winningRecipient: SignalRecipient
        let losingRecipient: SignalRecipient

        // We want to retain the phone number recipient only if it has a session
        // and the ServiceId recipient doesn't. Historically, we tried to be clever and
        // pick the session that had seen more use, but merging sessions should
        // only happen in exceptional circumstances these days.
        if !hasSessionForServiceId && hasSessionForPhoneNumber {
            Logger.warn("Discarding serviceId recipient in favor of phone number recipient.")
            winningRecipient = phoneNumberRecipient
            losingRecipient = serviceIdRecipient
        } else {
            Logger.warn("Discarding phone number recipient in favor of serviceId recipient.")
            winningRecipient = serviceIdRecipient
            losingRecipient = phoneNumberRecipient
        }
        owsAssertBeta(winningRecipient !== losingRecipient)

        // Make sure the winning recipient is fully qualified.
        winningRecipient.recipientPhoneNumber = phoneNumber
        winningRecipient.recipientUUID = serviceId.uuidValue.uuidString

        // Discard the losing recipient.
        // TODO: Should we clean up any state related to the discarded recipient?
        dataStore.removeRecipient(losingRecipient, transaction: transaction)

        temporaryShims.mergeUserProfilesIfNecessary(
            serviceId: serviceId,
            phoneNumber: phoneNumber,
            transaction: transaction
        )

        return winningRecipient
    }
}
