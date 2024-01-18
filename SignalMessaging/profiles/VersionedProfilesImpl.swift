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

        private static func storeKey(for aci: Aci) -> String {
            return aci.serviceIdUppercaseString
        }

        static func dropDeprecatedCredentialsIfNecessary(transaction: SDSAnyWriteTransaction) {
            deprecatedCredentialStore.removeAll(transaction: transaction)
        }

        static func hasValidCredential(
            for aci: Aci,
            transaction: SDSAnyReadTransaction
        ) throws -> Bool {
            try getValidCredential(for: aci, transaction: transaction) != nil
        }

        static func getValidCredential(
            for aci: Aci,
            transaction: SDSAnyReadTransaction
        ) throws -> ExpiringProfileKeyCredential? {
            guard let credentialData = expiringCredentialStore.getData(
                storeKey(for: aci),
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
                Logger.info("Found expired credential for serviceId \(aci)")
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
                transaction: transaction
            )
        }

        static func removeValue(for aci: Aci, transaction: SDSAnyWriteTransaction) {
            expiringCredentialStore.removeValue(forKey: storeKey(for: aci), transaction: transaction)
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
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let localAci = try tsAccountManager.localIdentifiersWithMaybeSneakyTransaction(authedAccount: authedAccount).aci
        let localProfileKey = try self.parseProfileKey(profileKey: profileKey)
        let commitment = try localProfileKey.getCommitment(userId: localAci)
        let commitmentData = commitment.serialize().asData

        func fetchLocalPaymentAddressProtoData() async -> Data? {
            await databaseStorage.awaitableWrite { tx in
                Self.paymentsHelper.lastKnownLocalPaymentAddressProtoData(transaction: tx)
            }
        }

        let profilePaymentAddressData: Data? = await {
            guard
                paymentsHelper.arePaymentsEnabled,
                !paymentsHelper.isKillSwitchActive,
                let addressProtoData = await fetchLocalPaymentAddressProtoData()
            else {
                return nil
            }
            var result = Data()
            var littleEndian: UInt32 = CFSwapInt32HostToLittle(UInt32(addressProtoData.count))
            withUnsafePointer(to: &littleEndian) { pointer in
                result.append(UnsafeBufferPointer(start: pointer, count: 1))
            }
            result.append(addressProtoData)
            return result
        }()

        let nameValue: ProfileValue? = try {
            guard let profileGivenName else {
                return nil
            }
            var nameComponents = PersonNameComponents()
            nameComponents.givenName = profileGivenName
            nameComponents.familyName = profileFamilyName

            guard let encryptedValue = OWSUserProfile.encrypt(
                profileNameComponents: nameComponents,
                profileKey: profileKey
            ) else {
                throw OWSAssertionError("Could not encrypt profile name.")
            }
            return encryptedValue
        }()

        func encryptOptionalData(_ value: Data?, paddedLengths: [Int]) throws -> ProfileValue? {
            guard let value, !value.isEmpty else {
                return nil
            }
            guard let encryptedValue = OWSUserProfile.encrypt(
                data: value,
                profileKey: profileKey,
                paddedLengths: paddedLengths
            ) else {
                throw OWSAssertionError("Could not encrypt profile value.")
            }
            return encryptedValue
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
            guard let encryptedData = OWSUserProfile.encrypt(profileData: encodedValue, profileKey: profileKey) else {
                throw OWSAssertionError("Couldn't encrypt profie value.")
            }
            return ProfileValue(encryptedData: encryptedData)
        }

        let bioValue = try encryptOptionalString(profileBio, paddedLengths: [128, 254, 512])
        let bioEmojiValue = try encryptOptionalString(profileBioEmoji, paddedLengths: [32])
        let paymentAddressValue = try encryptOptionalData(profilePaymentAddressData, paddedLengths: [554])
        let phoneNumberSharingValue = try encryptBoolean(databaseStorage.read { tx in
            udManager.phoneNumberSharingMode(tx: tx).orDefault == .everybody
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
        let response = try await networkManager.makePromise(request: request).awaitable()

        let avatarUrlPath: OptionalChange<String?>
        switch profileAvatarMutation {
        case .keepAvatar:
            avatarUrlPath = .noChange
        case .clearAvatar:
            avatarUrlPath = .setTo(nil)
        case .changeAvatar(let avatarData):
            guard let encryptedAvatarData = OWSUserProfile.encrypt(profileData: avatarData, profileKey: profileKey) else {
                throw OWSAssertionError("Could not encrypt profile avatar.")
            }
            avatarUrlPath = .setTo(try await uploadAvatar(
                formResponse: response.responseBodyJson,
                encryptedAvatarData: encryptedAvatarData
            ))
        }

        return VersionedProfileUpdate(avatarUrlPath: avatarUrlPath)
    }

    private func uploadAvatar(formResponse: Any?, encryptedAvatarData: Data) async throws -> String {
        guard let formResponse = formResponse as? [AnyHashable: Any] else {
            throw OWSAssertionError("Unexpected response.")
        }
        guard let uploadForm = OWSUploadFormV2.parseDictionary(formResponse) else {
            throw OWSAssertionError("Could not parse response.")
        }
        return try await OWSUpload.uploadV2(data: encryptedAvatarData, uploadForm: uploadForm, uploadUrlPath: "").awaitable()
    }

    // MARK: - Get

    public func versionedProfileRequest(
        for aci: Aci,
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
                for: SignalServiceAddress(aci),
                transaction: transaction)
            else {
                return
            }
            profileKeyForRequest = profileKeyForAddress
            let profileKey: ProfileKey = try self.parseProfileKey(profileKey: profileKeyForAddress)
            let profileKeyVersion = try profileKey.getProfileKeyVersion(userId: aci)
            profileKeyVersionArg = try profileKeyVersion.asHexadecimalString()

            // We need to request a credential if we don't have a valid one already.
            if !(try CredentialStore.hasValidCredential(for: aci, transaction: transaction)) {
                let clientZkProfileOperations = try self.clientZkProfileOperations()
                let context = try clientZkProfileOperations.createProfileKeyCredentialRequestContext(
                    userId: aci,
                    profileKey: profileKey
                )
                requestContext = context
                let credentialRequest = try context.getRequest()
                credentialRequestArg = credentialRequest.serialize().asData
            }
        }

        let request = OWSRequestFactory.getVersionedProfileRequest(
            aci: AciObjC(aci),
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

    public func didFetchProfile(profile: SignalServiceProfile, profileRequest: VersionedProfileRequest) async {
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

            // ACI TODO: This must be an Aci, but the compiler loses type information. Fix that.
            guard let aci = profile.serviceId as? Aci else {
                throw OWSAssertionError("Missing ACI.")
            }

            try await databaseStorage.awaitableWrite { tx throws in
                guard let currentProfileKey = self.profileManager.profileKey(for: SignalServiceAddress(aci), transaction: tx) else {
                    throw OWSAssertionError("Missing profile key in database.")
                }

                guard requestProfileKey.keyData == currentProfileKey.keyData else {
                    Logger.warn("Profile key for versioned profile fetch does not match current profile key.")
                    return
                }

                try CredentialStore.setCredential(profileKeyCredential, for: aci, transaction: tx)
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
