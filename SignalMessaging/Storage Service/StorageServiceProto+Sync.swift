//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SwiftProtobuf
import SignalServiceKit

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
        transaction: SDSAnyReadTransaction
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
        transaction: SDSAnyWriteTransaction
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
    private enum Constant {
        static let storageServiceUnregisteredThreshold = kMonthInterval
    }

    /// All contact records must have a UUID.
    var serviceId: UntypedServiceId

    /// Contact records may have a phone number.
    var serviceE164: E164?

    /// Contact records may be unregistered.
    var unregisteredAtTimestamp: UInt64?

    init?(serviceId: UntypedServiceId?, serviceE164: E164?, unregisteredAtTimestamp: UInt64?) {
        guard let serviceId else {
            return nil
        }
        self.serviceId = serviceId
        self.serviceE164 = serviceE164
        self.unregisteredAtTimestamp = unregisteredAtTimestamp
    }

    enum RegistrationStatus {
        case registered
        case unregisteredRecently
        case unregisteredMoreThanOneMonthAgo
    }

    func registrationStatus(currentDate: Date) -> RegistrationStatus {
        switch unregisteredAtTimestamp {
        case .none:
            return .registered

        case .some(let timestamp) where currentDate.timeIntervalSince(Date(millisecondsSince1970: timestamp)) <= Constant.storageServiceUnregisteredThreshold:
            return .unregisteredRecently

        case .some:
            return .unregisteredMoreThanOneMonthAgo
        }
    }

    fileprivate init?(_ contactRecord: StorageServiceProtoContactRecord) {
        let unregisteredAtTimestamp: UInt64?
        if contactRecord.unregisteredAtTimestamp == 0 {
            unregisteredAtTimestamp = nil  // registered
        } else {
            unregisteredAtTimestamp = contactRecord.unregisteredAtTimestamp
        }
        self.init(
            serviceId: UntypedServiceId.expectNilOrValid(uuidString: contactRecord.serviceUuid),
            serviceE164: E164.expectNilOrValid(stringValue: contactRecord.serviceE164),
            unregisteredAtTimestamp: unregisteredAtTimestamp
        )
    }

    static func fetch(for accountId: AccountId, transaction: SDSAnyReadTransaction) -> Self? {
        SignalRecipient.anyFetch(uniqueId: accountId, transaction: transaction).flatMap { Self($0) }
    }

    fileprivate init?(_ signalRecipient: SignalRecipient) {
        let unregisteredAtTimestamp: UInt64?
        if signalRecipient.isRegistered {
            unregisteredAtTimestamp = nil
        } else {
            unregisteredAtTimestamp = (
                signalRecipient.unregisteredAtTimestamp ?? SignalRecipient.Constants.distantPastUnregisteredTimestamp
            )
        }
        self.init(
            serviceId: signalRecipient.serviceId,
            serviceE164: E164.expectNilOrValid(stringValue: signalRecipient.phoneNumber),
            unregisteredAtTimestamp: unregisteredAtTimestamp
        )
    }

    func shouldBeInStorageService(currentDate: Date) -> Bool {
        switch registrationStatus(currentDate: currentDate) {
        case .registered, .unregisteredRecently:
            return true
        case .unregisteredMoreThanOneMonthAgo:
            return false
        }
    }
}

class StorageServiceContactRecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = AccountId
    typealias RecordType = StorageServiceProtoContactRecord

    private let localIdentifiers: LocalIdentifiers
    private let authedAccount: AuthedAccount
    private let blockingManager: BlockingManager
    private let bulkProfileFetch: BulkProfileFetch
    private let contactsManager: OWSContactsManager
    private let identityManager: OWSIdentityManager
    private let profileManager: OWSProfileManager
    private let tsAccountManager: TSAccountManager
    private let usernameLookupManager: UsernameLookupManager
    private let recipientMerger: RecipientMerger
    private let recipientHidingManager: RecipientHidingManager

    init(
        localIdentifiers: LocalIdentifiers,
        authedAccount: AuthedAccount,
        blockingManager: BlockingManager,
        bulkProfileFetch: BulkProfileFetch,
        contactsManager: OWSContactsManager,
        identityManager: OWSIdentityManager,
        profileManager: OWSProfileManager,
        tsAccountManager: TSAccountManager,
        usernameLookupManager: UsernameLookupManager,
        recipientMerger: RecipientMerger,
        recipientHidingManager: RecipientHidingManager
    ) {
        self.localIdentifiers = localIdentifiers
        self.authedAccount = authedAccount
        self.blockingManager = blockingManager
        self.bulkProfileFetch = bulkProfileFetch
        self.contactsManager = contactsManager
        self.identityManager = identityManager
        self.profileManager = profileManager
        self.tsAccountManager = tsAccountManager
        self.usernameLookupManager = usernameLookupManager
        self.recipientMerger = recipientMerger
        self.recipientHidingManager = recipientHidingManager
    }

    func unknownFields(for record: StorageServiceProtoContactRecord) -> UnknownStorage? { record.unknownFields }

    func buildRecord(
        for accountId: AccountId,
        unknownFields: UnknownStorage?,
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoContactRecord? {
        guard let recipient = SignalRecipient.anyFetch(uniqueId: accountId, transaction: transaction) else {
            return nil
        }

        guard let contact = StorageServiceContact(recipient), contact.shouldBeInStorageService(currentDate: Date()) else {
            return nil
        }

        let address = recipient.address

        if localIdentifiers.contains(address: address) {
            Logger.warn("Tried to create contact record from local account address")
            return nil
        }

        var builder = StorageServiceProtoContactRecord.builder()

        /// Helps determine if a username is the best identifier we have for
        /// this address.
        var usernameBetterIdentifierChecker = Usernames.BetterIdentifierChecker(forRecipient: recipient)

        builder.setServiceUuid(contact.serviceId.uuidValue.uuidString)

        if let serviceE164 = contact.serviceE164 {
            builder.setServiceE164(serviceE164.stringValue)
            usernameBetterIdentifierChecker.add(e164: serviceE164.stringValue)
        }

        if let unregisteredAtTimestamp = contact.unregisteredAtTimestamp {
            builder.setUnregisteredAtTimestamp(unregisteredAtTimestamp)
        }

        let isInWhitelist = profileManager.isUser(inProfileWhitelist: address, transaction: transaction)
        builder.setWhitelisted(isInWhitelist)

        builder.setBlocked(blockingManager.isAddressBlocked(address, transaction: transaction))

        // Identity

        if let identityKey = identityManager.identityKey(for: address, transaction: transaction) {
            builder.setIdentityKey(identityKey.prependKeyType())
        }

        let verificationState = identityManager.verificationState(for: address, transaction: transaction)
        builder.setIdentityState(.from(verificationState))

        // Profile

        let profileKey = profileManager.profileKeyData(for: address, transaction: transaction)
        let profileGivenName = profileManager.unfilteredGivenName(for: address, transaction: transaction)
        let profileFamilyName = profileManager.unfilteredFamilyName(for: address, transaction: transaction)

        if let profileKey = profileKey {
            builder.setProfileKey(profileKey)
        }

        if let profileGivenName = profileGivenName {
            builder.setGivenName(profileGivenName)
            usernameBetterIdentifierChecker.add(profileGivenName: profileGivenName)
        }

        if let profileFamilyName = profileFamilyName {
            builder.setFamilyName(profileFamilyName)
            usernameBetterIdentifierChecker.add(profileFamilyName: profileFamilyName)
        }

        if
            let account = contactsManager.fetchSignalAccount(for: address, transaction: transaction),
            let contact = account.contact
        {
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

            let isPrimaryAndHasLocalContact = tsAccountManager.isPrimaryDevice && contact.isFromLocalAddressBook
            let isLinkedAndHasSyncedContact = !tsAccountManager.isPrimaryDevice && !contact.isFromLocalAddressBook

            if isPrimaryAndHasLocalContact || isLinkedAndHasSyncedContact {
                if let systemGivenName = contact.firstName {
                    builder.setSystemGivenName(systemGivenName)
                    usernameBetterIdentifierChecker.add(systemContactGivenName: systemGivenName)
                }

                if let systemFamilyName = contact.lastName {
                    builder.setSystemFamilyName(systemFamilyName)
                    usernameBetterIdentifierChecker.add(systemContactFamilyName: systemFamilyName)
                }

                if let systemNickname = contact.nickname {
                    builder.setSystemNickname(systemNickname)
                    usernameBetterIdentifierChecker.add(systemContactNickname: systemNickname)
                }
            }
        }

        if let thread = TSContactThread.getWithContactAddress(address, transaction: transaction) {
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)

            builder.setArchived(threadAssociatedData.isArchived)
            builder.setMarkedUnread(threadAssociatedData.isMarkedUnread)
            builder.setMutedUntilTimestamp(threadAssociatedData.mutedUntilTimestamp)
        }

        if let storyContextAssociatedData = StoryFinder.getAssocatedData(forContactAdddress: address, transaction: transaction) {
            builder.setHideStory(storyContextAssociatedData.isHidden)
        }

        // Username

        if
            usernameBetterIdentifierChecker.usernameIsBestIdentifier(),
            let username = usernameLookupManager.fetchUsername(
                forAci: contact.serviceId,
                transaction: transaction.asV2Read
            )
        {
            // Only add a username to the ContactRecord if we have no other
            // identifiers to display.
            builder.setUsername(username)
        }

        // Unknown

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return builder.buildInfallibly()
    }

    func buildStorageItem(for record: StorageServiceProtoContactRecord) -> StorageService.StorageItem {
        return StorageService.StorageItem(identifier: .generate(type: .contact), contact: record)
    }

    func mergeRecord(
        _ record: StorageServiceProtoContactRecord,
        transaction: SDSAnyWriteTransaction
    ) -> StorageServiceMergeResult<AccountId> {
        let immutableAddress = SignalServiceAddress(
            uuid: UntypedServiceId(uuidString: record.serviceUuid)?.uuidValue,
            phoneNumber: E164(record.serviceE164)?.stringValue,
            ignoreCache: true
        )
        guard immutableAddress.isValid, let contact = StorageServiceContact(record) else {
            owsFailDebug("address unexpectedly missing for contact")
            return .invalid
        }
        if localIdentifiers.aci.untypedServiceId == contact.serviceId {
            owsFailDebug("Trying to merge contact with our own serviceId.")
            return .invalid
        }
        if let phoneNumber = contact.serviceE164, localIdentifiers.contains(phoneNumber: phoneNumber) {
            owsFailDebug("Trying to merge contact with our own phone number.")
            return .invalid
        }

        let recipient = recipientMerger.applyMergeFromLinkedDevice(
            localIdentifiers: localIdentifiers,
            serviceId: contact.serviceId,
            phoneNumber: contact.serviceE164,
            tx: transaction.asV2Write
        )
        if let unregisteredAtTimestamp = contact.unregisteredAtTimestamp {
            recipient.markAsUnregisteredAndSave(at: unregisteredAtTimestamp, source: .storageService, tx: transaction)
        } else {
            recipient.markAsRegisteredAndSave(source: .storageService, tx: transaction)
        }

        let address = recipient.address

        var needsUpdate = false

        // Gather some local contact state to do comparisons against.
        let localProfileKey = profileManager.profileKey(for: address, transaction: transaction)
        let localGivenName = profileManager.unfilteredGivenName(for: address, transaction: transaction)
        let localFamilyName = profileManager.unfilteredFamilyName(for: address, transaction: transaction)
        let localIdentityKey = identityManager.identityKey(for: address, transaction: transaction)
        let localIdentityState = identityManager.verificationState(for: address, transaction: transaction)
        let localIsBlocked = blockingManager.isAddressBlocked(address, transaction: transaction)
        let localIsWhitelisted = profileManager.isUser(inProfileWhitelist: address, transaction: transaction)

        // If our local profile key record differs from what's on the service, use the service's value.
        if let profileKey = record.profileKey, localProfileKey?.keyData != profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: address,
                userProfileWriter: .storageService,
                authedAccount: authedAccount,
                transaction: transaction
            )

        // If we have a local profile key for this user but the service doesn't mark it as needing update.
        } else if localProfileKey != nil && !record.hasProfileKey {
            needsUpdate = true
        }

        // Given name can never be cleared, so ignore all info
        // about the profile if there's no given name.
        if record.hasGivenName && (localGivenName != record.givenName || localFamilyName != record.familyName) {
            // If we already have a profile for this user, ignore
            // any content received via storage service. Instead,
            // we'll just kick off a fetch of that user's profile
            // to make sure everything is up-to-date.
            if localGivenName != nil {
                bulkProfileFetch.fetchProfile(address: address)
            } else {
                profileManager.setProfileGivenName(
                    record.givenName,
                    familyName: record.familyName,
                    for: address,
                    userProfileWriter: .storageService,
                    authedAccount: authedAccount,
                    transaction: transaction
                )
            }
        } else if localGivenName != nil && !record.hasGivenName || localFamilyName != nil && !record.hasFamilyName {
            needsUpdate = true
        }

        if mergeSystemContactNames(in: record, address: address, transaction: transaction) {
            needsUpdate = true
        }

        // If our local identity differs from the service, use the service's value.
        if let identityKeyWithType = record.identityKey, let identityState = record.identityState?.verificationState,
            let identityKey = try? identityKeyWithType.removeKeyType(),
            localIdentityKey != identityKey || localIdentityState != identityState {

            identityManager.setVerificationState(
                identityState,
                identityKey: identityKey,
                address: address,
                isUserInitiatedChange: false,
                transaction: transaction
            )

        // If we have a local identity for this user but the service doesn't mark it as needing update.
        } else if localIdentityKey != nil && !record.hasIdentityKey {
            needsUpdate = true
        }

        // If our local blocked state differs from the service state, use the service's value.
        if record.blocked != localIsBlocked {
            if record.blocked {
                blockingManager.addBlockedAddress(address, blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedAddress(address, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if record.whitelisted != localIsWhitelisted {
            if record.whitelisted {
                profileManager.addUser(
                    toProfileWhitelist: address,
                    userProfileWriter: .storageService,
                    transaction: transaction
                )
            } else {
                profileManager.removeUser(
                    fromProfileWhitelist: address,
                    userProfileWriter: .storageService,
                    transaction: transaction
                )
            }
        }

        let localThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
        let localThreadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: localThread, transaction: transaction)

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
            sourceContext: .contact(contactUuid: contact.serviceId.uuidValue),
            transaction: transaction
        )
        if record.hideStory != localStoryContextAssociatedData.isHidden {
            localStoryContextAssociatedData.update(updateStorageService: false, isHidden: record.hideStory, transaction: transaction)
        }

        let usernameIsBestIdentifierOnRecord: Bool = {
            var betterIdentifierChecker = Usernames.BetterIdentifierChecker(forRecipient: recipient)

            betterIdentifierChecker.add(e164: record.serviceE164)
            betterIdentifierChecker.add(profileGivenName: record.givenName)
            betterIdentifierChecker.add(profileFamilyName: record.familyName)
            betterIdentifierChecker.add(systemContactGivenName: record.systemGivenName)
            betterIdentifierChecker.add(systemContactFamilyName: record.systemFamilyName)
            betterIdentifierChecker.add(systemContactNickname: record.systemNickname)

            return betterIdentifierChecker.usernameIsBestIdentifier()
        }()

        usernameLookupManager.saveUsername(
            usernameIsBestIdentifierOnRecord ? record.username : nil,
            forAci: contact.serviceId,
            transaction: transaction.asV2Write
        )

        return .merged(needsUpdate: needsUpdate, recipient.accountId)
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
        address: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {

        let localAccount = contactsManager.fetchSignalAccount(for: address, transaction: transaction)

        if tsAccountManager.isPrimaryDevice {
            let localContact = localAccount?.contact?.isFromLocalAddressBook == true ? localAccount?.contact : nil
            let localSystemGivenName = localContact?.firstName?.nilIfEmpty
            let localSystemFamilyName = localContact?.lastName?.nilIfEmpty
            let localSystemNickname = localContact?.nickname?.nilIfEmpty
            // On the primary device, we should mark it as `needsUpdate` if it doesn't match the local state.
            return (
                localSystemGivenName != record.systemGivenName
                || localSystemFamilyName != record.systemFamilyName
                || localSystemNickname != record.systemNickname
            )
        }

        // Otherwise, we should update the state on linked devices to match.

        let newAccount: SignalAccount?

        let systemFullName = Contact.fullName(
            fromGivenName: record.systemGivenName,
            familyName: record.systemFamilyName,
            nickname: record.systemNickname
        )
        if let systemFullName {
            let newContact = Contact(
                address: address,
                phoneNumberLabel: CommonStrings.mainPhoneNumberLabel,
                givenName: record.systemGivenName,
                familyName: record.systemFamilyName,
                nickname: record.systemNickname,
                fullName: systemFullName
            )

            // TODO: we should find a way to fill in `multipleAccountLabelText`.
            // This is the string that helps disambiguate when multiple
            // `SignalAccount`s are associated with the same system contact.
            // For example, Alice may have a work and mobile number, both of
            // of which are registered with Signal. This text could be (work)
            // or (mobile), to help disambiguate - otherwise, both Signal
            // accounts will present as just "Alice".
            let multipleAccountLabelText = ""

            newAccount = SignalAccount(
                contact: newContact,
                contactAvatarHash: nil,
                multipleAccountLabelText: multipleAccountLabelText,
                recipientPhoneNumber: address.phoneNumber,
                recipientUUID: address.uuidString
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
                localAccount.anyRemove(transaction: transaction)
                didModifySignalAccount = true
            }
            if let newAccount {
                newAccount.anyInsert(transaction: transaction)
                didModifySignalAccount = true
            }
            if didModifySignalAccount {
                contactsManager.didUpdateSignalAccounts(transaction: transaction)
            }
        }

        // We should never set `needsUpdates` from a linked device for system
        // contact names. Linked devices should always update their local state to
        // match Storage Service.
        return false
    }
}

// MARK: -

extension StorageServiceProtoContactRecordIdentityState {
    static func from(_ state: OWSVerificationState) -> StorageServiceProtoContactRecordIdentityState {
        switch state {
        case .verified:
            return .verified
        case .default:
            return .default
        case .noLongerVerified:
            return .unverified
        }
    }

    var verificationState: OWSVerificationState {
        switch self {
        case .verified:
            return .verified
        case .default:
            return .default
        case .unverified:
            return .noLongerVerified
        case .UNRECOGNIZED:
            owsFailDebug("unrecognized verification state")
            return .default
        }
    }
}

// MARK: - Group V1 Record

class StorageServiceGroupV1RecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = Data
    typealias RecordType = StorageServiceProtoGroupV1Record

    private let blockingManager: BlockingManager
    private let profileManager: ProfileManagerProtocol

    init(
        blockingManager: BlockingManager,
        profileManager: ProfileManagerProtocol
    ) {
        self.blockingManager = blockingManager
        self.profileManager = profileManager
    }

    func unknownFields(for record: StorageServiceProtoGroupV1Record) -> UnknownStorage? { record.unknownFields }

    func buildStorageItem(for record: StorageServiceProtoGroupV1Record) -> StorageService.StorageItem {
        return StorageService.StorageItem(identifier: .generate(type: .groupv1), groupV1: record)
    }

    func buildRecord(
        for groupId: Data,
        unknownFields: UnknownStorage?,
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoGroupV1Record? {
        var builder = StorageServiceProtoGroupV1Record.builder(id: groupId)

        builder.setWhitelisted(profileManager.isGroupId(inProfileWhitelist: groupId, transaction: transaction))
        builder.setBlocked(blockingManager.isGroupIdBlocked(groupId, transaction: transaction))

        let threadId = TSGroupThread.threadId(forGroupId: groupId, transaction: transaction)
        let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: threadId,
                                                                       ignoreMissing: true,
                                                                       transaction: transaction)

        builder.setArchived(threadAssociatedData.isArchived)
        builder.setMarkedUnread(threadAssociatedData.isMarkedUnread)
        builder.setMutedUntilTimestamp(threadAssociatedData.mutedUntilTimestamp)

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return builder.buildInfallibly()
    }

    func mergeRecord(
        _ record: StorageServiceProtoGroupV1Record,
        transaction: SDSAnyWriteTransaction
    ) -> StorageServiceMergeResult<Data> {
        let id = record.id

        // We might be learning of a v1 group id for the first time that
        // corresponds to a v2 group without a v1-to-v2 group id mapping.
        TSGroupThread.ensureGroupIdMapping(forGroupId: id, transaction: transaction)

        // Gather some local contact state to do comparisons against.
        let localIsBlocked = blockingManager.isGroupIdBlocked(id, transaction: transaction)
        let localIsWhitelisted = profileManager.isGroupId(inProfileWhitelist: id, transaction: transaction)

        // If our local blocked state differs from the service state, use the service's value.
        if record.blocked != localIsBlocked {
            if record.blocked {
                blockingManager.addBlockedGroup(groupId: id, blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedGroup(groupId: id, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if record.whitelisted != localIsWhitelisted {
            if record.whitelisted {
                profileManager.addGroupId(toProfileWhitelist: id,
                                          userProfileWriter: .storageService,
                                          transaction: transaction)
            } else {
                profileManager.removeGroupId(fromProfileWhitelist: id,
                                             userProfileWriter: .storageService,
                                             transaction: transaction)
            }
        }

        let localThreadId = TSGroupThread.threadId(forGroupId: id, transaction: transaction)
        ThreadAssociatedData.create(for: localThreadId, warnIfPresent: false, transaction: transaction)
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

        return .merged(needsUpdate: false, id)
    }
}

// MARK: - Group V2 Record

class StorageServiceGroupV2RecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = Data
    typealias RecordType = StorageServiceProtoGroupV2Record

    private let authedAccount: AuthedAccount
    private let blockingManager: BlockingManager
    private let groupsV2: GroupsV2Swift
    private let profileManager: ProfileManagerProtocol

    init(
        authedAccount: AuthedAccount,
        blockingManager: BlockingManager,
        groupsV2: GroupsV2Swift,
        profileManager: ProfileManagerProtocol
    ) {
        self.authedAccount = authedAccount
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
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoGroupV2Record? {
        guard groupsV2.isValidGroupV2MasterKey(masterKeyData) else {
            owsFailDebug("Invalid master key.")
            return nil
        }

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKeyData)
        } catch {
            owsFailDebug("Invalid master key \(error).")
            return nil
        }

        let groupId = groupContextInfo.groupId

        var builder = StorageServiceProtoGroupV2Record.builder(masterKey: masterKeyData)

        builder.setWhitelisted(profileManager.isGroupId(inProfileWhitelist: groupId, transaction: transaction))
        builder.setBlocked(blockingManager.isGroupIdBlocked(groupId, transaction: transaction))

        let threadId = TSGroupThread.threadId(forGroupId: groupId, transaction: transaction)
        let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: threadId,
                                                                       ignoreMissing: true,
                                                                       transaction: transaction)

        builder.setArchived(threadAssociatedData.isArchived)
        builder.setMarkedUnread(threadAssociatedData.isMarkedUnread)
        builder.setMutedUntilTimestamp(threadAssociatedData.mutedUntilTimestamp)

        if let storyContextAssociatedData = StoryFinder.getAssociatedData(forContext: .group(groupId: groupId), transaction: transaction) {
            builder.setHideStory(storyContextAssociatedData.isHidden)
        }

        if let thread = TSGroupThread.anyFetchGroupThread(uniqueId: threadId, transaction: transaction) {
            builder.setStorySendMode(thread.storyViewMode.storageServiceMode)
        } else if let enqueuedRecord = groupsV2.groupRecordPendingStorageServiceRestore(
            masterKeyData: masterKeyData,
            transaction: transaction
        ) {
            // We have a record pending restoration from storage service,
            // preserve any of the data that we weren't able to restore
            // yet because the thread record doesn't exist.
            enqueuedRecord.storySendMode.map { builder.setStorySendMode($0) }
        }

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return builder.buildInfallibly()
    }

    func mergeRecord(
        _ record: StorageServiceProtoGroupV2Record,
        transaction: SDSAnyWriteTransaction
    ) -> StorageServiceMergeResult<Data> {
        let masterKey = record.masterKey

        guard groupsV2.isValidGroupV2MasterKey(masterKey) else {
            owsFailDebug("Invalid master key.")
            return .invalid
        }

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
        } catch {
            owsFailDebug("Invalid master key.")
            return .invalid
        }
        let groupId = groupContextInfo.groupId

        // We might be learning of a v1 group id for the first time that
        // corresponds to a v2 group without a v1-to-v2 group id mapping.
        TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)

        var needsUpdate = false

        if let localThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            let localStorySendMode = localThread.storyViewMode.storageServiceMode
            if let storySendMode = record.storySendMode {
                if localStorySendMode != storySendMode {
                    localThread.updateWithStoryViewMode(.init(storageServiceMode: storySendMode), transaction: transaction)
                }
            } else {
                needsUpdate = true
            }
        } else {
            groupsV2.restoreGroupFromStorageServiceIfNecessary(groupRecord: record, account: authedAccount, transaction: transaction)
        }

        // Gather some local contact state to do comparisons against.
        let localIsBlocked = blockingManager.isGroupIdBlocked(groupId, transaction: transaction)
        let localIsWhitelisted = profileManager.isGroupId(inProfileWhitelist: groupId, transaction: transaction)

        // If our local blocked state differs from the service state, use the service's value.
        if record.blocked != localIsBlocked {
            if record.blocked {
                blockingManager.addBlockedGroup(groupId: groupId, blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedGroup(groupId: groupId, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if record.whitelisted != localIsWhitelisted {
            if record.whitelisted {
                profileManager.addGroupId(toProfileWhitelist: groupId,
                                          userProfileWriter: .storageService,
                                          transaction: transaction)
            } else {
                profileManager.removeGroupId(fromProfileWhitelist: groupId,
                                             userProfileWriter: .storageService,
                                             transaction: transaction)
            }
        }

        let localThreadId = TSGroupThread.threadId(forGroupId: groupId, transaction: transaction)
        ThreadAssociatedData.create(for: localThreadId, warnIfPresent: false, transaction: transaction)
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
            sourceContext: .group(groupId: groupId),
            transaction: transaction
        )
        if record.hideStory != localStoryContextAssociatedData.isHidden {
            localStoryContextAssociatedData.update(updateStorageService: false, isHidden: record.hideStory, transaction: transaction)
        }

        return .merged(needsUpdate: needsUpdate, masterKey)
    }
}

// MARK: - Account Record

class StorageServiceAccountRecordUpdater: StorageServiceRecordUpdater {
    typealias IdType = Void
    typealias RecordType = StorageServiceProtoAccountRecord

    private let localIdentifiers: LocalIdentifiers
    private let authedAccount: AuthedAccount
    private let dmConfigurationStore: DisappearingMessagesConfigurationStore
    private let legacyChangePhoneNumber: LegacyChangePhoneNumber
    private let localUsernameManager: LocalUsernameManager
    private let paymentsHelper: PaymentsHelperSwift
    private let preferences: Preferences
    private let profileManager: OWSProfileManager
    private let receiptManager: OWSReceiptManager
    private let storageServiceManager: StorageServiceManager
    private let subscriptionManager: SubscriptionManager
    private let systemStoryManager: SystemStoryManagerProtocol
    private let tsAccountManager: TSAccountManager
    private let typingIndicators: TypingIndicators
    private let udManager: OWSUDManager
    private let usernameEducationManager: UsernameEducationManager

    init(
        localIdentifiers: LocalIdentifiers,
        authedAccount: AuthedAccount,
        dmConfigurationStore: DisappearingMessagesConfigurationStore,
        legacyChangePhoneNumber: LegacyChangePhoneNumber,
        localUsernameManager: LocalUsernameManager,
        paymentsHelper: PaymentsHelperSwift,
        preferences: Preferences,
        profileManager: OWSProfileManager,
        receiptManager: OWSReceiptManager,
        storageServiceManager: StorageServiceManager,
        subscriptionManager: SubscriptionManager,
        systemStoryManager: SystemStoryManagerProtocol,
        tsAccountManager: TSAccountManager,
        typingIndicators: TypingIndicators,
        udManager: OWSUDManager,
        usernameEducationManager: UsernameEducationManager
    ) {
        self.localIdentifiers = localIdentifiers
        self.authedAccount = authedAccount
        self.dmConfigurationStore = dmConfigurationStore
        self.legacyChangePhoneNumber = legacyChangePhoneNumber
        self.localUsernameManager = localUsernameManager
        self.paymentsHelper = paymentsHelper
        self.preferences = preferences
        self.profileManager = profileManager
        self.receiptManager = receiptManager
        self.storageServiceManager = storageServiceManager
        self.subscriptionManager = subscriptionManager
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
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoAccountRecord? {
        var builder = StorageServiceProtoAccountRecord.builder()

        let localAddress = localIdentifiers.aciAddress

        if let profileKey = profileManager.profileKeyData(for: localAddress, transaction: transaction) {
            builder.setProfileKey(profileKey)
        }

        let localUsernameState = localUsernameManager.usernameState(tx: transaction.asV2Read)
        if let username = localUsernameState.username {
            builder.setUsername(username)

            if let usernameLink = localUsernameState.usernameLink {
                var usernameLinkProtoBuilder = StorageServiceProtoAccountRecordUsernameLink.builder()

                usernameLinkProtoBuilder.setEntropy(usernameLink.entropy)
                usernameLinkProtoBuilder.setServerID(usernameLink.handle.data)
                usernameLinkProtoBuilder.setColor(
                    localUsernameManager.usernameLinkQRCodeColor(
                        tx: transaction.asV2Read
                    ).asProto
                )

                builder.setUsernameLink(usernameLinkProtoBuilder.buildInfallibly())
            }
        }

        if let profileGivenName = profileManager.unfilteredGivenName(for: localAddress, transaction: transaction) {
            builder.setGivenName(profileGivenName)
        }
        if let profileFamilyName = profileManager.unfilteredFamilyName(for: localAddress, transaction: transaction) {
            builder.setFamilyName(profileFamilyName)
        }

        if let profileAvatarUrlPath = profileManager.profileAvatarURLPath(
            for: localAddress,
            downloadIfMissing: true,
            authedAccount: authedAccount,
            transaction: transaction
        ) {
            Logger.info("profileAvatarUrlPath: yes")
            builder.setAvatarURL(profileAvatarUrlPath)
        } else {
            Logger.info("profileAvatarUrlPath: no")
        }

        if let thread = TSContactThread.getWithContactAddress(localAddress, transaction: transaction) {
            let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread, transaction: transaction)

            builder.setNoteToSelfArchived(threadAssociatedData.isArchived)
            builder.setNoteToSelfMarkedUnread(threadAssociatedData.isMarkedUnread)
        }

        let readReceiptsEnabled = receiptManager.areReadReceiptsEnabled(transaction: transaction)
        builder.setReadReceipts(readReceiptsEnabled)

        let storyViewReceiptsEnabled = StoryManager.areViewReceiptsEnabled(transaction: transaction)
        builder.setStoryViewReceiptsEnabled(.init(storyViewReceiptsEnabled))

        let sealedSenderIndicatorsEnabled = preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: transaction)
        builder.setSealedSenderIndicators(sealedSenderIndicatorsEnabled)

        let typingIndicatorsEnabled = typingIndicators.areTypingIndicatorsEnabled()
        builder.setTypingIndicators(typingIndicatorsEnabled)

        let proxiedLinkPreviewsEnabled = SSKPreferences.areLegacyLinkPreviewsEnabled(transaction: transaction)
        builder.setProxiedLinkPreviews(proxiedLinkPreviewsEnabled)

        let linkPreviewsEnabled = SSKPreferences.areLinkPreviewsEnabled(transaction: transaction)
        builder.setLinkPreviews(linkPreviewsEnabled)

        let phoneNumberSharingMode = udManager.phoneNumberSharingMode
        builder.setPhoneNumberSharingMode(phoneNumberSharingMode.asProtoMode)

        let notDiscoverableByPhoneNumber = !tsAccountManager.isDiscoverableByPhoneNumber(with: transaction)
        builder.setNotDiscoverableByPhoneNumber(notDiscoverableByPhoneNumber)

        let pinnedConversationProtos = PinnedThreadManager.pinnedConversationProtos(transaction: transaction)
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

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        let dmConfiguration = dmConfigurationStore.fetchOrBuildDefault(for: .universal, tx: transaction.asV2Read)
        builder.setUniversalExpireTimer(dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0)

        if profileManager.localProfileIsPniCapable() {
            // If we are PNI capable we should no longer use or rely on the
            // e164 from the AccountRecord since it doesn't store related PNI
            // material.
        } else {
            if let localE164 = E164(localAddress.phoneNumber?.strippedOrNil) {
                builder.setE164(localE164.stringValue)
            } else {
                owsFailDebug("Missing or invalid local E164!")
            }
        }

        if let customEmojiSet = ReactionManager.customEmojiSet(transaction: transaction) {
            builder.setPreferredReactionEmoji(customEmojiSet)
        }

        if let subscriberID = SubscriptionManagerImpl.getSubscriberID(transaction: transaction),
           let subscriberCurrencyCode = SubscriptionManagerImpl.getSubscriberCurrencyCode(transaction: transaction) {
            builder.setSubscriberID(subscriberID)
            builder.setSubscriberCurrencyCode(subscriberCurrencyCode)
        }

        builder.setMyStoryPrivacyHasBeenSet(StoryManager.hasSetMyStoriesPrivacy(transaction: transaction))

        builder.setReadOnboardingStory(systemStoryManager.isOnboardingStoryRead(transaction: transaction))
        builder.setViewedOnboardingStory(systemStoryManager.isOnboardingStoryViewed(transaction: transaction))

        builder.setDisplayBadgesOnProfile(subscriptionManager.displayBadgesOnProfile(transaction: transaction))
        builder.setSubscriptionManuallyCancelled(subscriptionManager.userManuallyCancelledSubscription(transaction: transaction))

        builder.setKeepMutedChatsArchived(SSKPreferences.shouldKeepMutedChatsArchived(transaction: transaction))

        builder.setStoriesDisabled(!StoryManager.areStoriesEnabled(transaction: transaction))

        builder.setCompletedUsernameOnboarding(
            !usernameEducationManager.shouldShowUsernameEducation(tx: transaction.asV2Read)
        )

        return builder.buildInfallibly()
    }

    func mergeRecord(
        _ record: StorageServiceProtoAccountRecord,
        transaction: SDSAnyWriteTransaction
    ) -> StorageServiceMergeResult<Void> {
        var needsUpdate = false

        let localAddress = localIdentifiers.aciAddress

        // Gather some local contact state to do comparisons against.
        let localProfileKey = profileManager.profileKey(for: localAddress, transaction: transaction)
        let localGivenName = profileManager.unfilteredGivenName(for: localAddress, transaction: transaction)
        let localFamilyName = profileManager.unfilteredFamilyName(for: localAddress, transaction: transaction)
        let localAvatarUrl = profileManager.profileAvatarURLPath(
            for: localAddress,
            downloadIfMissing: true,
            authedAccount: authedAccount,
            transaction: transaction
        )

        // On the primary device, we only ever want to
        // take the profile key from storage service if
        // we have no record of a local profile. This
        // allows us to restore your profile during onboarding,
        // but ensures no other device can ever change the profile
        // key other than the primary device.
        let allowsRemoteProfileKeyChanges = !profileManager.hasLocalProfile() || !tsAccountManager.isPrimaryDevice
        if allowsRemoteProfileKeyChanges, let profileKey = record.profileKey, localProfileKey?.keyData != profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: localAddress,
                userProfileWriter: .storageService,
                authedAccount: authedAccount,
                transaction: transaction
            )
        } else if localProfileKey != nil && !record.hasProfileKey {
            // If we have a local profile key for this user but the service doesn't, mark it as needing update.
            needsUpdate = true
        }

        // Given name can never be cleared, so ignore all info
        // about the profile if there's no given name.
        if record.hasGivenName && (localGivenName != record.givenName || localFamilyName != record.familyName || localAvatarUrl != record.avatarURL) {
            profileManager.setProfileGivenName(
                record.givenName,
                familyName: record.familyName,
                avatarUrlPath: record.avatarURL,
                for: localAddress,
                userProfileWriter: .storageService,
                authedAccount: authedAccount,
                transaction: transaction
            )
        } else if localGivenName != nil && !record.hasGivenName || localFamilyName != nil && !record.hasFamilyName || localAvatarUrl != nil && !record.hasAvatarURL {
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
                    entropy: remoteUsernameLinkProtoEntropy
                )
            {
                localUsernameManager.setLocalUsername(
                    username: remoteUsername,
                    usernameLink: remoteUsernameLink,
                    tx: transaction.asV2Write
                )

                if let remoteUsernameLinkColor = remoteUsernameLinkProto.color {
                    localUsernameManager.setUsernameLinkQRCodeColor(
                        color: Usernames.QRCodeColor(proto: remoteUsernameLinkColor),
                        tx: transaction.asV2Write
                    )
                }
            } else {
                localUsernameManager.setLocalUsernameWithCorruptedLink(
                    username: remoteUsername,
                    tx: transaction.asV2Write
                )
            }
        } else {
            localUsernameManager.clearLocalUsername(tx: transaction.asV2Write)
        }

        let localThread = TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
        let localThreadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: localThread, transaction: transaction)

        if record.noteToSelfArchived != localThreadAssociatedData.isArchived {
            localThreadAssociatedData.updateWith(isArchived: record.noteToSelfArchived, updateStorageService: false, transaction: transaction)
        }

        if record.noteToSelfMarkedUnread != localThreadAssociatedData.isMarkedUnread {
            localThreadAssociatedData.updateWith(isMarkedUnread: record.noteToSelfMarkedUnread, updateStorageService: false, transaction: transaction)
        }

        let localReadReceiptsEnabled = receiptManager.areReadReceiptsEnabled()
        if record.readReceipts != localReadReceiptsEnabled {
            receiptManager.setAreReadReceiptsEnabled(record.readReceipts, transaction: transaction)
        }

        let localViewReceiptsEnabled = StoryManager.areViewReceiptsEnabled(transaction: transaction)
        if let storyViewReceiptsEnabled = record.storyViewReceiptsEnabled?.boolValue {
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

        let linkPreviewsEnabled = SSKPreferences.areLinkPreviewsEnabled(transaction: transaction)
        if record.linkPreviews != linkPreviewsEnabled {
            SSKPreferences.setAreLinkPreviewsEnabled(record.linkPreviews, transaction: transaction)
        }

        let proxiedLinkPreviewsEnabled = SSKPreferences.areLegacyLinkPreviewsEnabled(transaction: transaction)
        if record.proxiedLinkPreviews != proxiedLinkPreviewsEnabled {
            SSKPreferences.setAreLegacyLinkPreviewsEnabled(record.proxiedLinkPreviews, transaction: transaction)
        }

        let localPhoneNumberSharingMode = udManager.phoneNumberSharingMode
        if record.phoneNumberSharingMode != localPhoneNumberSharingMode.asProtoMode {
            if let localMode = record.phoneNumberSharingMode?.asLocalMode {
                udManager.setPhoneNumberSharingMode(
                    localMode,
                    updateStorageService: false,
                    transaction: transaction.unwrapGrdbWrite
                )
            } else {
                Logger.error("Unknown phone number sharing mode \(String(describing: record.phoneNumberSharingMode))")
            }
        }

        let localNotDiscoverableByPhoneNumber = !tsAccountManager.isDiscoverableByPhoneNumber(with: transaction)
        if record.notDiscoverableByPhoneNumber != localNotDiscoverableByPhoneNumber || !tsAccountManager.hasDefinedIsDiscoverableByPhoneNumber(with: transaction) {
            tsAccountManager.setIsDiscoverableByPhoneNumber(
                !record.notDiscoverableByPhoneNumber,
                updateStorageService: false,
                authedAccount: authedAccount,
                transaction: transaction
            )
        }

        do {
            try PinnedThreadManager.processPinnedConversationsProto(record.pinnedConversations, transaction: transaction)
        } catch {
            owsFailDebug("Failed to process pinned conversations \(error)")
            needsUpdate = true
        }

        let localPrefersContactAvatars = SSKPreferences.preferContactAvatars(transaction: transaction)
        if record.preferContactAvatars != localPrefersContactAvatars {
            SSKPreferences.setPreferContactAvatars(
                record.preferContactAvatars,
                updateStorageService: false,
                transaction: transaction)
        }

        let localPaymentsState = paymentsHelper.paymentsState
        let servicePaymentsState = PaymentsState.build(
            arePaymentsEnabled: record.payments?.enabled ?? false,
            paymentsEntropy: record.payments?.paymentsEntropy
        )
        if localPaymentsState != servicePaymentsState {
            let mergedPaymentsState = PaymentsState.build(
                // Honor "arePaymentsEnabled" from the service.
                arePaymentsEnabled: servicePaymentsState.isEnabled,
                // Prefer paymentsEntropy from service, but try to retain local paymentsEntropy otherwise.
                paymentsEntropy: servicePaymentsState.paymentsEntropy ?? localPaymentsState.paymentsEntropy
            )
            paymentsHelper.setPaymentsState(
                mergedPaymentsState,
                originatedLocally: false,
                transaction: transaction
            )
        }

        let remoteExpireToken = DisappearingMessageToken.token(forProtoExpireTimer: record.universalExpireTimer)
        dmConfigurationStore.set(token: remoteExpireToken, for: .universal, tx: transaction.asV2Write)

        if !record.preferredReactionEmoji.isEmpty {
            // Treat new preferred emoji as a full source of truth (if not empty). Note
            // that we aren't doing any validation up front, which may be important if
            // another platform supports an emoji we don't (say, because a new version
            // of Unicode has come out). We deal with this when the custom set is read.
            ReactionManager.setCustomEmojiSet(record.preferredReactionEmoji, transaction: transaction)
        }

        if let subscriberIDData = record.subscriberID, let subscriberCurrencyCode = record.subscriberCurrencyCode {
            if subscriberIDData != SubscriptionManagerImpl.getSubscriberID(transaction: transaction) {
                SubscriptionManagerImpl.setSubscriberID(subscriberIDData, transaction: transaction)
            }

            if subscriberCurrencyCode != SubscriptionManagerImpl.getSubscriberCurrencyCode(transaction: transaction) {
                SubscriptionManagerImpl.setSubscriberCurrencyCode(subscriberCurrencyCode, transaction: transaction)
            }
        }

        let localDisplayBadgesOnProfile = subscriptionManager.displayBadgesOnProfile(transaction: transaction)
        if localDisplayBadgesOnProfile != record.displayBadgesOnProfile {
            subscriptionManager.setDisplayBadgesOnProfile(
                record.displayBadgesOnProfile,
                updateStorageService: false,
                transaction: transaction
            )
        }

        let localSubscriptionManuallyCancelled = subscriptionManager.userManuallyCancelledSubscription(transaction: transaction)
        if localSubscriptionManuallyCancelled != record.subscriptionManuallyCancelled {
            subscriptionManager.setUserManuallyCancelledSubscription(
                record.subscriptionManuallyCancelled,
                updateStorageService: false,
                transaction: transaction
            )
        }

        let localKeepMutedChatsArchived = SSKPreferences.shouldKeepMutedChatsArchived(transaction: transaction)
        if localKeepMutedChatsArchived != record.keepMutedChatsArchived {
            SSKPreferences.setShouldKeepMutedChatsArchived(record.keepMutedChatsArchived, transaction: transaction)
        }

        let localHasSetMyStoriesPrivacy = StoryManager.hasSetMyStoriesPrivacy(transaction: transaction)
        if !localHasSetMyStoriesPrivacy && record.myStoryPrivacyHasBeenSet {
            StoryManager.setHasSetMyStoriesPrivacy(transaction: transaction, shouldUpdateStorageService: false)
        }

        let localHasReadOnboardingStory = systemStoryManager.isOnboardingStoryRead(transaction: transaction)
        if !localHasReadOnboardingStory && record.readOnboardingStory {
            systemStoryManager.setHasReadOnboardingStory(transaction: transaction, updateStorageService: false)
        }

        let localHasViewedOnboardingStory = systemStoryManager.isOnboardingStoryViewed(transaction: transaction)
        if !localHasViewedOnboardingStory && record.viewedOnboardingStory {
            systemStoryManager.setHasViewedOnboardingStoryOnAnotherDevice(transaction: transaction)
        }

        if profileManager.localProfileIsPniCapable() {
            // If we are PNI capable we should no longer use or rely on the
            // e164 from the AccountRecord since it doesn't store related PNI
            // material.
        } else if let serviceLocalE164 = E164(record.e164?.strippedOrNil) {
            if localAddress.e164 != serviceLocalE164 {
                Logger.warn("localAddress.e164: \(String(describing: localAddress.e164)) != serviceLocalE164: \(serviceLocalE164)")

                if tsAccountManager.isPrimaryDevice(transaction: transaction) {
                    // It's not clear how we got into this scenario, but if we
                    // do it's bad. Once all clients are PNI-capable we can
                    // ignore the AccountRecord's e164 entirely, and remove
                    // this attempt to heal.
                    //
                    // PNI TODO: remove this logic after all clients are known PNI-capable.

                    transaction.addAsyncCompletionOffMain {
                        owsFailDebug("Attempting to heal from primary-device e164 mismatch with AccountRecord.")

                        // Consult "whoami" service endpoint; the service is the source of truth
                        // for the local phone number.  This ensures that the primary will always
                        // reflect the latest value.
                        self.legacyChangePhoneNumber.deprecated_updateLocalPhoneNumberOnAccountRecordMismatch()

                        // The primary should always reflect the latest value.
                        // If local db state doesn't agree with the storage service state,
                        // the primary needs to update the storage service.
                        self.storageServiceManager.recordPendingLocalAccountUpdates()
                    }
                } else if let localAci = tsAccountManager.localUuid(with: transaction) {
                    // If we're a linked device, we should always take the e164
                    // from StorageService.
                    tsAccountManager.updateLocalPhoneNumber(
                        E164ObjC(serviceLocalE164),
                        aci: localAci,
                        pni: tsAccountManager.localPni(with: transaction),
                        transaction: transaction
                    )
                } else {
                    owsFailDebug("Linked device missing local ACI!")
                }
            }
        } else {
            // If we don't have an e164 in StorageService yet, do so now.
            needsUpdate = true
        }

        let localStoriesDisabled = !StoryManager.areStoriesEnabled(transaction: transaction)
        if localStoriesDisabled != record.storiesDisabled {
            StoryManager.setAreStoriesEnabled(!record.storiesDisabled, shouldUpdateStorageService: false, transaction: transaction)
        }

        let hasCompletedUsernameOnboarding = !usernameEducationManager.shouldShowUsernameEducation(tx: transaction.asV2Read)
        if !hasCompletedUsernameOnboarding && record.completedUsernameOnboarding {
            usernameEducationManager.setShouldShowUsernameEducation(
                false,
                tx: transaction.asV2Write
            )
        }

        return .merged(needsUpdate: needsUpdate, ())
    }
}

// MARK: -

extension PhoneNumberSharingMode {
    var asProtoMode: StorageServiceProtoAccountRecordPhoneNumberSharingMode {
        switch self {
        case .everybody: return .everybody
        case .nobody: return .nobody
        }
    }
}

extension StorageServiceProtoAccountRecordPhoneNumberSharingMode {
    var asLocalMode: PhoneNumberSharingMode? {
        switch self {
        case .everybody: return .everybody
        case .contactsOnly: return nil
        case .nobody: return .nobody
        default:
            owsFailDebug("unexpected case \(self)")
            return nil
        }
    }
}

// MARK: -

extension PinnedThreadManager {
    public class func processPinnedConversationsProto(
        _ pinnedConversations: [StorageServiceProtoAccountRecordPinnedConversation],
        transaction: SDSAnyWriteTransaction
    ) throws {
        if pinnedConversations.count > maxPinnedThreads {
            Logger.warn("Received unexpected number of pinned threads (\(pinnedConversations.count))")
        }

        var pinnedThreadIds = [String]()
        for pinnedConversation in pinnedConversations {
            switch pinnedConversation.identifier {
            case .contact(let contact)?:
                let address = SignalServiceAddress(uuidString: contact.uuid, phoneNumber: contact.e164)
                guard address.isValid else {
                    owsFailDebug("Dropping pinned thread with invalid address \(address)")
                    continue
                }
                let thread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
                pinnedThreadIds.append(thread.uniqueId)
            case .groupMasterKey(let masterKey)?:
                let contextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKey)
                let threadUniqueId = TSGroupThread.threadId(forGroupId: contextInfo.groupId,
                                                            transaction: transaction)
                pinnedThreadIds.append(threadUniqueId)
            case .legacyGroupID(let groupId)?:
                let threadUniqueId = TSGroupThread.threadId(forGroupId: groupId,
                                                            transaction: transaction)
                pinnedThreadIds.append(threadUniqueId)
            default:
                break
            }
        }

        updatePinnedThreadIds(pinnedThreadIds, transaction: transaction)
    }

    public class func pinnedConversationProtos(
        transaction: SDSAnyReadTransaction
    ) -> [StorageServiceProtoAccountRecordPinnedConversation] {
        let pinnedThreads = PinnedThreadManager.pinnedThreads(transaction: transaction)

        var pinnedConversationProtos = [StorageServiceProtoAccountRecordPinnedConversation]()
        for pinnedThread in pinnedThreads {
            var pinnedConversationBuilder = StorageServiceProtoAccountRecordPinnedConversation.builder()

            if let groupThread = pinnedThread as? TSGroupThread {
                if let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 {
                    let masterKeyData: Data
                    do {
                        masterKeyData = try groupsV2.masterKeyData(forGroupModel: groupModelV2)
                    } catch {
                        owsFailDebug("Missing master key: \(error)")
                        continue
                    }
                    guard groupsV2.isValidGroupV2MasterKey(masterKeyData) else {
                        owsFailDebug("Invalid master key.")
                        continue
                    }

                    pinnedConversationBuilder.setIdentifier(.groupMasterKey(masterKeyData))
                } else {
                    pinnedConversationBuilder.setIdentifier(.legacyGroupID(groupThread.groupModel.groupId))
                }

            } else if let contactThread = pinnedThread as? TSContactThread {
                var contactBuilder = StorageServiceProtoAccountRecordPinnedConversationContact.builder()
                if let uuidString = contactThread.contactAddress.uuidString {
                    contactBuilder.setUuid(uuidString)
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

    private let threadRemover: ThreadRemover

    init(threadRemover: ThreadRemover) {
        self.threadRemover = threadRemover
    }

    func unknownFields(for record: StorageServiceProtoStoryDistributionListRecord) -> UnknownStorage? { record.unknownFields }

    func buildStorageItem(for record: StorageServiceProtoStoryDistributionListRecord) -> StorageService.StorageItem {
        return StorageService.StorageItem(identifier: .generate(type: .storyDistributionList), storyDistributionList: record)
    }

    func buildRecord(
        for distributionListIdentifier: Data,
        unknownFields: UnknownStorage?,
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoStoryDistributionListRecord? {
        guard let uniqueId = UUID(data: distributionListIdentifier)?.uuidString else {
            owsFailDebug("Invalid distributionListIdentifier.")
            return nil
        }

        var builder = StorageServiceProtoStoryDistributionListRecord.builder()
        builder.setIdentifier(distributionListIdentifier)

        if let deletedAtTimestamp = TSPrivateStoryThread.deletedAtTimestamp(
            forDistributionListIdentifier: distributionListIdentifier,
            transaction: transaction
        ) {
            builder.setDeletedAtTimestamp(deletedAtTimestamp)
        } else if let story = TSPrivateStoryThread.anyFetchPrivateStoryThread(
            uniqueId: uniqueId,
            transaction: transaction
        ) {
            builder.setName(story.name)
            builder.setRecipientUuids(story.addresses.compactMap { $0.uuidString })
            builder.setAllowsReplies(story.allowsReplies)
            builder.setIsBlockList(story.storyViewMode == .blockList)
        } else {
            return nil
        }

        // Unknown

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return builder.buildInfallibly()
    }

    func mergeRecord(
        _ record: StorageServiceProtoStoryDistributionListRecord,
        transaction: SDSAnyWriteTransaction
    ) -> StorageServiceMergeResult<Data> {
        guard let identifier = record.identifier, let uniqueId = UUID(data: identifier)?.uuidString else {
            owsFailDebug("identifier unexpectedly missing for distribution list")
            return .invalid
        }

        let existingStory = TSPrivateStoryThread.anyFetchPrivateStoryThread(
            uniqueId: uniqueId,
            transaction: transaction
        )

        // The story has been deleted on another device, record that
        // and ensure we don't try and put it back.
        guard record.deletedAtTimestamp == 0 else {
            if let existingStory {
                threadRemover.remove(existingStory, tx: transaction.asV2Write)
            }
            TSPrivateStoryThread.recordDeletedAtTimestamp(
                record.deletedAtTimestamp,
                forDistributionListIdentifier: identifier,
                transaction: transaction
            )
            return .merged(needsUpdate: false, identifier)
        }

        var needsUpdate = false

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

            let localStoryIsBlocklist = story.storyViewMode == .blockList
            let localStoryAddressUuidStrings = story.addresses.compactMap { $0.uuidString }
            if localStoryIsBlocklist != record.isBlockList || Set(localStoryAddressUuidStrings) != Set(record.recipientUuids) {
                story.updateWithStoryViewMode(
                    record.isBlockList ? .blockList : .explicit,
                    addresses: record.recipientUuids.map { SignalServiceAddress(uuidString: $0) },
                    updateStorageService: false,
                    transaction: transaction
                )
            }
        } else {
            guard let name = record.name else {
                owsFailDebug("new private story missing required name")
                return .invalid
            }
            let newStory = TSPrivateStoryThread(
                uniqueId: uniqueId,
                name: name,
                allowsReplies: record.allowsReplies,
                addresses: record.recipientUuids.map { SignalServiceAddress(uuidString: $0) },
                viewMode: record.isBlockList ? .blockList : .explicit
            )
            newStory.anyInsert(transaction: transaction)
        }

        return .merged(needsUpdate: needsUpdate, identifier)
    }
}

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

private extension Usernames.QRCodeColor {
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
