//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit
import ZKGroup

@objc
public class VersionedProfileUpdate: NSObject {
    // This will only be set if there is a profile avatar.
    @objc
    public let avatarUrlPath: String?

    required init(avatarUrlPath: String? = nil) {
        self.avatarUrlPath = avatarUrlPath
    }
}

// MARK: -

public struct VersionedProfileRequest {
    public let request: TSRequest
    public let requestContext: ProfileKeyCredentialRequestContext?
}

// MARK: -

@objc
public class VersionedProfiles: NSObject {

    // MARK: - Dependencies

    private class var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private class var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private class var uploadHTTPManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().cdnSessionManager
    }

    private class var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    public static let credentialStore = SDSKeyValueStore(collection: "VersionedProfiles.credentialStore")

    // Never instantiate this class.
    private override init() {}

    // MARK: -

    public class func clientZkProfileOperations() throws -> ClientZkProfileOperations {
        return ClientZkProfileOperations(serverPublicParams: try GroupsV2Utils.serverPublicParams())
    }

    // MARK: - Update

    @objc
    public class func updateProfileOnService(profileGivenName: String?,
                                             profileFamilyName: String?,
                                             profileAvatarData: Data?) {
        updateProfilePromise(profileGivenName: profileGivenName,
                             profileFamilyName: profileFamilyName,
                             profileAvatarData: profileAvatarData)
            .done { _ in
                Logger.verbose("success")

                // TODO: This is temporary for testing.
                let localAddress = TSAccountManager.sharedInstance().localAddress!
                ProfileFetcherJob.fetchAndUpdateProfilePromise(address: localAddress,
                                                               mainAppOnly: false,
                                                               ignoreThrottling: true,
                                                               shouldUpdateProfile: true,
                                                               fetchType: .versioned)
                    .done { _ in
                        Logger.verbose("success")
                    }.catch { error in
                        owsFailDebug("error: \(error)")
                    }.retainUntilComplete()
            }.catch { error in
                owsFailDebug("error: \(error)")
            }.retainUntilComplete()
    }

    public class func updateProfilePromise(profileGivenName: String?,
                                           profileFamilyName: String?,
                                           profileAvatarData: Data?) -> Promise<VersionedProfileUpdate> {

        return DispatchQueue.global().async(.promise) {
            let profileKey: OWSAES256Key = self.profileManager.localProfileKey()
            return profileKey
        }.then(on: DispatchQueue.global()) { (profileKey: OWSAES256Key) -> Promise<TSNetworkManager.Response> in
            let localProfileKey = try self.parseProfileKey(profileKey: profileKey)

            let commitment = try localProfileKey.getCommitment()
            let commitmentData = commitment.serialize().asData
            let hasAvatar = profileAvatarData != nil
            var nameData: Data?
            if let profileGivenName = profileGivenName {
                var nameComponents = PersonNameComponents()
                nameComponents.givenName = profileGivenName
                nameComponents.familyName = profileFamilyName

                guard let encryptedPaddedProfileName = OWSProfileManager.shared().encrypt(profileNameComponents: nameComponents, profileKey: profileKey) else {
                    throw OWSAssertionError("Could not encrypt profile name.")
                }
                nameData = encryptedPaddedProfileName
            }

            let profileKeyVersion = try localProfileKey.getProfileKeyVersion()
            let profileKeyVersionString = try profileKeyVersion.asHexadecimalString()
            let request = OWSRequestFactory.versionedProfileSetRequest(withName: nameData, hasAvatar: hasAvatar, version: profileKeyVersionString, commitment: commitmentData)
            return self.networkManager.makePromise(request: request)
        }.then(on: DispatchQueue.global()) { (_: URLSessionDataTask, responseObject: Any?) -> Promise<VersionedProfileUpdate> in
            if let profileAvatarData = profileAvatarData {
                let profileKey: OWSAES256Key = self.profileManager.localProfileKey()
                guard let encryptedProfileAvatarData = OWSProfileManager.shared().encrypt(profileData: profileAvatarData, profileKey: profileKey) else {
                    throw OWSAssertionError("Could not encrypt profile avatar.")
                }
                return self.parseFormAndUpload(formResponseObject: responseObject,
                                               profileAvatarData: encryptedProfileAvatarData)
            }
            return Promise.value(VersionedProfileUpdate())
        }
    }

    private class func parseFormAndUpload(formResponseObject: Any?,
                                          profileAvatarData: Data) -> Promise<VersionedProfileUpdate> {
        let urlPath: String = ""
        let (promise, resolver) = Promise<VersionedProfileUpdate>.pending()
        DispatchQueue.global().async {
            guard let response = formResponseObject as? [AnyHashable: Any] else {
                resolver.reject(OWSAssertionError("Unexpected response."))
                return
            }
            guard let form = OWSUploadForm.parse(response) else {
                resolver.reject(OWSAssertionError("Could not parse response."))
                return
            }

            // TODO: We will probably (continue to) use this within profile manager.
            let avatarUrlPath = form.formKey

            self.uploadHTTPManager.post(urlPath,
                                        parameters: nil,
                                        constructingBodyWith: { (formData: AFMultipartFormData) -> Void in

                                            // We have to build up the form manually vs. simply passing in a paramaters dict
                                            // because AWS is sensitive to the order of the form params (at least the "key"
                                            // field must occur early on).
                                            //
                                            // For consistency, all fields are ordered here in a known working order.
                                            form.append(toForm: formData)

                                            AppendMultipartFormPath(formData, "Content-Type", OWSMimeTypeApplicationOctetStream)

                                            formData.appendPart(withForm: profileAvatarData, name: "file")
            },
                                        progress: { progress in
                                            Logger.verbose("progress: \(progress.fractionCompleted)")
            },
                                        success: { (_, _) in
                                            Logger.verbose("Success.")
                                            resolver.fulfill(VersionedProfileUpdate(avatarUrlPath: avatarUrlPath))
            }, failure: { (_, error) in
                owsFailDebug("Error: \(error)")
                resolver.reject(error)
            })
        }
        return promise
    }

    // MARK: - Get

    public class func versionedProfileRequest(address: SignalServiceAddress,
                                              udAccessKey: SMKUDAccessKey?) throws -> VersionedProfileRequest {
        guard address.isValid,
            let uuid: UUID = address.uuid else {
                throw OWSAssertionError("Invalid address: \(address)")
        }

        var requestContext: ProfileKeyCredentialRequestContext?
        var profileKeyVersionArg: String?
        var credentialRequestArg: Data?
        try databaseStorage.read { transaction in
            // We try to include the profile key if we have one.
            guard let profileKeyForAddress: OWSAES256Key = self.profileManager.profileKey(for: address, transaction: transaction) else {
                return
            }
            let profileKey: ProfileKey = try self.parseProfileKey(profileKey: profileKeyForAddress)
            let profileKeyVersion = try profileKey.getProfileKeyVersion()
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

        return VersionedProfileRequest(request: request, requestContext: requestContext)
    }

    // MARK: -

    public class func parseProfileKey(profileKey: OWSAES256Key) throws -> ProfileKey {
        let profileKeyData: Data = profileKey.keyData
        let profileKeyDataBytes = [UInt8](profileKeyData)
        return try ProfileKey(contents: profileKeyDataBytes)
    }

    public class func didFetchProfile(profile: SignalServiceProfile,
                                      profileRequest: VersionedProfileRequest) {
        do {
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
                credentialStore.setData(credentialData, key: uuid.uuidString, transaction: transaction)
            }
        } catch {
            owsFailDebug("Invalid credential: \(error).")
            return
        }
    }

    // MARK: - Credentials

    public class func profileKeyCredentialData(for address: SignalServiceAddress,
                                                transaction: SDSAnyReadTransaction) throws -> Data? {
        guard address.isValid,
            let uuid = address.uuid else {
                throw OWSAssertionError("Invalid address: \(address)")
        }
        return credentialStore.getData(uuid.uuidString, transaction: transaction)
    }

    public class func profileKeyCredential(for address: SignalServiceAddress,
                                           transaction: SDSAnyReadTransaction) throws -> ProfileKeyCredential? {
        guard let data = try profileKeyCredentialData(for: address, transaction: transaction) else {
            return nil
        }
        let bytes = [UInt8](data)
        let credential = try ProfileKeyCredential(contents: bytes)
        return credential
    }

    @objc(clearProfileKeyCredentialForAddress:transaction:)
    public class func clearProfileKeyCredential(for address: SignalServiceAddress,
                                                transaction: SDSAnyWriteTransaction) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address)")
            return
        }
        guard let uuid = address.uuid else {
            return
        }
        credentialStore.removeValue(forKey: uuid.uuidString, transaction: transaction)
    }

    public class func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction) {
        credentialStore.removeAll(transaction: transaction)
    }
}

// MARK: -

public extension Array where Element == UInt8 {
    var asData: Data {
        return Data(self)
    }
}
