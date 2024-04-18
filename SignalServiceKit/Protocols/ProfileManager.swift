//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public enum OptionalChange<Wrapped: Equatable>: Equatable {
    case noChange
    case setTo(Wrapped)

    public func map<U>(_ transform: (Wrapped) -> U) -> OptionalChange<U> {
        switch self {
        case .noChange:
            return .noChange
        case .setTo(let value):
            return .setTo(transform(value))
        }
    }

    public func orExistingValue(_ existingValue: @autoclosure () -> Wrapped) -> Wrapped {
        switch self {
        case .setTo(let value):
            return value
        case .noChange:
            return existingValue()
        }
    }

    public func orElseIfNoChange(_ fallbackValue: @autoclosure () -> Self) -> Self {
        switch self {
        case .setTo:
            return self
        case .noChange:
            return fallbackValue()
        }
    }
}

public protocol ProfileManager: ProfileManagerProtocol {
    func fetchLocalUsersProfile(mainAppOnly: Bool, authedAccount: AuthedAccount) -> Promise<FetchedProfile>
    func fetchUserProfiles(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [OWSUserProfile?]

    func downloadAndDecryptLocalUserAvatarIfNeeded(authedAccount: AuthedAccount) async throws

    /// Downloads & decrypts the avatar at a particular URL.
    ///
    /// While this method de-dupes in-flight requests, it won't de-dupe requests
    /// once they've finished. If you download an avatar at a particular path,
    /// wait for it to finish, and then ask to download the same avatar again,
    /// this method will download it twice.
    func downloadAndDecryptAvatar(
        avatarUrlPath: String,
        profileKey: OWSAES256Key
    ) async throws -> URL

    func updateProfile(
        address: SignalServiceAddress,
        decryptedProfile: DecryptedProfile?,
        avatarUrlPath: OptionalChange<String?>,
        avatarFileName: OptionalChange<String?>,
        profileBadges: [OWSUserProfileBadgeInfo],
        lastFetchDate: Date,
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        tx: SDSAnyWriteTransaction
    )

    func updateLocalProfile(
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
    ) -> Promise<Void>

    func reuploadLocalProfile(
        unsavedRotatedProfileKey: OWSAES256Key?,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void>

    func didSendOrReceiveMessage(
        from address: SignalServiceAddress,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyWriteTransaction
    )

    func setProfile(
        for address: SignalServiceAddress,
        givenName: OptionalChange<String?>,
        familyName: OptionalChange<String?>,
        avatarUrlPath: OptionalChange<String?>,
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyWriteTransaction
    )

    func setProfileKeyDataAndFetchProfile(
        _ profileKeyData: Data,
        forAddress address: SignalServiceAddress,
        onlyFillInIfMissing: Bool,
        userProfileWriter: UserProfileWriter,
        authedAccount: AuthedAccount,
        transaction tx: SDSAnyWriteTransaction
    )

    func setProfileKeyData(
        _ profileKeyData: Data,
        for address: SignalServiceAddress,
        onlyFillInIfMissing: Bool,
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        transaction tx: SDSAnyWriteTransaction
    ) -> Bool
}
