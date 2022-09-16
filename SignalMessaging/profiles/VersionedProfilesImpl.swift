//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import LibSignalClient

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
public class VersionedProfilesImpl: NSObject, VersionedProfilesSwift, VersionedProfiles {

    private enum CredentialStore {
        private static let credentialStore = SDSKeyValueStore(collection: "VersionedProfiles.credentialStore")

        private static func storeKey(forAddress address: SignalServiceAddress) throws -> String {
            guard
                address.isValid,
                let uuid = address.uuid
            else {
                throw OWSAssertionError("Address invalid or missing UUID: \(address)")
            }

            return uuid.uuidString
        }

        static func hasCredential(
            forAddress address: SignalServiceAddress,
            transaction: SDSAnyReadTransaction
        ) throws -> Bool {
            credentialStore.hasValue(
                forKey: try storeKey(forAddress: address),
                transaction: transaction
            )
        }

        static func getCredential(
            forAddress address: SignalServiceAddress,
            transaction: SDSAnyReadTransaction
        ) throws -> ProfileKeyCredential? {
            guard let credentialData = credentialStore.getData(
                try storeKey(forAddress: address),
                transaction: transaction
            ) else {
                return nil
            }

            return try ProfileKeyCredential(contents: [UInt8](credentialData))
        }

        static func setCredential(
            _ credential: ProfileKeyCredential,
            forAddress address: SignalServiceAddress,
            transaction: SDSAnyWriteTransaction
        ) throws {
            let credentialData = credential.serialize().asData

            guard !credentialData.isEmpty else {
                throw OWSAssertionError("Invalid credential data")
            }

            credentialStore.setData(
                credentialData,
                key: try storeKey(forAddress: address),
                transaction: transaction
            )
        }

        static func removeValue(
            forAddress address: SignalServiceAddress,
            transaction: SDSAnyWriteTransaction
        ) throws {
            credentialStore.removeValue(
                forKey: try storeKey(forAddress: address),
                transaction: transaction
            )
        }

        static func removeAll(transaction: SDSAnyWriteTransaction) {
            credentialStore.removeAll(transaction: transaction)
        }
    }

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

        let profileKeyToUse = unsavedRotatedProfileKey ?? self.profileManager.localProfileKey()
        return firstly(on: .global()) {
            guard let localUuid = self.tsAccountManager.localUuid else {
                throw OWSAssertionError("Missing localUuid.")
            }

            if unsavedRotatedProfileKey != nil {
                Logger.info("Updating local profile with unsaved rotated profile key")
            }
            return localUuid
        }.then(on: .global()) { (localUuid: UUID) -> Promise<HTTPResponse> in
            let localProfileKey = try self.parseProfileKey(profileKey: profileKeyToUse)
            let commitment = try localProfileKey.getCommitment(uuid: localUuid)
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
                                                                  profileKey: profileKeyToUse) else {
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
                                                                  profileKey: profileKeyToUse,
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

            let profileKeyVersion = try localProfileKey.getProfileKeyVersion(uuid: localUuid)
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
                guard let encryptedProfileAvatarData = OWSUserProfile.encrypt(profileData: profileAvatarData,
                                                                              profileKey: profileKeyToUse) else {
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
        guard
            address.isValid,
            let uuid: UUID = address.uuid
        else {
            throw OWSAssertionError("Address invalid or missing UUID: \(address)")
        }

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
            let profileKeyVersion = try profileKey.getProfileKeyVersion(uuid: uuid)
            profileKeyVersionArg = try profileKeyVersion.asHexadecimalString()

            // We need to request a credential if we don't have one already.
            if !(try CredentialStore.hasCredential(forAddress: address, transaction: transaction)) {
                let clientZkProfileOperations = try self.clientZkProfileOperations()
                let context = try clientZkProfileOperations.createProfileKeyCredentialRequestContext(uuid: uuid,
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
                throw OWSAssertionError("Invalid credential response.")
            }
            guard let requestContext = profileRequest.requestContext else {
                throw OWSAssertionError("Missing request context.")
            }

            let credentialResponse = try ProfileKeyCredentialResponse(contents: [UInt8](credentialResponseData))
            let clientZkProfileOperations = try self.clientZkProfileOperations()
            let profileKeyCredential = try clientZkProfileOperations.receiveProfileKeyCredential(
                profileKeyCredentialRequestContext: requestContext,
                profileKeyCredentialResponse: credentialResponse
            )

            guard let requestProfileKey = profileRequest.profileKey else {
                throw OWSAssertionError("Missing profile key for credential from versioned profile fetch.")
            }

            let address = profile.address

            try databaseStorage.write { transaction throws in
                guard let currentProfileKey = profileManager.profileKey(for: address, transaction: transaction) else {
                    throw OWSAssertionError("Missing profile key in database.")
                }

                guard requestProfileKey.keyData == currentProfileKey.keyData else {
                    if DebugFlags.internalLogging {
                        Logger.info("requestProfileKey: \(requestProfileKey.keyData.hexadecimalString) != currentProfileKey: \(currentProfileKey.keyData.hexadecimalString)")
                    }
                    Logger.warn("Profile key for versioned profile fetch does not match current profile key.")
                    return
                }

                try CredentialStore.setCredential(
                    profileKeyCredential,
                    forAddress: address,
                    transaction: transaction
                )
            }
        } catch {
            owsFailDebug("Invalid credential: \(error).")
            return
        }
    }

    // MARK: - Credentials

    public func profileKeyCredential(
        for address: SignalServiceAddress,
        transaction: SDSAnyReadTransaction
    ) throws -> ProfileKeyCredential? {
        try CredentialStore.getCredential(
            forAddress: address,
            transaction: transaction
        )
    }

    @objc(clearProfileKeyCredentialForAddress:transaction:)
    public func clearProfileKeyCredential(
        for address: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) {
        do {
            try CredentialStore.removeValue(forAddress: address, transaction: transaction)
        } catch let error {
            owsFailDebug("Failed to clear credential for address \(address): \(error)")
        }
    }

    public func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction) {
        CredentialStore.removeAll(transaction: transaction)
    }
}
