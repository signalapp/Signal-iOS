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

    private var recipientWhitelist: Set<SignalServiceAddress> = []
    private var threadWhitelist: Set<String> = []
}

extension OWSFakeProfileManager: ProfileManagerProtocol {
    func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile? {
        owsFail("Not implemented.")
    }

    func userProfile(for addressParam: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile? {
        owsPrecondition(!addressParam.isLocalAddress)
        return fakeUserProfiles![addressParam]
    }

    func normalizeRecipientInProfileWhitelist(_ recipient: SignalRecipient, tx: DBWriteTransaction) {
    }

    func isUser(inProfileWhitelist address: SignalServiceAddress, transaction: DBReadTransaction) -> Bool {
        recipientWhitelist.contains(address)
    }

    func isThread(inProfileWhitelist thread: TSThread, transaction: DBReadTransaction) -> Bool {
        threadWhitelist.contains(thread.uniqueId)
    }

    func addUser(toProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) {
        recipientWhitelist.insert(address)
    }

    func addUsers(toProfileWhitelist addresses: [SignalServiceAddress], userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) {
        recipientWhitelist.formUnion(addresses)
    }

    func removeUser(fromProfileWhitelist address: SignalServiceAddress) {
        recipientWhitelist.remove(address)
    }

    func removeUser(fromProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) {
        recipientWhitelist.remove(address)
    }

    func isGroupId(inProfileWhitelist groupId: Data, transaction: DBReadTransaction) -> Bool {
        threadWhitelist.contains(groupId.hexadecimalString)
    }

    func addGroupId(toProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) {
        threadWhitelist.insert(groupId.hexadecimalString)
    }

    func removeGroupId(fromProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) {
        threadWhitelist.remove(groupId.hexadecimalString)
    }

    func addThread(toProfileWhitelist thread: TSThread, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) {
        if thread.isGroupThread, let groupThread = thread as? TSGroupThread {
            addGroupId(toProfileWhitelist: groupThread.groupModel.groupId, userProfileWriter: userProfileWriter, transaction: transaction)
        } else if !thread.isGroupThread, let contactThread = thread as? TSContactThread {
            addUser(toProfileWhitelist: contactThread.contactAddress, userProfileWriter: userProfileWriter, transaction: transaction)
        }
    }

    func rotateProfileKeyUponRecipientHide(withTx tx: DBWriteTransaction) {
    }

    func forceRotateLocalProfileKeyForGroupDeparture(with transaction: DBWriteTransaction) {
    }
}

extension OWSFakeProfileManager: ProfileManager {
    func warmCaches() {
    }

    public func fetchLocalUsersProfile(authedAccount: AuthedAccount) async throws -> FetchedProfile {
        throw OWSGenericError("Not supported.")
    }

    public func fetchUserProfiles(for addresses: [SignalServiceAddress], tx: DBReadTransaction) -> [OWSUserProfile?] {
        return addresses.map { fakeUserProfiles?[$0] }
    }

    public func downloadAndDecryptLocalUserAvatarIfNeeded(authedAccount: AuthedAccount) async throws {
        throw OWSGenericError("Not supported.")
    }

    public func downloadAndDecryptAvatar(avatarUrlPath: String, profileKey: ProfileKey) async throws -> URL {
        throw OWSGenericError("Not supported.")
    }

    public func updateProfile(
        address: OWSUserProfile.InsertableAddress,
        decryptedProfile: DecryptedProfile?,
        avatarUrlPath: OptionalChange<String?>,
        avatarFileName: OptionalChange<String?>,
        profileBadges: [OWSUserProfileBadgeInfo],
        lastFetchDate: Date,
        userProfileWriter: UserProfileWriter,
        tx: DBWriteTransaction
    ) {
    }

    public func updateLocalProfile(
        profileGivenName: OptionalChange<OWSUserProfile.NameComponent>,
        profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>,
        profileBio: OptionalChange<String?>,
        profileBioEmoji: OptionalChange<String?>,
        profileAvatarData: OptionalAvatarChange<Data?>,
        visibleBadgeIds: OptionalChange<[String]>,
        unsavedRotatedProfileKey: Aes256Key?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        return Promise(error: OWSGenericError("Not supported."))
    }

    public func reuploadLocalProfile(authedAccount: AuthedAccount) {
        owsFailDebug("Not supported.")
    }

    public func reuploadLocalProfile(
        unsavedRotatedProfileKey: Aes256Key?,
        mustReuploadAvatar: Bool,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        return Promise(error: OWSGenericError("Not supported."))
    }

    public func didSendOrReceiveMessage(
        serviceId: ServiceId,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
    }

    public func setProfileKeyData(
        _ profileKeyData: Data,
        for serviceId: ServiceId,
        onlyFillInIfMissing: Bool,
        shouldFetchProfile: Bool,
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
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
            isPhoneNumberShared: userProfile.isPhoneNumberShared
        )
    }

    public func fillInProfileKeys(
        allProfileKeys: [Aci: Data],
        authoritativeProfileKeys: [Aci: Data],
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
    }

    public func allWhitelistedAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] { [] }
    public func allWhitelistedRegisteredAddresses(tx: DBReadTransaction) -> [SignalServiceAddress] { [] }
}

#endif
