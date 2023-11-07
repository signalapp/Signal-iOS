//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public protocol RecipientMerger {
    /// We're registering, linking, changing our number, etc. This is the only
    /// time we're allowed to "merge" the identifiers for our own account.
    func applyMergeForLocalAccount(
        aci: Aci,
        phoneNumber: E164,
        pni: Pni?,
        tx: DBWriteTransaction
    ) -> SignalRecipient

    /// We've learned about an association from Storage Service.
    func applyMergeFromStorageService(
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        serviceIds: AtLeastOneServiceId,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient

    func applyMergeFromContactSync(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient

    /// We've learned about an association from CDS.
    func applyMergeFromContactDiscovery(
        localIdentifiers: LocalIdentifiers,
        phoneNumber: E164,
        pni: Pni,
        aci: Aci?,
        tx: DBWriteTransaction
    ) -> SignalRecipient?

    /// We've learned about an association from a Sealed Sender message. These
    /// always come from an ACI, but they might not have a phone number if phone
    /// number sharing is disabled.
    func applyMergeFromSealedSender(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient

    func applyMergeFromPniSignature(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        pni: Pni,
        tx: DBWriteTransaction
    )
}

protocol RecipientMergeObserver {
    /// We are about to learn a new association between identifiers.
    ///
    /// - parameter recipient: The recipient whose identifiers are about to be
    /// removed or replaced.
    ///
    /// - parameter mightReplaceNonnilPhoneNumber: If true, we might be about to
    /// update an ACI/phone number association. This property exists mostly as a
    /// performance optimization for ``AuthorMergeObserver``.
    func willBreakAssociation(for recipient: SignalRecipient, mightReplaceNonnilPhoneNumber: Bool, tx: DBWriteTransaction)

    /// We just learned a new association between identifiers.
    ///
    /// If you provide only a single identifier to a merge, then it's not
    /// possible for us to learn about an association. However, if you provide
    /// two or more identifiers, and if it's the first time we've learned that
    /// they're linked, this callback will be invoked.
    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction)
}

struct MergedRecipient {
    let isLocalRecipient: Bool
    let oldRecipient: SignalRecipient?
    let newRecipient: SignalRecipient
}

class RecipientMergerImpl: RecipientMerger {
    private let aciSessionStore: SignalSessionStore
    private let identityManager: OWSIdentityManager
    private let observers: Observers
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let recipientFetcher: RecipientFetcher
    private let storageServiceManager: StorageServiceManager

    /// Initializes a RecipientMerger.
    ///
    /// - Parameter observers: Observers that are notified after a new
    /// association is learned. They are notified in the same transaction in
    /// which we learned about the new association, and they are notified in the
    /// order in which they are provided.
    init(
        aciSessionStore: SignalSessionStore,
        identityManager: OWSIdentityManager,
        observers: Observers,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        storageServiceManager: StorageServiceManager
    ) {
        self.aciSessionStore = aciSessionStore
        self.identityManager = identityManager
        self.observers = observers
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.storageServiceManager = storageServiceManager
    }

    struct Observers {
        let preThreadMerger: [RecipientMergeObserver]
        let threadMerger: ThreadMerger
        let postThreadMerger: [RecipientMergeObserver]
    }

    static func buildObservers(
        authorMergeHelper: AuthorMergeHelper,
        callRecordStore: CallRecordStore,
        chatColorSettingStore: ChatColorSettingStore,
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore,
        groupMemberUpdater: GroupMemberUpdater,
        groupMemberStore: GroupMemberStore,
        interactionStore: InteractionStore,
        profileManager: ProfileManagerProtocol,
        recipientMergeNotifier: RecipientMergeNotifier,
        signalServiceAddressCache: SignalServiceAddressCache,
        threadAssociatedDataStore: ThreadAssociatedDataStore,
        threadRemover: ThreadRemover,
        threadReplyInfoStore: ThreadReplyInfoStore,
        threadStore: ThreadStore,
        userProfileStore: UserProfileStore,
        wallpaperStore: WallpaperStore
    ) -> Observers {
        // PNI TODO: Merge ReceiptForLinkedDevice if needed.
        return Observers(
            preThreadMerger: [
                signalServiceAddressCache,
                AuthorMergeObserver(authorMergeHelper: authorMergeHelper),
                SignalAccountMergeObserver(),
                ProfileWhitelistMerger(profileManager: profileManager),
                UserProfileMerger(userProfileStore: userProfileStore),
            ],
            threadMerger: ThreadMerger(
                callRecordStore: callRecordStore,
                chatColorSettingStore: chatColorSettingStore,
                disappearingMessagesConfigurationManager: ThreadMerger.Wrappers.DisappearingMessagesConfigurationManager(),
                disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
                interactionStore: interactionStore,
                pinnedThreadManager: ThreadMerger.Wrappers.PinnedThreadManager(),
                sdsThreadMerger: ThreadMerger.Wrappers.SDSThreadMerger(),
                threadAssociatedDataManager: ThreadMerger.Wrappers.ThreadAssociatedDataManager(),
                threadAssociatedDataStore: threadAssociatedDataStore,
                threadRemover: threadRemover,
                threadReplyInfoStore: threadReplyInfoStore,
                threadStore: threadStore,
                wallpaperStore: wallpaperStore
            ),
            postThreadMerger: [
                // The group member MergeObserver depends on `SignalServiceAddressCache`,
                // so ensure that one's listed first.
                GroupMemberMergeObserverImpl(
                    threadStore: threadStore,
                    groupMemberUpdater: groupMemberUpdater,
                    groupMemberStore: groupMemberStore
                ),
                PhoneNumberChangedMessageInserter(
                    groupMemberStore: groupMemberStore,
                    interactionStore: interactionStore,
                    threadAssociatedDataStore: threadAssociatedDataStore,
                    threadStore: threadStore
                ),
                recipientMergeNotifier
            ]
        )
    }

    func applyMergeForLocalAccount(
        aci: Aci,
        phoneNumber: E164,
        pni: Pni?,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        let aciResult = mergeAlways(aci: aci, phoneNumber: phoneNumber, isLocalRecipient: true, tx: tx)
        if let pni {
            return mergeAlways(phoneNumber: phoneNumber, pni: pni, isLocalRecipient: true, tx: tx)
        }
        return aciResult
    }

    func applyMergeFromStorageService(
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        serviceIds: AtLeastOneServiceId,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        // The caller checks this, but we assert here to maintain consistency with
        // all the other merging methods that check this themselves.
        owsAssert(!localIdentifiers.containsAnyOf(aci: serviceIds.aci, phoneNumber: phoneNumber, pni: serviceIds.pni))

        let updatedValues = { () -> (phoneNumber: E164, pni: Pni)? in
            let pni = serviceIds.pni
            // A primary device must not change an E164/PNI association based on a
            // merge from Storage Service. Instead, it will ignore the change and trust
            // CDS to tell it the correct value.
            if isPrimaryDevice {
                // If we already have a PNI for this phone number, use that.
                if let phoneNumber, let alreadyKnownPni = fetchPni(for: phoneNumber, tx: tx) {
                    return (phoneNumber, alreadyKnownPni)
                }
                // If we already have a phone number for this PNI, use that.
                if let pni, let alreadyKnownPhoneNumber = fetchPhoneNumber(for: pni, tx: tx) {
                    return (alreadyKnownPhoneNumber, pni)
                }
            } else {
                // If no phone number is specified and we know it, use that.
                if phoneNumber == nil, let pni, let alreadyKnownPhoneNumber = fetchPhoneNumber(for: pni, tx: tx) {
                    return (alreadyKnownPhoneNumber, pni)
                }
            }
            return nil
        }()

        return _applyValidatedMergeFromStorageService(
            isPrimaryDevice: isPrimaryDevice,
            serviceIds: AtLeastOneServiceId(aci: serviceIds.aci, pni: updatedValues?.pni ?? serviceIds.pni)!,
            phoneNumber: updatedValues?.phoneNumber ?? phoneNumber,
            tx: tx
        )
    }

    private func _applyValidatedMergeFromStorageService(
        isPrimaryDevice: Bool,
        serviceIds: AtLeastOneServiceId,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        // If there's a phone number, things are straightforward.
        let aciPhoneNumberRecipient: SignalRecipient? = {
            guard let aci = serviceIds.aci, let phoneNumber else {
                return nil
            }
            // Explicit cast to guarantee this method doesn't return an Optional.
            return mergeAlways(aci: aci, phoneNumber: phoneNumber, isLocalRecipient: false, tx: tx) as SignalRecipient
        }()
        let phoneNumberPniRecipient: SignalRecipient? = {
            guard let phoneNumber, let pni = serviceIds.pni else {
                return nil
            }
            // Explicit cast to guarantee this method doesn't return an Optional.
            return mergeAlways(phoneNumber: phoneNumber, pni: pni, isLocalRecipient: false, tx: tx) as SignalRecipient
        }()
        if let phoneNumberResult = phoneNumberPniRecipient ?? aciPhoneNumberRecipient {
            return phoneNumberResult
        }

        // If we have an E164, then at least one of the two `mergeAlways` calls
        // above will be triggered. This happens because we have
        // `AtLeastOneServiceId`. If we reach this point, it means we don't have a
        // phone number, so we try a special ACI/PNI fill-in-the-blanks merge.
        if let aci = serviceIds.aci, let pni = serviceIds.pni {
            return mergeAlwaysFromStorageService(isPrimaryDevice: isPrimaryDevice, aci: aci, pni: pni, tx: tx)
        }

        // Finally, we just fall back to the single present identifier.
        return recipientFetcher.fetchOrCreate(serviceId: serviceIds.aciOrElsePni, tx: tx)
    }

    func applyMergeFromContactSync(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        guard let phoneNumber else {
            return recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        }
        return mergeIfNotLocalIdentifier(localIdentifiers: localIdentifiers, aci: aci, phoneNumber: phoneNumber, tx: tx)
    }

    func applyMergeFromSealedSender(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        guard let phoneNumber else {
            return recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        }
        return mergeIfNotLocalIdentifier(localIdentifiers: localIdentifiers, aci: aci, phoneNumber: phoneNumber, tx: tx)
    }

    func applyMergeFromPniSignature(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        pni: Pni,
        tx: DBWriteTransaction
    ) {
        guard
            let aciRecipient = recipientDatabaseTable.fetchRecipient(serviceId: aci, transaction: tx),
            let pniRecipient = recipientDatabaseTable.fetchRecipient(serviceId: pni, transaction: tx),
            pniRecipient.aciString == nil
        else {
            owsFail("Can't apply PNI signature merge with precondition violations")
        }

        if localIdentifiers.containsAnyOf(aci: aci, phoneNumber: nil, pni: pni) {
            Logger.warn("Can't apply PNI signature merge with our own identifiers")
            return
        }

        mergeAndNotify(
            existingRecipients: [pniRecipient, aciRecipient],
            mightReplaceNonnilPhoneNumber: true,
            insertSessionSwitchoverIfNeeded: false,
            isLocalMerge: false,
            tx: tx
        ) {
            aciRecipient.phoneNumber = pniRecipient.phoneNumber
            aciRecipient.pni = pniRecipient.pni
            pniRecipient.phoneNumber = nil
            pniRecipient.pni = nil
            return aciRecipient
        }
    }

    func applyMergeFromContactDiscovery(
        localIdentifiers: LocalIdentifiers,
        phoneNumber: E164,
        pni: Pni,
        aci: Aci?,
        tx: DBWriteTransaction
    ) -> SignalRecipient? {
        // If you type in your own phone number, ignore the result and return your
        // own recipient.
        if localIdentifiers.contains(phoneNumber: phoneNumber) {
            return recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx)
        }
        // Otherwise, if CDS tells us that our PNI belongs to some other account,
        // we can't fulfill the request. If we did fulfill the request, we'd either
        // return a result without a PNI or a result with a stale PNI. Both of
        // those are unacceptable.
        if localIdentifiers.pni == pni {
            return nil
        }
        // Finally, if CDS tells us our ACI is associated with another phone
        // number, ignore the ACI and process the phone number/PNI pair.
        var aci = aci
        if localIdentifiers.aci == aci {
            aci = nil
        }
        if let aci {
            _ = mergeAlways(aci: aci, phoneNumber: phoneNumber, isLocalRecipient: false, tx: tx)
        }
        return mergeAlways(phoneNumber: phoneNumber, pni: pni, isLocalRecipient: false, tx: tx)
    }

    /// Performs a merge unless a provided identifier refers to the local user.
    ///
    /// With the exception of registration, change number, etc., we're never
    /// allowed to initiate a merge with our own identifiers. Instead, we simply
    /// return whichever recipient exists for the provided `aci`.
    private func mergeIfNotLocalIdentifier(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        if localIdentifiers.containsAnyOf(aci: aci, phoneNumber: phoneNumber, pni: nil) {
            return recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        }
        return mergeAlways(aci: aci, phoneNumber: phoneNumber, isLocalRecipient: false, tx: tx)
    }

    // MARK: - Merge Logic

    /// Performs a merge for the provided identifiers.
    ///
    /// There may be a ``SignalRecipient`` for one or more of the provided
    /// identifiers. If there is, we'll update and return that value (see the
    /// rules below). Otherwise, we'll create a new instance.
    ///
    /// A merge indicates that `aci` & `phoneNumber` refer to the same account.
    /// As part of this operation, the database will be updated to reflect that
    /// relationship.
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
    private func mergeAlways(
        aci: Aci,
        phoneNumber: E164,
        isLocalRecipient: Bool,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        let aciRecipient = recipientDatabaseTable.fetchRecipient(serviceId: aci, transaction: tx)

        // If these values have already been merged, we can return the result
        // without any modifications. This will be the path taken in 99% of cases
        // (ie, we'll hit this path every time a recipient sends you a message,
        // assuming they haven't changed their phone number).
        if let aciRecipient, aciRecipient.phoneNumber == phoneNumber.stringValue {
            return aciRecipient
        }

        Logger.info("Updating \(aci)'s phone number")

        // In every other case, we need to change *something*. The goal of the
        // remainder of this method is to ensure there's a `SignalRecipient` such
        // that calling this method again, immediately, with the same parameters
        // would match the the prior `if` check and return early without making any
        // modifications.

        let phoneNumberRecipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx)
        let alreadyKnownPni = phoneNumberRecipient?.pni

        return mergeAndNotify(
            existingRecipients: [phoneNumberRecipient, aciRecipient].compacted(),
            mightReplaceNonnilPhoneNumber: true,
            insertSessionSwitchoverIfNeeded: true,
            isLocalMerge: isLocalRecipient,
            tx: tx
        ) {
            let existingRecipient = _mergeHighTrust(
                aci: aci,
                phoneNumber: phoneNumber,
                aciRecipient: aciRecipient,
                phoneNumberRecipient: phoneNumberRecipient,
                tx: tx
            )
            return existingRecipient ?? SignalRecipient(aci: aci, pni: alreadyKnownPni, phoneNumber: phoneNumber)
        }
    }

    private func _mergeHighTrust(
        aci: Aci,
        phoneNumber: E164,
        aciRecipient: SignalRecipient?,
        phoneNumberRecipient: SignalRecipient?,
        tx: DBWriteTransaction
    ) -> SignalRecipient? {
        if let aciRecipient {
            guard let phoneNumberRecipient else {
                aciRecipient.phoneNumber = phoneNumber.stringValue
                aciRecipient.pni = nil
                return aciRecipient
            }

            aciRecipient.phoneNumber = phoneNumberRecipient.phoneNumber
            aciRecipient.pni = phoneNumberRecipient.pni
            phoneNumberRecipient.phoneNumber = nil
            phoneNumberRecipient.pni = nil
            return aciRecipient
        }

        if let phoneNumberRecipient {
            if phoneNumberRecipient.aciString != nil {
                // We can't change the ACI because it's non-empty. Instead, we must create
                // a new SignalRecipient. We clear the phone number here since it will
                // belong to the new SignalRecipient.
                phoneNumberRecipient.phoneNumber = nil
                phoneNumberRecipient.pni = nil
                return nil
            }

            phoneNumberRecipient.aci = aci
            return phoneNumberRecipient
        }

        // We couldn't find a recipient, so create a new one.
        return nil
    }

    @discardableResult
    private func mergeAlways(
        phoneNumber: E164,
        pni: Pni,
        isLocalRecipient: Bool,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        let phoneNumberRecipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx)

        // If the phone number & PNI are already associated, do nothing.
        if let phoneNumberRecipient, phoneNumberRecipient.pni == pni {
            return phoneNumberRecipient
        }

        Logger.info("Associating \(pni) with a phone number")

        let pniRecipient = recipientDatabaseTable.fetchRecipient(serviceId: pni, transaction: tx)

        return mergeAndNotify(
            existingRecipients: [pniRecipient, phoneNumberRecipient].compacted(),
            mightReplaceNonnilPhoneNumber: false,
            insertSessionSwitchoverIfNeeded: true,
            isLocalMerge: isLocalRecipient,
            tx: tx
        ) {
            let existingRecipient = _mergeAlways(
                phoneNumber: phoneNumber,
                pni: pni,
                phoneNumberRecipient: phoneNumberRecipient,
                pniRecipient: pniRecipient,
                tx: tx
            )
            return existingRecipient ?? SignalRecipient(aci: nil, pni: pni, phoneNumber: phoneNumber)
        }
    }

    private func _mergeAlways(
        phoneNumber: E164,
        pni: Pni,
        phoneNumberRecipient: SignalRecipient?,
        pniRecipient: SignalRecipient?,
        tx: DBWriteTransaction
    ) -> SignalRecipient? {
        // If we have a phoneNumberRecipient, we'll always prefer that one because
        // the PNI is property of the phone number (not the other way).
        if let phoneNumberRecipient {
            guard let pniRecipient else {
                // If the PNI isn't on some other row, add it to this one.
                phoneNumberRecipient.pni = pni
                return phoneNumberRecipient
            }
            // If the PNI is on some other row, steal it for this one.
            phoneNumberRecipient.pni = pni
            pniRecipient.pni = nil
            return phoneNumberRecipient
        }

        // If we have a pniRecipient, we can use it if it doesn't have a phone
        // number. If it does, that takes precedence, and we need a new recipient.
        if let pniRecipient {
            if pniRecipient.phoneNumber != nil {
                pniRecipient.pni = nil
                return nil
            }

            pniRecipient.phoneNumber = phoneNumber.stringValue
            return pniRecipient
        }

        // We couldn't find a recipient, so create a new one.
        return nil
    }

    private func mergeAlwaysFromStorageService(
        isPrimaryDevice: Bool,
        aci: Aci,
        pni: Pni,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        let aciRecipient = recipientDatabaseTable.fetchRecipient(serviceId: aci, transaction: tx)

        // If the ACI & PNI are already associated, do nothing.
        if let aciRecipient, aciRecipient.pni == pni {
            return aciRecipient
        }

        Logger.info("Associating \(aci) with \(pni)")

        let pniRecipient = recipientDatabaseTable.fetchRecipient(serviceId: pni, transaction: tx)
        owsAssertDebug(pniRecipient?.phoneNumber == nil)

        return mergeAndNotify(
            existingRecipients: [aciRecipient, pniRecipient].compacted(),
            mightReplaceNonnilPhoneNumber: false,
            insertSessionSwitchoverIfNeeded: true,
            isLocalMerge: false,
            tx: tx
        ) {
            let existingRecipient = _mergeAlwaysFromStorageService(
                aci: aci,
                pni: pni,
                isPrimaryDevice: isPrimaryDevice,
                aciRecipient: aciRecipient,
                pniRecipient: pniRecipient,
                tx: tx
            )
            return existingRecipient ?? SignalRecipient(aci: aci, pni: pni, phoneNumber: nil)
        }
    }

    private func _mergeAlwaysFromStorageService(
        aci: Aci,
        pni: Pni,
        isPrimaryDevice: Bool,
        aciRecipient: SignalRecipient?,
        pniRecipient: SignalRecipient?,
        tx: DBWriteTransaction
    ) -> SignalRecipient? {
        if let aciRecipient {
            let canAssignPni: Bool = {
                if aciRecipient.phoneNumber == nil {
                    // If there's no phone number, we're not changing an E164/PNI association.
                    return true
                }
                if aciRecipient.pni == nil {
                    // If there's no PNI, then we're making the initial association, which is fine.
                    return true
                }
                if !isPrimaryDevice {
                    // If we're a linked device, then we're allowed to change any association.
                    return true
                }
                return false
            }()
            if canAssignPni {
                if let pniRecipient {
                    pniRecipient.phoneNumber = nil
                    pniRecipient.pni = nil
                }
                aciRecipient.pni = pni
            }
            return aciRecipient
        }

        if let pniRecipient {
            if pniRecipient.aciString != nil {
                pniRecipient.phoneNumber = nil
                pniRecipient.pni = nil
                return nil
            }
            pniRecipient.aci = aci
            return pniRecipient
        }

        return nil
    }

    // MARK: - Helpers

    private func fetchPni(for phoneNumber: E164, tx: DBReadTransaction) -> Pni? {
        return recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx)?.pni
    }

    private func fetchPhoneNumber(for pni: Pni, tx: DBReadTransaction) -> E164? {
        return E164(recipientDatabaseTable.fetchRecipient(serviceId: pni, transaction: tx)?.phoneNumber)
    }

    // MARK: - Merge Handling

    @discardableResult
    private func mergeAndNotify(
        existingRecipients: [SignalRecipient],
        mightReplaceNonnilPhoneNumber: Bool,
        insertSessionSwitchoverIfNeeded: Bool,
        isLocalMerge: Bool,
        tx: DBWriteTransaction,
        applyMerge: () -> SignalRecipient
    ) -> SignalRecipient {
        let oldRecipients = existingRecipients.map { $0.copyRecipient() }

        // If PN_1 is associated with ACI_A when this method starts, and if we're
        // trying to associate PN_1 with ACI_B, then we should ensure everything
        // that currently references PN_1 is updated to reference ACI_A. At this
        // point in time, everything we've saved locally with PN_1 is associated
        // with the ACI_A account, so we should mark it as such in the database.
        // After this point, everything new will be associated with ACI_B.
        //
        // Also, if PN_2 is associated with ACI_B when this method starts, and if
        // we're trying to associate PN_1 with ACI_B, then we also should ensure
        // everything that currently references PN_2 is updated to reference ACI_B.
        existingRecipients.forEach { recipient in
            observers.willBreakAssociation(for: recipient, mightReplaceNonnilPhoneNumber: mightReplaceNonnilPhoneNumber, tx: tx)
        }

        let mergedRecipient = applyMerge()

        let sessionEvents = prepareSessionEventsToInsert(
            oldRecipients: oldRecipients,
            newRecipients: existingRecipients,
            mergedRecipient: mergedRecipient,
            tx: tx
        )

        // Always put `mergedRecipient` at the end to ensure we don't violate
        // UNIQUE constraints. Note that `mergedRecipient` might be brand new, so
        // we might not find it during the call to `removeAll`.
        var affectedRecipients = existingRecipients
        affectedRecipients.removeAll(where: { $0.uniqueId == mergedRecipient.uniqueId })
        affectedRecipients.append(mergedRecipient)

        for affectedRecipient in affectedRecipients {
            if affectedRecipient.isEmpty {
                // TODO: Should we clean up any more state related to the discarded recipient?
                aciSessionStore.mergeRecipient(affectedRecipient, into: mergedRecipient, tx: tx)
                identityManager.mergeRecipient(affectedRecipient, into: mergedRecipient, tx: tx)
                recipientDatabaseTable.removeRecipient(affectedRecipient, transaction: tx)
            } else if existingRecipients.contains(where: { $0.uniqueId == affectedRecipient.uniqueId }) {
                recipientDatabaseTable.updateRecipient(affectedRecipient, transaction: tx)
            } else {
                recipientDatabaseTable.insertRecipient(affectedRecipient, transaction: tx)
            }
        }

        storageServiceManager.recordPendingUpdates(updatedAccountIds: affectedRecipients.map { $0.uniqueId })

        let threadMergeEventCount = observers.didLearnAssociation(
            mergedRecipient: MergedRecipient(
                isLocalRecipient: isLocalMerge,
                oldRecipient: oldRecipients.first(where: { $0.uniqueId == mergedRecipient.uniqueId }),
                newRecipient: mergedRecipient
            ),
            tx: tx
        )

        for sessionEvent in sessionEvents {
            insertSessionEvent(
                sessionEvent,
                insertSessionSwitchoverIfNeeded: insertSessionSwitchoverIfNeeded,
                mergedRecipient: mergedRecipient,
                mergedRecipientHasThreadMergeEvent: threadMergeEventCount > 0,
                tx: tx
            )
        }

        return mergedRecipient
    }

    // MARK: - Events

    private enum SessionEvent {
        case sessionSwitchover(SignalRecipient, phoneNumber: String?)
        case safetyNumberChange(SignalRecipient, wasIdentityVerified: Bool)
    }

    private func prepareSessionEventsToInsert(
        oldRecipients: [SignalRecipient],
        newRecipients: [SignalRecipient],
        mergedRecipient: SignalRecipient,
        tx: DBWriteTransaction
    ) -> [SessionEvent] {
        var result = [SessionEvent]()
        for (oldRecipient, newRecipient) in zip(oldRecipients, newRecipients) {
            let recipientPair = MergePair(
                fromValue: oldRecipient,
                intoValue: newRecipient.isEmpty ? mergedRecipient : newRecipient
            )

            guard aciSessionStore.mightContainSession(for: recipientPair.fromValue, tx: tx) else {
                continue
            }

            // Check out `sessionIdentifier(for:)` to understand this logic.
            let sessionIdentifier = recipientPair.map { self.sessionIdentifier(for: $0) }
            if sessionIdentifier.fromValue != sessionIdentifier.intoValue {
                result.append(prepareSessionSwitchoverEvent(recipientPair: recipientPair, tx: tx))
                continue
            }

            let recipientIdentity = recipientPair.map { identityManager.recipientIdentity(for: $0.uniqueId, tx: tx) }
            if
                let fromValue = recipientIdentity.fromValue,
                let intoValue = recipientIdentity.intoValue,
                fromValue.identityKey != intoValue.identityKey
            {
                result.append(.safetyNumberChange(recipientPair.intoValue, wasIdentityVerified: fromValue.wasIdentityVerified))
                continue
            }
        }
        return result
    }

    private func prepareSessionSwitchoverEvent(
        recipientPair: MergePair<SignalRecipient>,
        tx: DBWriteTransaction
    ) -> SessionEvent {
        // If we're UPDATING a recipient, then we need to clear the session. If
        // we're MERGING a recipient, then the merge destination should already
        // have its own session; if it doesn't, then the caller will handle merging
        // the session/identity for these recipients.
        if recipientPair.fromValue.uniqueId == recipientPair.intoValue.uniqueId {
            identityManager.removeRecipientIdentity(for: recipientPair.fromValue.uniqueId, tx: tx)
            aciSessionStore.deleteAllSessions(for: recipientPair.fromValue.uniqueId, tx: tx)
        }

        // The canonical case is adding an ACI to a recipient that already had a
        // phone number. Other cases shouldn't happen, so we show a generic
        // fallback message in those cases.
        return .sessionSwitchover(recipientPair.intoValue, phoneNumber: {
            if let phoneNumber = recipientPair.fromValue.phoneNumber, recipientPair.intoValue.aciString != nil {
                return phoneNumber
            }
            return nil
        }())
    }

    private func insertSessionEvent(
        _ sessionEvent: SessionEvent,
        insertSessionSwitchoverIfNeeded: Bool,
        mergedRecipient: SignalRecipient,
        mergedRecipientHasThreadMergeEvent: Bool,
        tx: DBWriteTransaction
    ) {
        switch sessionEvent {
        case .sessionSwitchover(let recipient, let phoneNumber):
            guard insertSessionSwitchoverIfNeeded else {
                // We have a valid PNI signature, so we don't need an SSE.
                break
            }
            if recipient.uniqueId == mergedRecipient.uniqueId, mergedRecipientHasThreadMergeEvent {
                // We have a thread merge event, so we don't need an SSE for this
                // recipient. Note that we may have stolen the PNI from some other thread,
                // and *that* thread might need an event.
                break
            }
            identityManager.insertSessionSwitchoverEvent(for: recipient, phoneNumber: phoneNumber, tx: tx)
        case .safetyNumberChange(let recipient, let wasIdentityVerified):
            guard let aci = recipient.aci else {
                owsFailDebug("Can't insert a Safety Number event without an ACI.")
                break
            }
            identityManager.insertIdentityChangeInfoMessage(for: aci, wasIdentityVerified: wasIdentityVerified, tx: tx)
        }
    }

    /// Returns an opaque "session identifier" for the recipient.
    ///
    /// When this identifier changes, we need to insert a session switchover
    /// event. We do so when switching from the PNI session to the ACI session,
    /// when losing the PNI but keeping the phone number, or when switching from
    /// one PNI to another PNI. The latter two shouldn't happen, but they are
    /// technically session switchovers and therefore need to be handled.
    ///
    /// Notable behaviors:
    /// - Once an ACI is assigned, no session switchovers are possible.
    /// - Once an ACI is assigned, it never changes (hence the "aci" constant).
    /// - If the PNI changes, so does the session identifier.
    /// - If the PNI disappears, we add a preemptive session switchover since we
    /// won't add one when learning the new PNI.
    /// - If a phone number-only recipient learns an ACI, that's not a session
    /// switchover. Instead, it's part of a years-old migration from phone
    /// numbers to ACIs.
    private func sessionIdentifier(for recipient: SignalRecipient) -> some Equatable {
        if recipient.aci == nil, let pni = recipient.pni {
            return pni.serviceIdString
        }
        return "aci"
    }
}

// MARK: - Observers

extension RecipientMergerImpl.Observers {
    func willBreakAssociation(for recipient: SignalRecipient, mightReplaceNonnilPhoneNumber: Bool, tx: DBWriteTransaction) {
        return notifyObservers(
            notifyObserver: { $0.willBreakAssociation(for: recipient, mightReplaceNonnilPhoneNumber: mightReplaceNonnilPhoneNumber, tx: tx) },
            notifyThreadMerger: { threadMerger.willBreakAssociation(for: recipient, mightReplaceNonnilPhoneNumber: mightReplaceNonnilPhoneNumber, tx: tx) }
        )
    }

    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction) -> Int {
        return notifyObservers(
            notifyObserver: { $0.didLearnAssociation(mergedRecipient: mergedRecipient, tx: tx) },
            notifyThreadMerger: { threadMerger.didLearnAssociation(mergedRecipient: mergedRecipient, tx: tx) }
        )
    }

    private func notifyObservers<T>(
        notifyObserver: (RecipientMergeObserver) -> Void,
        notifyThreadMerger: () -> T
    ) -> T {
        preThreadMerger.forEach(notifyObserver)
        let result = notifyThreadMerger()
        postThreadMerger.forEach(notifyObserver)
        return result
    }
}

// MARK: - SignalServiceAddressCache

extension SignalServiceAddressCache: RecipientMergeObserver {
    func willBreakAssociation(for recipient: SignalRecipient, mightReplaceNonnilPhoneNumber: Bool, tx: DBWriteTransaction) {}

    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction) {
        updateRecipient(mergedRecipient.newRecipient)

        // If there are any threads with addresses that have been merged, we should
        // reload them from disk. This allows us to rebuild the addresses with the
        // proper hash values.
        modelReadCaches.evacuateAllCaches()
    }
}

// MARK: - RecipientMergeNotifier

extension Notification.Name {
    public static let didLearnRecipientAssociation = Notification.Name("didLearnRecipientAssociation")
}

public class RecipientMergeNotifier: RecipientMergeObserver {
    private let scheduler: Scheduler

    public init(scheduler: Scheduler) {
        self.scheduler = scheduler
    }

    func willBreakAssociation(for recipient: SignalRecipient, mightReplaceNonnilPhoneNumber: Bool, tx: DBWriteTransaction) {}

    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction) {
        tx.addAsyncCompletion(on: scheduler) {
            NotificationCenter.default.post(name: .didLearnRecipientAssociation, object: self)
        }
    }
}
