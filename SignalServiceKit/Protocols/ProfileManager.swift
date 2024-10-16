//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

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

public enum OptionalAvatarChange<Wrapped: Equatable>: Equatable {
    /// There's no change to the avatar. The existing one is fine.
    case noChange

    /// There's no user-provided change to the avatar, but the avatar needs to
    /// be re-uploaded anyways (perhaps we're rotating the profile key or
    /// perhaps we detected an inconsistency).
    case noChangeButMustReupload

    /// There's a change to the avatar.
    case setTo(Wrapped)

    public func map<U>(_ transform: (Wrapped) -> U) -> OptionalAvatarChange<U> {
        switch self {
        case .noChange:
            return .noChange
        case .noChangeButMustReupload:
            return .noChangeButMustReupload
        case .setTo(let value):
            return .setTo(transform(value))
        }
    }

    private var importanceLevel: Int {
        switch self {
        case .noChange:
            return 0
        case .noChangeButMustReupload:
            return 1
        case .setTo:
            return 2
        }
    }

    public func isLessImportantThan(_ otherValue: OptionalAvatarChange<Wrapped>) -> Bool {
        return self.importanceLevel < otherValue.importanceLevel
    }
}

public protocol ProfileManager: ProfileManagerProtocol {

    // MARK: -

    func fetchLocalUsersProfile(authedAccount: AuthedAccount) -> Promise<FetchedProfile>
    func fetchUserProfiles(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [OWSUserProfile?]

    func reuploadLocalProfile(authedAccount: AuthedAccount)

    func reuploadLocalProfile(
        unsavedRotatedProfileKey: Aes256Key?,
        mustReuploadAvatar: Bool,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    ) -> Promise<Void>

    func downloadAndDecryptLocalUserAvatarIfNeeded(authedAccount: AuthedAccount) async throws

    // MARK: -

    /// Downloads & decrypts the avatar at a particular URL.
    ///
    /// While this method de-dupes in-flight requests, it won't de-dupe requests
    /// once they've finished. If you download an avatar at a particular path,
    /// wait for it to finish, and then ask to download the same avatar again,
    /// this method will download it twice.
    func downloadAndDecryptAvatar(
        avatarUrlPath: String,
        profileKey: ProfileKey
    ) async throws -> URL

    func updateProfile(
        address: OWSUserProfile.InsertableAddress,
        decryptedProfile: DecryptedProfile?,
        avatarUrlPath: OptionalChange<String?>,
        avatarFileName: OptionalChange<String?>,
        profileBadges: [OWSUserProfileBadgeInfo],
        lastFetchDate: Date,
        userProfileWriter: UserProfileWriter,
        tx: SDSAnyWriteTransaction
    )

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
        tx: SDSAnyWriteTransaction
    ) -> Promise<Void>

    func didSendOrReceiveMessage(
        serviceId: ServiceId,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    )

    func setProfileKeyData(
        _ profileKeyData: Data,
        for serviceId: ServiceId,
        onlyFillInIfMissing: Bool,
        shouldFetchProfile: Bool,
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        authedAccount: AuthedAccount,
        tx: DBWriteTransaction
    )

    func fillInProfileKeys(
        allProfileKeys: [Aci: Data],
        authoritativeProfileKeys: [Aci: Data],
        userProfileWriter: UserProfileWriter,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    )

    // MARK: -

    func allWhitelistedAddresses(tx: SDSAnyReadTransaction) -> [SignalServiceAddress]
    func allWhitelistedRegisteredAddresses(tx: SDSAnyReadTransaction) -> [SignalServiceAddress]
}
