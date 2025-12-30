//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
public import LibSignalClient

public enum ProfileRequestError: Error {
    case notAuthorized
    case notFound
    case rateLimit
}

// MARK: -

public class ProfileFetcherJob {
    private let serviceId: ServiceId
    private let groupIdContext: GroupIdentifier?
    private let mustFetchNewCredential: Bool
    private let authedAccount: AuthedAccount

    private let accountChecker: AccountChecker
    private let db: any DB
    private let disappearingMessagesConfigurationStore: any DisappearingMessagesConfigurationStore
    private let identityManager: any OWSIdentityManager
    private let paymentsHelper: any PaymentsHelper
    private let profileManager: any ProfileManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let syncManager: any SyncManagerProtocol
    private let tsAccountManager: any TSAccountManager
    private let udManager: any OWSUDManager
    private let versionedProfiles: any VersionedProfiles

    init(
        serviceId: ServiceId,
        groupIdContext: GroupIdentifier?,
        mustFetchNewCredential: Bool,
        authedAccount: AuthedAccount,
        accountChecker: AccountChecker,
        db: any DB,
        disappearingMessagesConfigurationStore: any DisappearingMessagesConfigurationStore,
        identityManager: any OWSIdentityManager,
        paymentsHelper: any PaymentsHelper,
        profileManager: any ProfileManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        syncManager: any SyncManagerProtocol,
        tsAccountManager: any TSAccountManager,
        udManager: any OWSUDManager,
        versionedProfiles: any VersionedProfiles,
    ) {
        self.serviceId = serviceId
        self.groupIdContext = groupIdContext
        self.mustFetchNewCredential = mustFetchNewCredential
        self.authedAccount = authedAccount
        self.accountChecker = accountChecker
        self.db = db
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
        self.identityManager = identityManager
        self.paymentsHelper = paymentsHelper
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.syncManager = syncManager
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
        self.versionedProfiles = versionedProfiles
    }

    // MARK: -

    public func run() async throws -> FetchedProfile {
        let backgroundTask = addBackgroundTask()
        defer {
            backgroundTask.end()
        }

        let localIdentifiers = try tsAccountManager.localIdentifiersWithMaybeSneakyTransaction(authedAccount: authedAccount)
        do {
            let fetchedProfile = try await requestProfile(localIdentifiers: localIdentifiers)
            try await updateProfile(fetchedProfile: fetchedProfile, localIdentifiers: localIdentifiers)
            return fetchedProfile
        } catch ProfileRequestError.notFound {
            let isRegistered = db.read { tx in
                return recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx)?.isRegistered == true
            }
            if isRegistered {
                try? await accountChecker.checkIfAccountExists(serviceId: serviceId)
            }
            throw ProfileRequestError.notFound
        }
    }

    private func requestProfile(localIdentifiers: LocalIdentifiers) async throws -> FetchedProfile {
        do {
            return try await Retry.performWithBackoff(maxAttempts: 3) {
                return try await requestProfileAttempt(localIdentifiers: localIdentifiers)
            }
        } catch where error.httpStatusCode == 401 {
            throw ProfileRequestError.notAuthorized
        } catch where error.httpStatusCode == 404 {
            throw ProfileRequestError.notFound
        } catch where error.httpStatusCode == 429 {
            throw ProfileRequestError.rateLimit
        }
    }

    private func requestProfileAttempt(localIdentifiers: LocalIdentifiers) async throws -> FetchedProfile {
        let serviceId = self.serviceId
        let versionedProfiles = self.versionedProfiles

        let versionedFetchParameters = try db.read { tx in
            return try self.readVersionedFetchParameters(localIdentifiers: localIdentifiers, tx: tx)
        }
        if let versionedFetchParameters {
            let versionedProfileRequest = try versionedProfiles.versionedProfileRequest(
                for: versionedFetchParameters.aci,
                profileKey: versionedFetchParameters.profileKey,
                shouldRequestCredential: versionedFetchParameters.shouldRequestCredential,
                udAccessKey: versionedFetchParameters.auth?.key,
                auth: self.authedAccount.chatServiceAuth,
            )
            do {
                let response = try await makeRequest(versionedProfileRequest.request)
                guard let params = response.responseBodyParamParser else {
                    throw OWSAssertionError("Missing or invalid JSON!")
                }
                let profile = try SignalServiceProfile.fromResponse(
                    serviceId: serviceId,
                    params: params,
                )

                await versionedProfiles.didFetchProfile(profile: profile, profileRequest: versionedProfileRequest)

                return FetchedProfile(profile: profile, profileKey: versionedProfileRequest.profileKey)
            } catch where versionedFetchParameters.auth != nil && error.httpStatusCode == 401 {
                // Fall back to an unversioned fetch...
            }
        }

        if self.mustFetchNewCredential {
            throw ProfileFetcherError.couldNotFetchCredential
        }

        // If we can't fetch a versioned profile, or if we run into an auth error
        // when using an access key, fall back to an unversioned profile fetch.

        let endorsement = { () -> GroupSendFullTokenBuilder? in
            guard let groupId = self.groupIdContext else {
                return nil
            }
            do {
                return try db.read { tx in try readGroupSendEndorsement(groupId: groupId, tx: tx) }
            } catch {
                owsFailDebug("Couldn't fetch GSE for profile fetch: \(error)")
                return nil
            }
        }()

        let requestMaker = RequestMaker(
            label: "Profile Fetch",
            serviceId: serviceId,
            canUseStoryAuth: false,
            accessKey: nil,
            endorsement: endorsement,
            authedAccount: self.authedAccount,
            options: [.allowIdentifiedFallback, .isProfileFetch],
        )

        let result = try await requestMaker.makeRequest { sealedSenderAuth in
            return OWSRequestFactory.getUnversionedProfileRequest(
                serviceId: serviceId,
                auth: sealedSenderAuth.map({ .sealedSender($0) }) ?? .identified(self.authedAccount.chatServiceAuth),
            )
        }

        guard let params = result.response.responseBodyParamParser else {
            throw OWSAssertionError("Missing or invalid JSON!")
        }
        let profile = try SignalServiceProfile.fromResponse(
            serviceId: serviceId,
            params: params,
        )

        return FetchedProfile(profile: profile, profileKey: nil)
    }

    private struct VersionedFetchParameters {
        var aci: Aci
        var profileKey: ProfileKey
        var shouldRequestCredential: Bool
        var auth: OWSUDAccess?
    }

    private func readVersionedFetchParameters(
        localIdentifiers: LocalIdentifiers,
        tx: DBReadTransaction,
    ) throws -> VersionedFetchParameters? {
        let _versionedFetchParameters = Self._readVersionedFetchParameters(
            serviceId: self.serviceId,
            localIdentifiers: localIdentifiers,
            profileManager: self.profileManager,
            udManager: self.udManager,
            tx: tx,
        )
        guard let _versionedFetchParameters else {
            return nil
        }
        return VersionedFetchParameters(
            aci: _versionedFetchParameters.aci,
            profileKey: _versionedFetchParameters.profileKey,
            shouldRequestCredential: try (
                self.mustFetchNewCredential
                    || self.versionedProfiles.validProfileKeyCredential(for: _versionedFetchParameters.aci, transaction: tx) == nil
            ),
            auth: _versionedFetchParameters.auth,
        )
    }

    private struct _VersionedFetchParameters {
        var aci: Aci
        var profileKey: ProfileKey
        var auth: OWSUDAccess?
    }

    private static func _readVersionedFetchParameters(
        serviceId: ServiceId,
        localIdentifiers: LocalIdentifiers,
        profileManager: any ProfileManager,
        udManager: any OWSUDManager,
        tx: DBReadTransaction,
    ) -> _VersionedFetchParameters? {
        switch serviceId.concreteType {
        case .pni:
            return nil
        case .aci(let aci):
            let profileKey = profileManager.userProfile(
                for: SignalServiceAddress(aci),
                tx: tx,
            )?.profileKey
            guard let profileKey else {
                return nil
            }
            let auth: OWSUDAccess?
            if localIdentifiers.aci == aci {
                // Don't use UD for "self" profile fetches.
                auth = nil
            } else if let udAccess = udManager.udAccess(for: aci, tx: tx) {
                auth = udAccess
            } else {
                // We probably have the wrong profile key. Fall back to an unversioned
                // fetch; that'll allow us to check if we know the profile key or not.
                return nil
            }

            return _VersionedFetchParameters(
                aci: aci,
                profileKey: ProfileKey(profileKey),
                auth: auth,
            )
        }
    }

    public static func canTryToFetchCredential(
        serviceId: ServiceId,
        localIdentifiers: LocalIdentifiers,
        profileManager: any ProfileManager,
        udManager: any OWSUDManager,
        tx: DBReadTransaction,
    ) -> Bool {
        return _readVersionedFetchParameters(
            serviceId: serviceId,
            localIdentifiers: localIdentifiers,
            profileManager: profileManager,
            udManager: udManager,
            tx: tx,
        ) != nil
    }

    private func readGroupSendEndorsement(groupId: GroupIdentifier, tx: DBReadTransaction) throws -> GroupSendFullTokenBuilder? {
        guard let aci = serviceId as? Aci else {
            return nil
        }
        let threadStore = DependenciesBridge.shared.threadStore
        guard let groupThread = threadStore.fetchGroupThread(groupId: groupId, tx: tx) else {
            throw OWSAssertionError("Can't find group that should exist.")
        }
        guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Can't access v2 model for group with v2 identifier.")
        }
        let endorsementStore = DependenciesBridge.shared.groupSendEndorsementStore
        let combinedEndorsement = try endorsementStore.fetchCombinedEndorsement(groupThreadId: groupThread.sqliteRowId!, tx: tx)
        guard let combinedEndorsement else {
            // Perhaps we haven't fetched it or it expired.
            return nil
        }
        guard
            let recipient = recipientDatabaseTable.fetchRecipient(serviceId: aci, transaction: tx),
            let individualEndorsement = try endorsementStore.fetchIndividualEndorsement(
                groupThreadId: groupThread.sqliteRowId!,
                recipientId: recipient.id,
                tx: tx,
            )
        else {
            throw OWSAssertionError("Can't find GSE for group member that should have one.")
        }
        return GroupSendFullTokenBuilder(
            secretParams: try groupModel.secretParams(),
            expiration: combinedEndorsement.expiration,
            endorsement: try GroupSendEndorsement(contents: individualEndorsement.endorsement),
        )
    }

    private func makeRequest(_ request: TSRequest) async throws -> HTTPResponse {
        let networkManager = SSKEnvironment.shared.networkManagerRef
        return try await networkManager.asyncRequest(request)
    }

    private func updateProfile(
        fetchedProfile: FetchedProfile,
        localIdentifiers: LocalIdentifiers,
    ) async throws {
        await updateProfile(
            fetchedProfile: fetchedProfile,
            avatarDownloadResult: try await downloadAvatarIfNeeded(
                fetchedProfile,
                localIdentifiers: localIdentifiers,
            ),
            localIdentifiers: localIdentifiers,
        )
    }

    private struct AvatarDownloadResult {
        var remoteRelativePath: OptionalChange<String?>
        var localFileUrl: OptionalChange<URL?>
    }

    private func downloadAvatarIfNeeded(
        _ fetchedProfile: FetchedProfile,
        localIdentifiers: LocalIdentifiers,
    ) async throws -> AvatarDownloadResult {
        if localIdentifiers.contains(serviceId: fetchedProfile.profile.serviceId) {
            // Profile fetches NEVER touch the local user's avatar.
            return AvatarDownloadResult(remoteRelativePath: .noChange, localFileUrl: .noChange)
        }
        guard let profileKey = fetchedProfile.profileKey, fetchedProfile.decryptedProfile != nil else {
            // If we don't have a profile key for this user, or if the rest of their
            // encrypted profile wasn't valid, don't change their avatar because we
            // aren't changing their name.
            return AvatarDownloadResult(remoteRelativePath: .noChange, localFileUrl: .noChange)
        }
        guard let newAvatarUrlPath = fetchedProfile.profile.avatarUrlPath else {
            // If profile has no avatar, we don't need to download the avatar.
            return AvatarDownloadResult(remoteRelativePath: .setTo(nil), localFileUrl: .setTo(nil))
        }
        let profileAddress = SignalServiceAddress(fetchedProfile.profile.serviceId)
        let didAlreadyDownloadAvatar = db.read { tx -> Bool in
            let userProfile = profileManager.userProfile(for: profileAddress, tx: tx)
            guard let userProfile else {
                return false
            }
            return userProfile.avatarUrlPath == newAvatarUrlPath && userProfile.hasAvatarData()
        }
        if didAlreadyDownloadAvatar {
            return AvatarDownloadResult(remoteRelativePath: .noChange, localFileUrl: .noChange)
        }

        let shouldPreventDownload = db.read { tx -> Bool in
            SSKEnvironment.shared.contactManagerImplRef.shouldBlockAvatarDownload(
                address: profileAddress,
                tx: tx,
            )
        }

        if shouldPreventDownload {
            return AvatarDownloadResult(remoteRelativePath: .setTo(newAvatarUrlPath), localFileUrl: .setTo(nil))
        }

        let temporaryAvatarUrl: URL?
        do {
            temporaryAvatarUrl = try await profileManager.downloadAndDecryptAvatar(
                avatarUrlPath: newAvatarUrlPath,
                profileKey: profileKey,
            )
        } catch {
            Logger.warn("Error: \(error)")
            // Reaching this point with anything other than a network failure or
            // timeout should be very rare. It might reflect:
            //
            // * A race around rotating profile keys which would cause a decryption
            //   error.
            //
            // * An incomplete profile update (profile updated but avatar not uploaded
            //   afterward). This might be due to a race with an update that is in
            //   flight. We should eventually recover since profile updates are
            //   durable.
            temporaryAvatarUrl = nil
        }
        return AvatarDownloadResult(
            remoteRelativePath: .setTo(newAvatarUrlPath),
            localFileUrl: .setTo(temporaryAvatarUrl),
        )
    }

    private func updateProfile(
        fetchedProfile: FetchedProfile,
        avatarDownloadResult: AvatarDownloadResult,
        localIdentifiers: LocalIdentifiers,
    ) async {
        let profile = fetchedProfile.profile
        let serviceId = profile.serviceId

        await db.awaitableWrite { transaction in
            if let aci = serviceId as? Aci {
                self.updateUnidentifiedAccess(
                    aci: aci,
                    verifier: profile.unidentifiedAccessVerifier,
                    hasUnrestrictedAccess: profile.hasUnrestrictedUnidentifiedAccess,
                    tx: transaction,
                )
            }

            // First, we add ensure we have a copy of any new badge in our badge store
            let badgeModels = fetchedProfile.profile.badges.map { $0.1 }
            let persistedBadgeIds: [String] = badgeModels.compactMap {
                do {
                    try self.profileManager.badgeStore.createOrUpdateBadge($0, transaction: transaction)
                    return $0.id
                } catch {
                    owsFailDebug("Failed to save badgeId: \($0.id). \(error)")
                    return nil
                }
            }

            // Then, we update the profile. `profileBadges` will contain the badgeId of
            // badges in the badge store
            let profileBadgeMetadata = fetchedProfile.profile.badges
                .map { $0.0 }
                .filter { persistedBadgeIds.contains($0.badgeId) }

            let avatarFilename: OptionalChange<String?>
            do {
                avatarFilename = try OWSUserProfile.consumeTemporaryAvatarFileUrl(
                    avatarDownloadResult.localFileUrl,
                    tx: transaction,
                )
            } catch {
                Logger.warn("Couldn't move downloaded avatar: \(error)")
                avatarFilename = .noChange
            }

            if !localIdentifiers.contains(serviceId: serviceId) || localIdentifiers.aci == serviceId {
                self.profileManager.updateProfile(
                    address: OWSUserProfile.insertableAddress(serviceId: serviceId, localIdentifiers: localIdentifiers),
                    decryptedProfile: fetchedProfile.decryptedProfile,
                    avatarUrlPath: avatarDownloadResult.remoteRelativePath,
                    avatarFileName: avatarFilename,
                    profileBadges: profileBadgeMetadata,
                    lastFetchDate: Date(),
                    userProfileWriter: .profileFetch,
                    tx: transaction,
                )
            }

            self.updateCapabilitiesIfNeeded(
                serviceId: serviceId,
                fetchedCapabilities: fetchedProfile.profile.capabilities,
                localIdentifiers: localIdentifiers,
                tx: transaction,
            )

            if localIdentifiers.aci == serviceId {
                self.reconcileLocalProfileIfNeeded(fetchedProfile: fetchedProfile)
            }

            let identityManager = DependenciesBridge.shared.identityManager
            identityManager.saveIdentityKey(profile.identityKey, for: serviceId, tx: transaction)

            let paymentAddress = fetchedProfile.decryptedProfile?.paymentAddress(identityKey: fetchedProfile.identityKey)
            self.paymentsHelper.setArePaymentsEnabled(
                for: serviceId,
                hasPaymentsEnabled: paymentAddress != nil,
                transaction: transaction,
            )
        }
    }

    private func updateUnidentifiedAccess(
        aci: Aci,
        verifier: Data?,
        hasUnrestrictedAccess: Bool,
        tx: DBWriteTransaction,
    ) {
        let unidentifiedAccessMode: UnidentifiedAccessMode = {
            guard let verifier else {
                // If there is no verifier, at least one of this user's devices
                // do not support UD.
                return .disabled
            }

            if hasUnrestrictedAccess {
                return .unrestricted
            }

            guard let udAccessKey = udManager.udAccessKey(for: aci, tx: tx) else {
                return .disabled
            }

            let dataToVerify = Data(count: 32)
            let expectedVerifier = Data(HMAC<SHA256>.authenticationCode(for: dataToVerify, using: .init(data: udAccessKey.keyData)))
            guard expectedVerifier.ows_constantTimeIsEqual(to: verifier) else {
                return .disabled
            }

            return .enabled
        }()
        udManager.setUnidentifiedAccessMode(unidentifiedAccessMode, for: aci, tx: tx)
    }

    private func updateCapabilitiesIfNeeded(
        serviceId: ServiceId,
        fetchedCapabilities: SignalServiceProfile.Capabilities,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    ) {
        let registrationState = tsAccountManager.registrationState(tx: tx)

        var shouldSendProfileSync = false

        if
            localIdentifiers.aci == serviceId,
            fetchedCapabilities.dummyCapability
        {
            // Space to detect changes to our own capabilities, and run code
            // such as migrations in response.
            //
            // See comment on `dummyCapability`: it's always false, but lets us
            // keep this code around without the compiler complaining.
            shouldSendProfileSync = true
        }

        if
            shouldSendProfileSync,
            registrationState.isRegistered
        {
            /// If some capability is newly enabled, we want all devices to be aware.
            /// This would happen automatically the next time those devices
            /// fetch the local profile, but we'd prefer it happen ASAP!
            syncManager.sendFetchLatestProfileSyncMessage(tx: tx)
        }
    }

    private func reconcileLocalProfileIfNeeded(fetchedProfile: FetchedProfile) {
        guard CurrentAppContext().isMainApp else {
            return
        }
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice else {
            return
        }
        DependenciesBridge.shared.localProfileChecker.didFetchLocalProfile(LocalProfileChecker.RemoteProfile(
            avatarUrlPath: fetchedProfile.profile.avatarUrlPath,
            decryptedProfile: fetchedProfile.decryptedProfile,
        ))
    }

    private func addBackgroundTask() -> OWSBackgroundTask {
        return OWSBackgroundTask(label: "\(#function)", completionBlock: { [weak self] status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }
            guard self != nil else {
                return
            }
            Logger.error("background task time ran out before profile fetch completed.")
        })
    }
}

// MARK: -

public struct DecryptedProfile {
    public let nameComponents: Result<(givenName: String, familyName: String?)?, Error>
    public let bio: Result<String?, Error>
    public let bioEmoji: Result<String?, Error>
    public let paymentAddressData: Result<Data?, Error>
    public let phoneNumberSharing: Result<Bool?, Error>
}

// MARK: -

public struct FetchedProfile {
    let profile: SignalServiceProfile
    let profileKey: ProfileKey?
    public let decryptedProfile: DecryptedProfile?
    public let identityKey: IdentityKey

    init(profile: SignalServiceProfile, profileKey: ProfileKey?) {
        self.profile = profile
        self.profileKey = profileKey
        self.decryptedProfile = Self.decrypt(profile: profile, profileKey: profileKey)
        self.identityKey = profile.identityKey
    }

    private static func decrypt(profile: SignalServiceProfile, profileKey: ProfileKey?) -> DecryptedProfile? {
        guard let profileKey else {
            return nil
        }
        let hasAnyField: Bool = (
            profile.profileNameEncrypted != nil
                || profile.bioEncrypted != nil
                || profile.bioEmojiEncrypted != nil
                || profile.paymentAddressEncrypted != nil
                || profile.phoneNumberSharingEncrypted != nil,
        )
        guard hasAnyField else {
            return nil
        }
        let nameComponents = Result { try profile.profileNameEncrypted.map {
            try OWSUserProfile.decrypt(profileNameData: $0, profileKey: profileKey)
        }}
        let bio = Result { try profile.bioEncrypted.flatMap {
            try OWSUserProfile.decrypt(profileStringData: $0, profileKey: profileKey)
        }}
        let bioEmoji = Result { try profile.bioEmojiEncrypted.flatMap {
            try OWSUserProfile.decrypt(profileStringData: $0, profileKey: profileKey)
        }}
        let paymentAddressData = Result { try profile.paymentAddressEncrypted.map {
            try OWSUserProfile.decrypt(profileData: $0, profileKey: profileKey)
        }}
        let phoneNumberSharing = Result { try profile.phoneNumberSharingEncrypted.map {
            try OWSUserProfile.decrypt(profileBooleanData: $0, profileKey: profileKey)
        }}
        return DecryptedProfile(
            nameComponents: nameComponents,
            bio: bio,
            bioEmoji: bioEmoji,
            paymentAddressData: paymentAddressData,
            phoneNumberSharing: phoneNumberSharing,
        )
    }
}

// MARK: -

public extension DecryptedProfile {
    func paymentAddress(identityKey: IdentityKey) -> TSPaymentAddress? {
        do {
            guard var paymentAddressData = try paymentAddressData.get() else {
                return nil
            }
            guard let (dataLength, dataLengthCount) = UInt32.from(littleEndianData: paymentAddressData) else {
                owsFailDebug("couldn't find paymentAddressData's length")
                return nil
            }
            paymentAddressData = paymentAddressData.dropFirst(dataLengthCount)
            paymentAddressData = paymentAddressData.prefix(Int(dataLength))
            guard paymentAddressData.count == dataLength else {
                owsFailDebug("paymentAddressData is too short")
                return nil
            }
            let proto = try SSKProtoPaymentAddress(serializedData: paymentAddressData)
            return try TSPaymentAddress.fromProto(proto, identityKey: identityKey)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }
}
