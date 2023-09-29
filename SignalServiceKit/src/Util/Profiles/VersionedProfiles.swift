//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
public class VersionedProfileUpdate: NSObject {
    // This will only be set if there is a profile avatar.
    @objc
    public let avatarUrlPath: String?

    public required init(avatarUrlPath: String? = nil) {
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

    func updateProfilePromise(
        profileGivenName: String?,
        profileFamilyName: String?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarData: Data?,
        visibleBadgeIds: [String],
        unsavedRotatedProfileKey: OWSAES256Key?,
        authedAccount: AuthedAccount
    ) -> Promise<VersionedProfileUpdate>

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

@objc
public class MockVersionedProfiles: NSObject, VersionedProfilesSwift, VersionedProfiles {
    public func clearProfileKeyCredential(for aci: AciObjC,
                                          transaction: SDSAnyWriteTransaction) {}

    public func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction) {}
    public func clearProfileKeyCredentials(tx: DBWriteTransaction) {}

    public func versionedProfileRequest(
        for aci: Aci,
        udAccessKey: SMKUDAccessKey?,
        auth: ChatServiceAuth
    ) throws -> VersionedProfileRequest {
        owsFail("Not implemented.")
    }

    public func didFetchProfile(profile: SignalServiceProfile, profileRequest: VersionedProfileRequest) async {}

    public func updateProfilePromise(
        profileGivenName: String?,
        profileFamilyName: String?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarData: Data?,
        visibleBadgeIds: [String],
        unsavedRotatedProfileKey: OWSAES256Key?,
        authedAccount: AuthedAccount
    ) -> Promise<VersionedProfileUpdate> {
        owsFail("Not implemented.")
    }

    public func validProfileKeyCredential(for aci: Aci,
                                          transaction: SDSAnyReadTransaction) throws -> ExpiringProfileKeyCredential? {
        owsFail("Not implemented")
    }
}
