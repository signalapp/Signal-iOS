//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

#if TESTABLE_BUILD

extension OWSFakeProfileManager: ProfileManager {
    public func fullNames(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [String?] {
        if let fakeDisplayNames {
            return addresses.map { fakeDisplayNames[$0] }
        } else {
            return Array(repeating: "some fake profile name", count: addresses.count)
        }
    }

    public func fetchLocalUsersProfile(mainAppOnly: Bool, authedAccount: AuthedAccount) -> Promise<FetchedProfile> {
        return Promise(error: OWSGenericError("Not supported."))
    }

    public func updateLocalProfile(
        profileGivenName: String?,
        profileFamilyName: String?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarData: Data?,
        visibleBadgeIds: [String],
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
}

#endif
