//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

#if TESTABLE_BUILD

class OWSFakeProfileManager: NSObject {
    let badgeStore: BadgeStore = BadgeStore()
    var fakeUserProfiles: [SignalServiceAddress: OWSUserProfile]?
    var profileKeys: [SignalServiceAddress: Aes256Key] = [:]
    var stubbedStoriesCapabilityMap: [SignalServiceAddress: Bool] = [:]
    let localProfileKey: Aes256Key = Aes256Key()
    private(set) var localGivenName: String?
    private(set) var localFamilyName: String?
    private(set) var localFullName: String?
    private(set) var localProfileAvatarData: Data?
    private(set) var localProfileBadgeInfo: [OWSUserProfileBadgeInfo]?

    private var recipientWhitelist: Set<SignalServiceAddress> = []
    private var threadWhitelist: Set<String> = []

    override init() {
    }
}

extension OWSFakeProfileManager: ProfileManagerProtocol {
    func getUserProfile(for addressParam: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile? {
        nil
    }

    func fullName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String? {
        "some fake profile name"
    }

    func profileKeyData(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Data? {
        profileKeys[address]?.keyData
    }

    func profileKey(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Aes256Key? {
        profileKeys[address]
    }

    func normalizeRecipientInProfileWhitelist(_ recipient: SignalRecipient, tx: SDSAnyWriteTransaction) {
    }

    func isUser(inProfileWhitelist address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        recipientWhitelist.contains(address)
    }

    func isThread(inProfileWhitelist thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        threadWhitelist.contains(thread.uniqueId)
    }

    func addUser(toProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        recipientWhitelist.insert(address)
    }

    func addUsers(toProfileWhitelist addresses: [SignalServiceAddress], userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        recipientWhitelist.formUnion(addresses)
    }

    func removeUser(fromProfileWhitelist address: SignalServiceAddress) {
        recipientWhitelist.remove(address)
    }

    func removeUser(fromProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        recipientWhitelist.remove(address)
    }

    func isGroupId(inProfileWhitelist groupId: Data, transaction: SDSAnyReadTransaction) -> Bool {
        threadWhitelist.contains(groupId.hexadecimalString)
    }

    func addGroupId(toProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        threadWhitelist.insert(groupId.hexadecimalString)
    }

    func removeGroupId(fromProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        threadWhitelist.remove(groupId.hexadecimalString)
    }

    func addThread(toProfileWhitelist thread: TSThread, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction) {
        if thread.isGroupThread, let groupThread = thread as? TSGroupThread {
            addGroupId(toProfileWhitelist: groupThread.groupModel.groupId, userProfileWriter: userProfileWriter, transaction: transaction)
        } else if !thread.isGroupThread, let contactThread = thread as? TSContactThread {
            addUser(toProfileWhitelist: contactThread.contactAddress, userProfileWriter: userProfileWriter, transaction: transaction)
        }
    }

    func warmCaches() {
    }

    var hasLocalProfile: Bool {
        hasProfileName || localProfileAvatarData != nil
    }

    var hasProfileName: Bool {
        guard let localGivenName else {
            return false
        }
        return localGivenName.isEmpty
    }

    var localProfileAvatarImage: UIImage? {
        guard let localProfileAvatarData else {
            return nil
        }
        return UIImage(data: localProfileAvatarData)
    }

    func localProfileExists(with transaction: SDSAnyReadTransaction) -> Bool {
        hasLocalProfile
    }

    func localProfileWasUpdated(_ localUserProfile: OWSUserProfile) {
    }

    func hasProfileAvatarData(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        false
    }

    func profileAvatarData(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Data? {
        nil
    }

    func profileAvatarURLPath(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String? {
        nil
    }

    func rotateProfileKeyUponRecipientHide(withTx tx: SDSAnyWriteTransaction) {
    }

    func forceRotateLocalProfileKeyForGroupDeparture(with transaction: SDSAnyWriteTransaction) {
    }
}

extension OWSFakeProfileManager: ProfileManager {
    public func fetchLocalUsersProfile(authedAccount: AuthedAccount) -> Promise<FetchedProfile> {
        return Promise(error: OWSGenericError("Not supported."))
    }

    public func fetchUserProfiles(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [OWSUserProfile?] {
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
        tx: SDSAnyWriteTransaction
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
        tx: SDSAnyWriteTransaction
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
        self.profileKeys[SignalServiceAddress(serviceId)] = Aes256Key(data: profileKeyData)!
    }

    public func fillInProfileKeys(
        allProfileKeys: [Aci: Data],
        authoritativeProfileKeys: [Aci: Data],
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
    }

    public func allWhitelistedAddresses(tx: SDSAnyReadTransaction) -> [SignalServiceAddress] { [] }
    public func allWhitelistedRegisteredAddresses(tx: SDSAnyReadTransaction) -> [SignalServiceAddress] { [] }
}

#endif
