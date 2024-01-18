//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public struct VersionedProfileUpdate {
    // This will only be set if there is a profile avatar.
    public let avatarUrlPath: OptionalChange<String?>

    public init(avatarUrlPath: OptionalChange<String?>) {
        self.avatarUrlPath = avatarUrlPath
    }
}

// MARK: -

@objc
public protocol VersionedProfileRequest: AnyObject {
    var request: TSRequest { get }
    var profileKey: OWSAES256Key? { get }
}

// MARK: -

@objc
public protocol VersionedProfiles: AnyObject {
    @objc(clearProfileKeyCredentialForServiceId:transaction:)
    func clearProfileKeyCredential(
        for aci: AciObjC,
        transaction: SDSAnyWriteTransaction
    )

    func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction)
}

// MARK: -

public protocol VersionedProfilesSwift: VersionedProfiles {

    func updateProfile(
        profileGivenName: String?,
        profileFamilyName: String?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarMutation: VersionedProfileAvatarMutation,
        visibleBadgeIds: [String],
        profileKey: OWSAES256Key,
        authedAccount: AuthedAccount
    ) async throws -> VersionedProfileUpdate

    func versionedProfileRequest(
        for aci: Aci,
        udAccessKey: SMKUDAccessKey?,
        auth: ChatServiceAuth
    ) throws -> VersionedProfileRequest

    func validProfileKeyCredential(
        for aci: Aci,
        transaction: SDSAnyReadTransaction
    ) throws -> ExpiringProfileKeyCredential?

    func didFetchProfile(
        profile: SignalServiceProfile,
        profileRequest: VersionedProfileRequest
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

@objc
public class MockVersionedProfiles: NSObject, VersionedProfilesSwift, VersionedProfiles {
    public func clearProfileKeyCredential(for aci: AciObjC,
                                          transaction: SDSAnyWriteTransaction) {}

    public func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction) {}

    var didClearProfileKeyCredentials = false

    public func clearProfileKeyCredentials(tx: DBWriteTransaction) {
        didClearProfileKeyCredentials = true
    }

    public func versionedProfileRequest(
        for aci: Aci,
        udAccessKey: SMKUDAccessKey?,
        auth: ChatServiceAuth
    ) throws -> VersionedProfileRequest {
        owsFail("Not implemented.")
    }

    public func didFetchProfile(profile: SignalServiceProfile, profileRequest: VersionedProfileRequest) async {}

    public func updateProfile(
        profileGivenName: String?,
        profileFamilyName: String?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarMutation: VersionedProfileAvatarMutation,
        visibleBadgeIds: [String],
        profileKey: OWSAES256Key,
        authedAccount: AuthedAccount
    ) async throws -> VersionedProfileUpdate {
        owsFail("Not implemented.")
    }

    public func validProfileKeyCredential(for aci: Aci,
                                          transaction: SDSAnyReadTransaction) throws -> ExpiringProfileKeyCredential? {
        owsFail("Not implemented")
    }
}
