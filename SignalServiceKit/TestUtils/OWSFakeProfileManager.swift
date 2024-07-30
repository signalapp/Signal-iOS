//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

#if TESTABLE_BUILD

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

    public func downloadAndDecryptAvatar(avatarUrlPath: String, profileKey: OWSAES256Key) async throws -> URL {
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
        unsavedRotatedProfileKey: OWSAES256Key?,
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
        unsavedRotatedProfileKey: OWSAES256Key?,
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
        self.profileKeys[SignalServiceAddress(serviceId)] = OWSAES256Key(data: profileKeyData)!
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
