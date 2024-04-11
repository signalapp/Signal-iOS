//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

#if TESTABLE_BUILD

extension OWSFakeProfileManager: ProfileManager {
    public func fetchLocalUsersProfile(mainAppOnly: Bool, authedAccount: AuthedAccount) -> Promise<FetchedProfile> {
        return Promise(error: OWSGenericError("Not supported."))
    }

    public func fetchUserProfiles(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [OWSUserProfile?] {
        return addresses.map { fakeUserProfiles?[$0] }
    }

    public func updateProfile(
        address: SignalServiceAddress,
        decryptedProfile: DecryptedProfile?,
        avatarUrlPath: OptionalChange<String?>,
        avatarFileName: OptionalChange<String?>,
        profileBadges: [OWSUserProfileBadgeInfo],
        lastFetchDate: Date,
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    ) {
    }

    public func updateLocalProfile(
        profileGivenName: OptionalChange<OWSUserProfile.NameComponent>,
        profileFamilyName: OptionalChange<OWSUserProfile.NameComponent?>,
        profileBio: OptionalChange<String?>,
        profileBioEmoji: OptionalChange<String?>,
        profileAvatarData: OptionalChange<Data?>,
        visibleBadgeIds: OptionalChange<[String]>,
        unsavedRotatedProfileKey: OWSAES256Key?,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        tx: SDSAnyWriteTransaction
    ) -> Promise<Void> {
        return Promise(error: OWSGenericError("Not supported."))
    }

    public func reuploadLocalProfile(unsavedRotatedProfileKey: OWSAES256Key?, authedAccount: AuthedAccount, tx: DBWriteTransaction) -> Promise<Void> {
        return Promise(error: OWSGenericError("Not supported."))
    }

    public func downloadAndDecryptAvatar(avatarUrlPath: String, profileKey: OWSAES256Key) async throws -> URL {
        throw OWSGenericError("Not supported.")
    }

    public func didSendOrReceiveMessage(from address: SignalServiceAddress, localIdentifiers: LocalIdentifiers, transaction: SDSAnyWriteTransaction) {
    }

    public func setProfile(for address: SignalServiceAddress, givenName: OptionalChange<String?>, familyName: OptionalChange<String?>, avatarUrlPath: OptionalChange<String?>, userProfileWriter: UserProfileWriter, localIdentifiers: LocalIdentifiers, transaction: SDSAnyWriteTransaction) {
    }
}

#endif
