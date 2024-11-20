//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public struct VersionedProfileRequest {
    public let aci: Aci
    public let request: TSRequest
    public let profileKey: ProfileKey
    public let requestContext: ProfileKeyCredentialRequestContext?

    public init(
        aci: Aci,
        request: TSRequest,
        profileKey: ProfileKey,
        requestContext: ProfileKeyCredentialRequestContext?
    ) {
        self.aci = aci
        self.request = request
        self.profileKey = profileKey
        self.requestContext = requestContext
    }
}

// MARK: -

public class VersionedProfilesImpl: NSObject, VersionedProfilesSwift, VersionedProfiles {

    private enum CredentialStore {
        private static let deprecatedCredentialStore = KeyValueStore(collection: "VersionedProfiles.credentialStore")

        private static let expiringCredentialStore = KeyValueStore(collection: "VersionedProfilesImpl.expiringCredentialStore")

        private static func storeKey(for aci: Aci) -> String {
            return aci.serviceIdUppercaseString
        }

        static func dropDeprecatedCredentialsIfNecessary(transaction: SDSAnyWriteTransaction) {
            deprecatedCredentialStore.removeAll(transaction: transaction.asV2Write)
        }

        static func getValidCredential(
            for aci: Aci,
            transaction: SDSAnyReadTransaction
        ) throws -> ExpiringProfileKeyCredential? {
            guard let credentialData = expiringCredentialStore.getData(
                storeKey(for: aci),
                transaction: transaction.asV2Read
            ) else {
                return nil
            }

            let credential = try ExpiringProfileKeyCredential(contents: [UInt8](credentialData))

            guard credential.isValid else {
                // Safe to leave the expired credential here - we can't clear it
                // because we're in a read-only transaction. When we try and
                // fetch a new credential for this address we'll overwrite this
                // expired one.
                return nil
            }

            return credential
        }

        static func setCredential(
            _ credential: ExpiringProfileKeyCredential,
            for aci: Aci,
            transaction: SDSAnyWriteTransaction
        ) throws {
            let credentialData = credential.serialize().asData

            guard !credentialData.isEmpty else {
                throw OWSAssertionError("Invalid credential data")
            }

            expiringCredentialStore.setData(
                credentialData,
                key: storeKey(for: aci),
                transaction: transaction.asV2Write
            )
        }

        static func removeValue(for aci: Aci, transaction: SDSAnyWriteTransaction) {
            expiringCredentialStore.removeValue(forKey: storeKey(for: aci), transaction: transaction.asV2Write)
        }

        static func removeAll(transaction: SDSAnyWriteTransaction) {
            expiringCredentialStore.removeAll(transaction: transaction.asV2Write)
        }
    }

    // MARK: - Init

    public init(appReadiness: AppReadiness) {
        super.init()

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            // Once we think all clients in the world have migrated to expiring
            // credentials we can remove this.
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                CredentialStore.dropDeprecatedCredentialsIfNecessary(transaction: transaction)
            }
        }
    }

    // MARK: -

    public func clientZkProfileOperations() -> ClientZkProfileOperations {
        return ClientZkProfileOperations(serverPublicParams: GroupsV2Protos.serverPublicParams())
    }

    // MARK: - Update

    public func updateProfile(
        profileGivenName: OWSUserProfile.NameComponent?,
        profileFamilyName: OWSUserProfile.NameComponent?,
        profileBio: String?,
        profileBioEmoji: String?,
        profileAvatarMutation: VersionedProfileAvatarMutation,
        visibleBadgeIds: [String],
        profileKey: Aes256Key,
        authedAccount: AuthedAccount
    ) async throws -> VersionedProfileUpdate {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localAci = try tsAccountManager.localIdentifiersWithMaybeSneakyTransaction(authedAccount: authedAccount).aci
        let localProfileKey = try self.parseProfileKey(profileKey: profileKey)
        let commitment = try localProfileKey.getCommitment(userId: localAci)
        let commitmentData = commitment.serialize().asData

        func fetchLocalPaymentAddressProtoData() async -> Data? {
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                SSKEnvironment.shared.paymentsHelperRef.lastKnownLocalPaymentAddressProtoData(transaction: tx)
            }
        }

        let profilePaymentAddressData: Data? = await {
            guard
                SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled,
                !SSKEnvironment.shared.paymentsHelperRef.isKillSwitchActive
            else {
                return nil
            }
            guard
                let addressProtoData = await fetchLocalPaymentAddressProtoData(),
                addressProtoData.count > 0
            else {
                owsFailDebug("Payments enabled, but paymentAddress is missing or empty.")
                return nil
            }
            var result = Data()
            result.append(UInt32(addressProtoData.count).littleEndianData)
            result.append(addressProtoData)
            return result
        }()

        let nameValue: ProfileValue? = try {
            guard let profileGivenName else {
                return nil
            }
            return try OWSUserProfile.encrypt(
                givenName: profileGivenName,
                familyName: profileFamilyName,
                profileKey: profileKey
            )
        }()

        func encryptOptionalData(_ value: Data?, paddedLengths: [Int]) throws -> ProfileValue? {
            guard let value, !value.isEmpty else {
                return nil
            }
            return try OWSUserProfile.encrypt(data: value, profileKey: profileKey, paddedLengths: paddedLengths)
        }

        func encryptOptionalString(_ value: String?, paddedLengths: [Int]) throws -> ProfileValue? {
            guard let value, !value.isEmpty else {
                return nil
            }
            guard let stringData = value.data(using: .utf8) else {
                owsFailDebug("Invalid value.")
                return nil
            }
            return try encryptOptionalData(stringData, paddedLengths: paddedLengths)
        }

        func encryptBoolean(_ value: Bool) throws -> ProfileValue {
            let encodedValue = Data([value ? 1 : 0])
            let encryptedData = try OWSUserProfile.encrypt(profileData: encodedValue, profileKey: profileKey)
            return ProfileValue(encryptedData: encryptedData)
        }

        let bioValue = try encryptOptionalString(profileBio, paddedLengths: [128, 254, 512])
        let bioEmojiValue = try encryptOptionalString(profileBioEmoji, paddedLengths: [32])
        let paymentAddressValue = try encryptOptionalData(profilePaymentAddressData, paddedLengths: [554])
        let phoneNumberSharingValue = try encryptBoolean(SSKEnvironment.shared.databaseStorageRef.read { tx in
            SSKEnvironment.shared.udManagerRef.phoneNumberSharingMode(tx: tx.asV2Read).orDefault == .everybody
        })

        let profileKeyVersion = try localProfileKey.getProfileKeyVersion(userId: localAci)
        let profileKeyVersionString = try profileKeyVersion.asHexadecimalString()

        let hasAvatar: Bool
        let sameAvatar: Bool
        switch profileAvatarMutation {
        case .keepAvatar:
            hasAvatar = true
            sameAvatar = true
        case .clearAvatar:
            hasAvatar = false
            sameAvatar = false
        case .changeAvatar:
            hasAvatar = true
            sameAvatar = false
        }

        let request = OWSRequestFactory.setVersionedProfileRequest(
            name: nameValue,
            bio: bioValue,
            bioEmoji: bioEmojiValue,
            hasAvatar: hasAvatar,
            sameAvatar: sameAvatar,
            paymentAddress: paymentAddressValue,
            phoneNumberSharing: phoneNumberSharingValue,
            visibleBadgeIds: visibleBadgeIds,
            version: profileKeyVersionString,
            commitment: commitmentData,
            auth: authedAccount.chatServiceAuth
        )
        let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)

        let avatarUrlPath: OptionalChange<String?>
        switch profileAvatarMutation {
        case .keepAvatar:
            avatarUrlPath = .noChange
        case .clearAvatar:
            avatarUrlPath = .setTo(nil)
        case .changeAvatar(let avatarData):
            let encryptedAvatarData = try OWSUserProfile.encrypt(profileData: avatarData, profileKey: profileKey)
            avatarUrlPath = .setTo(try await uploadAvatar(
                formResponseData: response.responseBodyData,
                encryptedAvatarData: encryptedAvatarData
            ))
        }

        return VersionedProfileUpdate(avatarUrlPath: avatarUrlPath)
    }

    private func uploadAvatar(formResponseData: Data?, encryptedAvatarData: Data) async throws -> String {
        guard
            let formResponseData,
            let uploadForm = try? JSONDecoder().decode(Upload.CDN0.Form.self, from: formResponseData)
        else {
            throw OWSAssertionError("Could not parse response.")
        }
        return try await Upload.CDN0.upload(data: encryptedAvatarData, uploadForm: uploadForm)
    }

    // MARK: - Get

    public func versionedProfileRequest(
        for aci: Aci,
        profileKey: ProfileKey,
        shouldRequestCredential: Bool,
        udAccessKey: SMKUDAccessKey?,
        auth: ChatServiceAuth
    ) throws -> VersionedProfileRequest {
        // We need to request a credential if we don't have a valid one already.
        var requestContext: ProfileKeyCredentialRequestContext?
        if shouldRequestCredential {
            requestContext = try self.clientZkProfileOperations().createProfileKeyCredentialRequestContext(
                userId: aci,
                profileKey: profileKey
            )
        }

        return VersionedProfileRequest(
            aci: aci,
            request: OWSRequestFactory.getVersionedProfileRequest(
                aci: aci,
                profileKeyVersion: try profileKey.getProfileKeyVersion(userId: aci).asHexadecimalString(),
                credentialRequest: try requestContext?.getRequest().serialize().asData,
                udAccessKey: udAccessKey,
                auth: auth
            ),
            profileKey: profileKey,
            requestContext: requestContext
        )
    }

    // MARK: -

    public func parseProfileKey(profileKey: Aes256Key) throws -> ProfileKey {
        let profileKeyData: Data = profileKey.keyData
        let profileKeyDataBytes = [UInt8](profileKeyData)
        return try ProfileKey(contents: profileKeyDataBytes)
    }

    public func didFetchProfile(profile: SignalServiceProfile, profileRequest: VersionedProfileRequest) async {
        do {
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
            let clientZkProfileOperations = self.clientZkProfileOperations()
            let profileKeyCredential = try clientZkProfileOperations.receiveExpiringProfileKeyCredential(
                profileKeyCredentialRequestContext: requestContext,
                profileKeyCredentialResponse: credentialResponse
            )

            guard profile.serviceId == profileRequest.aci else {
                throw OWSAssertionError("Missing ACI.")
            }

            try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx throws in
                guard let currentProfileKey = SSKEnvironment.shared.profileManagerRef.profileKey(for: SignalServiceAddress(profileRequest.aci), transaction: tx) else {
                    throw OWSAssertionError("Missing profile key in database.")
                }

                guard profileRequest.profileKey.serialize().asData == currentProfileKey.keyData else {
                    Logger.warn("Profile key for versioned profile fetch does not match current profile key.")
                    return
                }

                try CredentialStore.setCredential(profileKeyCredential, for: profileRequest.aci, transaction: tx)
            }
        } catch {
            owsFailDebug("Invalid credential: \(error).")
            return
        }
    }

    // MARK: - Credentials

    public func validProfileKeyCredential(
        for aci: Aci,
        transaction: SDSAnyReadTransaction
    ) throws -> ExpiringProfileKeyCredential? {
        try CredentialStore.getValidCredential(for: aci, transaction: transaction)
    }

    @objc(clearProfileKeyCredentialForServiceId:transaction:)
    public func clearProfileKeyCredential(
        for aci: AciObjC,
        transaction: SDSAnyWriteTransaction
    ) {
        CredentialStore.removeValue(for: aci.wrappedAciValue, transaction: transaction)
    }

    public func clearProfileKeyCredentials(transaction: SDSAnyWriteTransaction) {
        CredentialStore.removeAll(transaction: transaction)
    }

    public func clearProfileKeyCredentials(tx: DBWriteTransaction) {
        clearProfileKeyCredentials(transaction: SDSDB.shimOnlyBridge(tx))
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
