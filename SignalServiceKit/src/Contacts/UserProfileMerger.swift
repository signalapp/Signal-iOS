//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

class UserProfileMerger: RecipientMergeObserver {
    private let userProfileStore: UserProfileStore
    private let setProfileKeyShim: (OWSUserProfile, OWSAES256Key, DBWriteTransaction) -> Void

    init(
        userProfileStore: UserProfileStore,
        setProfileKeyShim: @escaping (OWSUserProfile, OWSAES256Key, DBWriteTransaction) -> Void
    ) {
        self.userProfileStore = userProfileStore
        self.setProfileKeyShim = setProfileKeyShim
    }

    convenience init(userProfileStore: UserProfileStore) {
        self.init(
            userProfileStore: userProfileStore,
            setProfileKeyShim: { userProfile, profileKey, tx in
                userProfile.update(
                    profileKey: profileKey,
                    userProfileWriter: .localUser,
                    authedAccount: .implicit(),
                    transaction: SDSDB.shimOnlyBridge(tx),
                    completion: {
                        NSObject.profileManager.fetchProfile(for: userProfile.address, authedAccount: .implicit())
                    }
                )
            }
        )
    }

    func willBreakAssociation(aci: Aci, phoneNumber: E164, transaction tx: DBWriteTransaction) {
        mergeUserProfiles(aci: aci, phoneNumber: phoneNumber, tx: tx)
    }

    func didLearnAssociation(mergedRecipient: MergedRecipient, transaction tx: DBWriteTransaction) {
        if mergedRecipient.isLocalRecipient {
            // The local recipient uses a constant key as its identifier in the
            // database. However, if you change your own number, you may claim a phone
            // number that was connected to some other account, and we want to
            // guarantee that that profile is deleted.
            fetchAndExpungeUserProfiles(
                aci: mergedRecipient.aci,
                phoneNumber: mergedRecipient.newPhoneNumber,
                tx: tx
            ).forEach {
                userProfileStore.removeUserProfile($0, tx: tx)
            }
        } else {
            mergeUserProfiles(aci: mergedRecipient.aci, phoneNumber: mergedRecipient.newPhoneNumber, tx: tx)
        }
    }

    private func mergeUserProfiles(aci: Aci, phoneNumber: E164, tx: DBWriteTransaction) {
        let userProfiles = fetchAndExpungeUserProfiles(aci: aci, phoneNumber: phoneNumber, tx: tx)
        guard let userProfileToMergeInto = userProfiles.first else {
            return
        }
        // One of these might not be set, or one of them might have a non-canonical
        // representation (eg uppercase UUID). Make sure both of these are updated
        // to reflect that latest (ACI, E164) pair for the account.
        userProfileToMergeInto.recipientUUID = aci.serviceIdUppercaseString
        userProfileToMergeInto.recipientPhoneNumber = phoneNumber.stringValue
        userProfileStore.updateUserProfile(userProfileToMergeInto, tx: tx)

        for userProfileToMergeFrom in userProfiles.dropFirst() {
            if userProfileToMergeInto.profileKey == nil, let profileKey = userProfileToMergeFrom.profileKey {
                setProfileKeyShim(userProfileToMergeInto, profileKey, tx)
            }
            userProfileStore.removeUserProfile(userProfileToMergeFrom, tx: tx)
        }
    }

    private func fetchAndExpungeUserProfiles(aci: Aci, phoneNumber: E164, tx: DBWriteTransaction) -> [OWSUserProfile] {
        var results = [OWSUserProfile]()

        // Find any profiles already associated with `serviceId`.
        results.append(contentsOf: userProfileStore.fetchUserProfiles(for: aci.untypedServiceId, tx: tx))

        // Find any profiles associated with `newPhoneNumber` that can be merged.
        for phoneNumberProfile in userProfileStore.fetchUserProfiles(for: phoneNumber, tx: tx) {
            switch phoneNumberProfile.recipientUUID {
            case aci.serviceIdUppercaseString:
                // This profile already matches `serviceId`, so it's already in userProfiles.
                break
            case .some:
                // This profile is associated with some other `serviceId`; expunge its
                // phone number because we've just learned that it's out of date.
                phoneNumberProfile.recipientPhoneNumber = nil
                userProfileStore.updateUserProfile(phoneNumberProfile, tx: tx)
            case .none:
                // This profile isn't associated with a `serviceId`, so we can claim it.
                results.append(phoneNumberProfile)
            }
        }

        return results
    }
}
