//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

#if TESTABLE_BUILD

class OWSFakeProfileManager {
    let badgeStore: BadgeStore = BadgeStore()
    var fakeUserProfiles: [SignalServiceAddress: OWSUserProfile]?
    var localProfile: OWSUserProfile?
    var localProfileKey: Aes256Key?

    private var recipientWhitelist: Set<SignalRecipient.RowId> = []
    private var groupIdWhitelist: Set<Data> = []
}

extension OWSFakeProfileManager: ProfileManagerProtocol {
    func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile? {
        return localProfile
    }

    func userProfile(for addressParam: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile? {
        owsPrecondition(!addressParam.isLocalAddress)
        return fakeUserProfiles![addressParam]
    }

    func addRecipientToProfileWhitelist(_ recipient: inout SignalRecipient, userProfileWriter: UserProfileWriter, tx: DBWriteTransaction) {
        recipient.status = .whitelisted
        recipientWhitelist.insert(recipient.id)
    }

    func removeRecipientFromProfileWhitelist(_ recipient: inout SignalRecipient, userProfileWriter: UserProfileWriter, tx: DBWriteTransaction) {
        recipient.status = .unspecified
        recipientWhitelist.remove(recipient.id)
    }

    func isRecipientInProfileWhitelist(_ recipient: SignalRecipient, tx: DBReadTransaction) -> Bool {
        return recipientWhitelist.contains(recipient.id)
    }

    func isGroupId(inProfileWhitelist groupId: Data, transaction: DBReadTransaction) -> Bool {
        return groupIdWhitelist.contains(groupId)
    }

    func addGroupId(toProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) {
        groupIdWhitelist.insert(groupId)
    }

    func removeGroupId(fromProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) {
        groupIdWhitelist.remove(groupId)
    }

    func setLocalProfileKey(_ key: Aes256Key, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) {
        localProfileKey = key
    }

    func rotateProfileKeyUponRecipientHide(withTx tx: DBWriteTransaction) {
    }

    func forceRotateLocalProfileKeyForGroupDeparture(with transaction: DBWriteTransaction) {
    }
}

extension OWSFakeProfileManager: ProfileManager {
    func warmCaches() {
    }

    func fetchLocalUsersProfile(authedAccount: AuthedAccount) async throws -> FetchedProfile {
        throw OWSGenericError("Not supported.")
    }

    func fetchUserProfiles(for addresses: [SignalServiceAddress], tx: DBReadTransaction) -> [OWSUserProfile?] {
        return addresses.map { fakeUserProfiles?[$0] }
    }

    func downloadAndDecryptLocalUserAvatarIfNeeded(authedAccount: AuthedAccount) async throws {
        throw OWSGenericError("Not supported.")
    }

    func downloadAndDecryptAvatar(avatarUrlPath: String, profileKey: ProfileKey) async throws -> URL {
        throw OWSGenericError("Not supported.")
    }

    func updateProfile(
        address: OWSUserProfile.InsertableAddress,
        decryptedProfile: DecryptedProfile?,
        avatarUrlPath: OptionalChange<String?>,
        avatarFileName: OptionalChange<String?>,
        profileBadges: [OWSUserProfileBadgeInfo],
        lastFetchDate: Date,
        userProfileWriter: UserProfileWriter,
        tx: DBWriteTransaction,
    ) {
    }

    func updateLocalProfile(
        profileGivenName: OptionalChange<OWSUserProfile.NameComponent>,
        profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>,
        profileBio: OptionalChange<String?>,
        profileBioEmoji: OptionalChange<String?>,
        profileAvatarData: OptionalAvatarChange<Data?>,
        visibleBadgeIds: OptionalChange<[String]>,
        unsavedRotatedProfileKey: Aes256Key?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction,
    ) -> Promise<Void> {
        return Promise(error: OWSGenericError("Not supported."))
    }

    func reuploadLocalProfile(
        unsavedRotatedProfileKey: Aes256Key?,
        mustReuploadAvatar: Bool,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction,
    ) -> Promise<Void> {
        return Promise(error: OWSGenericError("Not supported."))
    }

    func didSendOrReceiveMessage(
        serviceId: ServiceId,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
    }

    func setProfileKeyData(
        _ profileKeyData: Data,
        for serviceId: ServiceId,
        onlyFillInIfMissing: Bool,
        shouldFetchProfile: Bool,
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction,
    ) {
        let address = SignalServiceAddress(serviceId)
        let userProfile = self.fakeUserProfiles![address]!
        self.fakeUserProfiles![address] = OWSUserProfile(
            id: userProfile.id,
            uniqueId: userProfile.uniqueId,
            serviceIdString: userProfile.serviceIdString,
            phoneNumber: userProfile.phoneNumber,
            avatarFileName: userProfile.avatarFileName,
            avatarUrlPath: userProfile.avatarUrlPath,
            profileKey: Aes256Key(data: profileKeyData)!,
            givenName: userProfile.givenName,
            familyName: userProfile.familyName,
            bio: userProfile.bio,
            bioEmoji: userProfile.bioEmoji,
            badges: userProfile.badges,
            lastFetchDate: userProfile.lastFetchDate,
            lastMessagingDate: userProfile.lastMessagingDate,
            isPhoneNumberShared: userProfile.isPhoneNumberShared,
        )
    }

    func fillInProfileKeys(
        allProfileKeys: [Aci: Data],
        authoritativeProfileKeys: [Aci: Data],
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
    }

    func allWhitelistedAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] { [] }
    func allWhitelistedRegisteredAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] { [] }
}

#endif
