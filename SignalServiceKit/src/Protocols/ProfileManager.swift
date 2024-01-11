//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public protocol ProfileManager: ProfileManagerProtocol {
    func fullNames(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [String?]
    func fetchLocalUsersProfile(mainAppOnly: Bool, authedAccount: AuthedAccount) -> Promise<FetchedProfile>

    func updateLocalProfile(
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
    ) -> Promise<Void>

    func reuploadLocalProfile(
        unsavedRotatedProfileKey: OWSAES256Key?,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void>
}
