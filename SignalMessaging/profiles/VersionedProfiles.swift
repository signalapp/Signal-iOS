//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

    // MARK: -

    // Never instantiate this class.
    private override init() {}

    private class func asData(bytes: [UInt8]) -> Data {
        return NSData(bytes: bytes, length: bytes.count) as Data
    }

    @objc
    public class func updateProfileOnService(profileName: String?,
                                             profileAvatarData: Data?) {
        updateProfilePromise(profileName: profileName,
                             profileAvatarData: profileAvatarData)
            .done { _ in
                Logger.verbose("success")
            }.catch { error in
                owsFailDebug("error: \(error)")
            }.retainUntilComplete()
    }

    public class func updateProfilePromise(profileName: String?,
                                           profileAvatarData: Data?) -> Promise<VersionedProfileUpdate> {

        return DispatchQueue.global().async(.promise) {
            let profileKey: OWSAES256Key = self.profileManager.localProfileKey()
            return profileKey
        }.then(on: DispatchQueue.global()) { (profileKey: OWSAES256Key) -> Promise<TSNetworkManager.Response> in
            let profileKeyData: Data = profileKey.keyData
            guard profileKeyData.count == kAES256_KeyByteLength else {
                throw OWSErrorMakeAssertionError("Invalid profile key: \(profileKeyData.count)")
            }
            let profileKeyDataBytes = [UInt8](profileKeyData)
            guard profileKeyDataBytes.count == kAES256_KeyByteLength else {
                throw OWSErrorMakeAssertionError("Invalid profile key bytes: \(profileKeyDataBytes.count)")
            }
            let localProfileKey = try ProfileKey(contents: profileKeyDataBytes)
            let commitment = try localProfileKey.getCommitment()
            let commitmentData = self.asData(bytes: commitment.serialize())
            let hasAvatar = profileAvatarData != nil
            var nameData: Data?
            if let profileName = profileName {
                guard let encryptedPaddedProfileName = OWSProfileManager.encryptProfileName(withUnpaddedName: profileName, localProfileKey: profileKey) else {
                    throw OWSErrorMakeAssertionError("Could not encrypt profile name.")
                }
                nameData = encryptedPaddedProfileName
            }

            let profileKeyVersion = try localProfileKey.getProfileKeyVersion()
            let profileKeyVersionData = self.asData(bytes: profileKeyVersion.serialize())

            let request = OWSRequestFactory.versionedProfileSetRequest(withName: nameData, hasAvatar: hasAvatar, version: profileKeyVersionData, commitment: commitmentData)
            return self.networkManager.makePromise(request: request)
        }.then(on: DispatchQueue.global()) { (response: TSNetworkManager.Response) -> Promise<VersionedProfileUpdate> in
            Logger.verbose("response: \(response)")
            if let profileAvatarData = profileAvatarData {
                return self.parseFormAndUpload(formResponseObject: response.responseObject,
                                               profileAvatarData: profileAvatarData)
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
}
