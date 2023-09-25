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

    /// We've learned about an association from another device.
    func applyMergeFromLinkedDevice(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient

    /// We've learned about an association from CDS.
    func applyMergeFromContactDiscovery(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164,
        tx: DBWriteTransaction
    ) -> SignalRecipient

    /// We've learned about an association from a Sealed Sender message. These
    /// always come from an ACI, but they might not have a phone number if phone
    /// number sharing is disabled.
    func applyMergeFromSealedSender(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164?,
        tx: DBWriteTransaction
    ) -> SignalRecipient
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

protocol RecipientMergerTemporaryShims {
    func hasActiveSignalProtocolSession(recipientId: String, deviceId: Int32, transaction: DBWriteTransaction) -> Bool
}

class RecipientMergerImpl: RecipientMerger {
    private let temporaryShims: RecipientMergerTemporaryShims
    private let observers: [RecipientMergeObserver]
    private let recipientFetcher: RecipientFetcher
    private let dataStore: RecipientDataStore
    private let storageServiceManager: StorageServiceManager

    /// Initializes a RecipientMerger.
    ///
    /// - Parameter observers: Observers that are notified after a new
    /// association is learned. They are notified in the same transaction in
    /// which we learned about the new association, and they are notified in the
    /// order in which they are provided.
    init(
        temporaryShims: RecipientMergerTemporaryShims,
        observers: [RecipientMergeObserver],
        recipientFetcher: RecipientFetcher,
        dataStore: RecipientDataStore,
        storageServiceManager: StorageServiceManager
    ) {
        self.temporaryShims = temporaryShims
        self.observers = observers
        self.recipientFetcher = recipientFetcher
        self.dataStore = dataStore
        self.storageServiceManager = storageServiceManager
    }

    static func buildObservers(
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
    ) -> [RecipientMergeObserver] {
        // PNI TODO: Merge ReceiptForLinkedDevice if needed.
        [
            signalServiceAddressCache,
            AuthorMergeObserver(),
            SignalAccountMergeObserver(),
            ProfileWhitelistMerger(profileManager: profileManager),
            UserProfileMerger(userProfileStore: userProfileStore),
            ThreadMerger(
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
    }

    func applyMergeForLocalAccount(
        aci: Aci,
        phoneNumber: E164,
        pni: Pni?,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        return mergeAlways(aci: aci, phoneNumber: phoneNumber, isLocalRecipient: true, tx: tx)
    }

    func applyMergeFromLinkedDevice(
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

    func applyMergeFromContactDiscovery(
        localIdentifiers: LocalIdentifiers,
        aci: Aci,
        phoneNumber: E164,
        tx: DBWriteTransaction
    ) -> SignalRecipient {
        return mergeIfNotLocalIdentifier(localIdentifiers: localIdentifiers, aci: aci, phoneNumber: phoneNumber, tx: tx)
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
        if localIdentifiers.contains(serviceId: aci) || localIdentifiers.contains(phoneNumber: phoneNumber) {
            return recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
        }
        return mergeAlways(aci: aci, phoneNumber: phoneNumber, isLocalRecipient: false, tx: tx)
    }

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
        let aciRecipient = dataStore.fetchRecipient(serviceId: aci, transaction: tx)

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

        let phoneNumberRecipient = dataStore.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx)

        return mergeAndNotify(
            existingRecipients: [phoneNumberRecipient, aciRecipient].compacted(),
            mightReplaceNonnilPhoneNumber: true,
            isLocalMerge: isLocalRecipient,
            tx: tx
        ) {
            switch _mergeHighTrust(
                aci: aci,
                phoneNumber: phoneNumber,
                aciRecipient: aciRecipient,
                phoneNumberRecipient: phoneNumberRecipient,
                tx: tx
            ) {
            case .some(let updatedRecipient):
                dataStore.updateRecipient(updatedRecipient, transaction: tx)
                storageServiceManager.recordPendingUpdates(updatedAccountIds: [updatedRecipient.accountId])
                return updatedRecipient
            case .none:
                let insertedRecipient = SignalRecipient(aci: aci, pni: nil, phoneNumber: phoneNumber)
                dataStore.insertRecipient(insertedRecipient, transaction: tx)
                return insertedRecipient
            }
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
                return aciRecipient
            }

            guard phoneNumberRecipient.aciString != nil else {
                return mergeRecipients(
                    aci: aci,
                    aciRecipient: aciRecipient,
                    phoneNumber: phoneNumber,
                    phoneNumberRecipient: phoneNumberRecipient,
                    transaction: tx
                )
            }

            // Ordering is critical here. We must save the cleared phone number on the
            // old recipient *before* we save the phone number on the new recipient.

            aciRecipient.phoneNumber = phoneNumberRecipient.phoneNumber
            phoneNumberRecipient.phoneNumber = nil
            dataStore.updateRecipient(phoneNumberRecipient, transaction: tx)
            return aciRecipient
        }

        if let phoneNumberRecipient {
            if phoneNumberRecipient.aciString != nil {
                // We can't change the ACI because it's non-empty. Instead, we must create
                // a new SignalRecipient. We clear the phone number here since it will
                // belong to the new SignalRecipient.
                phoneNumberRecipient.phoneNumber = nil
                dataStore.updateRecipient(phoneNumberRecipient, transaction: tx)
                return nil
            }

            phoneNumberRecipient.aci = aci
            return phoneNumberRecipient
        }

        // We couldn't find a recipient, so create a new one.
        return nil
    }

    private func mergeRecipients(
        aci: Aci,
        aciRecipient: SignalRecipient,
        phoneNumber: E164,
        phoneNumberRecipient: SignalRecipient,
        transaction: DBWriteTransaction
    ) -> SignalRecipient {
        // We have separate recipients in the db for the ACI and phone number.
        // There isn't an ideal way to do this, but we need to converge on one
        // recipient and discard the other.

        // We try to preserve the recipient that has a session.
        // (Note that we don't check for PNI sessions; we always prefer the ACI session there.)
        let hasSessionForAci = temporaryShims.hasActiveSignalProtocolSession(
            recipientId: aciRecipient.accountId,
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
        if !hasSessionForAci && hasSessionForPhoneNumber {
            Logger.warn("Discarding ACI recipient in favor of phone number recipient.")
            winningRecipient = phoneNumberRecipient
            losingRecipient = aciRecipient
        } else {
            Logger.warn("Discarding phone number recipient in favor of ACI recipient.")
            winningRecipient = aciRecipient
            losingRecipient = phoneNumberRecipient
        }
        owsAssertBeta(winningRecipient !== losingRecipient)

        // Make sure the winning recipient is fully qualified.
        winningRecipient.phoneNumber = phoneNumber.stringValue
        winningRecipient.aci = aci

        // Discard the losing recipient.
        // TODO: Should we clean up any state related to the discarded recipient?
        dataStore.removeRecipient(losingRecipient, transaction: transaction)

        return winningRecipient
    }

    @discardableResult
    private func mergeAndNotify(
        existingRecipients: [SignalRecipient],
        mightReplaceNonnilPhoneNumber: Bool,
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
            for observer in observers {
                observer.willBreakAssociation(
                    for: recipient,
                    mightReplaceNonnilPhoneNumber: mightReplaceNonnilPhoneNumber,
                    tx: tx
                )
            }
        }

        let mergedRecipient = applyMerge()

        for observer in observers {
            observer.didLearnAssociation(
                mergedRecipient: MergedRecipient(
                    isLocalRecipient: isLocalMerge,
                    oldRecipient: oldRecipients.first(where: { $0.uniqueId == mergedRecipient.uniqueId }),
                    newRecipient: mergedRecipient
                ),
                tx: tx
            )
        }

        return mergedRecipient
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
