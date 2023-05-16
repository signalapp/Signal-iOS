//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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

public class VersionedProfilesImpl: NSObject, VersionedProfilesSwift, VersionedProfiles {

    private enum CredentialStore {
        private static let deprecatedCredentialStore = SDSKeyValueStore(collection: "VersionedProfiles.credentialStore")

        private static let expiringCredentialStore = SDSKeyValueStore(collection: "VersionedProfilesImpl.expiringCredentialStore")

        private static func storeKey(for serviceId: ServiceId) -> String {
            return serviceId.uuidValue.uuidString
        }

        static func dropDeprecatedCredentialsIfNecessary(transaction: SDSAnyWriteTransaction) {
            deprecatedCredentialStore.removeAll(transaction: transaction)
        }

        static func hasValidCredential(
            for serviceId: ServiceId,
            transaction: SDSAnyReadTransaction
        ) throws -> Bool {
            try getValidCredential(for: serviceId, transaction: transaction) != nil
        }

        static func getValidCredential(
            for serviceId: ServiceId,
            transaction: SDSAnyReadTransaction
        ) throws -> ExpiringProfileKeyCredential? {
            guard let credentialData = expiringCredentialStore.getData(
                storeKey(for: serviceId),
                transaction: transaction
            ) else {
                return nil
            }

            let credential = try ExpiringProfileKeyCredential(contents: [UInt8](credentialData))

            guard credential.isValid else {
                // Safe to leave the expired credential here - we can't clear it
                // because we're in a read-only transaction. When we try and
                // fetch a new credential for this address we'll overwrite this
                // expired one.
                Logger.info("Found expired credential for serviceId \(serviceId)")
                return nil
            }

            return credential
        }

        static func setCredential(
            _ credential: ExpiringProfileKeyCredential,
            for serviceId: ServiceId,
            transaction: SDSAnyWriteTransaction
        ) throws {
            let credentialData = credential.serialize().asData

            guard !credentialData.isEmpty else {
                throw OWSAssertionError("Invalid credential data")
            }

            expiringCredentialStore.setData(
                credentialData,
                key: storeKey(for: serviceId),
                transaction: transaction
            )
        }

        static func removeValue(for serviceId: ServiceId, transaction: SDSAnyWriteTransaction) {
            expiringCredentialStore.removeValue(forKey: storeKey(for: serviceId), transaction: transaction)
        }

        static func removeAll(transaction: SDSAnyWriteTransaction) {
            expiringCredentialStore.removeAll(transaction: transaction)
        }
    }

    // MARK: - Init

    override public init() {
        super.init()

        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            // Once we think all clients in the world have migrated to expiring
            // credentials we can remove this.
            self.databaseStorage.asyncWrite { transaction in
                CredentialStore.dropDeprecatedCredentialsIfNecessary(transaction: transaction)
            }
        }
    }

    // MARK: -

    public func clientZkProfileOperations() throws -> ClientZkProfileOperations {
        return ClientZkProfileOperations(serverPublicParams: try GroupsV2Protos.serverPublicParams())
    }

    // MARK: - Update

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

        let profileKeyToUse = unsavedRotatedProfileKey ?? self.profileManager.localProfileKey()
        return firstly(on: DispatchQueue.global()) {
            let localUuid: UUID
            switch authedAccount.info {
            case .explicit(let info):
                localUuid = info.aci
            case .implicit:
                guard let uuid = self.tsAccountManager.localUuid else {
                    throw OWSAssertionError("Missing localUuid.")
                }
                localUuid = uuid
            }

            if unsavedRotatedProfileKey != nil {
                Logger.info("Updating local profile with unsaved rotated profile key")
            }
            return localUuid
        }.then(on: DispatchQueue.global()) { (localUuid: UUID) -> Promise<HTTPResponse> in
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
            let request = OWSRequestFactory.versionedProfileSetRequest(
                withName: nameValue,
                bio: bioValue,
                bioEmoji: bioEmojiValue,
                hasAvatar: hasAvatar,
                paymentAddress: paymentAddressValue,
                visibleBadgeIds: visibleBadgeIds,
                version: profileKeyVersionString,
                commitment: commitmentData,
                auth: authedAccount.chatServiceAuth
            )
            return self.networkManager.makePromise(request: request)
        }.then(on: DispatchQueue.global()) { response -> Promise<VersionedProfileUpdate> in
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

    public func versionedProfileRequest(
        for serviceId: ServiceId,
        udAccessKey: SMKUDAccessKey?,
        auth: ChatServiceAuth
    ) throws -> VersionedProfileRequest {
        var requestContext: ProfileKeyCredentialRequestContext?
        var profileKeyVersionArg: String?
        var credentialRequestArg: Data?
        var profileKeyForRequest: OWSAES256Key?
        try databaseStorage.read { transaction in
            // We try to include the profile key if we have one.
            guard let profileKeyForAddress = self.profileManager.profileKey(
                for: SignalServiceAddress(serviceId),
                transaction: transaction)
            else {
                return
            }
            profileKeyForRequest = profileKeyForAddress
            let profileKey: ProfileKey = try self.parseProfileKey(profileKey: profileKeyForAddress)
            let profileKeyVersion = try profileKey.getProfileKeyVersion(uuid: serviceId.uuidValue)
            profileKeyVersionArg = try profileKeyVersion.asHexadecimalString()

            // We need to request a credential if we don't have a valid one already.
            if !(try CredentialStore.hasValidCredential(for: serviceId, transaction: transaction)) {
                let clientZkProfileOperations = try self.clientZkProfileOperations()
                let context = try clientZkProfileOperations.createProfileKeyCredentialRequestContext(
                    uuid: serviceId.uuidValue,
                    profileKey: profileKey
                )
                requestContext = context
                let credentialRequest = try context.getRequest()
                credentialRequestArg = credentialRequest.serialize().asData
            }
        }

        let request = OWSRequestFactory.getVersionedProfileRequest(
            serviceId: ServiceIdObjC(serviceId),
            profileKeyVersion: profileKeyVersionArg,
            credentialRequest: credentialRequestArg,
            udAccessKey: udAccessKey,
            auth: auth
        )

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

            let credentialResponse = try ExpiringProfileKeyCredentialResponse(contents: [UInt8](credentialResponseData))
            let clientZkProfileOperations = try self.clientZkProfileOperations()
            let profileKeyCredential = try clientZkProfileOperations.receiveExpiringProfileKeyCredential(
                profileKeyCredentialRequestContext: requestContext,
                profileKeyCredentialResponse: credentialResponse
            )

            guard let requestProfileKey = profileRequest.profileKey else {
                throw OWSAssertionError("Missing profile key for credential from versioned profile fetch.")
            }

            guard let serviceId = profile.address.serviceId else {
                throw OWSAssertionError("Missing serviceId.")
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

                try CredentialStore.setCredential(profileKeyCredential, for: serviceId, transaction: transaction)
            }
        } catch {
            owsFailDebug("Invalid credential: \(error).")
            return
        }
    }

    // MARK: - Credentials

    public func validProfileKeyCredential(
        for serviceId: ServiceId,
        transaction: SDSAnyReadTransaction
    ) throws -> ExpiringProfileKeyCredential? {
        try CredentialStore.getValidCredential(for: serviceId, transaction: transaction)
    }

    @objc(clearProfileKeyCredentialForServiceId:transaction:)
    public func clearProfileKeyCredential(
        for serviceId: ServiceIdObjC,
        transaction: SDSAnyWriteTransaction
    ) {
        CredentialStore.removeValue(for: serviceId.wrappedValue, transaction: transaction)
    }

    public func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction) {
        CredentialStore.removeAll(transaction: transaction)
    }
}

extension ExpiringProfileKeyCredential {
    /// Checks if the credential is valid.
    ///
    /// `fileprivate` here since callers into this file should only ever receive
    /// valid credentials, and so we should discourage redundant validity
    /// checking elsewhere.
    fileprivate var isValid: Bool {
        return expirationTime > Date()
    }
}
