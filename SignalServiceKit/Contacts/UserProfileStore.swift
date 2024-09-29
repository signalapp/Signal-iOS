//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public protocol UserProfileStore {
    func fetchUserProfile(for rowId: OWSUserProfile.RowId, tx: DBReadTransaction) -> OWSUserProfile?
    func fetchUserProfiles(for serviceId: ServiceId, tx: DBReadTransaction) -> [OWSUserProfile]
    func fetchUserProfiles(for phoneNumber: E164, tx: DBReadTransaction) -> [OWSUserProfile]

    func updateUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction)
    func removeUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction)
}

public class UserProfileStoreImpl: UserProfileStore {
    public init() {}

    public func fetchUserProfile(for rowId: OWSUserProfile.RowId, tx: DBReadTransaction) -> OWSUserProfile? {
        return SDSCodableModelDatabaseInterfaceImpl().fetchModel(modelType: OWSUserProfile.self, rowId: rowId, tx: tx)
    }

    public func fetchUserProfiles(for serviceId: ServiceId, tx: DBReadTransaction) -> [OWSUserProfile] {
        return UserProfileFinder().fetchUserProfiles(serviceId: serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchUserProfiles(for phoneNumber: E164, tx: DBReadTransaction) -> [OWSUserProfile] {
        return UserProfileFinder().fetchUserProfiles(phoneNumber: phoneNumber.stringValue, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func updateUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction) {
        userProfile.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func removeUserProfile(_ userProfile: OWSUserProfile, tx: DBWriteTransaction) {
        userProfile.anyRemove(transaction: SDSDB.shimOnlyBridge(tx))
    }
}

#if TESTABLE_BUILD

class MockUserProfileStore: UserProfileStore {
    var userProfiles = [OWSUserProfile]()

    func fetchUserProfile(for rowId: OWSUserProfile.RowId, tx: DBReadTransaction) -> OWSUserProfile? {
        return userProfiles.first(where: { $0.id == rowId })
    }

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
