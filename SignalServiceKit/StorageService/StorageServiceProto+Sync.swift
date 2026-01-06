//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalRingRTC
import SwiftProtobuf

// MARK: - Record Updater Protocol

protocol StorageServiceRecordUpdater {
    associatedtype IdType
    associatedtype RecordType

    func unknownFields(for record: RecordType) -> UnknownStorage?

    /// Creates a Record that can be put in Storage Service.
    ///
    /// - Parameter localId: The unique identifier of the item being built.
    ///
    /// - Parameter unknownFields: Any unknown fields already present for the
    /// item with this identifier. If there's a value, that value should be
    /// transferred to the result.
    ///
    /// - Parameter transaction: A database transaction.
    ///
    /// - Returns: A record with the values for the item identified by
    /// `localId`. If `localId` doesn't exist, or if `localId` isn't valid,
    /// `nil` is returned. Callers should exclude items which return `nil`.
    func buildRecord(
        for localId: IdType,
        unknownFields: UnknownStorage?,
        transaction: DBReadTransaction,
    ) -> RecordType?

    func buildStorageItem(for record: RecordType) -> StorageService.StorageItem

    /// Updates local device state to match a Record from Storage Service.
    ///
    /// Our general merge philosophy is that the latest value on the service is
    /// always right. There are some edge cases where this could cause user
    /// changes to get blown away, such as if you're changing values
    /// simultaneously on two devices or if you force quit the application
    /// before it has had a chance to sync. To mitigate these issues, we push
    /// changes quickly when they're made (because changes are infrequent).
    ///
    /// If this is unreliable, we could maintain timestamps representing the
    /// remote and local update time for every value we sync. For now, we'd like
    /// to avoid that as it adds its own set of problems.
    ///
    /// - Parameter record: The record that should be merged.
    ///
    /// - Parameter transaction: A database transaction.
    ///
    /// - Returns: A type indicating the result of the merge.
    func mergeRecord(
        _ record: RecordType,
        transaction: DBWriteTransaction,
    ) -> StorageServiceMergeResult<IdType>
}

enum StorageServiceMergeResult<IdType> {
    /// The merge couldn't be completed because the record is malformed. This
    /// happens most often when the record doesn't have an identifier. For
    /// example, if there's a group record that doesn't specify the group to
    /// which it pertains, it's invalid and should be deleted.
    case invalid

    /// The merge completed successfully. The first associated value indicates
    /// whether or not there are changes on the local device that should be
    /// synced. The second associated value indicates the identifier for the
    /// item that was merged.
    case merged(needsUpdate: Bool, IdType)
}

// MARK: - Contact Record

struct StorageServiceContact {
    /// Contact records must have at least an ACI or a PNI.
    let serviceIds: AtLeastOneServiceId

    var aci: Aci? { serviceIds.aci }
    var pni: Pni? { serviceIds.pni }

    /// Contact records may have a phone number.
    let phoneNumber: E164?

    /// Contact records may be unregistered.
    let unregisteredAtTimestamp: UInt64?

    init?(aci: Aci?, phoneNumber: E164?, pni: Pni?, unregisteredAtTimestamp: UInt64?) {
        guard let serviceIds = AtLeastOneServiceId(aci: aci, pni: pni) else {
            return nil
        }
        self.serviceIds = serviceIds
        self.phoneNumber = phoneNumber
        self.unregisteredAtTimestamp = unregisteredAtTimestamp
    }

    enum RegistrationStatus {
        case registered
        case unregisteredRecently
        case unregisteredAWhileAgo
    }

    func registrationStatus(currentDate: Date, remoteConfig: RemoteConfig) -> RegistrationStatus {
        switch unregisteredAtTimestamp {
        case .none:
            return .registered

        case .some(let timestamp) where currentDate.timeIntervalSince(Date(millisecondsSince1970: timestamp)) <= remoteConfig.messageQueueTime:
            return .unregisteredRecently

        case .some:
            return .unregisteredAWhileAgo
        }
    }

    fileprivate init?(_ contactRecord: StorageServiceProtoContactRecord) {
        let unregisteredAtTimestamp: UInt64?
        if contactRecord.unregisteredAtTimestamp == 0 {
            unregisteredAtTimestamp = nil // registered
        } else {
            unregisteredAtTimestamp = contactRecord.unregisteredAtTimestamp
        }
        let pni: Pni?
        if let pniBinary = contactRecord.pniBinary {
            pni = UUID(data: pniBinary).map(Pni.init(fromUUID:))
        } else {
            pni = Pni.parseFrom(pniString: contactRecord.pni)
        }
        self.init(
            aci: Aci.parseFrom(
                serviceIdBinary: contactRecord.aciBinary,
                serviceIdString: contactRecord.aci,
            ),
            phoneNumber: E164.expectNilOrValid(stringValue: contactRecord.e164),
            pni: pni,
            unregisteredAtTimestamp: unregisteredAtTimestamp,
        )
    }

    init?(_ signalRecipient: SignalRecipient) {
        let unregisteredAtTimestamp: UInt64?
        if signalRecipient.isRegistered {
            unregisteredAtTimestamp = nil
        } else {
            unregisteredAtTimestamp = (
                signalRecipient.unregisteredAtTimestamp ?? SignalRecipient.Constants.distantPastUnregisteredTimestamp,
            )
        }
        self.init(
            aci: signalRecipient.aci,
            phoneNumber: E164.expectNilOrValid(stringValue: signalRecipient.phoneNumber?.stringValue),
            pni: signalRecipient.pni,
            unregisteredAtTimestamp: unregisteredAtTimestamp,
        )
    }

    func shouldBeInStorageService(currentDate: Date, remoteConfig: RemoteConfig) -> Bool {
        switch registrationStatus(currentDate: currentDate, remoteConfig: remoteConfig) {
        case .registered, .unregisteredRecently:
            return true
        case .unregisteredAWhileAgo:
            return false
        }
    }

    func matchesAnyLocalIdentifier(in localIdentifiers: LocalIdentifiers) -> Bool {
        return localIdentifiers.containsAnyOf(aci: aci, phoneNumber: phoneNumber, pni: pni)
    }
}

class StorageServiceContactRecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = RecipientUniqueId
    typealias RecordType = StorageServiceProtoContactRecord

    private let localIdentifiers: LocalIdentifiers
    private let isPrimaryDevice: Bool
    private let authedAccount: AuthedAccount

    private let avatarDefaultColorManager: AvatarDefaultColorManager
    private let blockingManager: BlockingManager
    private let contactsManager: OWSContactsManager
    private let identityManager: OWSIdentityManager
    private let nicknameManager: NicknameManager
    private let profileFetcher: any ProfileFetcher
    private let profileManager: OWSProfileManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let recipientManager: any SignalRecipientManager
    private let recipientMerger: RecipientMerger
    private let recipientHidingManager: RecipientHidingManager
    private let remoteConfigProvider: any RemoteConfigProvider
    private let signalServiceAddressCache: SignalServiceAddressCache
    private let tsAccountManager: TSAccountManager
    private let usernameLookupManager: UsernameLookupManager

    init(
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        authedAccount: AuthedAccount,
        avatarDefaultColorManager: AvatarDefaultColorManager,
        blockingManager: BlockingManager,
        contactsManager: OWSContactsManager,
        identityManager: OWSIdentityManager,
        nicknameManager: NicknameManager,
        profileFetcher: ProfileFetcher,
        profileManager: OWSProfileManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientManager: any SignalRecipientManager,
        recipientMerger: RecipientMerger,
        recipientHidingManager: RecipientHidingManager,
        remoteConfigProvider: any RemoteConfigProvider,
        signalServiceAddressCache: SignalServiceAddressCache,
        tsAccountManager: TSAccountManager,
        usernameLookupManager: UsernameLookupManager,
    ) {
        self.localIdentifiers = localIdentifiers
        self.isPrimaryDevice = isPrimaryDevice
        self.authedAccount = authedAccount

        self.avatarDefaultColorManager = avatarDefaultColorManager
        self.blockingManager = blockingManager
        self.contactsManager = contactsManager
        self.identityManager = identityManager
        self.nicknameManager = nicknameManager
        self.profileFetcher = profileFetcher
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientManager = recipientManager
        self.recipientMerger = recipientMerger
        self.recipientHidingManager = recipientHidingManager
        self.remoteConfigProvider = remoteConfigProvider
        self.signalServiceAddressCache = signalServiceAddressCache
        self.tsAccountManager = tsAccountManager
        self.usernameLookupManager = usernameLookupManager
    }

    func unknownFields(for record: StorageServiceProtoContactRecord) -> UnknownStorage? { record.unknownFields }

    func buildRecord(
        for recipientUniqueId: RecipientUniqueId,
        unknownFields: UnknownStorage?,
        transaction tx: DBReadTransaction,
    ) -> StorageServiceProtoContactRecord? {
        guard let recipient = recipientDatabaseTable.fetchRecipient(uniqueId: recipientUniqueId, tx: tx) else {
            return nil
        }

        guard let contact = StorageServiceContact(recipient) else {
            return nil
        }

        if contact.matchesAnyLocalIdentifier(in: localIdentifiers) {
            owsFailDebug("Can't create contact with any local identifier")
            return nil
        }

        guard contact.shouldBeInStorageService(currentDate: Date(), remoteConfig: remoteConfigProvider.currentConfig()) else {
            return nil
        }

        var builder = StorageServiceProtoContactRecord.builder()

        /// Helps determine if a username is the best identifier we have for
        /// this address.
        var usernameBetterIdentifierChecker = Usernames.BetterIdentifierChecker(forRecipient: recipient)

        if let aci = contact.aci {
            if BuildFlags.serviceIdStrings {
                builder.setAci(aci.serviceIdString)
            }
            if BuildFlags.serviceIdBinaryConstantOverhead {
                builder.setAciBinary(aci.serviceIdBinary)
            }
        }
        if let phoneNumber = contact.phoneNumber {
            builder.setE164(phoneNumber.stringValue)
            usernameBetterIdentifierChecker.add(e164: phoneNumber.stringValue)
        }
        if let pni = contact.pni {
            if BuildFlags.serviceIdStrings {
                builder.setPni(pni.rawUUID.uuidString.lowercased())
            }
            if BuildFlags.serviceIdBinaryConstantOverhead {
                builder.setPniBinary(pni.rawUUID.data)
            }
        }

        if let unregisteredAtTimestamp = contact.unregisteredAtTimestamp {
            builder.setUnregisteredAtTimestamp(unregisteredAtTimestamp)
        }

        // This could be an ACI or a PNI address.
        let anyAddress = SignalServiceAddress(contact.serviceIds.aciOrElsePni)

        let isInWhitelist = profileManager.isRecipientInProfileWhitelist(recipient, tx: tx)
        builder.setWhitelisted(isInWhitelist)

        builder.setBlocked(blockingManager.isAddressBlocked(anyAddress, transaction: tx))
        builder.setHidden(recipientHidingManager.isHiddenAddress(anyAddress, tx: tx))

        // Identity

        if let identityKey = try? identityManager.identityKey(for: contact.serviceIds.aciOrElsePni, tx: tx) {
            builder.setIdentityKey(identityKey.serialize())
        }

        let verificationState = identityManager.verificationState(for: anyAddress, tx: tx)
        builder.setIdentityState(.from(verificationState))

        // Profile

        let userProfile = profileManager.userProfile(for: anyAddress, tx: tx)

        let profileKey = userProfile?.profileKey?.keyData
        let profileGivenName = userProfile?.givenName
        let profileFamilyName = userProfile?.familyName

        if let profileKey {
            builder.setProfileKey(profileKey)
        }

        if let profileGivenName {
            builder.setGivenName(profileGivenName)
            usernameBetterIdentifierChecker.add(profileGivenName: profileGivenName)
        }

        if let profileFamilyName {
            builder.setFamilyName(profileFamilyName)
            usernameBetterIdentifierChecker.add(profileFamilyName: profileFamilyName)
        }

        let systemContact = { () -> SignalAccount? in
            guard let phoneNumber = contact.phoneNumber else {
                return nil
            }
            return contactsManager.fetchSignalAccount(
                forPhoneNumber: phoneNumber.stringValue,
                transaction: tx,
            )
        }()

        if let systemContact {
            // We have a contact for this address, whose name we may want to
            // add to this ContactRecord. We should add it if:
            //
            // - We are a primary device, and this contact is from our local
            //   address book. In this case, we want to let linked devices
            //   know about our "system contact".
            //
            // - We are a linked device, and this is a contact we synced from
            //   the primary device (via a previous ContactRecord). In this
            //   case, we want to preserve the name the primary device
            //   originally uploaded.

            let isPrimary = isPrimaryDevice
            let isPrimaryAndHasLocalContact = isPrimary && systemContact.isFromLocalAddressBook
            let isLinkedAndHasSyncedContact = !isPrimary && !systemContact.isFromLocalAddressBook

            if isPrimaryAndHasLocalContact || isLinkedAndHasSyncedContact {
                let systemGivenName = systemContact.givenName
                builder.setSystemGivenName(systemGivenName)
                usernameBetterIdentifierChecker.add(systemContactGivenName: systemGivenName)

                let systemFamilyName = systemContact.familyName
                builder.setSystemFamilyName(systemFamilyName)
                usernameBetterIdentifierChecker.add(systemContactFamilyName: systemFamilyName)

                let systemNickname = systemContact.nickname
                builder.setSystemNickname(systemNickname)
                usernameBetterIdentifierChecker.add(systemContactNickname: systemNickname)
            }
        }

        if let thread = TSContactThread.getWithContactAddress(anyAddress, transaction: tx) {
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: tx)

            builder.setArchived(threadAssociatedData.isArchived)
            builder.setMarkedUnread(threadAssociatedData.isMarkedUnread)
            builder.setMutedUntilTimestamp(threadAssociatedData.mutedUntilTimestamp)
        }

        if let aci = contact.aci, let associatedData = StoryFinder.getAssociatedData(forAci: aci, tx: tx) {
            builder.setHideStory(associatedData.isHidden)
        }

        // Username

        let username: String? = {
            // Only add a username to the ContactRecord if we have no other identifiers
            // to display.
            guard let aci = contact.aci, usernameBetterIdentifierChecker.usernameIsBestIdentifier() else {
                return nil
            }
            return usernameLookupManager.fetchUsername(forAci: aci, transaction: tx)
        }()
        if let username {
            builder.setUsername(username)
        }

        // Nickname/note

        if let nicknameRecord = nicknameManager.fetchNickname(for: recipient, tx: tx) {
            var nicknameBuilder = StorageServiceProtoContactRecordName.builder()
            nicknameRecord.givenName.map { nicknameBuilder.setGiven($0) }
            nicknameRecord.familyName.map { nicknameBuilder.setFamily($0) }
            builder.setNickname(nicknameBuilder.buildInfallibly())
            nicknameRecord.note.map { builder.setNote($0) }
        }

        // Avatar color

        builder.setAvatarColor(
            avatarDefaultColorManager.defaultColor(
                useCase: .contact(recipient: recipient),
                tx: tx,
            ).asStorageServiceProtoAvatarColor,
        )

        // Unknown

        if let unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return builder.buildInfallibly()
    }

    func buildStorageItem(for record: StorageServiceProtoContactRecord) -> StorageService.StorageItem {
        return StorageService.StorageItem(identifier: .generate(type: .contact), contact: record)
    }

    static func shouldDeferMerge(_ record: StorageServiceProtoContactRecord) -> Bool {
        return StorageServiceContact(record)?.aci == nil
    }

    func mergeRecord(
        _ record: StorageServiceProtoContactRecord,
        transaction: DBWriteTransaction,
    ) -> StorageServiceMergeResult<RecipientUniqueId> {
        guard let contact = StorageServiceContact(record) else {
            owsFailDebug("Can't merge record with invalid identifiers: hasAci? \(record.hasAci) hasAciBinary? \(record.hasAciBinary) hasPni? \(record.hasPni) hasPniBinary? \(record.hasPniBinary) hasPhoneNumber? \(record.hasE164)")
            return .invalid
        }

        if contact.matchesAnyLocalIdentifier(in: localIdentifiers) {
            owsFailDebug("Can't merge record for the local user") // this should be an AccountRecord
            return .invalid
        }

        var recipient = recipientMerger.applyMergeFromStorageService(
            localIdentifiers: localIdentifiers,
            isPrimaryDevice: isPrimaryDevice,
            serviceIds: contact.serviceIds,
            phoneNumber: contact.phoneNumber,
            tx: transaction,
        )
        if let unregisteredAtTimestamp = contact.unregisteredAtTimestamp {
            recipientManager.markAsUnregisteredAndSave(
                &recipient,
                unregisteredAt: .specificTimeFromOtherDevice(unregisteredAtTimestamp),
                shouldUpdateStorageService: false,
                tx: transaction,
            )
            // For Storage Service, we only perform contact splitting if it's an
            // ACI-only recipient. The recipient returned from
            // `applyMergeFromStorageService` will have our local state, so we
            // explicitly check the remote state here.
            if contact.phoneNumber == nil, contact.pni == nil {
                recipientMerger.splitUnregisteredRecipientIfNeeded(
                    localIdentifiers: localIdentifiers,
                    unregisteredRecipient: &recipient,
                    tx: transaction,
                )
            }
        } else {
            recipientManager.markAsRegisteredAndSave(
                &recipient,
                shouldUpdateStorageService: false,
                tx: transaction,
            )
        }

        guard let serviceIds = AtLeastOneServiceId(aci: recipient.aci, pni: recipient.pni) else {
            owsFailDebug("Can't have a merge result without a ServiceId")
            return .invalid
        }

        return _mergeRecord(
            record,
            recipient: &recipient,
            serviceIds: serviceIds,
            // If we merge and don't end up with what's in Storage Service, then it
            // probably means that a linked device is wrong or we've hit a race
            // condition where we learned something that's not yet reflected in Storage
            // Service. When this happens, we should schedule an update to make sure
            // Storage Service knows everything we know.
            needsUpdate:
            recipient.aci != contact.aci
                || E164(recipient.phoneNumber?.stringValue) != contact.phoneNumber
                || recipient.pni != contact.pni
            ,
            tx: transaction,
        )
    }

    private func _mergeRecord(
        _ record: StorageServiceProtoContactRecord,
        recipient: inout SignalRecipient,
        serviceIds: AtLeastOneServiceId,
        needsUpdate: Bool,
        tx: DBWriteTransaction,
    ) -> StorageServiceMergeResult<RecipientUniqueId> {
        var needsUpdate = needsUpdate

        let anyAddress = SignalServiceAddress(serviceIds.aciOrElsePni)

        // Gather some local contact state to do comparisons against.
        let localIsBlocked = blockingManager.isAddressBlocked(anyAddress, transaction: tx)
        let localIsHidden = recipientHidingManager.isHiddenAddress(anyAddress, tx: tx)
        let localIsWhitelisted = profileManager.isRecipientInProfileWhitelist(recipient, tx: tx)
        let localUserProfile = profileManager.userProfile(for: anyAddress, tx: tx)

        // If our local profile key record differs from what's on the service, use the service's value.
        if let profileKey = record.profileKey, localUserProfile?.profileKey?.keyData != profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: serviceIds.aciOrElsePni,
                onlyFillInIfMissing: false,
                shouldFetchProfile: false,
                userProfileWriter: .storageService,
                localIdentifiers: localIdentifiers,
                authedAccount: authedAccount,
                tx: tx,
            )

            // If we have a local profile key for this user but the service doesn't mark it as needing update.
        } else if localUserProfile?.profileKey != nil && !record.hasProfileKey {
            needsUpdate = true
        }

        // Given name can never be cleared, so ignore all info about the profile if
        // there's no given name.
        if record.hasGivenName && (localUserProfile?.givenName != record.givenName || localUserProfile?.familyName != record.familyName) {
            let profileAddress = OWSUserProfile.insertableAddress(
                serviceId: serviceIds.aciOrElsePni,
                localIdentifiers: localIdentifiers,
            )
            let localUserProfile = OWSUserProfile.getOrBuildUserProfile(
                for: profileAddress,
                userProfileWriter: .storageService,
                tx: tx,
            )
            localUserProfile.update(
                givenName: .setTo(record.givenName),
                familyName: .setTo(record.familyName),
                userProfileWriter: .storageService,
                transaction: tx,
            )
        } else if localUserProfile?.givenName != nil && !record.hasGivenName || localUserProfile?.familyName != nil && !record.hasFamilyName {
            needsUpdate = true
        }

        if mergeSystemContactNames(in: record, recipient: recipient, serviceIds: serviceIds, tx: tx) {
            needsUpdate = true
        }

        // If our local identity differs from the service, use the service's value.
        let localIdentityKey = try? identityManager.identityKey(for: serviceIds.aciOrElsePni, tx: tx)
        if let identityKey = record.identityKey.flatMap({ try? IdentityKey(bytes: $0) }) {
            if identityKey != localIdentityKey {
                identityManager.saveIdentityKey(identityKey, for: serviceIds.aciOrElsePni, tx: tx)
            }
            // Make sure we fetch this after changing the identity key.
            let identityState = record.identityState.verificationState
            let localIdentityState = identityManager.verificationState(for: anyAddress, tx: tx)
            if identityState != localIdentityState {
                _ = identityManager.setVerificationState(
                    identityState,
                    of: identityKey.publicKey.keyBytes,
                    for: anyAddress,
                    isUserInitiatedChange: false,
                    tx: tx,
                )
            }
        }
        // If we have a local identity for this user but the service doesn't, mark it as needing update.
        if localIdentityKey != nil && !record.hasIdentityKey {
            needsUpdate = true
        }

        // If our local blocked state differs from the service state, use the service's value.
        if record.blocked != localIsBlocked {
            if record.blocked {
                blockingManager.addBlockedAddress(anyAddress, blockMode: .remote, transaction: tx)
            } else {
                blockingManager.removeBlockedAddress(anyAddress, wasLocallyInitiated: false, transaction: tx)
            }
        }

        // If our local hidden state differs from the service state, use the service's value.
        if record.hidden != localIsHidden {
            if record.hidden {
                do {
                    try recipientHidingManager.addHiddenRecipient(
                        anyAddress,
                        inKnownMessageRequestState: false,
                        wasLocallyInitiated: false,
                        tx: tx,
                    )
                } catch {
                    Logger.warn("Recipient hidden remotely could not be hidden locally.")
                }
            } else {
                recipientHidingManager.removeHiddenRecipient(anyAddress, wasLocallyInitiated: false, tx: tx)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if record.whitelisted != localIsWhitelisted {
            if record.whitelisted {
                profileManager.addRecipientToProfileWhitelist(&recipient, userProfileWriter: .storageService, tx: tx)
            } else {
                profileManager.removeRecipientFromProfileWhitelist(&recipient, userProfileWriter: .storageService, tx: tx)
            }
        }

        let localThread = TSContactThread.getOrCreateThread(withContactAddress: anyAddress, transaction: tx)
        let localThreadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: localThread, transaction: tx)

        if record.archived != localThreadAssociatedData.isArchived {
            localThreadAssociatedData.updateWith(isArchived: record.archived, updateStorageService: false, transaction: tx)
        }

        if record.markedUnread != localThreadAssociatedData.isMarkedUnread {
            localThreadAssociatedData.updateWith(isMarkedUnread: record.markedUnread, updateStorageService: false, transaction: tx)
        }

        if record.mutedUntilTimestamp != localThreadAssociatedData.mutedUntilTimestamp {
            localThreadAssociatedData.updateWith(mutedUntilTimestamp: record.mutedUntilTimestamp, updateStorageService: false, transaction: tx)
        }

        if let aci = serviceIds.aci {
            let localStoryContextAssociatedData = StoryContextAssociatedData.fetchOrDefault(
                sourceContext: .contact(contactAci: aci),
                transaction: tx,
            )
            if record.hideStory != localStoryContextAssociatedData.isHidden {
                localStoryContextAssociatedData.update(updateStorageService: false, isHidden: record.hideStory, transaction: tx)
            }
        }

        if let aci = serviceIds.aci {
            let usernameIsBestIdentifierOnRecord: Bool = {
                var betterIdentifierChecker = Usernames.BetterIdentifierChecker(forRecipient: recipient)

                betterIdentifierChecker.add(e164: record.e164)
                betterIdentifierChecker.add(profileGivenName: record.givenName)
                betterIdentifierChecker.add(profileFamilyName: record.familyName)
                betterIdentifierChecker.add(systemContactGivenName: record.systemGivenName)
                betterIdentifierChecker.add(systemContactFamilyName: record.systemFamilyName)
                betterIdentifierChecker.add(systemContactNickname: record.systemNickname)

                return betterIdentifierChecker.usernameIsBestIdentifier()
            }()

            usernameLookupManager.saveUsername(
                usernameIsBestIdentifierOnRecord ? record.username : nil,
                forAci: aci,
                transaction: tx,
            )
        }

        if record.nickname?.hasGiven == true || record.nickname?.hasFamily == true || record.hasNote {
            let nicknameRecord = NicknameRecord(
                recipient: recipient,
                givenName: record.nickname?.given,
                familyName: record.nickname?.family,
                note: record.note,
            )
            nicknameManager.createOrUpdate(
                nicknameRecord: nicknameRecord,
                // Don't create a recursive Storage Service sync
                updateStorageServiceFor: nil,
                tx: tx,
            )
        } else {
            nicknameManager.deleteNickname(
                recipientRowID: recipient.id,
                // Don't create a recursive Storage Service sync
                updateStorageServiceFor: nil,
                tx: tx,
            )
        }

        if mergeDefaultAvatarColor(in: record, recipient: recipient, tx: tx) {
            needsUpdate = true
        }

        return .merged(needsUpdate: needsUpdate, recipient.uniqueId)
    }

    /// Merge system contact names from this ContactRecord with local state.
    ///
    /// On primary devices, confirms that storage service has the correct
    /// values. On linked devices, system contact data in this ContactRecord
    /// will supercede any existing contact data for the given address.
    ///
    /// - Returns: True if the record in StorageService should be updated. This
    /// can happen on primary devices if StorageService has the wrong system
    /// contact names.
    private func mergeSystemContactNames(
        in record: StorageServiceProtoContactRecord,
        recipient: SignalRecipient,
        serviceIds: AtLeastOneServiceId,
        tx: DBWriteTransaction,
    ) -> Bool {
        // If there's no phone number, there's no system contact. If a phone number
        // is removed, it'll be claimed by another account; if it's not claimed,
        // the merging logic will delete the SignalAccount.
        guard let phoneNumber = recipient.phoneNumber?.stringValue else {
            return false
        }

        let localAccount = contactsManager.fetchSignalAccount(
            forPhoneNumber: phoneNumber,
            transaction: tx,
        )

        if isPrimaryDevice {
            let localContact = localAccount?.isFromLocalAddressBook == true
            let localSystemGivenName = localContact ? localAccount?.givenName : nil
            let localSystemFamilyName = localContact ? localAccount?.familyName : nil
            let localSystemNickname = localContact ? localAccount?.nickname : nil
            // On the primary device, we should mark it as `needsUpdate` if it doesn't match the local state.
            return
                localSystemGivenName != record.systemGivenName
                    || localSystemFamilyName != record.systemFamilyName
                    || localSystemNickname != record.systemNickname

        }

        // Otherwise, we should update the state on linked devices to match.

        let newAccount: SignalAccount?

        let systemFullName = Contact.fullName(
            fromGivenName: record.systemGivenName,
            familyName: record.systemFamilyName,
            nickname: record.systemNickname,
        )
        if let systemFullName {
            // TODO: we should find a way to fill in `multipleAccountLabelText`.
            // This is the string that helps disambiguate when multiple
            // `SignalAccount`s are associated with the same system contact.
            // For example, Alice may have a work and mobile number, both of
            // of which are registered with Signal. This text could be (work)
            // or (mobile), to help disambiguate - otherwise, both Signal
            // accounts will present as just "Alice".
            let multipleAccountLabelText = ""

            newAccount = SignalAccount(
                recipientPhoneNumber: phoneNumber,
                recipientServiceId: serviceIds.aciOrElsePni,
                multipleAccountLabelText: multipleAccountLabelText,
                cnContactId: nil,
                givenName: record.systemGivenName ?? "",
                familyName: record.systemFamilyName ?? "",
                nickname: record.systemNickname ?? "",
                fullName: systemFullName,
                contactAvatarHash: nil,
            )
        } else {
            newAccount = nil
        }

        switch (localAccount, newAccount) {
        case (.some(let oldAccount), .some(let newAccount)) where oldAccount.hasSameContent(newAccount):
            // What we've saved locally matches what Storage Service wants us to save.
            // Don't make any changes.
            break

        default:
            // We *might* have something locally, and there *might* be something in
            // Storage Service. We should make them match, and we should notify about
            // updates if we make any changes. If both are `nil`, we'll fall into this
            // case and `didModifySignalAccount` will remain false.
            var didModifySignalAccount = false
            if let localAccount {
                localAccount.anyRemove(transaction: tx)
                didModifySignalAccount = true
            }
            if let newAccount {
                newAccount.anyInsert(transaction: tx)
                didModifySignalAccount = true
            }
            if didModifySignalAccount {
                contactsManager.didUpdateSignalAccounts(transaction: tx)
            }
            let aciToUpdate = SignalAccount.aciForPhoneNumberVisibilityUpdate(
                oldAccount: localAccount,
                newAccount: newAccount,
            )
            if aciToUpdate != nil {
                // Tell the cache to refresh its state for this recipient. It will check
                // whether or not the number should be visible based on this state and the
                // state of system contacts.
                signalServiceAddressCache.updateRecipient(recipient, tx: tx)
            }
        }

        // We should never set `needsUpdates` from a linked device for system
        // contact names. Linked devices should always update their local state to
        // match Storage Service.
        return false
    }

    /// Merge the default avatar color from this ContactRecord with local state.
    ///
    /// - Returns Whether this record needs updating. For example, the primary
    /// may need to overwrite state set by a linked device.
    private func mergeDefaultAvatarColor(
        in record: StorageServiceProtoContactRecord,
        recipient: SignalRecipient,
        tx: DBWriteTransaction,
    ) -> Bool {
        let localDefaultAvatarColor = avatarDefaultColorManager.defaultColor(
            useCase: .contact(recipient: recipient),
            tx: tx,
        )
        let remoteDefaultAvatarColor = record.avatarColor.flatMap {
            AvatarTheme.from(storageServiceProtoAvatarColor: $0)
        }

        guard localDefaultAvatarColor != remoteDefaultAvatarColor else {
            return false
        }

        if isPrimaryDevice {
            return true
        } else if let remoteDefaultAvatarColor {
            try? avatarDefaultColorManager.persistDefaultColor(
                remoteDefaultAvatarColor,
                recipientRowId: recipient.id,
                tx: tx,
            )
        }

        return false
    }
}

// MARK: -

extension StorageServiceProtoContactRecordIdentityState {
    static func from(_ state: VerificationState) -> StorageServiceProtoContactRecordIdentityState {
        switch state {
        case .verified:
            return .verified
        case .implicit(isAcknowledged: _):
            return .default
        case .noLongerVerified:
            return .unverified
        }
    }

    var verificationState: VerificationState {
        switch self {
        case .verified:
            return .verified
        case .default:
            return .implicit(isAcknowledged: false)
        case .unverified:
            return .noLongerVerified
        case .UNRECOGNIZED:
            owsFailDebug("unrecognized verification state")
            return .implicit(isAcknowledged: false)
        }
    }
}

// MARK: - Group V1 Record

/// A record updater for V1 groups that treats any contained fields as unknown.
///
/// We no longer rely on GroupV1 records from StorageService, as the groups they
/// correspond to are long-defunct. Consequently, this record updater simply
/// treats all fields in the record as unknown, thereby preserving fields any
/// older linked devices may still be parsing without using it ourselves.
///
/// 90 days after all clients are treating GroupV1 records as unknown, we can
/// stop re-uploading the unknown fields - thereby removing those records.
///
/// Eventually, if we no longer care about removing existing unused records, we
/// can remove the GroupV1 record from our protos entirely.
class StorageServiceGroupV1RecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = Data
    typealias RecordType = StorageServiceProtoGroupV1Record

    init() {}

    func unknownFields(for record: StorageServiceProtoGroupV1Record) -> UnknownStorage? { record.unknownFields }

    func buildStorageItem(for record: StorageServiceProtoGroupV1Record) -> StorageService.StorageItem {
        return StorageService.StorageItem(identifier: .generate(type: .groupv1), groupV1: record)
    }

    func buildRecord(
        for groupId: Data,
        unknownFields: UnknownStorage?,
        transaction: DBReadTransaction,
    ) -> StorageServiceProtoGroupV1Record? {
        var builder = StorageServiceProtoGroupV1Record.builder(id: groupId)

        if let unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return builder.buildInfallibly()
    }

    func mergeRecord(
        _ record: StorageServiceProtoGroupV1Record,
        transaction: DBWriteTransaction,
    ) -> StorageServiceMergeResult<Data> {
        return .merged(needsUpdate: false, record.id)
    }
}

// MARK: - Group V2 Record

class StorageServiceGroupV2RecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = Data
    typealias RecordType = StorageServiceProtoGroupV2Record

    private let authedAccount: AuthedAccount
    private let isPrimaryDevice: Bool

    private let avatarDefaultColorManager: AvatarDefaultColorManager
    private let blockingManager: BlockingManager
    private let groupsV2: GroupsV2
    private let profileManager: ProfileManager

    init(
        authedAccount: AuthedAccount,
        isPrimaryDevice: Bool,
        avatarDefaultColorManager: AvatarDefaultColorManager,
        blockingManager: BlockingManager,
        groupsV2: GroupsV2,
        profileManager: ProfileManager,
    ) {
        self.authedAccount = authedAccount
        self.isPrimaryDevice = isPrimaryDevice

        self.avatarDefaultColorManager = avatarDefaultColorManager
        self.blockingManager = blockingManager
        self.groupsV2 = groupsV2
        self.profileManager = profileManager
    }

    func unknownFields(for record: StorageServiceProtoGroupV2Record) -> UnknownStorage? { record.unknownFields }

    func buildStorageItem(for record: StorageServiceProtoGroupV2Record) -> StorageService.StorageItem {
        return StorageService.StorageItem(identifier: .generate(type: .groupv2), groupV2: record)
    }

    func buildRecord(
        for masterKeyData: Data,
        unknownFields: UnknownStorage?,
        transaction: DBReadTransaction,
    ) -> StorageServiceProtoGroupV2Record? {
        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: masterKeyData)
        } catch {
            owsFailDebug("Invalid master key \(error).")
            return nil
        }

        let groupId = groupContextInfo.groupId

        var builder = StorageServiceProtoGroupV2Record.builder(masterKey: masterKeyData)

        builder.setWhitelisted(profileManager.isGroupId(inProfileWhitelist: groupId.serialize(), transaction: transaction))
        builder.setBlocked(blockingManager.isGroupIdBlocked(groupId, transaction: transaction))

        let threadId = TSGroupThread.threadId(forGroupId: groupId.serialize(), transaction: transaction)
        let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(
            for: threadId,
            ignoreMissing: true,
            transaction: transaction,
        )

        builder.setArchived(threadAssociatedData.isArchived)
        builder.setMarkedUnread(threadAssociatedData.isMarkedUnread)
        builder.setMutedUntilTimestamp(threadAssociatedData.mutedUntilTimestamp)

        let groupThread = TSGroupThread.fetch(forGroupId: groupId, tx: transaction)
        switch groupThread?.mentionNotificationMode {
        case .none, .default:
            break
        case .never:
            builder.setDontNotifyForMentionsIfMuted(true)
        case .always:
            builder.setDontNotifyForMentionsIfMuted(false)
        }

        if let storyContextAssociatedData = StoryFinder.getAssociatedData(forContext: .group(groupId: groupId.serialize()), transaction: transaction) {
            builder.setHideStory(storyContextAssociatedData.isHidden)
        }

        if let thread = TSGroupThread.anyFetchGroupThread(uniqueId: threadId, transaction: transaction) {
            builder.setStorySendMode(thread.storyViewMode.storageServiceMode)
        } else if
            let enqueuedRecord = groupsV2.groupRecordPendingStorageServiceRestore(
                masterKeyData: masterKeyData,
                transaction: transaction,
            )
        {
            // We have a record pending restoration from storage service,
            // preserve any of the data that we weren't able to restore
            // yet because the thread record doesn't exist.
            builder.setStorySendMode(enqueuedRecord.storySendMode)
        }

        builder.setAvatarColor(
            avatarDefaultColorManager.defaultColor(
                useCase: .group(groupId: groupId.serialize()),
                tx: transaction,
            ).asStorageServiceProtoAvatarColor,
        )

        if let unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return builder.buildInfallibly()
    }

    func mergeRecord(
        _ record: StorageServiceProtoGroupV2Record,
        transaction: DBWriteTransaction,
    ) -> StorageServiceMergeResult<Data> {
        var needsUpdate = false

        let masterKey = record.masterKey

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: masterKey)
        } catch {
            owsFailDebug("Invalid master key.")
            return .invalid
        }
        let groupId = groupContextInfo.groupId

        if let localThread = TSGroupThread.fetch(forGroupId: groupId, tx: transaction) {
            let localStorySendMode = localThread.storyViewMode.storageServiceMode
            if localStorySendMode != record.storySendMode {
                localThread.updateWithStoryViewMode(.init(storageServiceMode: record.storySendMode), transaction: transaction)
            }

            // If the group thread doesn't exist, we will create it and reapply this update so the
            // setting won't be lost. Note this isn't true for contact threads, only group threads,
            // so TSContactThread metadata needs to live on ThreadAssociatedData so it can be saved
            // even if the thread doesn't exist. But this field only applies to group threads, so
            // no need.
            switch (localThread.mentionNotificationMode, record.dontNotifyForMentionsIfMuted) {
            case (.default, false), (.never, false):
                localThread.updateWithMentionNotificationMode(.always, wasLocallyInitiated: false, transaction: transaction)
            case (.default, true), (.always, true):
                localThread.updateWithMentionNotificationMode(.never, wasLocallyInitiated: false, transaction: transaction)
            case (.never, true), (.always, false):
                // No change
                break
            }
        } else {
            groupsV2.restoreGroupFromStorageServiceIfNecessary(groupRecord: record, account: authedAccount, transaction: transaction)
        }

        // Gather some local contact state to do comparisons against.
        let localIsBlocked = blockingManager.isGroupIdBlocked(groupId, transaction: transaction)
        let localIsWhitelisted = profileManager.isGroupId(inProfileWhitelist: groupId.serialize(), transaction: transaction)

        // If our local blocked state differs from the service state, use the service's value.
        if record.blocked != localIsBlocked {
            if record.blocked {
                blockingManager.addBlockedGroupId(groupId.serialize(), blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedGroup(groupId: groupId.serialize(), wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if record.whitelisted != localIsWhitelisted {
            if record.whitelisted {
                profileManager.addGroupId(
                    toProfileWhitelist: groupId.serialize(),
                    userProfileWriter: .storageService,
                    transaction: transaction,
                )
            } else {
                profileManager.removeGroupId(
                    fromProfileWhitelist: groupId.serialize(),
                    userProfileWriter: .storageService,
                    transaction: transaction,
                )
            }
        }

        let localThreadId = TSGroupThread.threadId(forGroupId: groupId.serialize(), transaction: transaction)
        ThreadAssociatedData.create(for: localThreadId, transaction: transaction)
        let localThreadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: localThreadId, transaction: transaction)

        if record.archived != localThreadAssociatedData.isArchived {
            localThreadAssociatedData.updateWith(isArchived: record.archived, updateStorageService: false, transaction: transaction)
        }

        if record.markedUnread != localThreadAssociatedData.isMarkedUnread {
            localThreadAssociatedData.updateWith(isMarkedUnread: record.markedUnread, updateStorageService: false, transaction: transaction)
        }

        if record.mutedUntilTimestamp != localThreadAssociatedData.mutedUntilTimestamp {
            localThreadAssociatedData.updateWith(mutedUntilTimestamp: record.mutedUntilTimestamp, updateStorageService: false, transaction: transaction)
        }

        let localStoryContextAssociatedData = StoryContextAssociatedData.fetchOrDefault(
            sourceContext: .group(groupId: groupId.serialize()),
            transaction: transaction,
        )
        if record.hideStory != localStoryContextAssociatedData.isHidden {
            localStoryContextAssociatedData.update(updateStorageService: false, isHidden: record.hideStory, transaction: transaction)
        }

        if mergeDefaultAvatarColor(in: record, groupId: groupId, tx: transaction) {
            needsUpdate = true
        }

        return .merged(needsUpdate: needsUpdate, masterKey)
    }

    /// Merge the default avatar color from this GroupV2Record with local state.
    ///
    /// - Returns Whether this record needs updating. For example, the primary
    /// may need to overwrite state set by a linked device.
    private func mergeDefaultAvatarColor(
        in record: StorageServiceProtoGroupV2Record,
        groupId: GroupIdentifier,
        tx: DBWriteTransaction,
    ) -> Bool {
        let localDefaultAvatarColor = avatarDefaultColorManager.defaultColor(
            useCase: .group(groupId: groupId.serialize()),
            tx: tx,
        )
        let remoteDefaultAvatarColor = record.avatarColor.flatMap {
            AvatarTheme.from(storageServiceProtoAvatarColor: $0)
        }

        guard localDefaultAvatarColor != remoteDefaultAvatarColor else {
            return false
        }

        if isPrimaryDevice {
            return true
        } else if let remoteDefaultAvatarColor {
            try? avatarDefaultColorManager.persistDefaultColor(
                remoteDefaultAvatarColor,
                groupId: groupId.serialize(),
                tx: tx,
            )
        }

        return false
    }
}

// MARK: - Account Record

class StorageServiceAccountRecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = Void
    typealias RecordType = StorageServiceProtoAccountRecord

    private let localIdentifiers: LocalIdentifiers
    private let isPrimaryDevice: Bool
    private let authedAccount: AuthedAccount

    private let avatarDefaultColorManager: AvatarDefaultColorManager
    private let backupPlanManager: BackupPlanManager
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let dmConfigurationStore: DisappearingMessagesConfigurationStore
    private let linkPreviewSettingStore: LinkPreviewSettingStore
    private let localUsernameManager: LocalUsernameManager
    private let paymentsHelper: PaymentsHelperSwift
    private let phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager
    private let pinnedThreadManager: PinnedThreadManager
    private let preferences: Preferences
    private let profileManager: OWSProfileManager
    private let receiptManager: OWSReceiptManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let storageServiceManager: StorageServiceManager
    private let systemStoryManager: SystemStoryManagerProtocol
    private let tsAccountManager: TSAccountManager
    private let typingIndicators: TypingIndicators
    private let udManager: OWSUDManager
    private let usernameEducationManager: UsernameEducationManager

    init(
        localIdentifiers: LocalIdentifiers,
        isPrimaryDevice: Bool,
        authedAccount: AuthedAccount,
        avatarDefaultColorManager: AvatarDefaultColorManager,
        backupPlanManager: BackupPlanManager,
        backupSubscriptionManager: BackupSubscriptionManager,
        dmConfigurationStore: DisappearingMessagesConfigurationStore,
        linkPreviewSettingStore: LinkPreviewSettingStore,
        localUsernameManager: LocalUsernameManager,
        paymentsHelper: PaymentsHelperSwift,
        phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager,
        pinnedThreadManager: PinnedThreadManager,
        preferences: Preferences,
        profileManager: OWSProfileManager,
        receiptManager: OWSReceiptManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        registrationStateChangeManager: RegistrationStateChangeManager,
        storageServiceManager: StorageServiceManager,
        systemStoryManager: SystemStoryManagerProtocol,
        tsAccountManager: TSAccountManager,
        typingIndicators: TypingIndicators,
        udManager: OWSUDManager,
        usernameEducationManager: UsernameEducationManager,
    ) {
        self.localIdentifiers = localIdentifiers
        self.isPrimaryDevice = isPrimaryDevice
        self.authedAccount = authedAccount

        self.avatarDefaultColorManager = avatarDefaultColorManager
        self.backupPlanManager = backupPlanManager
        self.backupSubscriptionManager = backupSubscriptionManager
        self.dmConfigurationStore = dmConfigurationStore
        self.linkPreviewSettingStore = linkPreviewSettingStore
        self.localUsernameManager = localUsernameManager
        self.paymentsHelper = paymentsHelper
        self.phoneNumberDiscoverabilityManager = phoneNumberDiscoverabilityManager
        self.pinnedThreadManager = pinnedThreadManager
        self.preferences = preferences
        self.profileManager = profileManager
        self.receiptManager = receiptManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.registrationStateChangeManager = registrationStateChangeManager
        self.storageServiceManager = storageServiceManager
        self.systemStoryManager = systemStoryManager
        self.tsAccountManager = tsAccountManager
        self.typingIndicators = typingIndicators
        self.udManager = udManager
        self.usernameEducationManager = usernameEducationManager
    }

    func unknownFields(for record: StorageServiceProtoAccountRecord) -> UnknownStorage? { record.unknownFields }

    func buildStorageItem(for record: StorageServiceProtoAccountRecord) -> StorageService.StorageItem {
        return StorageService.StorageItem(identifier: .generate(type: .account), account: record)
    }

    func buildRecord(
        for ignoredId: Void,
        unknownFields: UnknownStorage?,
        transaction: DBReadTransaction,
    ) -> StorageServiceProtoAccountRecord? {
        var builder = StorageServiceProtoAccountRecord.builder()

        let localAddress = localIdentifiers.aciAddress

        let localProfile = profileManager.localUserProfile(tx: transaction)

        if let profileKey = localProfile?.profileKey {
            builder.setProfileKey(profileKey.keyData)
        }

        let localUsernameState = localUsernameManager.usernameState(tx: transaction)
        if let username = localUsernameState.username {
            builder.setUsername(username)

            if let usernameLink = localUsernameState.usernameLink {
                var usernameLinkProtoBuilder = StorageServiceProtoAccountRecordUsernameLink.builder()

                usernameLinkProtoBuilder.setEntropy(usernameLink.entropy)
                usernameLinkProtoBuilder.setServerID(usernameLink.handle.data)
                usernameLinkProtoBuilder.setColor(
                    localUsernameManager.usernameLinkQRCodeColor(
                        tx: transaction,
                    ).asProto,
                )

                builder.setUsernameLink(usernameLinkProtoBuilder.buildInfallibly())
            }
        }

        if let profileGivenName = localProfile?.givenName {
            builder.setGivenName(profileGivenName)
        }
        if let profileFamilyName = localProfile?.familyName {
            builder.setFamilyName(profileFamilyName)
        }
        if let profileAvatarUrlPath = localProfile?.avatarUrlPath {
            builder.setAvatarURL(profileAvatarUrlPath)
        }

        if let thread = TSContactThread.getWithContactAddress(localAddress, transaction: transaction) {
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)

            builder.setNoteToSelfArchived(threadAssociatedData.isArchived)
            builder.setNoteToSelfMarkedUnread(threadAssociatedData.isMarkedUnread)
        }

        let readReceiptsEnabled = OWSReceiptManager.areReadReceiptsEnabled(transaction: transaction)
        builder.setReadReceipts(readReceiptsEnabled)

        let storyViewReceiptsEnabled = StoryManager.areViewReceiptsEnabled(transaction: transaction)
        builder.setStoryViewReceiptsEnabled(.init(storyViewReceiptsEnabled))

        let sealedSenderIndicatorsEnabled = preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: transaction)
        builder.setSealedSenderIndicators(sealedSenderIndicatorsEnabled)

        let typingIndicatorsEnabled = typingIndicators.areTypingIndicatorsEnabled()
        builder.setTypingIndicators(typingIndicatorsEnabled)

        let proxiedLinkPreviewsEnabled = SSKPreferences.areLegacyLinkPreviewsEnabled(transaction: transaction)
        builder.setProxiedLinkPreviews(proxiedLinkPreviewsEnabled)

        let linkPreviewsEnabled = linkPreviewSettingStore.areLinkPreviewsEnabled(tx: transaction)
        builder.setLinkPreviews(linkPreviewsEnabled)

        let phoneNumberSharingMode = udManager.phoneNumberSharingMode(tx: transaction)
        builder.setPhoneNumberSharingMode(phoneNumberSharingMode.asProtoMode)

        builder.setNotDiscoverableByPhoneNumber(
            tsAccountManager.phoneNumberDiscoverability(tx: transaction).orDefault.isNotDiscoverableByPhoneNumber,
        )

        let pinnedConversationProtos = self.pinnedConversationProtos(transaction: transaction)
        builder.setPinnedConversations(pinnedConversationProtos)

        let preferContactAvatars = SSKPreferences.preferContactAvatars(transaction: transaction)
        builder.setPreferContactAvatars(preferContactAvatars)

        let paymentsState = paymentsHelper.paymentsState
        var paymentsBuilder = StorageServiceProtoAccountRecordPayments.builder()
        paymentsBuilder.setEnabled(paymentsState.isEnabled)
        if let paymentsEntropy = paymentsState.paymentsEntropy {
            paymentsBuilder.setPaymentsEntropy(paymentsEntropy)
        }
        builder.setPayments(paymentsBuilder.buildInfallibly())

        if let unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        let dmConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .universal, tx: transaction)
        builder.setUniversalExpireTimer(dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0)

        if let customEmojiSet = ReactionManager.customEmojiSet(transaction: transaction) {
            builder.setPreferredReactionEmoji(customEmojiSet)
        }

        if
            let donationSubscriberID = DonationSubscriptionManager.getSubscriberID(transaction: transaction),
            let donationSubscriberCurrencyCode = DonationSubscriptionManager.getSubscriberCurrencyCode(transaction: transaction)
        {
            builder.setDonorSubscriberID(donationSubscriberID)
            builder.setDonorSubscriberCurrencyCode(donationSubscriberCurrencyCode)
        }
        builder.setDonorSubscriptionManuallyCancelled(DonationSubscriptionManager.userManuallyCancelledSubscription(transaction: transaction))

        if let backupSubscriberData = backupSubscriptionManager.getIAPSubscriberData(tx: transaction) {
            var subscriberDataBuilder = StorageServiceProtoAccountRecordIAPSubscriberData.builder()
            subscriberDataBuilder.setSubscriberID(backupSubscriberData.subscriberId)

            switch backupSubscriberData.iapSubscriptionId {
            case .originalTransactionId(let value):
                subscriberDataBuilder.setIapSubscriptionID(.originalTransactionID(value))
            case .purchaseToken(let value):
                subscriberDataBuilder.setIapSubscriptionID(.purchaseToken(value))
            }

            builder.setBackupSubscriberData(subscriberDataBuilder.buildInfallibly())
        }

        builder.setMyStoryPrivacyHasBeenSet(StoryManager.hasSetMyStoriesPrivacy(transaction: transaction))

        builder.setReadOnboardingStory(systemStoryManager.isOnboardingStoryRead(transaction: transaction))
        builder.setViewedOnboardingStory(systemStoryManager.isOnboardingStoryViewed(transaction: transaction))

        builder.setDisplayBadgesOnProfile(DonationSubscriptionManager.displayBadgesOnProfile(transaction: transaction))

        builder.setKeepMutedChatsArchived(SSKPreferences.shouldKeepMutedChatsArchived(transaction: transaction))

        builder.setStoriesDisabled(!StoryManager.areStoriesEnabled(transaction: transaction))

        builder.setCompletedUsernameOnboarding(
            !usernameEducationManager.shouldShowUsernameEducation(tx: transaction),
        )

        if
            let localRecipient = recipientDatabaseTable.fetchRecipient(
                serviceId: localIdentifiers.aci,
                transaction: transaction,
            )
        {
            builder.setAvatarColor(
                avatarDefaultColorManager.defaultColor(
                    useCase: .contact(recipient: localRecipient),
                    tx: transaction,
                ).asStorageServiceProtoAvatarColor,
            )
        }

        let backupLevel: LibSignalClient.BackupLevel? = switch backupPlanManager.backupPlan(tx: transaction) {
        case .disabled, .disabling: nil
        case .free: .free
        case .paid, .paidExpiringSoon, .paidAsTester: .paid
        }
        if let backupLevel {
            builder.setBackupTier(UInt64(backupLevel.rawValue))
        } else {
            // Leave backupTier unset.
        }

        return builder.buildInfallibly()
    }

    func mergeRecord(
        _ record: StorageServiceProtoAccountRecord,
        transaction: DBWriteTransaction,
    ) -> StorageServiceMergeResult<Void> {
        var needsUpdate = false

        let localAddress = localIdentifiers.aciAddress

        // Gather some local contact state to do comparisons against.
        let localUserProfile = profileManager.localUserProfile(tx: transaction)
        let localAvatarUrl = localUserProfile?.avatarUrlPath

        // On the primary device, we only ever want to take the profile key from
        // storage service if we have no record of a local profile. This allows us
        // to restore your profile during onboarding but ensures no other device
        // can ever change the profile key other than the primary device.
        let allowsRemoteProfileKeyChanges = !isPrimaryDevice || (localUserProfile?.givenName?.isEmpty != false && localUserProfile?.loadAvatarImage() == nil)
        if allowsRemoteProfileKeyChanges, let profileKey = record.profileKey, localUserProfile?.profileKey?.keyData != profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: localIdentifiers.aci,
                onlyFillInIfMissing: false,
                shouldFetchProfile: true,
                userProfileWriter: .storageService,
                localIdentifiers: localIdentifiers,
                authedAccount: authedAccount,
                tx: transaction,
            )
        } else if localUserProfile?.profileKey != nil && !record.hasProfileKey {
            // If we have a local profile key for this user but the service doesn't, mark it as needing update.
            needsUpdate = true
        }

        // We normalize the names based on what we'd eventually send to the server
        // when uploading our profile. If we don't, then we'd eventually change our
        // profile name when reuploading anyways (this isn't that bad). However! If
        // the normalized version becomes nil/empty, then reuploading would cause
        // us to clear our profile name, and that's bad. Therefore, we must ensure
        // values from Storage Service are valid before accepting them.
        let remoteGivenName = record.givenName
        let remoteFamilyName = record.familyName

        let remoteGivenNameComponent = remoteGivenName.flatMap { OWSUserProfile.NameComponent(truncating: $0) }
        let remoteFamilyNameComponent = remoteFamilyName.flatMap { OWSUserProfile.NameComponent(truncating: $0) }

        let normalizedRemoteGivenName = remoteGivenNameComponent?.stringValue.rawValue
        let normalizedRemoteFamilyName = remoteFamilyNameComponent?.stringValue.rawValue

        // If we had to normalize the values, we need to put the normalized
        // versions back into Storage Service for our other devices. Note: If all
        // of our linked devices are properly enforcing the name length limits &
        // stripping behaviors, this should be impossible.
        if remoteGivenName != normalizedRemoteGivenName || remoteFamilyName != normalizedRemoteFamilyName {
            needsUpdate = true
        }

        // Given name can never be cleared, so ignore all info about the profile if
        // there's no given name.
        if
            let normalizedRemoteGivenName,
            localUserProfile?.givenName != normalizedRemoteGivenName
            || localUserProfile?.familyName != normalizedRemoteFamilyName
            || localAvatarUrl != record.avatarURL
        {
            let localUserProfile = OWSUserProfile.getOrBuildUserProfileForLocalUser(
                userProfileWriter: .storageService,
                tx: transaction,
            )
            localUserProfile.update(
                givenName: .setTo(normalizedRemoteGivenName),
                familyName: .setTo(normalizedRemoteFamilyName),
                avatarUrlPath: .setTo(record.avatarURL),
                userProfileWriter: .storageService,
                transaction: transaction,
            )
            transaction.addSyncCompletion { [authedAccount, profileManager] in
                Task {
                    do {
                        try await profileManager.downloadAndDecryptLocalUserAvatarIfNeeded(authedAccount: authedAccount)
                    } catch {
                        Logger.warn("Couldn't download local avatar: \(error)")
                    }
                }
            }
        } else if
            localUserProfile?.givenName != nil && !record.hasGivenName
            || localUserProfile?.familyName != nil && !record.hasFamilyName
            || localAvatarUrl != nil && !record.hasAvatarURL
        {
            needsUpdate = true
        }

        if let remoteUsername = record.username {
            if
                let remoteUsernameLinkProto = record.usernameLink,
                let remoteUsernameLinkProtoHandleData = remoteUsernameLinkProto.serverID,
                let remoteUsernameLinkProtoHandle = UUID(data: remoteUsernameLinkProtoHandleData),
                let remoteUsernameLinkProtoEntropy = remoteUsernameLinkProto.entropy,
                let remoteUsernameLink = Usernames.UsernameLink(
                    handle: remoteUsernameLinkProtoHandle,
                    entropy: remoteUsernameLinkProtoEntropy,
                )
            {
                localUsernameManager.setLocalUsername(
                    username: remoteUsername,
                    usernameLink: remoteUsernameLink,
                    tx: transaction,
                )

                localUsernameManager.setUsernameLinkQRCodeColor(
                    color: QRCodeColor(proto: remoteUsernameLinkProto.color),
                    tx: transaction,
                )
            } else {
                localUsernameManager.setLocalUsernameWithCorruptedLink(
                    username: remoteUsername,
                    tx: transaction,
                )
            }
        } else {
            localUsernameManager.clearLocalUsername(tx: transaction)
        }

        let localThread = TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
        let localThreadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: localThread, transaction: transaction)

        if record.noteToSelfArchived != localThreadAssociatedData.isArchived {
            localThreadAssociatedData.updateWith(isArchived: record.noteToSelfArchived, updateStorageService: false, transaction: transaction)
        }

        if record.noteToSelfMarkedUnread != localThreadAssociatedData.isMarkedUnread {
            localThreadAssociatedData.updateWith(isMarkedUnread: record.noteToSelfMarkedUnread, updateStorageService: false, transaction: transaction)
        }

        let localReadReceiptsEnabled = OWSReceiptManager.areReadReceiptsEnabled(transaction: transaction)
        if record.readReceipts != localReadReceiptsEnabled {
            receiptManager.setAreReadReceiptsEnabled(record.readReceipts, transaction: transaction)
        }

        let localViewReceiptsEnabled = StoryManager.areViewReceiptsEnabled(transaction: transaction)
        if let storyViewReceiptsEnabled = record.storyViewReceiptsEnabled.boolValue {
            if storyViewReceiptsEnabled != localViewReceiptsEnabled {
                StoryManager.setAreViewReceiptsEnabled(storyViewReceiptsEnabled, shouldUpdateStorageService: false, transaction: transaction)
            }
        } else {
            needsUpdate = true
        }

        let sealedSenderIndicatorsEnabled = preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: transaction)
        if record.sealedSenderIndicators != sealedSenderIndicatorsEnabled {
            preferences.setShouldShowUnidentifiedDeliveryIndicators(record.sealedSenderIndicators, transaction: transaction)
        }

        let typingIndicatorsEnabled = typingIndicators.areTypingIndicatorsEnabled()
        if record.typingIndicators != typingIndicatorsEnabled {
            typingIndicators.setTypingIndicatorsEnabled(value: record.typingIndicators, transaction: transaction)
        }

        let linkPreviewsEnabled = linkPreviewSettingStore.areLinkPreviewsEnabled(tx: transaction)
        if record.linkPreviews != linkPreviewsEnabled {
            linkPreviewSettingStore.setAreLinkPreviewsEnabled(record.linkPreviews, tx: transaction)
        }

        let proxiedLinkPreviewsEnabled = SSKPreferences.areLegacyLinkPreviewsEnabled(transaction: transaction)
        if record.proxiedLinkPreviews != proxiedLinkPreviewsEnabled {
            SSKPreferences.setAreLegacyLinkPreviewsEnabled(record.proxiedLinkPreviews, transaction: transaction)
        }

        let localPhoneNumberSharingMode = udManager.phoneNumberSharingMode(tx: transaction)
        if record.phoneNumberSharingMode != localPhoneNumberSharingMode.asProtoMode {
            if let localMode = record.phoneNumberSharingMode.asLocalMode {
                udManager.setPhoneNumberSharingMode(localMode, updateStorageServiceAndProfile: false, tx: transaction)
            } else {
                Logger.error("Unknown phone number sharing mode \(String(describing: record.phoneNumberSharingMode))")
            }
        }

        let localPhoneNumberDiscoverability = tsAccountManager.phoneNumberDiscoverability(tx: transaction)
        if record.notDiscoverableByPhoneNumber != localPhoneNumberDiscoverability?.isNotDiscoverableByPhoneNumber {
            phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                record.notDiscoverableByPhoneNumber ? .nobody : .everybody,
                updateAccountAttributes: false,
                updateStorageService: false,
                authedAccount: authedAccount,
                tx: transaction,
            )
        }

        do {
            try self.processPinnedConversationsProto(record.pinnedConversations, transaction: transaction)
        } catch {
            owsFailDebug("Failed to process pinned conversations \(error)")
            needsUpdate = true
        }

        let localPrefersContactAvatars = SSKPreferences.preferContactAvatars(transaction: transaction)
        if record.preferContactAvatars != localPrefersContactAvatars {
            SSKPreferences.setPreferContactAvatars(
                record.preferContactAvatars,
                updateStorageService: false,
                transaction: transaction,
            )
        }

        let localPaymentsState = paymentsHelper.paymentsState
        let servicePaymentsState = PaymentsState.build(
            arePaymentsEnabled: record.payments?.enabled ?? false,
            paymentsEntropy: record.payments?.paymentsEntropy,
        )
        if localPaymentsState != servicePaymentsState {
            let mergedPaymentsState = PaymentsState.build(
                // Honor "arePaymentsEnabled" from the service.
                arePaymentsEnabled: servicePaymentsState.isEnabled,
                // Prefer paymentsEntropy from service, but try to retain local paymentsEntropy otherwise.
                paymentsEntropy: servicePaymentsState.paymentsEntropy ?? localPaymentsState.paymentsEntropy,
            )
            paymentsHelper.setPaymentsState(
                mergedPaymentsState,
                originatedLocally: false,
                transaction: transaction,
            )
        }

        let remoteExpireToken: DisappearingMessageToken = .token(forProtoExpireTimerSeconds: record.universalExpireTimer)
        dmConfigurationStore.setUniversalTimer(token: remoteExpireToken, tx: transaction)

        if !record.preferredReactionEmoji.isEmpty {
            // Treat new preferred emoji as a full source of truth (if not empty). Note
            // that we aren't doing any validation up front, which may be important if
            // another platform supports an emoji we don't (say, because a new version
            // of Unicode has come out). We deal with this when the custom set is read.
            ReactionManager.setCustomEmojiSet(record.preferredReactionEmoji, transaction: transaction)
        }

        if
            let donationSubscriberId = record.donorSubscriberID,
            let donationSubscriberCurrencyCode = record.donorSubscriberCurrencyCode
        {
            if donationSubscriberId != DonationSubscriptionManager.getSubscriberID(transaction: transaction) {
                DonationSubscriptionManager.setSubscriberID(donationSubscriberId, transaction: transaction)
            }

            if donationSubscriberCurrencyCode != DonationSubscriptionManager.getSubscriberCurrencyCode(transaction: transaction) {
                DonationSubscriptionManager.setSubscriberCurrencyCode(donationSubscriberCurrencyCode, transaction: transaction)
            }
        }

        let localDonationSubscriptionManuallyCancelled = DonationSubscriptionManager.userManuallyCancelledSubscription(transaction: transaction)
        if localDonationSubscriptionManuallyCancelled != record.donorSubscriptionManuallyCancelled {
            DonationSubscriptionManager.setUserManuallyCancelledSubscription(
                record.donorSubscriptionManuallyCancelled,
                updateStorageService: false,
                transaction: transaction,
            )
        }

        if
            let backupSubscriberData = record.backupSubscriberData,
            let subscriberId = backupSubscriberData.subscriberID,
            let iapSubscriptionIdProto = backupSubscriberData.iapSubscriptionID
        {
            typealias IAPSubscriberData = BackupSubscription.IAPSubscriberData

            let iapSubscriptionId: IAPSubscriberData.IAPSubscriptionId
            switch iapSubscriptionIdProto {
            case .originalTransactionID(let value):
                iapSubscriptionId = .originalTransactionId(value)
            case .purchaseToken(let value):
                iapSubscriptionId = .purchaseToken(value)
            }

            backupSubscriptionManager.restoreIAPSubscriberData(
                IAPSubscriberData(
                    subscriberId: subscriberId,
                    iapSubscriptionId: iapSubscriptionId,
                ),
                tx: transaction,
            )
        }

        let localDisplayBadgesOnProfile = DonationSubscriptionManager.displayBadgesOnProfile(transaction: transaction)
        if localDisplayBadgesOnProfile != record.displayBadgesOnProfile {
            DonationSubscriptionManager.setDisplayBadgesOnProfile(
                record.displayBadgesOnProfile,
                updateStorageService: false,
                transaction: transaction,
            )
        }

        let localKeepMutedChatsArchived = SSKPreferences.shouldKeepMutedChatsArchived(transaction: transaction)
        if localKeepMutedChatsArchived != record.keepMutedChatsArchived {
            SSKPreferences.setShouldKeepMutedChatsArchived(record.keepMutedChatsArchived, transaction: transaction)
        }

        let localHasSetMyStoriesPrivacy = StoryManager.hasSetMyStoriesPrivacy(transaction: transaction)
        if !localHasSetMyStoriesPrivacy, record.myStoryPrivacyHasBeenSet {
            StoryManager.setHasSetMyStoriesPrivacy(true, shouldUpdateStorageService: false, transaction: transaction)
        }

        let localHasReadOnboardingStory = systemStoryManager.isOnboardingStoryRead(transaction: transaction)
        if !localHasReadOnboardingStory, record.readOnboardingStory {
            systemStoryManager.setHasReadOnboardingStory(transaction: transaction, updateStorageService: false)
        }

        let localHasViewedOnboardingStory = systemStoryManager.isOnboardingStoryViewed(transaction: transaction)
        if !localHasViewedOnboardingStory, record.viewedOnboardingStory {
            try? systemStoryManager.setHasViewedOnboardingStory(source: .otherDevice, transaction: transaction)
        }

        let localStoriesDisabled = !StoryManager.areStoriesEnabled(transaction: transaction)
        if localStoriesDisabled != record.storiesDisabled {
            StoryManager.setAreStoriesEnabled(!record.storiesDisabled, shouldUpdateStorageService: false, transaction: transaction)
        }

        let hasCompletedUsernameOnboarding = !usernameEducationManager.shouldShowUsernameEducation(tx: transaction)
        if !hasCompletedUsernameOnboarding, record.completedUsernameOnboarding {
            usernameEducationManager.setShouldShowUsernameEducation(
                false,
                tx: transaction,
            )
        }

        mergeBackupPlan(in: record, tx: transaction)

        if mergeDefaultAvatarColor(in: record, tx: transaction) {
            needsUpdate = true
        }

        return .merged(needsUpdate: needsUpdate, ())
    }

    private func mergeBackupPlan(
        in record: StorageServiceProtoAccountRecord,
        tx: DBWriteTransaction,
    ) {
        guard !isPrimaryDevice else {
            // Never set the BackupPlan on a primary via Storage Service.
            return
        }

        if let backupTierRawValue = record.backupTier {
            if
                let backupTierUInt8 = UInt8(exactly: backupTierRawValue),
                let backupLevel = LibSignalClient.BackupLevel(rawValue: backupTierUInt8)
            {
                backupPlanManager.setBackupPlan(fromStorageService: backupLevel, tx: tx)
            } else {
                let logger = PrefixedLogger(prefix: "[Backups]")
                logger.warn("Ignoring backupTier value: \(backupTierRawValue)")
            }
        } else {
            backupPlanManager.setBackupPlan(fromStorageService: nil, tx: tx)
        }
    }

    /// Merge the default avatar color from this AccountRecord with local state.
    ///
    /// - Returns Whether this record needs updating. For example, the primary
    /// may need to overwrite state set by a linked device.
    private func mergeDefaultAvatarColor(
        in record: StorageServiceProtoAccountRecord,
        tx: DBWriteTransaction,
    ) -> Bool {
        guard
            let localRecipient = recipientDatabaseTable.fetchRecipient(
                serviceId: localIdentifiers.aci,
                transaction: tx,
            )
        else {
            return false
        }

        let localDefaultAvatarColor = avatarDefaultColorManager.defaultColor(
            useCase: .contact(recipient: localRecipient),
            tx: tx,
        )
        let remoteDefaultAvatarColor = record.avatarColor.flatMap {
            AvatarTheme.from(storageServiceProtoAvatarColor: $0)
        }

        guard localDefaultAvatarColor != remoteDefaultAvatarColor else {
            return false
        }

        if isPrimaryDevice {
            return true
        } else if let remoteDefaultAvatarColor {
            try? avatarDefaultColorManager.persistDefaultColor(
                remoteDefaultAvatarColor,
                recipientRowId: localRecipient.id,
                tx: tx,
            )
        }

        return false
    }
}

// MARK: -

extension Optional where Wrapped == PhoneNumberSharingMode {
    var asProtoMode: StorageServiceProtoAccountRecordPhoneNumberSharingMode {
        switch self {
        case .none: return .unknown
        case .nobody: return .nobody
        case .everybody: return .everybody
        }
    }
}

extension StorageServiceProtoAccountRecordPhoneNumberSharingMode {
    var asLocalMode: PhoneNumberSharingMode? {
        switch self {
        case .unknown: return nil
        case .everybody: return .everybody
        case .nobody: return .nobody
        default:
            owsFailDebug("unexpected case \(self)")
            return nil
        }
    }
}

// MARK: -

extension StorageServiceAccountRecordUpdater {

    private func processPinnedConversationsProto(
        _ pinnedConversations: [StorageServiceProtoAccountRecordPinnedConversation],
        transaction: DBWriteTransaction,
    ) throws {
        if pinnedConversations.count > PinnedThreads.maxPinnedThreads {
            Logger.warn("Received unexpected number of pinned threads (\(pinnedConversations.count))")
        }

        var pinnedThreadIds = [String]()
        for pinnedConversation in pinnedConversations {
            switch pinnedConversation.identifier {
            case .contact(let contact)?:
                let address = SignalServiceAddress.legacyAddress(
                    serviceId: ServiceId.parseFrom(
                        serviceIdBinary: contact.serviceIDBinary,
                        serviceIdString: contact.serviceID,
                    ),
                    phoneNumber: contact.e164,
                )
                guard address.isValid else {
                    owsFailDebug("Dropping pinned thread with invalid address \(address)")
                    continue
                }
                let thread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
                pinnedThreadIds.append(thread.uniqueId)
            case .groupMasterKey(let masterKey)?:
                let contextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: masterKey)
                let threadUniqueId = TSGroupThread.threadId(forGroupId: contextInfo.groupId.serialize(), transaction: transaction)
                pinnedThreadIds.append(threadUniqueId)
            case .legacyGroupID(let groupId)?:
                let threadUniqueId = TSGroupThread.threadId(
                    forGroupId: groupId,
                    transaction: transaction,
                )
                pinnedThreadIds.append(threadUniqueId)
            default:
                break
            }
        }

        pinnedThreadManager.updatePinnedThreadIds(pinnedThreadIds, updateStorageService: false, tx: transaction)
    }

    private func pinnedConversationProtos(
        transaction: DBReadTransaction,
    ) -> [StorageServiceProtoAccountRecordPinnedConversation] {
        let pinnedThreads = pinnedThreadManager.pinnedThreads(tx: transaction)

        var pinnedConversationProtos = [StorageServiceProtoAccountRecordPinnedConversation]()
        for pinnedThread in pinnedThreads {
            var pinnedConversationBuilder = StorageServiceProtoAccountRecordPinnedConversation.builder()

            if let groupThread = pinnedThread as? TSGroupThread {
                if let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 {
                    let masterKey: GroupMasterKey
                    do {
                        masterKey = try groupModelV2.masterKey()
                    } catch {
                        owsFailDebug("Missing master key: \(error)")
                        continue
                    }
                    pinnedConversationBuilder.setIdentifier(.groupMasterKey(masterKey.serialize()))
                } else {
                    pinnedConversationBuilder.setIdentifier(.legacyGroupID(groupThread.groupModel.groupId))
                }

            } else if let contactThread = pinnedThread as? TSContactThread {
                var contactBuilder = StorageServiceProtoAccountRecordPinnedConversationContact.builder()
                if let serviceId = contactThread.contactAddress.serviceId {
                    if BuildFlags.serviceIdStrings {
                        contactBuilder.setServiceID(serviceId.serviceIdString)
                    }
                    if BuildFlags.serviceIdBinaryConstantOverhead {
                        contactBuilder.setServiceIDBinary(serviceId.serviceIdBinary)
                    }
                } else if let e164 = contactThread.contactAddress.phoneNumber {
                    contactBuilder.setE164(e164)
                } else {
                    owsFailDebug("Missing uuid and phone number for thread")
                }
                pinnedConversationBuilder.setIdentifier(.contact(contactBuilder.buildInfallibly()))
            }

            pinnedConversationProtos.append(pinnedConversationBuilder.buildInfallibly())
        }

        return pinnedConversationProtos
    }
}

// MARK: - Story Distribution List Record

class StorageServiceStoryDistributionListRecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = Data
    typealias RecordType = StorageServiceProtoStoryDistributionListRecord

    private let privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let recipientFetcher: RecipientFetcher
    private let storyRecipientManager: StoryRecipientManager
    private let storyRecipientStore: StoryRecipientStore
    private let threadRemover: any ThreadRemover

    init(
        privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        storyRecipientManager: StoryRecipientManager,
        storyRecipientStore: StoryRecipientStore,
        threadRemover: any ThreadRemover,
    ) {
        self.privateStoryThreadDeletionManager = privateStoryThreadDeletionManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.storyRecipientManager = storyRecipientManager
        self.storyRecipientStore = storyRecipientStore
        self.threadRemover = threadRemover
    }

    func unknownFields(for record: StorageServiceProtoStoryDistributionListRecord) -> UnknownStorage? { record.unknownFields }

    func buildStorageItem(for record: StorageServiceProtoStoryDistributionListRecord) -> StorageService.StorageItem {
        return StorageService.StorageItem(identifier: .generate(type: .storyDistributionList), storyDistributionList: record)
    }

    func buildRecord(
        for distributionListIdentifier: Data,
        unknownFields: UnknownStorage?,
        transaction: DBReadTransaction,
    ) -> StorageServiceProtoStoryDistributionListRecord? {
        guard let uniqueId = UUID(data: distributionListIdentifier)?.uuidString else {
            owsFailDebug("Invalid distributionListIdentifier.")
            return nil
        }

        var builder = StorageServiceProtoStoryDistributionListRecord.builder()
        builder.setIdentifier(distributionListIdentifier)

        if
            let deletedAtTimestamp = privateStoryThreadDeletionManager.deletedAtTimestamp(
                forDistributionListIdentifier: distributionListIdentifier,
                tx: transaction,
            )
        {
            builder.setDeletedAtTimestamp(deletedAtTimestamp)
        } else if
            let story = TSPrivateStoryThread.anyFetchPrivateStoryThread(
                uniqueId: uniqueId,
                transaction: transaction,
            )
        {
            builder.setName(story.name)
            let recipients = (try? storyRecipientManager.fetchRecipients(forStoryThread: story, tx: transaction)) ?? []
            let serviceIds = recipients.compactMap { $0.aci ?? $0.pni }
            if BuildFlags.serviceIdStrings {
                builder.setRecipientServiceIds(serviceIds.map(\.serviceIdString))
            }
            if BuildFlags.serviceIdBinaryVariableOverhead {
                builder.setRecipientServiceIdsBinary(serviceIds.map(\.serviceIdBinary))
            }
            builder.setAllowsReplies(story.allowsReplies)
            builder.setIsBlockList(story.storyViewMode == .blockList)
        } else {
            return nil
        }

        // Unknown

        if let unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return builder.buildInfallibly()
    }

    func mergeRecord(
        _ record: StorageServiceProtoStoryDistributionListRecord,
        transaction: DBWriteTransaction,
    ) -> StorageServiceMergeResult<Data> {
        guard let identifier = record.identifier, let uniqueId = UUID(data: identifier) else {
            owsFailDebug("identifier unexpectedly missing for distribution list")
            return .invalid
        }

        let existingStory = TSPrivateStoryThread.anyFetchPrivateStoryThread(
            uniqueId: uniqueId.uuidString,
            transaction: transaction,
        )

        // The story has been deleted on another device, record that
        // and ensure we don't try and put it back.
        guard record.deletedAtTimestamp == 0 else {
            if let existingStory {
                threadRemover.remove(existingStory, tx: transaction)
            }
            privateStoryThreadDeletionManager.recordDeletedAtTimestamp(
                record.deletedAtTimestamp,
                forDistributionListIdentifier: identifier,
                tx: transaction,
            )
            return .merged(needsUpdate: false, identifier)
        }

        var needsUpdate = false

        let remoteRecipientServiceIds: [ServiceId]
        if !record.recipientServiceIdsBinary.isEmpty {
            remoteRecipientServiceIds = record.recipientServiceIdsBinary.compactMap { try? ServiceId.parseFrom(serviceIdBinary: $0) }
        } else {
            remoteRecipientServiceIds = record.recipientServiceIds.compactMap { try? ServiceId.parseFrom(serviceIdString: $0) }
        }

        let remoteRecipientIds = remoteRecipientServiceIds.map {
            return recipientFetcher.fetchOrCreate(serviceId: $0, tx: transaction).id
        }

        if let story = existingStory {
            // My Story has a hardcoded, localized name that we don't sync
            if !story.isMyStory {
                let localName = story.name
                if let name = record.name, localName != name {
                    story.updateWithName(name, updateStorageService: false, transaction: transaction)
                } else if !record.hasName {
                    needsUpdate = true
                }
            }

            let localAllowsReplies = story.allowsReplies
            if record.allowsReplies != localAllowsReplies {
                story.updateWithAllowsReplies(record.allowsReplies, updateStorageService: false, transaction: transaction)
            }

            let hasChanged: Bool = (
                (story.storyViewMode == .blockList) != record.isBlockList
                    || Set(remoteRecipientIds) != (try? storyRecipientStore.fetchRecipientIds(forStoryThreadId: story.sqliteRowId!, tx: transaction)).map(Set.init(_:)),
            )

            if hasChanged {
                story.updateWithStoryViewMode(
                    record.isBlockList ? .blockList : .explicit,
                    storyRecipientIds: .setTo(remoteRecipientIds),
                    updateStorageService: false,
                    transaction: transaction,
                )
            }
        } else {
            guard let name = record.name else {
                owsFailDebug("new private story missing required name")
                return .invalid
            }
            let newStory = TSPrivateStoryThread(
                uniqueId: uniqueId.uuidString,
                name: name,
                allowsReplies: record.allowsReplies,
                viewMode: record.isBlockList ? .blockList : .explicit,
            )
            newStory.anyInsert(transaction: transaction)

            failIfThrows {
                try storyRecipientManager.setRecipientIds(
                    remoteRecipientIds,
                    for: newStory,
                    shouldUpdateStorageService: false,
                    tx: transaction,
                )
            }
        }

        return .merged(needsUpdate: needsUpdate, identifier)
    }
}

// MARK: - Call Link Record

class StorageServiceCallLinkRecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = Data
    typealias RecordType = StorageServiceProtoCallLinkRecord

    let callLinkStore: any CallLinkRecordStore
    private let callRecordDeleteManager: any CallRecordDeleteManager
    private let callRecordStore: any CallRecordStore

    init(
        callLinkStore: any CallLinkRecordStore,
        callRecordDeleteManager: any CallRecordDeleteManager,
        callRecordStore: any CallRecordStore,
    ) {
        self.callLinkStore = callLinkStore
        self.callRecordDeleteManager = callRecordDeleteManager
        self.callRecordStore = callRecordStore
    }

    func unknownFields(for record: StorageServiceProtoCallLinkRecord) -> UnknownStorage? { record.unknownFields }

    func buildStorageItem(for record: StorageServiceProtoCallLinkRecord) -> StorageService.StorageItem {
        return StorageService.StorageItem(identifier: .generate(type: .callLink), callLink: record)
    }

    func buildRecord(
        for rootKeyData: Data,
        unknownFields: UnknownStorage?,
        transaction tx: DBReadTransaction,
    ) -> StorageServiceProtoCallLinkRecord? {
        guard let rootKey = try? CallLinkRootKey(rootKeyData) else {
            owsFailDebug("Invalid CallLinkRootKey")
            return nil
        }
        let roomId = rootKey.deriveRoomId()
        let callLink: CallLinkRecord?
        do {
            callLink = try self.callLinkStore.fetch(roomId: roomId, tx: tx)
        } catch {
            owsFailDebug("Skipping CallLink that can't be fetched: \(rootKey.description)")
            return nil
        }

        guard let callLink, callLink.adminPasskey != nil || callLink.adminDeletedAtTimestampMs != nil else {
            // We're not an admin, so this link doesn't go in Storage Service.
            return nil
        }

        var builder = StorageServiceProtoCallLinkRecord.builder()
        builder.setRootKey(rootKey.bytes)
        if let adminDeletedAtTimestampMs = callLink.adminDeletedAtTimestampMs {
            builder.setDeletedAtTimestampMs(adminDeletedAtTimestampMs)
        } else if let adminPasskey = callLink.adminPasskey {
            builder.setAdminPasskey(adminPasskey)
        }

        if let unknownFields {
            builder.setUnknownFields(unknownFields)
        }
        return builder.buildInfallibly()
    }

    func mergeRecord(
        _ record: StorageServiceProtoCallLinkRecord,
        transaction tx: DBWriteTransaction,
    ) -> StorageServiceMergeResult<Data> {
        guard let rootKeyData = record.rootKey, let rootKey = try? CallLinkRootKey(rootKeyData) else {
            owsFailDebug("invalid rootKey")
            return .invalid
        }
        do {
            var (callLink, _) = try self.callLinkStore.fetchOrInsert(rootKey: rootKey, tx: tx)
            // The earliest deletion timestamp takes precendence when merging.
            if record.deletedAtTimestampMs > 0 || callLink.adminDeletedAtTimestampMs != nil {
                self.callRecordDeleteManager.deleteCallRecords(
                    try self.callRecordStore.fetchExisting(conversationId: .callLink(callLinkRowId: callLink.id), limit: nil, tx: tx),
                    sendSyncMessageOnDelete: false,
                    tx: tx,
                )
                callLink.markDeleted(atTimestampMs: [record.deletedAtTimestampMs, callLink.adminDeletedAtTimestampMs].compacted().min()!)
            } else if let adminPasskey = record.adminPasskey?.nilIfEmpty {
                callLink.adminPasskey = adminPasskey
                callLink.setNeedsFetch()
            }
            try self.callLinkStore.update(callLink, tx: tx)
        } catch {
            owsFailDebug("Couldn't merge CallLink \(rootKey.description): \(error)")
        }
        return .merged(needsUpdate: false, rootKey.bytes)
    }
}

// MARK: -

extension StorageServiceProtoOptionalBool {
    var boolValue: Bool? {
        switch self {
        case .unset: return nil
        case .true: return true
        case .false: return false
        case .UNRECOGNIZED: return nil
        }
    }

    init(_ boolValue: Bool) {
        self = boolValue ? .true : .false
    }
}

private extension QRCodeColor {
    var asProto: StorageServiceProtoAccountRecordUsernameLinkColor {
        switch self {
        case .blue: return .blue
        case .white: return .white
        case .grey: return .grey
        case .olive: return .olive
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        }
    }

    init(proto: StorageServiceProtoAccountRecordUsernameLinkColor) {
        switch proto {
        case .blue: self = .blue
        case .white: self = .white
        case .grey: self = .grey
        case .olive: self = .olive
        case .green: self = .green
        case .orange: self = .orange
        case .pink: self = .pink
        case .purple: self = .purple
        case .unknown, .UNRECOGNIZED:
            Logger.warn("Unrecognized username link color in proto!")
            self = .unknown
        }
    }
}
