//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SwiftProtobuf
import SignalServiceKit

// MARK: - Contact Record

extension StorageServiceProtoContactRecord: Dependencies {

    static func build(
        for accountId: AccountId,
        unknownFields: SwiftProtobuf.UnknownStorage? = nil,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoContactRecord {
        guard
            let address = OWSAccountIdFinder.address(forAccountId: accountId, transaction: transaction),
            let recipient = AnySignalRecipientFinder().signalRecipient(for: address, transaction: transaction)
        else {
            throw StorageService.StorageError.accountMissing
        }

        var builder = StorageServiceProtoContactRecord.builder()

        if !recipient.isRegistered, let unregisteredAtTimestamp = recipient.unregisteredAtTimestamp?.uint64Value {
            builder.setUnregisteredAtTimestamp(unregisteredAtTimestamp)
        }

        if let phoneNumber = address.phoneNumber {
            if PhoneNumber.resemblesE164(phoneNumber) {
                builder.setServiceE164(phoneNumber)
            } else {
                if DebugFlags.internalLogging {
                    Logger.warn("Invalid e164: \(phoneNumber).")
                }
                // TODO: Should we clean up the database?
                owsFailDebug("Invalid e164.")
            }
        }

        if let uuidString = address.uuidString {
            builder.setServiceUuid(uuidString)
        }

        let isInWhitelist = profileManager.isUser(inProfileWhitelist: address, transaction: transaction)
        let profileKey = profileManager.profileKeyData(for: address, transaction: transaction)
        let profileGivenName = profileManagerImpl.unfilteredGivenName(for: address, transaction: transaction)
        let profileFamilyName = profileManagerImpl.unfilteredFamilyName(for: address, transaction: transaction)

        builder.setBlocked(blockingManager.isAddressBlocked(address, transaction: transaction))
        builder.setWhitelisted(isInWhitelist)

        // Identity

        if let identityKey = identityManager.identityKey(for: address, transaction: transaction) {
            builder.setIdentityKey(identityKey.prependKeyType())
        }

        let verificationState = identityManager.verificationState(for: address, transaction: transaction)
        builder.setIdentityState(.from(verificationState))

        // Profile

        if let profileKey = profileKey {
            builder.setProfileKey(profileKey)
        }

        if let profileGivenName = profileGivenName {
            builder.setGivenName(profileGivenName)
        }

        if let profileFamilyName = profileFamilyName {
            builder.setFamilyName(profileFamilyName)
        }

        if
            let account = contactsManagerImpl.fetchSignalAccount(for: address, transaction: transaction),
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
                }

                if let systemFamilyName = contact.lastName {
                    builder.setSystemFamilyName(systemFamilyName)
                }

                if let systemNickname = contact.nickname {
                    builder.setSystemNickname(systemNickname)
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

        // Unknown

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return try builder.build()
    }

    enum MergeState {
        case resolved(AccountId)
        case needsUpdate(AccountId)
        case invalid
    }

    func mergeWithLocalContact(transaction: SDSAnyWriteTransaction) -> MergeState {
        guard let address = serviceAddress else {
            owsFailDebug("address unexpectedly missing for contact")
            return .invalid
        }
        // Our general merge philosophy is that the latest value on the service
        // is always right. There are some edge cases where this could cause
        // user changes to get blown away, such as if you're changing values
        // simultaneously on two devices or if you force quit the application,
        // your battery dies, etc. before it has had a chance to sync.
        //
        // In general, to try and mitigate these issues, we try and very proactively
        // push any changes up to the storage service as contact information
        // should not be changing very frequently.
        //
        // Should this prove unreliable, we may need to start maintaining time stamps
        // representing the remote and local last update time for every value we sync.
        // For now, we'd like to avoid that as it adds its own set of problems.

        let recipient = SignalRecipient.fetchOrCreate(for: address, trustLevel: .high, transaction: transaction)
        if unregisteredAtTimestamp > 0 {
            recipient.markAsUnregistered(at: unregisteredAtTimestamp, source: .storageService, transaction: transaction)
        } else {
            recipient.markAsRegistered(source: .storageService, transaction: transaction)
        }

        var mergeState: MergeState = .resolved(recipient.accountId)

        // Gather some local contact state to do comparisons against.
        let localProfileKey = profileManager.profileKey(for: address, transaction: transaction)
        let localGivenName = profileManagerImpl.unfilteredGivenName(for: address, transaction: transaction)
        let localFamilyName = profileManagerImpl.unfilteredFamilyName(for: address, transaction: transaction)
        let localIdentityKey = identityManager.identityKey(for: address, transaction: transaction)
        let localIdentityState = identityManager.verificationState(for: address, transaction: transaction)
        let localIsBlocked = blockingManager.isAddressBlocked(address, transaction: transaction)
        let localIsWhitelisted = profileManager.isUser(inProfileWhitelist: address, transaction: transaction)

        // If our local profile key record differs from what's on the service, use the service's value.
        if let profileKey = profileKey, localProfileKey?.keyData != profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: address,
                userProfileWriter: .storageService,
                transaction: transaction
            )

        // If we have a local profile key for this user but the service doesn't mark it as needing update.
        } else if localProfileKey != nil && !hasProfileKey {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // Given name can never be cleared, so ignore all info
        // about the profile if there's no given name.
        if hasGivenName && (localGivenName != givenName || localFamilyName != familyName) {
            // If we already have a profile for this user, ignore
            // any content received via storage service. Instead,
            // we'll just kick off a fetch of that user's profile
            // to make sure everything is up-to-date.
            if localGivenName != nil {
                Self.bulkProfileFetch.fetchProfile(address: address)
            } else {
                profileManager.setProfileGivenName(
                    givenName,
                    familyName: familyName,
                    for: address,
                    userProfileWriter: .storageService,
                    transaction: transaction
                )
            }
        } else if localGivenName != nil && !hasGivenName || localFamilyName != nil && !hasFamilyName {
            mergeState = .needsUpdate(recipient.accountId)
        }

        if mergeSystemNamesWithLocalContact(address: address, transaction: transaction) {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // If our local identity differs from the service, use the service's value.
        if let identityKeyWithType = identityKey, let identityState = identityState?.verificationState,
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
        } else if localIdentityKey != nil && !hasIdentityKey {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // If our local blocked state differs from the service state, use the service's value.
        if blocked != localIsBlocked {
            if blocked {
                blockingManager.addBlockedAddress(address, blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedAddress(address, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if whitelisted != localIsWhitelisted {
            if whitelisted {
                profileManager.addUser(toProfileWhitelist: address,
                                       userProfileWriter: .storageService,
                                       transaction: transaction)
            } else {
                profileManager.removeUser(fromProfileWhitelist: address,
                                          userProfileWriter: .storageService,
                                          transaction: transaction)
            }
        }

        let localThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
        let localThreadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: localThread, transaction: transaction)

        if archived != localThreadAssociatedData.isArchived {
            localThreadAssociatedData.updateWith(isArchived: archived, updateStorageService: false, transaction: transaction)
        }

        if markedUnread != localThreadAssociatedData.isMarkedUnread {
            localThreadAssociatedData.updateWith(isMarkedUnread: markedUnread, updateStorageService: false, transaction: transaction)
        }

        if mutedUntilTimestamp != localThreadAssociatedData.mutedUntilTimestamp {
            localThreadAssociatedData.updateWith(mutedUntilTimestamp: mutedUntilTimestamp, updateStorageService: false, transaction: transaction)
        }

        if let uuid = address.uuid {
            let localStoryContextAssociatedData = StoryContextAssociatedData.fetchOrDefault(
                sourceContext: .contact(contactUuid: uuid),
                transaction: transaction
            )
            if hideStory != localStoryContextAssociatedData.isHidden {
                localStoryContextAssociatedData.update(updateStorageService: false, isHidden: hideStory, transaction: transaction)
            }
        }

        return mergeState
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
    private func mergeSystemNamesWithLocalContact(
        address: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {

        let localAccount = contactsManagerImpl.fetchSignalAccount(for: address, transaction: transaction)

        if tsAccountManager.isPrimaryDevice {
            let localContact = localAccount?.contact?.isFromLocalAddressBook == true ? localAccount?.contact : nil
            let localSystemGivenName = localContact?.firstName?.nilIfEmpty
            let localSystemFamilyName = localContact?.lastName?.nilIfEmpty
            let localSystemNickname = localContact?.nickname?.nilIfEmpty
            // On the primary device, we should mark it as `needsUpdate` if it doesn't match the local state.
            return (
                localSystemGivenName != systemGivenName
                || localSystemFamilyName != systemFamilyName
                || localSystemNickname != systemNickname
            )
        }

        // Otherwise, we should update the state on linked devices to match.

        let newAccount: SignalAccount?

        let systemFullName = Contact.fullName(
            fromGivenName: systemGivenName,
            familyName: systemFamilyName,
            nickname: systemNickname
        )
        if let systemFullName {
            let newContact = Contact(
                address: address,
                phoneNumberLabel: CommonStrings.mainPhoneNumberLabel,
                givenName: systemGivenName,
                familyName: systemFamilyName,
                nickname: systemNickname,
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
        case (.some(let oldAccount), nil) where !FeatureFlags.contactDiscoveryV2 && oldAccount.contact?.isFromLocalAddressBook == true:
            // There's nothing in storage service, but we have a contact from the
            // address book on the local device. Don't make any changes.
            Logger.debug("No system contact found in contact record, keeping existing local address book contact!")

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
                contactsManagerImpl.didUpdateSignalAccounts(transaction: transaction)
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

extension StorageServiceProtoGroupV1Record: Dependencies {

    static func build(
        for groupId: Data,
        unknownFields: SwiftProtobuf.UnknownStorage? = nil,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoGroupV1Record {

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

        return try builder.build()
    }

    // Embeds the group id.
    enum MergeState {
        case resolved(Data)
        case needsUpdate(Data)
        case invalid
    }

    func mergeWithLocalGroup(transaction: SDSAnyWriteTransaction) -> MergeState {
        // We might be learning of a v1 group id for the first time that
        // corresponds to a v2 group without a v1-to-v2 group id mapping.
        TSGroupThread.ensureGroupIdMapping(forGroupId: id, transaction: transaction)

        // Our general merge philosophy is that the latest value on the service
        // is always right. There are some edge cases where this could cause
        // user changes to get blown away, such as if you're changing values
        // simultaneously on two devices or if you force quit the application,
        // your battery dies, etc. before it has had a chance to sync.
        //
        // In general, to try and mitigate these issues, we try and very proactively
        // push any changes up to the storage service as contact information
        // should not be changing very frequently.
        //
        // Should this prove unreliable, we may need to start maintaining time stamps
        // representing the remote and local last update time for every value we sync.
        // For now, we'd like to avoid that as it adds its own set of problems.

        // Gather some local contact state to do comparisons against.
        let localIsBlocked = blockingManager.isGroupIdBlocked(id, transaction: transaction)
        let localIsWhitelisted = profileManager.isGroupId(inProfileWhitelist: id, transaction: transaction)

        // If our local blocked state differs from the service state, use the service's value.
        if blocked != localIsBlocked {
            if blocked {
                blockingManager.addBlockedGroup(groupId: id, blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedGroup(groupId: id, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if whitelisted != localIsWhitelisted {
            if whitelisted {
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
        ThreadAssociatedData.createIfMissing(for: localThreadId, transaction: transaction)
        let localThreadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: localThreadId, transaction: transaction)

        if archived != localThreadAssociatedData.isArchived {
            localThreadAssociatedData.updateWith(isArchived: archived, updateStorageService: false, transaction: transaction)
        }

        if markedUnread != localThreadAssociatedData.isMarkedUnread {
            localThreadAssociatedData.updateWith(isMarkedUnread: markedUnread, updateStorageService: false, transaction: transaction)
        }

        if mutedUntilTimestamp != localThreadAssociatedData.mutedUntilTimestamp {
            localThreadAssociatedData.updateWith(mutedUntilTimestamp: mutedUntilTimestamp, updateStorageService: false, transaction: transaction)
        }

        return .resolved(id)
    }
}

// MARK: - Group V2 Record

extension StorageServiceProtoGroupV2Record: Dependencies {

    static func build(
        for masterKeyData: Data,
        unknownFields: SwiftProtobuf.UnknownStorage? = nil,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoGroupV2Record {

        guard groupsV2.isValidGroupV2MasterKey(masterKeyData) else {
            throw OWSAssertionError("Invalid master key.")
        }

        let groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKeyData)
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
        } else if let enqueuedRecord = groupsV2Swift.groupRecordPendingStorageServiceRestore(
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

        return try builder.build()
    }

    // Embeds the master key.
    enum MergeState: CustomStringConvertible {
        case resolved(Data)
        case needsUpdate(Data)
        case needsRefreshFromService(Data)
        case invalid

        // MARK: - CustomStringConvertible

        public var description: String {
            switch self {
            case .resolved:
                return "resolved"
            case .needsUpdate:
                return "needsUpdate"
            case .needsRefreshFromService:
                return "needsRefreshFromService"
            case .invalid:
                return "invalid"
            }
        }
    }

    func mergeWithLocalGroup(transaction: SDSAnyWriteTransaction) -> MergeState {
        // Our general merge philosophy is that the latest value on the service
        // is always right. There are some edge cases where this could cause
        // user changes to get blown away, such as if you're changing values
        // simultaneously on two devices or if you force quit the application,
        // your battery dies, etc. before it has had a chance to sync.
        //
        // In general, to try and mitigate these issues, we try and very proactively
        // push any changes up to the storage service as contact information
        // should not be changing very frequently.
        //
        // Should this prove unreliable, we may need to start maintaining time stamps
        // representing the remote and local last update time for every value we sync.
        // For now, we'd like to avoid that as it adds its own set of problems.

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

        var mergeState: MergeState = .resolved(masterKey)

        if let localThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            let localStorySendMode = localThread.storyViewMode.storageServiceMode
            if let storySendMode = storySendMode {
                if localStorySendMode != storySendMode {
                    localThread.updateWithStoryViewMode(.init(storageServiceMode: storySendMode), transaction: transaction)
                }
            } else {
                mergeState = .needsUpdate(masterKey)
            }
        } else {
            mergeState = .needsRefreshFromService(masterKey)
        }

        // Gather some local contact state to do comparisons against.
        let localIsBlocked = blockingManager.isGroupIdBlocked(groupId, transaction: transaction)
        let localIsWhitelisted = profileManager.isGroupId(inProfileWhitelist: groupId, transaction: transaction)

        // If our local blocked state differs from the service state, use the service's value.
        if blocked != localIsBlocked {
            if blocked {
                blockingManager.addBlockedGroup(groupId: groupId, blockMode: .remote, transaction: transaction)
            } else {
                blockingManager.removeBlockedGroup(groupId: groupId, wasLocallyInitiated: false, transaction: transaction)
            }
        }

        // If our local whitelisted state differs from the service state, use the service's value.
        if whitelisted != localIsWhitelisted {
            if whitelisted {
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
        ThreadAssociatedData.createIfMissing(for: localThreadId, transaction: transaction)
        let localThreadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: localThreadId,
                                                                            transaction: transaction)

        if archived != localThreadAssociatedData.isArchived {
            localThreadAssociatedData.updateWith(isArchived: archived, updateStorageService: false, transaction: transaction)
        }

        if markedUnread != localThreadAssociatedData.isMarkedUnread {
            localThreadAssociatedData.updateWith(isMarkedUnread: markedUnread, updateStorageService: false, transaction: transaction)
        }

        if mutedUntilTimestamp != localThreadAssociatedData.mutedUntilTimestamp {
            localThreadAssociatedData.updateWith(mutedUntilTimestamp: mutedUntilTimestamp, updateStorageService: false, transaction: transaction)
        }

        let localStoryContextAssociatedData = StoryContextAssociatedData.fetchOrDefault(
            sourceContext: .group(groupId: groupId),
            transaction: transaction
        )
        if hideStory != localStoryContextAssociatedData.isHidden {
            localStoryContextAssociatedData.update(updateStorageService: false, isHidden: hideStory, transaction: transaction)
        }

        return mergeState
    }
}

// MARK: - Account Record

extension StorageServiceProtoAccountRecord: Dependencies {

    static func build(
        unknownFields: SwiftProtobuf.UnknownStorage? = nil,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoAccountRecord {
        guard let localAddress = TSAccountManager.localAddress else {
            throw OWSAssertionError("Missing local address")
        }

        var builder = StorageServiceProtoAccountRecord.builder()

        if let profileKey = profileManager.profileKeyData(for: localAddress, transaction: transaction) {
            builder.setProfileKey(profileKey)
        }

        if let profileGivenName = profileManagerImpl.unfilteredGivenName(for: localAddress, transaction: transaction) {
            builder.setGivenName(profileGivenName)
        }
        if let profileFamilyName = profileManagerImpl.unfilteredFamilyName(for: localAddress, transaction: transaction) {
            builder.setFamilyName(profileFamilyName)
        }

        if let profileAvatarUrlPath = profileManager.profileAvatarURLPath(for: localAddress, downloadIfMissing: true, transaction: transaction) {
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

        let readReceiptsEnabled = receiptManager.areReadReceiptsEnabled()
        builder.setReadReceipts(readReceiptsEnabled)

        let storyViewReceiptsEnabled = StoryManager.areViewReceiptsEnabled(transaction: transaction)
        builder.setStoryViewReceiptsEnabled(.init(storyViewReceiptsEnabled))

        let sealedSenderIndicatorsEnabled = preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: transaction)
        builder.setSealedSenderIndicators(sealedSenderIndicatorsEnabled)

        let typingIndicatorsEnabled = typingIndicatorsImpl.areTypingIndicatorsEnabled()
        builder.setTypingIndicators(typingIndicatorsEnabled)

        let proxiedLinkPreviewsEnabled = SSKPreferences.areLegacyLinkPreviewsEnabled(transaction: transaction)
        builder.setProxiedLinkPreviews(proxiedLinkPreviewsEnabled)

        let linkPreviewsEnabled = SSKPreferences.areLinkPreviewsEnabled(transaction: transaction)
        builder.setLinkPreviews(linkPreviewsEnabled)

        let phoneNumberSharingMode = udManager.phoneNumberSharingMode
        builder.setPhoneNumberSharingMode(phoneNumberSharingMode.asProtoMode)

        let notDiscoverableByPhoneNumber = !tsAccountManager.isDiscoverableByPhoneNumber()
        builder.setNotDiscoverableByPhoneNumber(notDiscoverableByPhoneNumber)

        let pinnedConversationProtos = try PinnedThreadManager.pinnedConversationProtos(transaction: transaction)
        builder.setPinnedConversations(pinnedConversationProtos)

        let preferContactAvatars = SSKPreferences.preferContactAvatars(transaction: transaction)
        builder.setPreferContactAvatars(preferContactAvatars)

        let paymentsState = paymentsHelperSwift.paymentsState
        var paymentsBuilder = StorageServiceProtoAccountRecordPayments.builder()
        paymentsBuilder.setEnabled(paymentsState.isEnabled)
        if let paymentsEntropy = paymentsState.paymentsEntropy {
            paymentsBuilder.setPaymentsEntropy(paymentsEntropy)
        }
        builder.setPayments(try paymentsBuilder.build())

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        let dmConfiguration = OWSDisappearingMessagesConfiguration
            .fetchOrBuildDefaultUniversalConfiguration(with: transaction)
        builder.setUniversalExpireTimer(dmConfiguration.isEnabled ? dmConfiguration.durationSeconds : 0)

        if let localPhoneNumber = localAddress.phoneNumber?.strippedOrNil,
           PhoneNumber.resemblesE164(localPhoneNumber) {
            builder.setE164(localPhoneNumber)
        }

        if let customEmojiSet = ReactionManager.customEmojiSet(transaction: transaction) {
            builder.setPreferredReactionEmoji(customEmojiSet)
        }

        if let subscriberID = SubscriptionManager.getSubscriberID(transaction: transaction),
           let subscriberCurrencyCode = SubscriptionManager.getSubscriberCurrencyCode(transaction: transaction) {
            builder.setSubscriberID(subscriberID)
            builder.setSubscriberCurrencyCode(subscriberCurrencyCode)
        }

        builder.setMyStoryPrivacyHasBeenSet(StoryManager.hasSetMyStoriesPrivacy(transaction: transaction))

        builder.setReadOnboardingStory(Self.systemStoryManager.isOnboardingStoryRead(transaction: transaction))
        builder.setViewedOnboardingStory(Self.systemStoryManager.isOnboardingStoryViewed(transaction: transaction))

        builder.setDisplayBadgesOnProfile(subscriptionManager.displayBadgesOnProfile(transaction: transaction))
        builder.setSubscriptionManuallyCancelled(subscriptionManager.userManuallyCancelledSubscription(transaction: transaction))

        builder.setKeepMutedChatsArchived(SSKPreferences.shouldKeepMutedChatsArchived(transaction: transaction))

        builder.setStoriesDisabled(!StoryManager.areStoriesEnabled(transaction: transaction))

        return try builder.build()
    }

    enum MergeState: String {
        case resolved
        case needsUpdate
    }

    func mergeWithLocalAccount(transaction: SDSAnyWriteTransaction) -> MergeState {
        var mergeState: MergeState = .resolved

        guard let localAddress = TSAccountManager.localAddress else {
            owsFailDebug("missing local address")
            return .needsUpdate
        }

        // Gather some local contact state to do comparisons against.
        let localProfileKey = profileManager.profileKey(for: localAddress, transaction: transaction)
        let localGivenName = profileManagerImpl.unfilteredGivenName(for: localAddress, transaction: transaction)
        let localFamilyName = profileManagerImpl.unfilteredFamilyName(for: localAddress, transaction: transaction)
        let localAvatarUrl = profileManager.profileAvatarURLPath(for: localAddress, downloadIfMissing: true, transaction: transaction)

        // On the primary device, we only ever want to
        // take the profile key from storage service if
        // we have no record of a local profile. This
        // allows us to restore your profile during onboarding,
        // but ensures no other device can ever change the profile
        // key other than the primary device.
        let allowsRemoteProfileKeyChanges = !profileManager.hasLocalProfile() || !tsAccountManager.isPrimaryDevice

        if allowsRemoteProfileKeyChanges,
           let profileKey = profileKey,
           localProfileKey?.keyData != profileKey {
            profileManager.setProfileKeyData(
                profileKey,
                for: localAddress,
                userProfileWriter: .storageService,
                transaction: transaction
            )
        } else if localProfileKey != nil && !hasProfileKey {
            // If we have a local profile key for this user but the service doesn't mark it as needing update.
            mergeState = .needsUpdate
        }

        // Given name can never be cleared, so ignore all info
        // about the profile if there's no given name.
        if hasGivenName && (localGivenName != givenName || localFamilyName != familyName || localAvatarUrl != avatarURL) {
            profileManager.setProfileGivenName(
                givenName,
                familyName: familyName,
                avatarUrlPath: avatarURL,
                for: localAddress,
                userProfileWriter: .storageService,
                transaction: transaction
            )
        } else if localGivenName != nil && !hasGivenName || localFamilyName != nil && !hasFamilyName || localAvatarUrl != nil && !hasAvatarURL {
            mergeState = .needsUpdate
        }

        let localThread = TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
        let localThreadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: localThread, transaction: transaction)

        if noteToSelfArchived != localThreadAssociatedData.isArchived {
            localThreadAssociatedData.updateWith(isArchived: noteToSelfArchived, updateStorageService: false, transaction: transaction)
        }

        if noteToSelfMarkedUnread != localThreadAssociatedData.isMarkedUnread {
            localThreadAssociatedData.updateWith(isMarkedUnread: noteToSelfMarkedUnread, updateStorageService: false, transaction: transaction)
        }

        let localReadReceiptsEnabled = receiptManager.areReadReceiptsEnabled()
        if readReceipts != localReadReceiptsEnabled {
            receiptManager.setAreReadReceiptsEnabled(readReceipts, transaction: transaction)
        }

        let localViewReceiptsEnabled = StoryManager.areViewReceiptsEnabled(transaction: transaction)
        if let storyViewReceiptsEnabled = storyViewReceiptsEnabled?.boolValue {
            if storyViewReceiptsEnabled != localViewReceiptsEnabled {
                StoryManager.setAreViewReceiptsEnabled(storyViewReceiptsEnabled, shouldUpdateStorageService: false, transaction: transaction)
            }
        } else {
            mergeState = .needsUpdate
        }

        let sealedSenderIndicatorsEnabled = preferences.shouldShowUnidentifiedDeliveryIndicators(transaction: transaction)
        if sealedSenderIndicators != sealedSenderIndicatorsEnabled {
            preferences.setShouldShowUnidentifiedDeliveryIndicators(sealedSenderIndicators, transaction: transaction)
        }

        let typingIndicatorsEnabled = typingIndicatorsImpl.areTypingIndicatorsEnabled()
        if typingIndicators != typingIndicatorsEnabled {
            typingIndicatorsImpl.setTypingIndicatorsEnabled(value: typingIndicators, transaction: transaction)
        }

        let linkPreviewsEnabled = SSKPreferences.areLinkPreviewsEnabled(transaction: transaction)
        if linkPreviews != linkPreviewsEnabled {
            SSKPreferences.setAreLinkPreviewsEnabled(linkPreviews, transaction: transaction)
        }

        let proxiedLinkPreviewsEnabled = SSKPreferences.areLegacyLinkPreviewsEnabled(transaction: transaction)
        if proxiedLinkPreviews != proxiedLinkPreviewsEnabled {
            SSKPreferences.setAreLegacyLinkPreviewsEnabled(proxiedLinkPreviews, transaction: transaction)
        }

        let localPhoneNumberSharingMode = udManager.phoneNumberSharingMode
        if phoneNumberSharingMode != localPhoneNumberSharingMode.asProtoMode {
            if let localMode = phoneNumberSharingMode?.asLocalMode {
                udManager.setPhoneNumberSharingMode(
                    localMode,
                    updateStorageService: false,
                    transaction: transaction.unwrapGrdbWrite
                )
            } else {
                Logger.error("Unknown phone number sharing mode \(String(describing: phoneNumberSharingMode))")
            }
        }

        let localNotDiscoverableByPhoneNumber = !tsAccountManager.isDiscoverableByPhoneNumber()
        if notDiscoverableByPhoneNumber != localNotDiscoverableByPhoneNumber
            || !tsAccountManager.hasDefinedIsDiscoverableByPhoneNumber() {
            tsAccountManager.setIsDiscoverableByPhoneNumber(
                !notDiscoverableByPhoneNumber,
                updateStorageService: false,
                transaction: transaction
            )
        }

        do {
            try PinnedThreadManager.processPinnedConversationsProto(pinnedConversations, transaction: transaction)
        } catch {
            owsFailDebug("Failed to process pinned conversations \(error)")
            mergeState = .needsUpdate
        }

        let localPrefersContactAvatars = SSKPreferences.preferContactAvatars(transaction: transaction)
        if preferContactAvatars != localPrefersContactAvatars {
            SSKPreferences.setPreferContactAvatars(
                preferContactAvatars,
                updateStorageService: false,
                transaction: transaction)
        }

        let localPaymentsState = Self.paymentsHelperSwift.paymentsState
        let servicePaymentsState = PaymentsState.build(arePaymentsEnabled: self.payments?.enabled ?? false,
                                                       paymentsEntropy: self.payments?.paymentsEntropy)
        if localPaymentsState != servicePaymentsState {
            // Merge with payments states.
            //
            // 1. Honor "arePaymentsEnabled" from the service.
            let arePaymentsEnabled = servicePaymentsState.isEnabled
            // 2. Prefer paymentsEntropy from service, but try to retain local
            //    paymentsEntropy otherwise.
            let paymentsEntropy = servicePaymentsState.paymentsEntropy ?? localPaymentsState.paymentsEntropy
            let mergedPaymentsState = PaymentsState.build(arePaymentsEnabled: arePaymentsEnabled,
                                                          paymentsEntropy: paymentsEntropy)

            Self.paymentsHelperSwift.setPaymentsState(mergedPaymentsState,
                                                      originatedLocally: false,
                                                      transaction: transaction)
        }

        let localConfiguration = OWSDisappearingMessagesConfiguration.fetchOrBuildDefaultUniversalConfiguration(with: transaction)
        let localExpireToken = localConfiguration.asToken
        let remoteExpireToken = DisappearingMessageToken.token(forProtoExpireTimer: universalExpireTimer)
        if localExpireToken != remoteExpireToken {
            localConfiguration.applyToken(remoteExpireToken, transaction: transaction)
        }

        if !preferredReactionEmoji.isEmpty {
            // Treat new preferred emoji as a full source of truth (if not empty).
            // Note that we aren't doing any validation up front, which may be important if another platform supports
            // an emoji we don't (say, because a new version of Unicode has come out). We deal with this when the custom
            // set is read out.
            ReactionManager.setCustomEmojiSet(preferredReactionEmoji, transaction: transaction)
        }

        if let subscriberIDData = subscriberID, let subscriberCurrencyCode = subscriberCurrencyCode {
            if subscriberIDData != SubscriptionManager.getSubscriberID(transaction: transaction) {
                SubscriptionManager.setSubscriberID(subscriberIDData, transaction: transaction)
            }

            if subscriberCurrencyCode != SubscriptionManager.getSubscriberCurrencyCode(transaction: transaction) {
                SubscriptionManager.setSubscriberCurrencyCode(subscriberCurrencyCode, transaction: transaction)
            }
        }

        let localDisplayBadgesOnProfile = subscriptionManager.displayBadgesOnProfile(transaction: transaction)
        if localDisplayBadgesOnProfile != displayBadgesOnProfile {
            subscriptionManager.setDisplayBadgesOnProfile(
                displayBadgesOnProfile,
                updateStorageService: false,
                transaction: transaction
            )
        }

        let localSubscriptionManuallyCancelled = subscriptionManager.userManuallyCancelledSubscription(transaction: transaction)
        if localSubscriptionManuallyCancelled != subscriptionManuallyCancelled {
            subscriptionManager.setUserManuallyCancelledSubscription(
                subscriptionManuallyCancelled,
                updateStorageService: false,
                transaction: transaction
            )
        }

        let localKeepMutedChatsArchived = SSKPreferences.shouldKeepMutedChatsArchived(transaction: transaction)
        if localKeepMutedChatsArchived != keepMutedChatsArchived {
            SSKPreferences.setShouldKeepMutedChatsArchived(keepMutedChatsArchived, transaction: transaction)
        }

        let localHasSetMyStoriesPrivacy = StoryManager.hasSetMyStoriesPrivacy(transaction: transaction)
        if !localHasSetMyStoriesPrivacy && myStoryPrivacyHasBeenSet {
            StoryManager.setHasSetMyStoriesPrivacy(transaction: transaction, shouldUpdateStorageService: false)
        }

        let localHasReadOnboardingStory = systemStoryManager.isOnboardingStoryRead(transaction: transaction)
        if !localHasReadOnboardingStory && readOnboardingStory {
            systemStoryManager.setHasReadOnboardingStory(transaction: transaction, updateStorageService: false)
        }

        let localHasViewedOnboardingStory = systemStoryManager.isOnboardingStoryViewed(transaction: transaction)
        if !localHasViewedOnboardingStory && viewedOnboardingStory {
            systemStoryManager.setHasViewedOnboardingStoryOnAnotherDevice(transaction: transaction)
        }

        if let serviceLocalE164 = self.e164?.strippedOrNil,
           PhoneNumber.resemblesE164(serviceLocalE164) {
            // If the local phone number doesn't match the "local phone number" in the storage service...
            if localAddress.phoneNumber != serviceLocalE164 {
                Logger.warn("localAddress.phoneNumber: \(String(describing: localAddress.phoneNumber)) != serviceLocalE164: \(serviceLocalE164)")
                if tsAccountManager.isPrimaryDevice {
                    transaction.addAsyncCompletionOffMain {
                        // Consult "whoami" service endpoint; the service is the source of truth
                        // for the local phone number.  This ensures that the primary will always
                        // reflect the latest value.
                        ChangePhoneNumber.updateLocalPhoneNumber()

                        // The primary should always reflect the latest value.
                        // If local db state doesn't agree with the storage service state,
                        // the primary needs to update the storage service.
                        Self.storageServiceManager.recordPendingLocalAccountUpdates()
                    }
                } else {
                    // Linked devices should always take changes from the storage service.
                    if let uuid = localAddress.uuid {
                        tsAccountManager.updateLocalPhoneNumber(serviceLocalE164,
                                                                aci: uuid,
                                                                pni: tsAccountManager.localPni,
                                                                shouldUpdateStorageService: false,
                                                                transaction: transaction)
                    } else {
                        owsFailDebug("Missing uuid.")
                    }
                }
            }
        } else {
            // If no "local phone number" has been written to the storage service yet, do so now.
            mergeState = .needsUpdate
        }

        let localStoriesDisabled = !StoryManager.areStoriesEnabled(transaction: transaction)
        if localStoriesDisabled != storiesDisabled {
            StoryManager.setAreStoriesEnabled(!storiesDisabled, shouldUpdateStorageService: false, transaction: transaction)
        }

        return mergeState
    }
}

// MARK: -

extension PhoneNumberSharingMode {
    var asProtoMode: StorageServiceProtoAccountRecordPhoneNumberSharingMode {
        switch self {
        case .everybody: return .everybody
        case .contactsOnly: return .contactsOnly
        case .nobody: return .nobody
        }
    }
}

extension StorageServiceProtoAccountRecordPhoneNumberSharingMode {
    var asLocalMode: PhoneNumberSharingMode? {
        switch self {
        case .everybody: return .everybody
        case .contactsOnly: return .contactsOnly
        case .nobody: return .nobody
        default:
            owsFailDebug("unexpected case \(self)")
            return nil
        }
    }
}

// MARK: -

extension Data {
    func prependKeyType() -> Data {
        return (self as NSData).prependKeyType() as Data
    }

    func removeKeyType() throws -> Data {
        return try (self as NSData).removeKeyType() as Data
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
    ) throws -> [StorageServiceProtoAccountRecordPinnedConversation] {
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
                pinnedConversationBuilder.setIdentifier(.contact(try contactBuilder.build()))
            }

            pinnedConversationProtos.append(try pinnedConversationBuilder.build())
        }

        return pinnedConversationProtos
    }
}

// MARK: - Story Distribution List Record

extension StorageServiceProtoStoryDistributionListRecord: Dependencies {

    static func build(
        for distributionListIdentifier: Data,
        unknownFields: SwiftProtobuf.UnknownStorage? = nil,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoStoryDistributionListRecord {
        guard let uniqueId = UUID(data: distributionListIdentifier)?.uuidString else {
            throw StorageService.StorageError.assertion
        }

        var builder = StorageServiceProtoStoryDistributionListRecord.builder()
        builder.setIdentifier(distributionListIdentifier)

        if let deletedAtTimestamp = TSPrivateStoryThread.deletedAtTimestamp(
            forDistributionListIdentifer: distributionListIdentifier,
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
            throw StorageService.StorageError.storyMissing
        }

        // Unknown

        if let unknownFields = unknownFields {
            builder.setUnknownFields(unknownFields)
        }

        return try builder.build()
    }

    enum MergeState {
        case resolved(Data)
        case needsUpdate(Data)
        case invalid
    }

    func mergeWithLocalDistributionList(transaction: SDSAnyWriteTransaction) -> MergeState {
        guard let identifier = identifier, let uniqueId = UUID(data: identifier)?.uuidString else {
            owsFailDebug("identifier unexpectedly missing for distribution list")
            return .invalid
        }

        // Our general merge philosophy is that the latest value on the service
        // is always right. There are some edge cases where this could cause
        // user changes to get blown away, such as if you're changing values
        // simultaneously on two devices or if you force quit the application,
        // your battery dies, etc. before it has had a chance to sync.
        //
        // In general, to try and mitigate these issues, we try and very proactively
        // push any changes up to the storage service as contact information
        // should not be changing very frequently.
        //
        // Should this prove unreliable, we may need to start maintaining time stamps
        // representing the remote and local last update time for every value we sync.
        // For now, we'd like to avoid that as it adds its own set of problems.

        let existingStory = TSPrivateStoryThread.anyFetchPrivateStoryThread(
            uniqueId: uniqueId,
            transaction: transaction
        )

        var mergeState: MergeState = .resolved(identifier)

        // The story has been deleted on another device, record that
        // and ensure we don't try and put it back.
        guard deletedAtTimestamp == 0 else {
            existingStory?.anyRemove(transaction: transaction)
            TSPrivateStoryThread.recordDeletedAtTimestamp(
                deletedAtTimestamp,
                forDistributionListIdentifer: identifier,
                transaction: transaction
            )
            return mergeState
        }

        if let story = existingStory {
            // My Story has a hardcoded, localized name that we don't sync
            if !story.isMyStory {
                let localName = story.name
                if let name = name, localName != name {
                    story.updateWithName(name, updateStorageService: false, transaction: transaction)
                } else if !hasName {
                    mergeState = .needsUpdate(identifier)
                }
            }

            let localAllowsReplies = story.allowsReplies
            if allowsReplies != localAllowsReplies {
                story.updateWithAllowsReplies(allowsReplies, updateStorageService: false, transaction: transaction)
            }

            let localStoryIsBlocklist = story.storyViewMode == .blockList
            let localStoryAddressUuidStrings = story.addresses.compactMap { $0.uuidString }

            if localStoryIsBlocklist != isBlockList || Set(recipientUuids) != Set(localStoryAddressUuidStrings) {
                story.updateWithStoryViewMode(
                    isBlockList ? .blockList : .explicit,
                    addresses: recipientUuids.map { SignalServiceAddress(uuidString: $0) },
                    updateStorageService: false,
                    transaction: transaction
                )
            }
        } else {
            guard let name = name else {
                owsFailDebug("new private story missing required name")
                return .invalid
            }

            let newStory = TSPrivateStoryThread(
                uniqueId: uniqueId,
                name: name,
                allowsReplies: allowsReplies,
                addresses: recipientUuids.map { SignalServiceAddress(uuidString: $0) },
                viewMode: isBlockList ? .blockList : .explicit
            )
            newStory.anyInsert(transaction: transaction)
        }

        return mergeState
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
