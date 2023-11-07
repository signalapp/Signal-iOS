//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

@objc
public enum ProfileFetchError: Int, Error {
    case missing
    case throttled
    case notMainApp
    case rateLimit
    case unauthorized
}

// MARK: -

extension ProfileFetchError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missing:
            return "ProfileFetchError.missing"
        case .throttled:
            return "ProfileFetchError.throttled"
        case .notMainApp:
            return "ProfileFetchError.notMainApp"
        case .rateLimit:
            return "ProfileFetchError.rateLimit"
        case .unauthorized:
            return "ProfileFetchError.unauthorized"
        }
    }
}

// MARK: -

private struct ProfileFetchOptions {
    let mainAppOnly: Bool
    let ignoreThrottling: Bool
    let shouldUpdateStore: Bool
    let authedAccount: AuthedAccount

    init(
        mainAppOnly: Bool = true,
        ignoreThrottling: Bool = false,
        shouldUpdateStore: Bool = true,
        authedAccount: AuthedAccount
    ) {
        self.mainAppOnly = mainAppOnly
        self.ignoreThrottling = ignoreThrottling || DebugFlags.aggressiveProfileFetching.get()
        self.shouldUpdateStore = shouldUpdateStore
        self.authedAccount = authedAccount
    }
}

// MARK: -

@objc
public class ProfileFetcherJob: NSObject {

    private static var fetchDateMap = LRUCache<ServiceId, Date>(maxSize: 256)

    private let serviceId: ServiceId
    private let options: ProfileFetchOptions

    private var backgroundTask: OWSBackgroundTask?

    @objc
    public class func fetchProfilePromiseObjc(
        serviceId: ServiceIdObjC,
        mainAppOnly: Bool,
        ignoreThrottling: Bool,
        authedAccount: AuthedAccount
    ) -> AnyPromise {
        return AnyPromise(fetchProfilePromise(
            serviceId: serviceId.wrappedValue,
            mainAppOnly: mainAppOnly,
            ignoreThrottling: ignoreThrottling,
            authedAccount: authedAccount
        ))
    }

    public class func fetchProfilePromise(
        address: SignalServiceAddress,
        mainAppOnly: Bool = true,
        ignoreThrottling: Bool = false,
        shouldUpdateStore: Bool = true,
        authedAccount: AuthedAccount = .implicit()
    ) -> Promise<FetchedProfile> {
        guard let serviceId = address.serviceId else {
            return Promise(error: ProfileFetchError.missing)
        }
        return fetchProfilePromise(
            serviceId: serviceId,
            mainAppOnly: mainAppOnly,
            ignoreThrottling: ignoreThrottling,
            shouldUpdateStore: shouldUpdateStore,
            authedAccount: authedAccount
        )
    }

    public class func fetchProfilePromise(
        serviceId: ServiceId,
        mainAppOnly: Bool = true,
        ignoreThrottling: Bool = false,
        shouldUpdateStore: Bool = true,
        authedAccount: AuthedAccount = .implicit()
    ) -> Promise<FetchedProfile> {
        let options = ProfileFetchOptions(
            mainAppOnly: mainAppOnly,
            ignoreThrottling: ignoreThrottling,
            shouldUpdateStore: shouldUpdateStore,
            authedAccount: authedAccount
        )
        return Promise.wrapAsync { try await ProfileFetcherJob(serviceId: serviceId, options: options).run() }
    }

    @objc
    public class func fetchProfile(address: SignalServiceAddress, ignoreThrottling: Bool, authedAccount: AuthedAccount = .implicit()) {
        Task { await _fetchProfile(serviceId: address.serviceId, ignoreThrottling: ignoreThrottling, authedAccount: authedAccount) }
    }

    @objc
    public class func fetchProfile(serviceId: ServiceIdObjC, ignoreThrottling: Bool, authedAccount: AuthedAccount = .implicit()) {
        Task { await _fetchProfile(serviceId: serviceId.wrappedValue, ignoreThrottling: ignoreThrottling, authedAccount: authedAccount) }
    }

    private class func _fetchProfile(serviceId: ServiceId?, ignoreThrottling: Bool, authedAccount: AuthedAccount) async {
        do {
            guard let serviceId else {
                throw ProfileFetchError.missing
            }
            try await ProfileFetcherJob(
                serviceId: serviceId,
                options: ProfileFetchOptions(ignoreThrottling: ignoreThrottling, authedAccount: authedAccount)
            ).run()
        } catch {
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Error: \(error)")
            } else {
                switch error {
                case ProfileFetchError.missing:
                    Logger.warn("Error: \(error)")
                case ProfileFetchError.unauthorized:
                    if DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered {
                        owsFailDebug("Error: \(error)")
                    } else {
                        Logger.warn("Error: \(error)")
                    }
                default:
                    owsFailDebug("Error: \(error)")
                }
            }
        }
    }

    private init(serviceId: ServiceId, options: ProfileFetchOptions) {
        self.serviceId = serviceId
        self.options = options
    }

    // MARK: -

    @discardableResult
    private func run() async throws -> FetchedProfile {
        let backgroundTask = addBackgroundTask()
        defer {
            backgroundTask.end()
        }

        let fetchedProfile = try await requestProfile()
        if options.shouldUpdateStore {
            try await updateProfile(fetchedProfile: fetchedProfile, authedAccount: options.authedAccount)
        }
        return fetchedProfile
    }

    private func requestProfile() async throws -> FetchedProfile {

        guard !options.mainAppOnly || CurrentAppContext().isMainApp else {
            // We usually only refresh profiles in the MainApp to decrease the
            // chance of missed SN notifications in the AppExtension for our users
            // who choose not to verify contacts.
            throw ProfileFetchError.notMainApp
        }

        // Check throttling _before_ possible retries.
        if !options.ignoreThrottling {
            if let lastDate = lastFetchDate() {
                let lastTimeInterval = fabs(lastDate.timeIntervalSinceNow)
                // Don't check a profile more often than every N seconds.
                //
                // Throttle less in debug to make it easier to test problems
                // with our fetching logic.
                guard lastTimeInterval > Self.throttledProfileFetchFrequency else {
                    throw ProfileFetchError.throttled
                }
            }
        }

        if options.shouldUpdateStore {
            recordLastFetchDate()
        }

        return try await requestProfileWithRetries()
    }

    private static var throttledProfileFetchFrequency: TimeInterval {
        kMinuteInterval * 2.0
    }

    private func requestProfileWithRetries(retryCount: Int = 0) async throws -> FetchedProfile {
        do {
            return try await requestProfileAttempt()
        } catch {
            if error.httpStatusCode == 401 {
                throw ProfileFetchError.unauthorized
            }
            if error.httpStatusCode == 404 {
                throw ProfileFetchError.missing
            }
            if error.httpStatusCode == 413 || error.httpStatusCode == 429 {
                throw ProfileFetchError.rateLimit
            }

            switch error {
            case ProfileFetchError.throttled, ProfileFetchError.notMainApp:
                // These errors should only be thrown at a higher level.
                owsFailDebug("Unexpected error: \(error)")
                throw error
            case let error as SignalServiceProfile.ValidationError:
                // This should not be retried.
                owsFailDebug("skipping updateProfile retry. Invalid profile for: \(serviceId) error: \(error)")
                throw error
            default:
                let maxRetries = 3
                guard retryCount < maxRetries else {
                    Logger.warn("failed to get profile with error: \(error)")
                    throw error
                }

                return try await requestProfileWithRetries(retryCount: retryCount + 1)
            }
        }
    }

    private func requestProfileAttempt() async throws -> FetchedProfile {
        let serviceId = self.serviceId

        let udAccess: OWSUDAccess?
        if self.isFetchForLocalAccount(authedAccount: options.authedAccount) {
            // Don't use UD for "self" profile fetches.
            udAccess = nil
        } else {
            udAccess = databaseStorage.read { tx in udManager.udAccess(for: serviceId, tx: tx) }
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
                        let request = try self.versionedProfilesSwift.versionedProfileRequest(
                            for: aci,
                            udAccessKey: udAccessKeyForRequest,
                            auth: self.options.authedAccount.chatServiceAuth
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
                        auth: self.options.authedAccount.chatServiceAuth
                    )
                }
            },
            serviceId: serviceId,
            udAccess: udAccess,
            authedAccount: self.options.authedAccount,
            options: [.allowIdentifiedFallback, .isProfileFetch]
        )

        let result = try await requestMaker.makeRequest().awaitable()

        let profile = try SignalServiceProfile(serviceId: serviceId, responseObject: result.responseJson)

        // If we sent a versioned request, store the credential that was returned.
        if let versionedProfileRequest = currentVersionedProfileRequest {
            // This calls databaseStorage.write { }
            await versionedProfilesSwift.didFetchProfile(profile: profile, profileRequest: versionedProfileRequest)
        }

        return fetchedProfile(
            for: profile,
            profileKeyFromVersionedRequest: currentVersionedProfileRequest?.profileKey
        )
    }

    private func isFetchForLocalAccount(authedAccount: AuthedAccount) -> Bool {
        let localIdentifiers: LocalIdentifiers
        switch authedAccount.info {
        case .explicit(let info):
            localIdentifiers = info.localIdentifiers
        case .implicit:
            guard let implicitLocalIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
                owsFailDebug("Fetching without localIdentifiers.")
                return false
            }
            localIdentifiers = implicitLocalIdentifiers
        }
        return localIdentifiers.contains(serviceId: serviceId)
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
            profileKey = databaseStorage.read { profileManager.profileKey(for: SignalServiceAddress(profile.serviceId), transaction: $0) }
        }
        return FetchedProfile(profile: profile, profileKey: profileKey)
    }

    private func updateProfile(
        fetchedProfile: FetchedProfile,
        authedAccount: AuthedAccount
    ) async throws {
        await updateProfile(
            fetchedProfile: fetchedProfile,
            localAvatarUrlIfDownloaded: try await downloadAvatarIfNeeded(fetchedProfile, authedAccount: authedAccount),
            authedAccount: authedAccount
        )
    }

    private func downloadAvatarIfNeeded(
        _ fetchedProfile: FetchedProfile,
        authedAccount: AuthedAccount
    ) async throws -> URL? {
        guard let newAvatarUrlPath = fetchedProfile.profile.avatarUrlPath else {
            // If profile has no avatar, we don't need to download the avatar.
            return nil
        }
        guard let profileKey = fetchedProfile.profileKey else {
            // If we don't have a profile key for this user, don't bother downloading
            // their avatar - we can't decrypt it.
            return nil
        }
        let profileAddress = SignalServiceAddress(fetchedProfile.profile.serviceId)
        let didAlreadyDownloadAvatar = databaseStorage.read { transaction -> Bool in
            let oldAvatarUrlPath = profileManager.profileAvatarURLPath(
                for: profileAddress,
                downloadIfMissing: false,
                authedAccount: authedAccount,
                transaction: transaction
            )
            return (
                oldAvatarUrlPath == newAvatarUrlPath
                && profileManager.hasProfileAvatarData(profileAddress, transaction: transaction)
            )
        }
        if didAlreadyDownloadAvatar {
            return nil
        }
        let anyAvatarData: Any?
        do {
            anyAvatarData = try await profileManager.downloadAndDecryptProfileAvatar(
                forProfileAddress: profileAddress, avatarUrlPath: newAvatarUrlPath, profileKey: profileKey
            ).asAny().awaitable()
        } catch {
            Logger.warn("Error: \(error)")
            if error.isNetworkFailureOrTimeout, profileAddress.isLocalAddress {
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
            return nil
        }
        guard let avatarData = anyAvatarData as? Data else {
            throw OWSAssertionError("Unexpected result.")
        }
        return avatarData.isEmpty ? nil : profileManager.writeAvatarDataToFile(avatarData)
    }

    private func updateProfile(
        fetchedProfile: FetchedProfile,
        localAvatarUrlIfDownloaded: URL?,
        authedAccount: AuthedAccount
    ) async {
        let profile = fetchedProfile.profile
        let serviceId = profile.serviceId

        var givenName: String?
        var familyName: String?
        var bio: String?
        var bioEmoji: String?
        var paymentAddress: TSPaymentAddress?
        if let decryptedProfile = fetchedProfile.decryptedProfile {
            givenName = decryptedProfile.givenName?.nilIfEmpty
            familyName = decryptedProfile.familyName?.nilIfEmpty
            bio = decryptedProfile.bio?.nilIfEmpty
            bioEmoji = decryptedProfile.bioEmoji?.nilIfEmpty
            paymentAddress = decryptedProfile.paymentAddress
        }

        if DebugFlags.internalLogging {
            let profileKeyDescription = fetchedProfile.profileKey?.keyData.hexadecimalString ?? "None"
            let hasAvatar = profile.avatarUrlPath != nil
            let hasProfileNameEncrypted = profile.profileNameEncrypted != nil
            let hasGivenName = givenName?.nilIfEmpty != nil
            let hasFamilyName = familyName?.nilIfEmpty != nil
            let hasBio = bio?.nilIfEmpty != nil
            let hasBioEmoji = bioEmoji?.nilIfEmpty != nil
            let hasPaymentAddress = paymentAddress != nil
            let badges = fetchedProfile.profile.badges.map { "\"\($0.0.description)\"" }.joined(separator: "; ")

            Logger.info(
                "serviceId: \(serviceId), " +
                "hasAvatar: \(hasAvatar), " +
                "hasProfileNameEncrypted: \(hasProfileNameEncrypted), " +
                "hasGivenName: \(hasGivenName), " +
                "hasFamilyName: \(hasFamilyName), " +
                "hasBio: \(hasBio), " +
                "hasBioEmoji: \(hasBioEmoji), " +
                "hasPaymentAddress: \(hasPaymentAddress), " +
                "profileKey: \(profileKeyDescription), " +
                "badges: \(badges)"
            )
        }

        await databaseStorage.awaitableWrite { transaction in
            Self.updateUnidentifiedAccess(
                serviceId: serviceId,
                verifier: profile.unidentifiedAccessVerifier,
                hasUnrestrictedAccess: profile.hasUnrestrictedUnidentifiedAccess,
                tx: transaction
            )

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

            self.profileManager.updateProfile(
                for: SignalServiceAddress(serviceId),
                givenName: givenName,
                familyName: familyName,
                bio: bio,
                bioEmoji: bioEmoji,
                avatarUrlPath: profile.avatarUrlPath,
                optionalAvatarFileUrl: localAvatarUrlIfDownloaded,
                profileBadges: profileBadgeMetadata,
                lastFetch: Date(),
                isPniCapable: profile.isPniCapable,
                userProfileWriter: .profileFetch,
                authedAccount: authedAccount,
                transaction: transaction
            )

            let identityManager = DependenciesBridge.shared.identityManager
            identityManager.saveIdentityKey(profile.identityKey, for: serviceId, tx: transaction.asV2Write)

            self.paymentsHelper.setArePaymentsEnabled(
                for: ServiceIdObjC.wrapValue(serviceId),
                hasPaymentsEnabled: paymentAddress != nil,
                transaction: transaction
            )
        }
    }

    private static func updateUnidentifiedAccess(
        serviceId: ServiceId,
        verifier: Data?,
        hasUnrestrictedAccess: Bool,
        tx: SDSAnyWriteTransaction
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

            guard let udAccessKey = udManager.udAccessKey(for: serviceId, tx: tx) else {
                return .disabled
            }

            let dataToVerify = Data(count: 32)
            guard let expectedVerifier = Cryptography.computeSHA256HMAC(dataToVerify, key: udAccessKey.keyData) else {
                owsFailDebug("could not compute verification")
                return .disabled
            }

            guard expectedVerifier.ows_constantTimeIsEqual(to: verifier) else {
                Logger.verbose("verifier mismatch, new profile key?")
                return .disabled
            }

            return .enabled
        }()
        udManager.setUnidentifiedAccessMode(unidentifiedAccessMode, for: serviceId, tx: tx)
    }

    private func lastFetchDate() -> Date? {
        ProfileFetcherJob.fetchDateMap[serviceId]
    }

    private func recordLastFetchDate() {
        ProfileFetcherJob.fetchDateMap[serviceId] = Date()
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

public struct DecryptedProfile: Dependencies {
    public let givenName: String?
    public let familyName: String?
    public let bio: String?
    public let bioEmoji: String?
    public let paymentAddressData: Data?
    public let identityKey: IdentityKey
}

// MARK: -

public struct FetchedProfile {
    let profile: SignalServiceProfile
    let profileKey: OWSAES256Key?
    public let decryptedProfile: DecryptedProfile?

    init(profile: SignalServiceProfile, profileKey: OWSAES256Key?) {
        self.profile = profile
        self.profileKey = profileKey
        self.decryptedProfile = Self.decrypt(profile: profile, profileKey: profileKey)
    }

    private static func decrypt(profile: SignalServiceProfile, profileKey: OWSAES256Key?) -> DecryptedProfile? {
        guard let profileKey = profileKey else {
            return nil
        }
        var givenName: String?
        var familyName: String?
        var bio: String?
        var bioEmoji: String?
        var paymentAddressData: Data?
        let profileName = profile.profileNameEncrypted.flatMap {
            OWSUserProfile.decrypt(profileNameData: $0, profileKey: profileKey)
        }
        if let profileName {
            givenName = profileName.givenName
            familyName = profileName.familyName
        }
        if let bioEncrypted = profile.bioEncrypted {
            bio = OWSUserProfile.decrypt(profileStringData: bioEncrypted, profileKey: profileKey)
        }
        if let bioEmojiEncrypted = profile.bioEmojiEncrypted {
            bioEmoji = OWSUserProfile.decrypt(profileStringData: bioEmojiEncrypted, profileKey: profileKey)
        }
        if let paymentAddressEncrypted = profile.paymentAddressEncrypted {
            paymentAddressData = OWSUserProfile.decrypt(profileData: paymentAddressEncrypted, profileKey: profileKey)
        }
        return DecryptedProfile(
            givenName: givenName,
            familyName: familyName,
            bio: bio,
            bioEmoji: bioEmoji,
            paymentAddressData: paymentAddressData,
            identityKey: profile.identityKey
        )
    }
}

// MARK: -

public extension DecryptedProfile {

    var paymentAddress: TSPaymentAddress? {
        guard paymentsHelper.arePaymentsEnabled else {
            return nil
        }
        guard let paymentAddressDataWithLength = paymentAddressData else {
            return nil
        }

        do {
            let byteParser = ByteParser(data: paymentAddressDataWithLength, littleEndian: true)
            let length = byteParser.nextUInt32()
            guard length > 0 else {
                return nil
            }
            guard let paymentAddressDataWithoutLength = byteParser.readBytes(UInt(length)) else {
                owsFailDebug("Invalid payment address.")
                return nil
            }
            let proto = try SSKProtoPaymentAddress(serializedData: paymentAddressDataWithoutLength)
            let paymentAddress = try TSPaymentAddress.fromProto(proto, identityKey: identityKey)
            return paymentAddress
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }
}
