//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
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

    public static let credentialStore = SDSKeyValueStore(collection: "VersionedProfiles.credentialStore")

    // MARK: -

    public func clientZkProfileOperations() throws -> ClientZkProfileOperations {
        return ClientZkProfileOperations(serverPublicParams: try GroupsV2Protos.serverPublicParams())
    }

    // MARK: - Update

    public func updateProfilePromise(profileGivenName: String?,
                                     profileFamilyName: String?,
                                     profileBio: String?,
                                     profileBioEmoji: String?,
                                     profileAvatarData: Data?,
                                     visibleBadgeIds: [String],
                                     unsavedRotatedProfileKey: OWSAES256Key?) -> Promise<VersionedProfileUpdate> {

        firstly(on: .global()) {
            guard let localUuid = self.tsAccountManager.localUuid else {
                throw OWSAssertionError("Missing localUuid.")
            }

            if unsavedRotatedProfileKey != nil {
                Logger.info("Updating local profile with unsaved rotated profile key")
            }

            let profileKey: OWSAES256Key = unsavedRotatedProfileKey ?? self.profileManager.localProfileKey()
            return (localUuid, profileKey)
        }.then(on: .global()) { (localUuid: UUID, profileKey: OWSAES256Key) -> Promise<HTTPResponse> in
            let localProfileKey = try self.parseProfileKey(profileKey: profileKey)
            let zkgUuid = try localUuid.asZKGUuid()
            let commitment = try localProfileKey.getCommitment(uuid: zkgUuid)
            let commitmentData = commitment.serialize().asData
            let hasAvatar = profileAvatarData != nil

            func fetchLocalPaymentAddressProtoData() -> Data? {
                Self.databaseStorage.write { transaction in
                    Self.paymentsHelper.lastKnownLocalPaymentAddressProtoData(transaction: transaction)
                }
            }

            var profilePaymentAddressData: Data?
            if Self.paymentsHelper.arePaymentsEnabled,
               !Self.paymentsHelper.isKillSwitchActive,
               let addressProtoData = fetchLocalPaymentAddressProtoData() {

                var paymentAddressDataWithLength = Data()
                var littleEndian: UInt32 = CFSwapInt32HostToLittle(UInt32(addressProtoData.count))
                withUnsafePointer(to: &littleEndian) { pointer in
                    paymentAddressDataWithLength.append(UnsafeBufferPointer(start: pointer, count: 1))
                }
                paymentAddressDataWithLength.append(addressProtoData)
                profilePaymentAddressData = paymentAddressDataWithLength
            }

            var nameValue: ProfileValue?
            if let profileGivenName = profileGivenName {
                var nameComponents = PersonNameComponents()
                nameComponents.givenName = profileGivenName
                nameComponents.familyName = profileFamilyName

                guard let encryptedValue = OWSUserProfile.encrypt(profileNameComponents: nameComponents,
                                                                  profileKey: profileKey) else {
                    throw OWSAssertionError("Could not encrypt profile name.")
                }
                nameValue = encryptedValue
            }

            func encryptOptionalData(_ value: Data?,
                                     paddedLengths: [Int],
                                     validBase64Lengths: [Int]) throws -> ProfileValue? {
                guard let value = value,
                      !value.isEmpty else {
                    return nil
                }
                guard let encryptedValue = OWSUserProfile.encrypt(data: value,
                                                                  profileKey: profileKey,
                                                                  paddedLengths: paddedLengths,
                                                                  validBase64Lengths: validBase64Lengths) else {
                    throw OWSAssertionError("Could not encrypt profile value.")
                }
                return encryptedValue
            }

            func encryptOptionalString(_ value: String?,
                                       paddedLengths: [Int],
                                       validBase64Lengths: [Int]) throws -> ProfileValue? {
                guard let value = value,
                      !value.isEmpty else {
                    return nil
                }
                guard let stringData = value.data(using: .utf8) else {
                    owsFailDebug("Invalid value.")
                    return nil
                }
                return try encryptOptionalData(stringData,
                                               paddedLengths: paddedLengths,
                                               validBase64Lengths: validBase64Lengths)
            }

            // The Base 64 lengths reflect encryption + Base 64 encoding
            // of the max-length padded value.
            let bioValue = try encryptOptionalString(profileBio,
                                                     paddedLengths: [128, 254, 512 ],
                                                     validBase64Lengths: [208, 376, 720])

            let bioEmojiValue = try encryptOptionalString(profileBioEmoji,
                                                          paddedLengths: [32],
                                                          validBase64Lengths: [80])

            let paymentAddressValue = try encryptOptionalData(profilePaymentAddressData,
                                                              paddedLengths: [554],
                                                              validBase64Lengths: [776])

            let profileKeyVersion = try localProfileKey.getProfileKeyVersion(uuid: zkgUuid)
            let profileKeyVersionString = try profileKeyVersion.asHexadecimalString()
            let request = OWSRequestFactory.versionedProfileSetRequest(withName: nameValue,
                                                                       bio: bioValue,
                                                                       bioEmoji: bioEmojiValue,
                                                                       hasAvatar: hasAvatar,
                                                                       paymentAddress: paymentAddressValue,
                                                                       visibleBadgeIds: visibleBadgeIds,
                                                                       version: profileKeyVersionString,
                                                                       commitment: commitmentData)
            return self.networkManager.makePromise(request: request)
        }.then(on: .global()) { response -> Promise<VersionedProfileUpdate> in
            if let profileAvatarData = profileAvatarData {
                let profileKey: OWSAES256Key = self.profileManager.localProfileKey()
                guard let encryptedProfileAvatarData = OWSUserProfile.encrypt(profileData: profileAvatarData,
                                                                              profileKey: profileKey) else {
                    throw OWSAssertionError("Could not encrypt profile avatar.")
                }
                guard let json = response.responseBodyJson else {
                    throw OWSAssertionError("Missing or invalid JSON")
                }
                return self.parseFormAndUpload(formResponseObject: json,
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
            let address = profile.address
            guard let uuid = address.uuid else {
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

            guard let requestProfileKey = profileRequest.profileKey else {
                owsFailDebug("Missing profile key for credential from versioned profile fetch.")
                return
            }

            databaseStorage.write { transaction in
                guard let currentProfileKey = profileManager.profileKey(for: address, transaction: transaction) else {
                    owsFailDebug("Missing profile key in database.")
                    return
                }
                guard requestProfileKey.keyData == currentProfileKey.keyData else {
                    if DebugFlags.internalLogging {
                        Logger.info("requestProfileKey: \(requestProfileKey.keyData.hexadecimalString) != currentProfileKey: \(currentProfileKey.keyData.hexadecimalString)")
                    }
                    Logger.warn("Profile key for versioned profile fetch does not match current profile key.")
                    return
                }

                Logger.verbose("Updating credential for: \(uuid)")

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
