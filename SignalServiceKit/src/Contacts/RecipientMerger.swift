//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

protocol RecipientMerger {
    func merge(
        trustLevel: SignalRecipientTrustLevel,
        serviceId: ServiceId?,
        phoneNumber: E164?,
        transaction: DBWriteTransaction
    ) -> SignalRecipient?
}

protocol RecipientMergerTemporaryShims {
    func clearMappings(phoneNumber: E164, transaction: DBWriteTransaction)
    func clearMappings(serviceId: ServiceId, transaction: DBWriteTransaction)
    func didUpdatePhoneNumber(
        oldServiceIdString: String?,
        oldPhoneNumber: String?,
        newServiceIdString: String?,
        newPhoneNumber: E164?,
        transaction: DBWriteTransaction
    )
    func mergeUserProfilesIfNecessary(serviceId: ServiceId, phoneNumber: E164, transaction: DBWriteTransaction)
    func hasActiveSignalProtocolSession(recipientId: String, deviceId: Int32, transaction: DBWriteTransaction) -> Bool
}

class RecipientMergerImpl: RecipientMerger {
    private let temporaryShims: RecipientMergerTemporaryShims
    private let dataStore: RecipientDataStore
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
        phoneNumber: E164?,
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
    private func mergeLowTrust(serviceId: ServiceId?, phoneNumber: E164?, transaction: DBWriteTransaction) -> SignalRecipient? {
        if let serviceId {
            if let serviceIdRecipient = dataStore.fetchRecipient(serviceId: serviceId, transaction: transaction) {
                return serviceIdRecipient
            }
            let newInstance = SignalRecipient(serviceId: ServiceIdObjC(serviceId), phoneNumber: nil)
            dataStore.insertRecipient(newInstance, transaction: transaction)
            return newInstance
        }
        if let phoneNumber {
            if let phoneNumberRecipient = dataStore.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: transaction) {
                return phoneNumberRecipient
            }
            let newInstance = SignalRecipient(serviceId: nil, phoneNumber: E164ObjC(phoneNumber))
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
    private func mergeHighTrust(serviceId: ServiceId?, phoneNumber: E164?, transaction: DBWriteTransaction) -> SignalRecipient? {
        // If we don't have both identifiers, we can't merge anything, so just
        // fetch or create a recipient with whichever identifier was provided.
        guard let serviceId, let phoneNumber else {
            return mergeLowTrust(serviceId: serviceId, phoneNumber: phoneNumber, transaction: transaction)
        }

        let serviceIdRecipient = dataStore.fetchRecipient(serviceId: serviceId, transaction: transaction)

        // If these values have already been merged, we can return the result
        // without any modifications. This will be the path taken in 99% of cases
        // (ie, we'll hit this path every time a recipient sends you a message,
        // assuming they haven't changed their phone number).
        if let serviceIdRecipient, serviceIdRecipient.recipientPhoneNumber == phoneNumber.stringValue {
            return serviceIdRecipient
        }

        // In every other case, we need to change *something*. The goal of the
        // remainder of this method is to ensure there's a `SignalRecipient` such
        // that calling this method again, immediately, with the same parameters
        // would match the the prior `if` check and return early without making any
        // modifications.

        let mergedRecipient: SignalRecipient

        switch _mergeHighTrust(
            serviceId: serviceId,
            phoneNumber: phoneNumber,
            serviceIdRecipient: serviceIdRecipient,
            transaction: transaction
        ) {
        case .some(let updatedRecipient):
            mergedRecipient = updatedRecipient
            dataStore.updateRecipient(mergedRecipient, transaction: transaction)
            storageServiceManager.recordPendingUpdates(
                updatedAccountIds: [mergedRecipient.accountId],
                authedAccount: .implicit()
            )
        case .none:
            mergedRecipient = SignalRecipient(serviceId: ServiceIdObjC(serviceId), phoneNumber: E164ObjC(phoneNumber))
            dataStore.insertRecipient(mergedRecipient, transaction: transaction)
        }

        return mergedRecipient
    }

    private func _mergeHighTrust(
        serviceId: ServiceId,
        phoneNumber: E164,
        serviceIdRecipient: SignalRecipient?,
        transaction: DBWriteTransaction
    ) -> SignalRecipient? {
        let phoneNumberRecipient = dataStore.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: transaction)

        if let serviceIdRecipient {
            if let phoneNumberRecipient {
                if phoneNumberRecipient.recipientUUID == nil && serviceIdRecipient.recipientPhoneNumber == nil {
                    // These are the same, but not fully complete; we need to merge them.
                    return mergeRecipients(
                        serviceId: serviceId,
                        serviceIdRecipient: serviceIdRecipient,
                        phoneNumber: phoneNumber,
                        phoneNumberRecipient: phoneNumberRecipient,
                        transaction: transaction
                    )
                }

                // Ordering is critical here. We must remove the phone number from the old
                // recipient *before* we assign the phone number to the new recipient in
                // case there are any legacy phone number-only records in the database.

                updateRecipient(phoneNumberRecipient, phoneNumber: nil, transaction: transaction)
                dataStore.updateRecipient(phoneNumberRecipient, transaction: transaction)

                // Fall through now that we've cleaned up `phoneNumberRecipient`.
            }

            // We've already used `updateRecipient(_:phoneNumber:…)` (if necessary) to
            // ensure that `phoneNumberInstance` doesn't use `phoneNumber`.
            //
            // However, that will only update mappings in other database tables that
            // exactly match the address components of `phoneNumberInstance`. (?)
            //
            // The mappings in other tables might not exactly match the mappings in the
            // `SignalRecipient` table. Therefore, to avoid crashes and other mapping
            // problems, we need to ensure that no other tables have mappings that use
            // `phoneNumber` _before_ we update `serviceIdRecipient`'s phone number.
            temporaryShims.clearMappings(phoneNumber: phoneNumber, transaction: transaction)

            if let oldPhoneNumber = serviceIdRecipient.recipientPhoneNumber {
                Logger.info("Learned serviceId \(serviceId) changed from old phoneNumber \(oldPhoneNumber) to new phoneNumber \(phoneNumber)")
            } else {
                Logger.info("Learned serviceId \(serviceId) is associated with phoneNumber \(phoneNumber)")
            }

            updateRecipient(serviceIdRecipient, phoneNumber: phoneNumber, transaction: transaction)
            return serviceIdRecipient
        }

        if let phoneNumberRecipient {
            // There is no SignalRecipient for the new ServiceId, but other db tables
            // might have mappings for the new ServiceId. We need to clear that out.
            temporaryShims.clearMappings(serviceId: serviceId, transaction: transaction)

            if phoneNumberRecipient.recipientUUID != nil {
                // We can't change the ServiceId because it's non-empty. Instead, we must
                // create a new SignalRecipient. We clear the phone number here since it
                // will belong to the new SignalRecipient.
                Logger.info("Learned phoneNumber \(phoneNumber) transferred to serviceId \(serviceId)")
                updateRecipient(phoneNumberRecipient, phoneNumber: nil, transaction: transaction)
                dataStore.updateRecipient(phoneNumberRecipient, transaction: transaction)
                return nil
            }

            Logger.info("Learned serviceId \(serviceId) is associated with phoneNumber \(phoneNumber)")
            phoneNumberRecipient.recipientUUID = serviceId.uuidValue.uuidString
            return phoneNumberRecipient
        }

        // We couldn't find a recipient, so create a new one.
        return nil
    }

    private func updateRecipient(
        _ recipient: SignalRecipient,
        phoneNumber: E164?,
        transaction: DBWriteTransaction
    ) {
        let oldPhoneNumber = recipient.recipientPhoneNumber?.nilIfEmpty
        let oldServiceIdString = recipient.recipientUUID

        recipient.recipientPhoneNumber = phoneNumber?.stringValue

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
            newPhoneNumber: phoneNumber,
            transaction: transaction
        )
    }

    private func mergeRecipients(
        serviceId: ServiceId,
        serviceIdRecipient: SignalRecipient,
        phoneNumber: E164,
        phoneNumberRecipient: SignalRecipient,
        transaction: DBWriteTransaction
    ) -> SignalRecipient {
        owsAssertDebug(
            serviceIdRecipient.recipientPhoneNumber == nil
            || serviceIdRecipient.recipientPhoneNumber == phoneNumber.stringValue
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
            deviceId: Int32(OWSDevice.primaryDeviceId),
            transaction: transaction
        )
        let hasSessionForPhoneNumber = temporaryShims.hasActiveSignalProtocolSession(
            recipientId: phoneNumberRecipient.accountId,
            deviceId: Int32(OWSDevice.primaryDeviceId),
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
        winningRecipient.recipientPhoneNumber = phoneNumber.stringValue
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
