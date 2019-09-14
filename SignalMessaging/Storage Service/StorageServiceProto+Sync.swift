//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

// Helpers for building and restoring contact records.

extension StorageServiceProtoContactRecord {

    // MARK: - Dependencies

    static var profileManager: OWSProfileManager {
        return .shared()
    }

    var profileManager: OWSProfileManager {
        return .shared()
    }

    static var blockingManager: OWSBlockingManager {
        return .shared()
    }

    var blockingManager: OWSBlockingManager {
        return .shared()
    }

    static var identityManager: OWSIdentityManager {
        return .shared()
    }

    var identityManager: OWSIdentityManager {
        return .shared()
    }

    static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    static func build(
        for accountId: AccountId,
        contactIdentifier: StorageService.ContactIdentifier,
        transaction: SDSAnyReadTransaction
    ) throws -> StorageServiceProtoContactRecord {
        guard let address = OWSAccountIdFinder().address(forAccountId: accountId, transaction: transaction) else {
            throw StorageService.StorageError.assertion
        }

        let builder = StorageServiceProtoContactRecord.builder(key: contactIdentifier.data)

        if let phoneNumber = address.phoneNumber {
            builder.setServiceE164(phoneNumber)
        }

        if let uuidString = address.uuidString {
            builder.setServiceUuid(uuidString)
        }

        var isInWhitelist: Bool = false
        var profileKey: Data?
        var profileName: String?
        var profileAvatarData: Data?
        databaseStorage.read { transaction in
            isInWhitelist = profileManager.isUser(inProfileWhitelist: address,
                                                transaction: transaction)
            profileKey = profileManager.profileKeyData(for: address,
                                                       transaction: transaction)
            profileName = profileManager.profileName(for: address,
                                                     transaction: transaction)
            profileAvatarData = profileManager.profileAvatarData(for: address,
                                                                 transaction: transaction)
        }

        builder.setBlocked(blockingManager.isAddressBlocked(address))
        builder.setWhitelisted(isInWhitelist)

        // Identity
        let identityBuilder = StorageServiceProtoContactRecordIdentity.builder()

        if let identityKey = identityManager.identityKey(for: address, transaction: transaction) {
            identityBuilder.setKey(identityKey)
        }

        let verificationState = identityManager.verificationState(for: address, transaction: transaction)
        identityBuilder.setState(.from(verificationState))

        builder.setIdentity(try identityBuilder.build())

        // Profile

        let profileBuilder = StorageServiceProtoContactRecordProfile.builder()

        if let profileKey = profileKey {
            profileBuilder.setKey(profileKey)
        }

        if let profileName = profileName {
            profileBuilder.setName(profileName)
        }

        if let profileAvatarData = profileAvatarData {
            profileBuilder.setAvatar(profileAvatarData)
        }

        builder.setProfile(try profileBuilder.build())

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

        // Mark the user as registered, only registered contacts should exist in the sync'd data.
        let recipient = SignalRecipient.mark(asRegisteredAndGet: address, transaction: transaction)

        var mergeState: MergeState = .resolved(recipient.accountId)

        // If we don't yet have a profile for this user, restore the profile information.
        // Otherwise, assume ours is the defacto version and mark this user as pending update.
        if let profile = profile, profileManager.profileKey(for: address, transaction: transaction) == nil {
            if let key = profile.key {
                profileManager.setProfileKeyData(key, for: address, transaction: transaction)
            }

            // TODO: Maybe restore the name and avatar? For now we'll refetch them once we set the key.
        } else {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // If we don't yet have an identity key for this user, restore the identity information.
        // Otherwise, assume ours is the defacto version and mark this user as pending update.
        if let identity = identity, identityManager.identityKey(for: address) == nil {
            if let state = identity.state?.verificationState, let key = identity.key {
                identityManager.setVerificationState(
                    state,
                    identityKey: key,
                    address: address,
                    isUserInitiatedChange: false,
                    transaction: transaction
                )
            }
        } else {
            mergeState = .needsUpdate(recipient.accountId)
        }

        // If our block state doesn't match the conflicted version, default to whichever
        // version is currently blocked. We don't want to unblock someone accidentally
        // through a conflict resolution.
        if hasBlocked, blocked != blockingManager.isAddressBlocked(address) {
            if blocked {
                blockingManager.addBlockedAddress(address)
            } else {
                mergeState = .needsUpdate(recipient.accountId)
            }
        }

        // If our whitelist state doesn't match the conflicted version, default to
        // being whitelisted. There's currently no way to unwhitelist a contact.
        if hasWhitelisted, whitelisted != profileManager.isUser(inProfileWhitelist: address, transaction: transaction) {
            if whitelisted {
                profileManager.addUser(toProfileWhitelist: address)
            } else {
                mergeState = .needsUpdate(recipient.accountId)
            }
        }

        return mergeState
    }
}

// MARK: -

extension StorageServiceProtoContactRecordIdentity.StorageServiceProtoContactRecordIdentityState {
    static func from(_ state: OWSVerificationState) -> StorageServiceProtoContactRecordIdentity.StorageServiceProtoContactRecordIdentityState {
        switch state {
        case .verified:
            return .verified
        case .default:
            return .default
        case .noLongerVerified:
            return .unverified
        @unknown default:
            owsFailDebug("unexpected verification state")
            return .default
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
        }
    }
}
