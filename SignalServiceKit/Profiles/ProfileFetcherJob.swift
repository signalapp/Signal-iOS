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
    private let authedAccount: AuthedAccount

    private let db: any DB
    private let disappearingMessagesConfigurationStore: any DisappearingMessagesConfigurationStore
    private let identityManager: any OWSIdentityManager
    private let paymentsHelper: any PaymentsHelper
    private let profileManager: any ProfileManager
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let recipientManager: any SignalRecipientManager
    private let recipientMerger: any RecipientMerger
    private let storageServiceRecordIkmCapabilityStore: any StorageServiceRecordIkmCapabilityStore
    private let storageServiceRecordIkmMigrator: any StorageServiceRecordIkmMigrator
    private let syncManager: any SyncManagerProtocol
    private let tsAccountManager: any TSAccountManager
    private let udManager: any OWSUDManager
    private let versionedProfiles: any VersionedProfiles

    init(
        serviceId: ServiceId,
        authedAccount: AuthedAccount,
        db: any DB,
        disappearingMessagesConfigurationStore: any DisappearingMessagesConfigurationStore,
        identityManager: any OWSIdentityManager,
        paymentsHelper: any PaymentsHelper,
        profileManager: any ProfileManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        recipientManager: any SignalRecipientManager,
        recipientMerger: any RecipientMerger,
        storageServiceRecordIkmCapabilityStore: any StorageServiceRecordIkmCapabilityStore,
        storageServiceRecordIkmMigrator: any StorageServiceRecordIkmMigrator,
        syncManager: any SyncManagerProtocol,
        tsAccountManager: any TSAccountManager,
        udManager: any OWSUDManager,
        versionedProfiles: any VersionedProfiles
    ) {
        self.serviceId = serviceId
        self.authedAccount = authedAccount
        self.db = db
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
        self.identityManager = identityManager
        self.paymentsHelper = paymentsHelper
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientManager = recipientManager
        self.recipientMerger = recipientMerger
        self.storageServiceRecordIkmCapabilityStore = storageServiceRecordIkmCapabilityStore
        self.storageServiceRecordIkmMigrator = storageServiceRecordIkmMigrator
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
            await db.awaitableWrite { [serviceId] tx in
                let recipient = self.recipientDatabaseTable.fetchRecipient(serviceId: serviceId, transaction: tx)
                guard let recipient else {
                    return
                }
                self.recipientManager.markAsUnregisteredAndSave(
                    recipient,
                    unregisteredAt: .now,
                    shouldUpdateStorageService: true,
                    tx: tx
                )
                self.recipientMerger.splitUnregisteredRecipientIfNeeded(
                    localIdentifiers: localIdentifiers,
                    unregisteredRecipient: recipient,
                    tx: tx
                )
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

        let (profileKey, udAccess, shouldRequestCredential) = try db.read { (tx) -> (ProfileKey?, OWSUDAccess?, Bool) in
            switch serviceId.concreteType {
            case .aci(let aci):
                let profileKey = (self.profileManager.userProfile(
                    for: SignalServiceAddress(aci),
                    tx: SDSDB.shimOnlyBridge(tx)
                )?.profileKey).map(ProfileKey.init(_:))
                let udAccess: OWSUDAccess?
                if localIdentifiers.aci == aci {
                    // Don't use UD for "self" profile fetches.
                    udAccess = nil
                } else {
                    udAccess = udManager.udAccess(for: aci, tx: SDSDB.shimOnlyBridge(tx))
                }
                let profileKeyCredential = try versionedProfiles.validProfileKeyCredential(for: aci, transaction: SDSDB.shimOnlyBridge(tx))
                return (profileKey, udAccess, profileKeyCredential == nil)
            case .pni(_):
                return (nil, nil, false)
            }
        }

        let endorsement: GroupSendFullTokenBuilder?
        if profileKey == nil {
            // TODO: GSE: Fetch unversioned profiles using GSEs.
            endorsement = nil
        } else {
            endorsement = nil
        }

        let requestMaker = RequestMaker(
            label: "Profile Fetch",
            serviceId: serviceId,
            canUseStoryAuth: false,
            accessKey: udAccess,
            endorsement: endorsement,
            authedAccount: self.authedAccount,
            options: [.allowIdentifiedFallback, .isProfileFetch]
        )

        var versionedProfileRequest: VersionedProfileRequest?
        let result = try await requestMaker.makeRequest { sealedSenderAuth in
            if let aci = serviceId as? Aci, let profileKey {
                let udAccessKey: SMKUDAccessKey?
                switch sealedSenderAuth {
                case .story:
                    owsFail("Can't use story auth.")
                case .accessKey(let _udAccessKey):
                    udAccessKey = _udAccessKey
                case .endorsement:
                    owsFail("Can't have endorsement if we have a profile key.")
                case .none:
                    udAccessKey = nil
                }
                let request = try versionedProfiles.versionedProfileRequest(
                    for: aci,
                    profileKey: profileKey,
                    shouldRequestCredential: shouldRequestCredential,
                    udAccessKey: udAccessKey,
                    auth: self.authedAccount.chatServiceAuth
                )
                versionedProfileRequest = request
                return request.request
            } else {
                return OWSRequestFactory.getUnversionedProfileRequest(
                    serviceId: serviceId,
                    sealedSenderAuth: sealedSenderAuth,
                    auth: self.authedAccount.chatServiceAuth
                )
            }
        }

        let profile: SignalServiceProfile = try .fromResponse(
            serviceId: serviceId,
            responseObject: result.responseJson
        )

        // If we sent a versioned request, store the credential that was returned.
        if let versionedProfileRequest {
            // This calls databaseStorage.write { }
            await versionedProfiles.didFetchProfile(profile: profile, profileRequest: versionedProfileRequest)
        }

        return FetchedProfile(profile: profile, profileKey: profileKey)
    }

    private func updateProfile(
        fetchedProfile: FetchedProfile,
        localIdentifiers: LocalIdentifiers
    ) async throws {
        await updateProfile(
            fetchedProfile: fetchedProfile,
            avatarDownloadResult: try await downloadAvatarIfNeeded(
                fetchedProfile,
                localIdentifiers: localIdentifiers
            ),
            localIdentifiers: localIdentifiers
        )
    }

    private struct AvatarDownloadResult {
        var remoteRelativePath: OptionalChange<String?>
        var localFileUrl: OptionalChange<URL?>
    }

    private func downloadAvatarIfNeeded(
        _ fetchedProfile: FetchedProfile,
        localIdentifiers: LocalIdentifiers
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
            let userProfile = profileManager.userProfile(for: profileAddress, tx: SDSDB.shimOnlyBridge(tx))
            guard let userProfile else {
                return false
            }
            return userProfile.avatarUrlPath == newAvatarUrlPath && userProfile.hasAvatarData()
        }
        if didAlreadyDownloadAvatar {
            return AvatarDownloadResult(remoteRelativePath: .noChange, localFileUrl: .noChange)
        }
        let temporaryAvatarUrl: URL?
        do {
            temporaryAvatarUrl = try await profileManager.downloadAndDecryptAvatar(
                avatarUrlPath: newAvatarUrlPath,
                profileKey: profileKey
            )
        } catch {
            Logger.warn("Error: \(error)")
            if error.isNetworkFailureOrTimeout, localIdentifiers.contains(serviceId: fetchedProfile.profile.serviceId) {
                // Fetches and local profile updates can conflict. To avoid these conflicts
                // we treat "partial" profile fetches (where we download the profile but
                // not the associated avatar) as failures.
                throw SSKUnretryableError.partialLocalProfileFetch
            }
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
            localFileUrl: .setTo(temporaryAvatarUrl)
        )
    }

    private func updateProfile(
        fetchedProfile: FetchedProfile,
        avatarDownloadResult: AvatarDownloadResult,
        localIdentifiers: LocalIdentifiers
    ) async {
        let profile = fetchedProfile.profile
        let serviceId = profile.serviceId

        await db.awaitableWrite { transaction in
            self.updateUnidentifiedAccess(
                serviceId: serviceId,
                verifier: profile.unidentifiedAccessVerifier,
                hasUnrestrictedAccess: profile.hasUnrestrictedUnidentifiedAccess,
                tx: transaction
            )

            // First, we add ensure we have a copy of any new badge in our badge store
            let badgeModels = fetchedProfile.profile.badges.map { $0.1 }
            let persistedBadgeIds: [String] = badgeModels.compactMap {
                do {
                    try self.profileManager.badgeStore.createOrUpdateBadge($0, transaction: SDSDB.shimOnlyBridge(transaction))
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
                    tx: SDSDB.shimOnlyBridge(transaction)
                )
            } catch {
                Logger.warn("Couldn't move downloaded avatar: \(error)")
                avatarFilename = .noChange
            }

            self.profileManager.updateProfile(
                address: OWSUserProfile.insertableAddress(serviceId: serviceId, localIdentifiers: localIdentifiers),
                decryptedProfile: fetchedProfile.decryptedProfile,
                avatarUrlPath: avatarDownloadResult.remoteRelativePath,
                avatarFileName: avatarFilename,
                profileBadges: profileBadgeMetadata,
                lastFetchDate: Date(),
                userProfileWriter: .profileFetch,
                tx: SDSDB.shimOnlyBridge(transaction)
            )

            self.updateCapabilitiesIfNeeded(
                serviceId: serviceId,
                fetchedCapabilities: fetchedProfile.profile.capabilities,
                localIdentifiers: localIdentifiers,
                tx: transaction
            )

            if localIdentifiers.contains(serviceId: serviceId) {
                self.reconcileLocalProfileIfNeeded(fetchedProfile: fetchedProfile)
            }

            let identityManager = DependenciesBridge.shared.identityManager
            identityManager.saveIdentityKey(profile.identityKey, for: serviceId, tx: transaction)

            let paymentAddress = fetchedProfile.decryptedProfile?.paymentAddress(identityKey: fetchedProfile.identityKey)
            self.paymentsHelper.setArePaymentsEnabled(
                for: serviceId,
                hasPaymentsEnabled: paymentAddress != nil,
                transaction: SDSDB.shimOnlyBridge(transaction)
            )
        }
    }

    private func updateUnidentifiedAccess(
        serviceId: ServiceId,
        verifier: Data?,
        hasUnrestrictedAccess: Bool,
        tx: DBWriteTransaction
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

            guard let udAccessKey = udManager.udAccessKey(for: serviceId, tx: SDSDB.shimOnlyBridge(tx)) else {
                return .disabled
            }

            let dataToVerify = Data(count: 32)
            let expectedVerifier = Data(HMAC<SHA256>.authenticationCode(for: dataToVerify, using: .init(data: udAccessKey.keyData)))
            guard expectedVerifier.ows_constantTimeIsEqual(to: verifier) else {
                return .disabled
            }

            return .enabled
        }()
        udManager.setUnidentifiedAccessMode(unidentifiedAccessMode, for: serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    private func updateCapabilitiesIfNeeded(
        serviceId: ServiceId,
        fetchedCapabilities: SignalServiceProfile.Capabilities,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) {
        let registrationState = tsAccountManager.registrationState(tx: tx)

        var shouldSendProfileSync = false

        if
            localIdentifiers.contains(serviceId: serviceId),
            fetchedCapabilities.storageServiceRecordIkm
        {
            if !storageServiceRecordIkmCapabilityStore.isRecordIkmCapable(tx: tx) {
                storageServiceRecordIkmCapabilityStore.setIsRecordIkmCapable(tx: tx)

                shouldSendProfileSync = true
            }

            if registrationState.isRegisteredPrimaryDevice {
                /// Only primary devices should perform the `recordIkm`
                /// migration, since only primaries can create a Storage Service
                /// manifest.
                ///
                /// We want to do this in a transaction completion block, since
                /// it'll read from the database and we want to ensure this
                /// write has completed.
                tx.addAsyncCompletion(on: DispatchQueue.global()) { [storageServiceRecordIkmMigrator] in
                    storageServiceRecordIkmMigrator.migrateToManifestRecordIkmIfNecessary()
                }
            }
        }

        if
            shouldSendProfileSync,
            registrationState.isRegistered
        {
            /// If some capability is newly enabled, we want all devices to be aware.
            /// This would happen automatically the next time those devices
            /// fetch the local profile, but we'd prefer it happen ASAP!
            syncManager.sendFetchLatestProfileSyncMessage(tx: SDSDB.shimOnlyBridge(tx))
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
            decryptedProfile: fetchedProfile.decryptedProfile
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
            || profile.phoneNumberSharingEncrypted != nil
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
            phoneNumberSharing: phoneNumberSharing
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
