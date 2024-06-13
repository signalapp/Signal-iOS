//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

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
    private let deleteForMeSyncMessageSettingsStore: any DeleteForMeSyncMessageSettingsStore
    private let identityManager: any OWSIdentityManager
    private let paymentsHelper: any PaymentsHelper
    private let profileManager: any ProfileManager
    private let recipientDatabaseTable: any RecipientDatabaseTable
    private let recipientManager: any SignalRecipientManager
    private let recipientMerger: any RecipientMerger
    private let syncManager: any SyncManagerProtocol
    private let tsAccountManager: any TSAccountManager
    private let udManager: any OWSUDManager
    private let versionedProfiles: any VersionedProfilesSwift

    init(
        serviceId: ServiceId,
        authedAccount: AuthedAccount,
        db: any DB,
        deleteForMeSyncMessageSettingsStore: any DeleteForMeSyncMessageSettingsStore,
        identityManager: any OWSIdentityManager,
        paymentsHelper: any PaymentsHelper,
        profileManager: any ProfileManager,
        recipientDatabaseTable: any RecipientDatabaseTable,
        recipientManager: any SignalRecipientManager,
        recipientMerger: any RecipientMerger,
        syncManager: any SyncManagerProtocol,
        tsAccountManager: any TSAccountManager,
        udManager: any OWSUDManager,
        versionedProfiles: any VersionedProfilesSwift
    ) {
        self.serviceId = serviceId
        self.authedAccount = authedAccount
        self.db = db
        self.deleteForMeSyncMessageSettingsStore = deleteForMeSyncMessageSettingsStore
        self.identityManager = identityManager
        self.paymentsHelper = paymentsHelper
        self.profileManager = profileManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientManager = recipientManager
        self.recipientMerger = recipientMerger
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
        return try await requestProfileWithRetries(localIdentifiers: localIdentifiers)
    }

    private func requestProfileWithRetries(localIdentifiers: LocalIdentifiers, retryCount: Int = 0) async throws -> FetchedProfile {
        do {
            return try await requestProfileAttempt(localIdentifiers: localIdentifiers)
        } catch where error.httpStatusCode == 401 {
            throw ProfileRequestError.notAuthorized
        } catch where error.httpStatusCode == 404 {
            throw ProfileRequestError.notFound
        } catch where error.httpStatusCode == 413 || error.httpStatusCode == 429 {
            throw ProfileRequestError.rateLimit
        } catch where error.isRetryable && retryCount < 3 {
            return try await requestProfileWithRetries(localIdentifiers: localIdentifiers, retryCount: retryCount + 1)
        }
    }

    private func requestProfileAttempt(localIdentifiers: LocalIdentifiers) async throws -> FetchedProfile {
        let serviceId = self.serviceId

        let udAccess: OWSUDAccess?
        if localIdentifiers.contains(serviceId: serviceId) {
            // Don't use UD for "self" profile fetches.
            udAccess = nil
        } else {
            udAccess = db.read { tx in udManager.udAccess(for: serviceId, tx: SDSDB.shimOnlyBridge(tx)) }
        }

        var currentVersionedProfileRequest: VersionedProfileRequest?
        let requestMaker = RequestMaker(
            label: "Profile Fetch",
            requestFactoryBlock: { (udAccessKeyForRequest) -> TSRequest? in
                // Clear out any existing request.
                currentVersionedProfileRequest = nil

                switch serviceId {
                case let aci as Aci:
                    do {
                        let request = try self.versionedProfiles.versionedProfileRequest(
                            for: aci,
                            udAccessKey: udAccessKeyForRequest,
                            auth: self.authedAccount.chatServiceAuth
                        )
                        currentVersionedProfileRequest = request
                        return request.request
                    } catch {
                        owsFailDebug("Error: \(error)")
                        return nil
                    }
                default:
                    Logger.info("Unversioned profile fetch.")
                    return OWSRequestFactory.getUnversionedProfileRequest(
                        serviceId: ServiceIdObjC.wrapValue(serviceId),
                        udAccessKey: udAccessKeyForRequest,
                        auth: self.authedAccount.chatServiceAuth
                    )
                }
            },
            serviceId: serviceId,
            udAccess: udAccess,
            authedAccount: self.authedAccount,
            options: [.allowIdentifiedFallback, .isProfileFetch]
        )

        let result = try await requestMaker.makeRequest().awaitable()

        let profile: SignalServiceProfile = try .fromResponse(
            serviceId: serviceId,
            responseObject: result.responseJson
        )

        // If we sent a versioned request, store the credential that was returned.
        if let versionedProfileRequest = currentVersionedProfileRequest {
            // This calls databaseStorage.write { }
            await versionedProfiles.didFetchProfile(profile: profile, profileRequest: versionedProfileRequest)
        }

        return fetchedProfile(
            for: profile,
            profileKeyFromVersionedRequest: currentVersionedProfileRequest?.profileKey
        )
    }

    private func fetchedProfile(
        for profile: SignalServiceProfile,
        profileKeyFromVersionedRequest: OWSAES256Key?
    ) -> FetchedProfile {
        let profileKey: OWSAES256Key?
        if let profileKeyFromVersionedRequest {
            // We sent a versioned request, so use the corresponding profile key for
            // decryption. If we don't, we might try to decrypt an old profile with a
            // new key, and that won't work.
            profileKey = profileKeyFromVersionedRequest
        } else {
            // We sent an unversioned request, so just use any profile key that's
            // available. If we explicitly sent an unversioned request, we may have a
            // key available locally. If we wanted a versioned request but ended up
            // with an unversioned request, we may have received a key while the
            // profile fetch was in flight.
            profileKey = db.read { profileManager.profileKey(for: SignalServiceAddress(profile.serviceId), transaction: SDSDB.shimOnlyBridge($0)) }
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
            let oldAvatarUrlPath = profileManager.profileAvatarURLPath(
                for: profileAddress,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
            return (
                oldAvatarUrlPath == newAvatarUrlPath
                && profileManager.hasProfileAvatarData(profileAddress, transaction: SDSDB.shimOnlyBridge(tx))
            )
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
                address: OWSUserProfile.insertableAddress(for: serviceId, localIdentifiers: localIdentifiers),
                decryptedProfile: fetchedProfile.decryptedProfile,
                avatarUrlPath: avatarDownloadResult.remoteRelativePath,
                avatarFileName: avatarFilename,
                profileBadges: profileBadgeMetadata,
                lastFetchDate: Date(),
                userProfileWriter: .profileFetch,
                tx: SDSDB.shimOnlyBridge(transaction)
            )

            if localIdentifiers.contains(serviceId: serviceId) {
                self.updateLocalCapabilitiesIfNeeded(
                    fetchedCapabilities: fetchedProfile.profile.capabilities,
                    tx: transaction
                )

                self.reconcileLocalProfileIfNeeded(fetchedProfile: fetchedProfile)
            }

            let identityManager = DependenciesBridge.shared.identityManager
            identityManager.saveIdentityKey(profile.identityKey, for: serviceId, tx: transaction)

            let paymentAddress = fetchedProfile.decryptedProfile?.paymentAddress(identityKey: fetchedProfile.identityKey)
            self.paymentsHelper.setArePaymentsEnabled(
                for: ServiceIdObjC.wrapValue(serviceId),
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
            guard let expectedVerifier = Cryptography.computeSHA256HMAC(dataToVerify, key: udAccessKey.keyData) else {
                owsFailDebug("could not compute verification")
                return .disabled
            }

            guard expectedVerifier.ows_constantTimeIsEqual(to: verifier) else {
                return .disabled
            }

            return .enabled
        }()
        udManager.setUnidentifiedAccessMode(unidentifiedAccessMode, for: serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    private func updateLocalCapabilitiesIfNeeded(
        fetchedCapabilities: SignalServiceProfile.Capabilities,
        tx: DBWriteTransaction
    ) {
        if
            fetchedCapabilities.deleteSync,
            !deleteForMeSyncMessageSettingsStore.isSendingEnabled(tx: tx)
        {
            deleteForMeSyncMessageSettingsStore.enableSending(tx: tx)

            /// Now that the capability is enabled, we want to enable sending
            /// not just on this device but on all our devices. To that end, we
            /// can send a "fetch our latest profile" sync message to our other
            /// devices, which will make them fetch the profile and learn that
            /// they should also enable `DeleteForMe` sending.
            ///
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
    let profileKey: OWSAES256Key?
    public let decryptedProfile: DecryptedProfile?
    public let identityKey: IdentityKey

    init(profile: SignalServiceProfile, profileKey: OWSAES256Key?) {
        self.profile = profile
        self.profileKey = profileKey
        self.decryptedProfile = Self.decrypt(profile: profile, profileKey: profileKey)
        self.identityKey = profile.identityKey
    }

    private static func decrypt(profile: SignalServiceProfile, profileKey: OWSAES256Key?) -> DecryptedProfile? {
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
