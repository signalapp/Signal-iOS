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
                    profileKey: .setTo(profileKey),
                    userProfileWriter: .localUser,
                    authedAccount: .implicit(),
                    transaction: SDSDB.shimOnlyBridge(tx),
                    completion: {
                        ProfileFetcherJob.fetchProfile(address: userProfile.internalAddress, authedAccount: .implicit())
                    }
                )
            }
        )
    }

    func willBreakAssociation(for recipient: SignalRecipient, mightReplaceNonnilPhoneNumber: Bool, tx: DBWriteTransaction) {
        mergeUserProfiles(for: recipient, tx: tx)
    }

    func didLearnAssociation(mergedRecipient: MergedRecipient, tx: DBWriteTransaction) {
        if mergedRecipient.isLocalRecipient {
            // The local recipient uses a constant key as its identifier in the
            // database. However, if you change your own number, you may claim a phone
            // number that was connected to some other account, and we want to
            // guarantee that that profile is deleted.
            fetchAndExpungeUserProfiles(for: mergedRecipient.newRecipient, tx: tx).forEach {
                userProfileStore.removeUserProfile($0, tx: tx)
            }
        } else {
            mergeUserProfiles(for: mergedRecipient.newRecipient, tx: tx)
        }
    }

    private func mergeUserProfiles(for recipient: SignalRecipient, tx: DBWriteTransaction) {
        let userProfiles = fetchAndExpungeUserProfiles(for: recipient, tx: tx)
        guard let userProfileToMergeInto = userProfiles.first else {
            return
        }
        let normalizedAddress = NormalizedDatabaseRecordAddress(
            aci: recipient.aci,
            phoneNumber: recipient.phoneNumber,
            pni: recipient.pni
        )
        // One of these might not be set, or one of them might have a non-canonical
        // representation (eg upper vs. lowercase ServiceId). Make sure both of
        // these are updated to reflect that latest normalized value.
        userProfileToMergeInto.serviceIdString = normalizedAddress?.serviceId?.serviceIdUppercaseString
        userProfileToMergeInto.phoneNumber = normalizedAddress?.phoneNumber
        userProfileStore.updateUserProfile(userProfileToMergeInto, tx: tx)

        for userProfileToMergeFrom in userProfiles.dropFirst() {
            if userProfileToMergeInto.profileKey == nil, let profileKey = userProfileToMergeFrom.profileKey {
                setProfileKeyShim(userProfileToMergeInto, profileKey, tx)
            }
            userProfileStore.removeUserProfile(userProfileToMergeFrom, tx: tx)
        }
    }

    private func fetchAndExpungeUserProfiles(for recipient: SignalRecipient, tx: DBWriteTransaction) -> [OWSUserProfile] {
        return UniqueRecipientObjectMerger.fetchAndExpunge(
            for: recipient,
            serviceIdField: \.serviceIdString,
            phoneNumberField: \.phoneNumber,
            uniqueIdField: \.uniqueId,
            fetchObjectsForServiceId: { userProfileStore.fetchUserProfiles(for: $0, tx: tx) },
            fetchObjectsForPhoneNumber: { userProfileStore.fetchUserProfiles(for: $0, tx: tx) },
            updateObject: { userProfileStore.updateUserProfile($0, tx: tx) }
        )
    }
}
