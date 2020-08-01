//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit

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
public protocol VersionedProfileRequest: class {
    var request: TSRequest { get }
    var profileKey: OWSAES256Key? { get }
}

// MARK: -

@objc
public protocol VersionedProfiles: class {
    @objc(clearProfileKeyCredentialForAddress:transaction:)
    func clearProfileKeyCredential(for address: SignalServiceAddress,
                                   transaction: SDSAnyWriteTransaction)

    func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction)

    func versionedProfileRequest(address: SignalServiceAddress,
                                 udAccessKey: SMKUDAccessKey?) throws -> VersionedProfileRequest

    func didFetchProfile(profile: SignalServiceProfile,
                         profileRequest: VersionedProfileRequest)
}

// MARK: -

public protocol VersionedProfilesSwift: VersionedProfiles {
    func updateProfilePromise(profileGivenName: String?,
                              profileFamilyName: String?,
                              profileAvatarData: Data?) -> Promise<VersionedProfileUpdate>
}

// MARK: -

@objc
public class MockVersionedProfiles: NSObject, VersionedProfilesSwift {
    public func clearProfileKeyCredential(for address: SignalServiceAddress,
                                          transaction: SDSAnyWriteTransaction) {}

    public func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction) {}

    public func versionedProfileRequest(address: SignalServiceAddress,
                                        udAccessKey: SMKUDAccessKey?) throws -> VersionedProfileRequest {
        owsFail("Not implemented.")
    }

    public func didFetchProfile(profile: SignalServiceProfile,
                                profileRequest: VersionedProfileRequest) {}

    public func updateProfilePromise(profileGivenName: String?,
                                     profileFamilyName: String?,
                                     profileAvatarData: Data?) -> Promise<VersionedProfileUpdate> {
        owsFail("Not implemented.")
    }
}
