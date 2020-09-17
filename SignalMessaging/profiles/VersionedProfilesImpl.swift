//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

public class VersionedProfileRequestImpl: NSObject, VersionedProfileRequest {
    public let request: TSRequest
    public let requestContext: ProfileKeyCredentialRequestContext?
    public let profileKey: OWSAES256Key?

    public required init(request: TSRequest,
                         requestContext: ProfileKeyCredentialRequestContext?,
                         profileKey: OWSAES256Key?) {
        self.request = request
        self.requestContext = requestContext
        self.profileKey = profileKey
    }
}

// MARK: -

@objc
public class VersionedProfilesImpl: NSObject, VersionedProfilesSwift {

    // MARK: - Dependencies

    private var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var tsAccountManager: TSAccountManager {
        return .shared()
    }

    // MARK: -

    public static let credentialStore = SDSKeyValueStore(collection: "VersionedProfiles.credentialStore")

    // MARK: -

    public func clientZkProfileOperations() throws -> ClientZkProfileOperations {
        return ClientZkProfileOperations(serverPublicParams: try GroupsV2Protos.serverPublicParams())
    }

    // MARK: - Update

    @objc
    public func updateProfileOnService(profileGivenName: String?,
                                       profileFamilyName: String?,
                                       profileAvatarData: Data?) {
        firstly {
            updateProfilePromise(profileGivenName: profileGivenName,
                                 profileFamilyName: profileFamilyName,
                                 profileAvatarData: profileAvatarData)
        }.done { _ in
            Logger.verbose("success")

            // TODO: This is temporary for testing.
            let localAddress = TSAccountManager.shared().localAddress!
            firstly {
                ProfileFetcherJob.fetchProfilePromise(address: localAddress,
                                                      mainAppOnly: false,
                                                      ignoreThrottling: true,
                                                      fetchType: .versioned)
            }.done { _ in
                    Logger.verbose("success")
            }.catch { error in
                owsFailDebug("error: \(error)")
            }
        }.catch { error in
            owsFailDebug("error: \(error)")
        }
    }

    public func updateProfilePromise(profileGivenName: String?,
                                     profileFamilyName: String?,
                                     profileAvatarData: Data?) -> Promise<VersionedProfileUpdate> {

        return DispatchQueue.global().async(.promise) {
            guard let localUuid = self.tsAccountManager.localUuid else {
                throw OWSAssertionError("Missing localUuid.")
            }
            let profileKey: OWSAES256Key = self.profileManager.localProfileKey()
            return (localUuid, profileKey)
        }.then(on: DispatchQueue.global()) { (localUuid: UUID, profileKey: OWSAES256Key) -> Promise<TSNetworkManager.Response> in
            let localProfileKey = try self.parseProfileKey(profileKey: profileKey)
            let zkgUuid = try localUuid.asZKGUuid()
            let commitment = try localProfileKey.getCommitment(uuid: zkgUuid)
            let commitmentData = commitment.serialize().asData
            let hasAvatar = profileAvatarData != nil
            var nameData: Data?
            if let profileGivenName = profileGivenName {
                var nameComponents = PersonNameComponents()
                nameComponents.givenName = profileGivenName
                nameComponents.familyName = profileFamilyName

                guard let encryptedPaddedProfileName = OWSUserProfile.encrypt(profileNameComponents: nameComponents,
                                                                              profileKey: profileKey) else {
                                                                                throw OWSAssertionError("Could not encrypt profile name.")
                }
                nameData = encryptedPaddedProfileName
            }

            let profileKeyVersion = try localProfileKey.getProfileKeyVersion(uuid: zkgUuid)
            let profileKeyVersionString = try profileKeyVersion.asHexadecimalString()
            let request = OWSRequestFactory.versionedProfileSetRequest(withName: nameData, hasAvatar: hasAvatar, version: profileKeyVersionString, commitment: commitmentData)
            return self.networkManager.makePromise(request: request)
        }.then(on: DispatchQueue.global()) { (_: URLSessionDataTask, responseObject: Any?) -> Promise<VersionedProfileUpdate> in
            if let profileAvatarData = profileAvatarData {
                let profileKey: OWSAES256Key = self.profileManager.localProfileKey()
                guard let encryptedProfileAvatarData = OWSUserProfile.encrypt(profileData: profileAvatarData,
                                                                              profileKey: profileKey) else {
                                                                                throw OWSAssertionError("Could not encrypt profile avatar.")
                }
                return self.parseFormAndUpload(formResponseObject: responseObject,
                                               profileAvatarData: encryptedProfileAvatarData)
            }
            return Promise.value(VersionedProfileUpdate())
        }
    }

    private func parseFormAndUpload(formResponseObject: Any?,
                                    profileAvatarData: Data) -> Promise<VersionedProfileUpdate> {
        return firstly { () throws -> Promise<OWSUploadFormV2> in
            guard let response = formResponseObject as? [AnyHashable: Any] else {
                throw OWSAssertionError("Unexpected response.")
            }
            guard let form = OWSUploadFormV2.parseDictionary(response) else {
                throw OWSAssertionError("Could not parse response.")
            }
            return Promise.value(form)
        }.then(on: DispatchQueue.global()) { (uploadForm: OWSUploadFormV2) -> Promise<String> in
            OWSUpload.uploadV2(data: profileAvatarData, uploadForm: uploadForm, uploadUrlPath: "")
        }.map(on: DispatchQueue.global()) { (avatarUrlPath: String) -> VersionedProfileUpdate in
            return VersionedProfileUpdate(avatarUrlPath: avatarUrlPath)
        }
    }

    // MARK: - Get

    public func versionedProfileRequest(address: SignalServiceAddress,
                                        udAccessKey: SMKUDAccessKey?) throws -> VersionedProfileRequest {
        guard address.isValid,
            let uuid: UUID = address.uuid else {
                throw OWSAssertionError("Invalid address: \(address)")
        }
        let zkgUuid = try uuid.asZKGUuid()

        var requestContext: ProfileKeyCredentialRequestContext?
        var profileKeyVersionArg: String?
        var credentialRequestArg: Data?
        var profileKeyForRequest: OWSAES256Key?
        try databaseStorage.read { transaction in
            // We try to include the profile key if we have one.
            guard let profileKeyForAddress: OWSAES256Key = self.profileManager.profileKey(for: address,
                                                                                          transaction: transaction) else {
                return
            }
            profileKeyForRequest = profileKeyForAddress
            let profileKey: ProfileKey = try self.parseProfileKey(profileKey: profileKeyForAddress)
            let profileKeyVersion = try profileKey.getProfileKeyVersion(uuid: zkgUuid)
            profileKeyVersionArg = try profileKeyVersion.asHexadecimalString()

            // We need to request a credential if we don't have one already.
            let credential = try self.profileKeyCredentialData(for: address, transaction: transaction)
            if credential == nil {
                let clientZkProfileOperations = try self.clientZkProfileOperations()
                let context = try clientZkProfileOperations.createProfileKeyCredentialRequestContext(uuid: try uuid.asZKGUuid(),
                                                                                                     profileKey: profileKey)
                requestContext = context
                let credentialRequest = try context.getRequest()
                credentialRequestArg = credentialRequest.serialize().asData
            }
        }

        let request = OWSRequestFactory.getVersionedProfileRequest(address: address,
                                                                   profileKeyVersion: profileKeyVersionArg,
                                                                   credentialRequest: credentialRequestArg,
                                                                   udAccessKey: udAccessKey)

        return VersionedProfileRequestImpl(request: request, requestContext: requestContext, profileKey: profileKeyForRequest)
    }

    // MARK: -

    public func parseProfileKey(profileKey: OWSAES256Key) throws -> ProfileKey {
        let profileKeyData: Data = profileKey.keyData
        let profileKeyDataBytes = [UInt8](profileKeyData)
        return try ProfileKey(contents: profileKeyDataBytes)
    }

    public func didFetchProfile(profile: SignalServiceProfile,
                                profileRequest: VersionedProfileRequest) {
        do {
            guard let profileRequest = profileRequest as? VersionedProfileRequestImpl else {
                return
            }
            guard let credentialResponseData = profile.credential else {
                return
            }
            guard credentialResponseData.count > 0 else {
                owsFailDebug("Invalid credential response.")
                return
            }
            guard let uuid = profile.address.uuid else {
                owsFailDebug("Missing uuid.")
                return
            }
            guard let requestContext = profileRequest.requestContext else {
                owsFailDebug("Missing request context.")
                return
            }
            let credentialResponse = try ProfileKeyCredentialResponse(contents: [UInt8](credentialResponseData))
            let clientZkProfileOperations = try self.clientZkProfileOperations()
            let profileKeyCredential = try clientZkProfileOperations.receiveProfileKeyCredential(profileKeyCredentialRequestContext: requestContext, profileKeyCredentialResponse: credentialResponse)
            let credentialData = profileKeyCredential.serialize().asData
            guard credentialData.count > 0 else {
                owsFailDebug("Invalid credential data.")
                return
            }

            Logger.verbose("Updating credential for: \(uuid)")
            databaseStorage.write { transaction in
                Self.credentialStore.setData(credentialData, key: uuid.uuidString, transaction: transaction)
            }
        } catch {
            owsFailDebug("Invalid credential: \(error).")
            return
        }
    }

    // MARK: - Credentials

    public func profileKeyCredentialData(for address: SignalServiceAddress,
                                         transaction: SDSAnyReadTransaction) throws -> Data? {
        guard address.isValid,
            let uuid = address.uuid else {
                throw OWSAssertionError("Invalid address: \(address)")
        }
        return Self.credentialStore.getData(uuid.uuidString, transaction: transaction)
    }

    public func profileKeyCredential(for address: SignalServiceAddress,
                                     transaction: SDSAnyReadTransaction) throws -> ProfileKeyCredential? {
        guard let data = try profileKeyCredentialData(for: address, transaction: transaction) else {
            return nil
        }
        let bytes = [UInt8](data)
        let credential = try ProfileKeyCredential(contents: bytes)
        return credential
    }

    @objc(clearProfileKeyCredentialForAddress:transaction:)
    public func clearProfileKeyCredential(for address: SignalServiceAddress,
                                          transaction: SDSAnyWriteTransaction) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address)")
            return
        }
        guard let uuid = address.uuid else {
            return
        }
        Self.credentialStore.removeValue(forKey: uuid.uuidString, transaction: transaction)
    }

    public func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction) {
        Self.credentialStore.removeAll(transaction: transaction)
    }
}

// MARK: -

public extension Array where Element == UInt8 {
    var asData: Data {
        return Data(self)
    }
}
