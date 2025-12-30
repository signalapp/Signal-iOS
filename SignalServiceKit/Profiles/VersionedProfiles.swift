//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct VersionedProfileUpdate {
    // This will only be set if there is a profile avatar.
    public let avatarUrlPath: OptionalChange<String?>

    public init(avatarUrlPath: OptionalChange<String?>) {
        self.avatarUrlPath = avatarUrlPath
    }
}

// MARK: -

public protocol VersionedProfiles: AnyObject {

    func clearProfileKeyCredential(for aci: Aci, transaction: DBWriteTransaction)

    func clearProfileKeyCredentials(transaction: DBWriteTransaction)

    func updateProfile(
        profileGivenName: OWSUserProfile.NameComponent?,
        profileFamilyName: OWSUserProfile.NameComponent?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarMutation: VersionedProfileAvatarMutation,
        visibleBadgeIds: [String],
        profileKey: Aes256Key,
        authedAccount: AuthedAccount,
    ) async throws -> VersionedProfileUpdate

    func versionedProfileRequest(
        for aci: Aci,
        profileKey: ProfileKey,
        shouldRequestCredential: Bool,
        udAccessKey: SMKUDAccessKey?,
        auth: ChatServiceAuth,
    ) throws -> VersionedProfileRequest

    func validProfileKeyCredential(
        for aci: Aci,
        transaction: DBReadTransaction,
    ) throws -> ExpiringProfileKeyCredential?

    func didFetchProfile(
        profile: SignalServiceProfile,
        profileRequest: VersionedProfileRequest,
    ) async

    func clearProfileKeyCredentials(tx: DBWriteTransaction)
}

// MARK: -

public enum VersionedProfileAvatarMutation {
    /// There's an existing avatar that we want to keep.
    case keepAvatar
    /// There's either (a) no existing avatar and we don't want one after this
    /// change or (b) an existing avatar that we want to clear.
    case clearAvatar
    /// We want to set a new avatar.
    case changeAvatar(Data)
}

// MARK: -

public class MockVersionedProfiles: VersionedProfiles {
    public func clearProfileKeyCredential(for aci: Aci, transaction: DBWriteTransaction) {}

    public func clearProfileKeyCredentials(transaction: DBWriteTransaction) {}

    var didClearProfileKeyCredentials = false

    public func clearProfileKeyCredentials(tx: DBWriteTransaction) {
        didClearProfileKeyCredentials = true
    }

    public func versionedProfileRequest(
        for aci: Aci,
        profileKey: ProfileKey,
        shouldRequestCredential: Bool,
        udAccessKey: SMKUDAccessKey?,
        auth: ChatServiceAuth,
    ) throws -> VersionedProfileRequest {
        owsFail("Not implemented.")
    }

    public func didFetchProfile(profile: SignalServiceProfile, profileRequest: VersionedProfileRequest) async {}

    public func updateProfile(
        profileGivenName: OWSUserProfile.NameComponent?,
        profileFamilyName: OWSUserProfile.NameComponent?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarMutation: VersionedProfileAvatarMutation,
        visibleBadgeIds: [String],
        profileKey: Aes256Key,
        authedAccount: AuthedAccount,
    ) async throws -> VersionedProfileUpdate {
        owsFail("Not implemented.")
    }

    public func validProfileKeyCredential(
        for aci: Aci,
        transaction: DBReadTransaction,
    ) throws -> ExpiringProfileKeyCredential? {
        owsFail("Not implemented")
    }
}
