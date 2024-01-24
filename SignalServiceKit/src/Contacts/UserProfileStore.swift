//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

protocol UserProfileStore {
    func fetchUserProfiles(for serviceId: ServiceId, tx: DBReadTransaction) -> [OWSUserProfile]
    func fetchUserProfiles(for phoneNumber: E164, tx: DBReadTransaction) -> [OWSUserProfile]

    func updateUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction)
    func removeUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction)
}

class UserProfileStoreImpl: UserProfileStore {
    func fetchUserProfiles(for serviceId: ServiceId, tx: DBReadTransaction) -> [OWSUserProfile] {
        return UserProfileFinder().fetchUserProfiles(serviceId: serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }
    func fetchUserProfiles(for phoneNumber: E164, tx: DBReadTransaction) -> [OWSUserProfile] {
        return UserProfileFinder().fetchUserProfiles(phoneNumber: phoneNumber.stringValue, tx: SDSDB.shimOnlyBridge(tx))
    }

    func updateUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction) {
        userProfile.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    func removeUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction) {
        userProfile.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

class MockUserProfileStore: UserProfileStore {
    var userProfiles = [OWSUserProfile]()

    func fetchUserProfiles(for serviceId: ServiceId, tx: DBReadTransaction) -> [OWSUserProfile] {
        return userProfiles.filter { $0.serviceIdString == serviceId.serviceIdUppercaseString }.map { $0.shallowCopy() }
    }

    func fetchUserProfiles(for phoneNumber: E164, tx: DBReadTransaction) -> [OWSUserProfile] {
        return userProfiles.filter { $0.phoneNumber == phoneNumber.stringValue }.map { $0.shallowCopy() }
    }

    func updateUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction) {
        let index = userProfiles.firstIndex(where: { $0.uniqueId == userProfile.uniqueId })!
        userProfiles[index] = userProfile.copy() as! OWSUserProfile
    }

    func removeUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction) {
        userProfiles.removeAll(where: { $0.uniqueId == userProfile.uniqueId })
    }
}

#endif
