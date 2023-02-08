//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public enum ProfileFetchError: Int, Error {
    case missing
    case throttled
    case notMainApp
    case cantRequestVersionedProfile
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
        case .cantRequestVersionedProfile:
            return "ProfileFetchError.cantRequestVersionedProfile"
        case .rateLimit:
            return "ProfileFetchError.rateLimit"
        case .unauthorized:
            return "ProfileFetchError.unauthorized"
        }
    }
}

// MARK: -

@objc
public enum ProfileFetchType: UInt {
    // .default fetches honor FeatureFlag.versionedProfileFetches
    case `default`
    case unversioned
    case versioned
}

// MARK: -

private struct ProfileFetchOptions {
    let mainAppOnly: Bool
    let ignoreThrottling: Bool
    let shouldUpdateStore: Bool
    let fetchType: ProfileFetchType

    init(mainAppOnly: Bool = true,
         ignoreThrottling: Bool = false,
         shouldUpdateStore: Bool = true,
         fetchType: ProfileFetchType = .default) {
        self.mainAppOnly = mainAppOnly
        self.ignoreThrottling = ignoreThrottling || DebugFlags.aggressiveProfileFetching.get()
        self.shouldUpdateStore = shouldUpdateStore
        self.fetchType = fetchType
    }
}

// MARK: -

@objc
public class ProfileFetcherJob: NSObject {

    private static let queueCluster = GCDQueueCluster(label: "org.signal.profileFetcherJob",
                                                      concurrency: 5)

    private static var fetchDateMap = LRUCache<SignalServiceAddress, Date>(maxSize: 256)

    private let subject: SignalServiceAddress
    private let options: ProfileFetchOptions

    private var backgroundTask: OWSBackgroundTask?

    @objc
    public class func fetchProfilePromiseObjc(address: SignalServiceAddress,
                                              mainAppOnly: Bool,
                                              ignoreThrottling: Bool) -> AnyPromise {
        return AnyPromise(fetchProfilePromise(address: address,
                                              mainAppOnly: mainAppOnly,
                                              ignoreThrottling: ignoreThrottling))
    }

    public class func fetchProfilePromise(address: SignalServiceAddress,
                                          mainAppOnly: Bool = true,
                                          ignoreThrottling: Bool = false,
                                          shouldUpdateStore: Bool = true,
                                          fetchType: ProfileFetchType = .default) -> Promise<FetchedProfile> {
        let options = ProfileFetchOptions(mainAppOnly: mainAppOnly,
                                          ignoreThrottling: ignoreThrottling,
                                          shouldUpdateStore: shouldUpdateStore,
                                          fetchType: fetchType)
        return ProfileFetcherJob(subject: address, options: options).runAsPromise()
    }

    @objc
    public class func fetchProfile(address: SignalServiceAddress, ignoreThrottling: Bool) {
        let options = ProfileFetchOptions(ignoreThrottling: ignoreThrottling)
        firstly {
            ProfileFetcherJob(subject: address, options: options).runAsPromise()
        }.catch { error in
            if error.isNetworkFailureOrTimeout {
                Logger.warn("Error: \(error)")
            } else {
                switch error {
                case ProfileFetchError.missing:
                    Logger.warn("Error: \(error)")
                case ProfileFetchError.unauthorized:
                    if self.tsAccountManager.isRegisteredAndReady {
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

    private init(subject: SignalServiceAddress,
                 options: ProfileFetchOptions) {
        self.subject = subject
        self.options = options
    }

    // MARK: -

    private func runAsPromise() -> Promise<FetchedProfile> {
        return DispatchQueue.main.async(.promise) {
            self.addBackgroundTask()
        }.then(on: Self.queueCluster.next()) { _ in
            self.requestProfile()
        }.then(on: Self.queueCluster.next()) { fetchedProfile in
            firstly { () -> Promise<Void> in
                if self.options.shouldUpdateStore {
                    return self.updateProfile(fetchedProfile: fetchedProfile)
                }
                return .value(())
            }.map(on: Self.queueCluster.next()) { _ in
                return fetchedProfile
            }
        }
    }

    private func requestProfile() -> Promise<FetchedProfile> {

        guard !options.mainAppOnly || CurrentAppContext().isMainApp else {
            // We usually only refresh profiles in the MainApp to decrease the
            // chance of missed SN notifications in the AppExtension for our users
            // who choose not to verify contacts.
            return Promise(error: ProfileFetchError.notMainApp)
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
                    return Promise(error: ProfileFetchError.throttled)
                }
            }
        }

        if options.shouldUpdateStore {
            recordLastFetchDate()
        }

        return requestProfileWithRetries()
    }

    private static var throttledProfileFetchFrequency: TimeInterval {
        kMinuteInterval * 2.0
    }

    private func requestProfileWithRetries(retryCount: Int = 0) -> Promise<FetchedProfile> {
        let subject = self.subject

        let (promise, future) = Promise<FetchedProfile>.pending()
        firstly {
            requestProfileAttempt()
        }.done(on: Self.queueCluster.next()) { fetchedProfile in
            future.resolve(fetchedProfile)
        }.catch(on: Self.queueCluster.next()) { error in
            if error.httpStatusCode == 401 {
                return future.reject(ProfileFetchError.unauthorized)
            }
            if error.httpStatusCode == 404 {
                return future.reject(ProfileFetchError.missing)
            }
            if error.httpStatusCode == 413 || error.httpStatusCode == 429 {
                return future.reject(ProfileFetchError.rateLimit)
            }

            switch error {
            case ProfileFetchError.throttled, ProfileFetchError.notMainApp:
                // These errors should only be thrown at a higher level.
                owsFailDebug("Unexpected error: \(error)")
                future.reject(error)
                return
            case SignalServiceProfile.ValidationError.invalidIdentityKey:
                // There will be invalid identity keys on staging that can be safely ignored.
                // This should not be retried.
                if TSConstants.isUsingProductionService {
                    owsFailDebug("skipping updateProfile retry. Invalid profile for: \(subject) error: \(error)")
                } else {
                    Logger.warn("skipping updateProfile retry. Invalid profile for: \(subject) error: \(error)")
                }
                future.reject(error)
                return
            case let error as SignalServiceProfile.ValidationError:
                // This should not be retried.
                owsFailDebug("skipping updateProfile retry. Invalid profile for: \(subject) error: \(error)")
                future.reject(error)
                return
            default:
                let maxRetries = 3
                guard retryCount < maxRetries else {
                    Logger.warn("failed to get profile with error: \(error)")
                    future.reject(error)
                    return
                }

                firstly {
                    self.requestProfileWithRetries(retryCount: retryCount + 1)
                }.done(on: Self.queueCluster.next()) { fetchedProfile in
                    future.resolve(fetchedProfile)
                }.catch(on: Self.queueCluster.next()) { error in
                    future.reject(error)
                }
            }
        }
        return promise
    }

    private var shouldUseVersionedFetchForUuids: Bool {
        switch options.fetchType {
        case .default:
            return true
        case .versioned:
            return true
        case .unversioned:
            return false
        }
    }

    private func requestProfileAttempt() -> Promise<FetchedProfile> {
        let address = self.subject

        Logger.verbose("address: \(address)")

        // If we don't have a UUID, the request will fail, so bail out early.
        guard address.uuid != nil else {
            return Promise(error: ProfileFetchError.missing)
        }

        let shouldUseVersionedFetch = shouldUseVersionedFetchForUuids

        let udAccess: OWSUDAccess?
        if address.isLocalAddress {
            // Don't use UD for "self" profile fetches.
            udAccess = nil
        } else {
            udAccess = udManager.udAccess(forAddress: address, requireSyncAccess: false)
        }

        var currentVersionedProfileRequest: VersionedProfileRequest?
        let requestMaker = RequestMaker(
            label: "Profile Fetch",
            requestFactoryBlock: { (udAccessKeyForRequest) -> TSRequest? in
                // Clear out any existing request.
                currentVersionedProfileRequest = nil

                if shouldUseVersionedFetch {
                    do {
                        let request = try self.versionedProfiles.versionedProfileRequest(address: address, udAccessKey: udAccessKeyForRequest)
                        currentVersionedProfileRequest = request
                        return request.request
                    } catch {
                        owsFailDebug("Error: \(error)")
                        return nil
                    }
                } else {
                    Logger.info("Unversioned profile fetch.")
                    return OWSRequestFactory.getUnversionedProfileRequest(address: address, udAccessKey: udAccessKeyForRequest)
                }
            },
            udAuthFailureBlock: {
                // Do nothing
            },
            address: address,
            udAccess: udAccess,
            options: [.allowIdentifiedFallback, .isProfileFetch]
        )

        return firstly {
            return requestMaker.makeRequest()
        }.map(on: Self.queueCluster.next()) { (result: RequestMakerResult) -> FetchedProfile in
            let profile = try SignalServiceProfile(address: address, responseObject: result.responseJson)

            // If we sent a versioned request, store the credential that was returned.
            if let versionedProfileRequest = currentVersionedProfileRequest {
                // This calls databaseStorage.write { }
                self.versionedProfiles.didFetchProfile(profile: profile, profileRequest: versionedProfileRequest)
            }

            return self.fetchedProfile(
                for: profile,
                profileKeyFromVersionedRequest: currentVersionedProfileRequest?.profileKey
            )
        }
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
            profileKey = databaseStorage.read { profileManager.profileKey(for: profile.address, transaction: $0) }
        }
        return FetchedProfile(profile: profile, profileKey: profileKey)
    }

    private func updateProfile(fetchedProfile: FetchedProfile) -> Promise<Void> {
        firstly {
            // Before we update the profile, try to download and decrypt the avatar
            // data, if necessary.
            downloadAvatarIfNeeded(fetchedProfile)
        }.then(on: Self.queueCluster.next()) { localAvatarUrlIfDownloaded in
            self.updateProfile(
                fetchedProfile: fetchedProfile, localAvatarUrlIfDownloaded: localAvatarUrlIfDownloaded
            )
        }
    }

    private func downloadAvatarIfNeeded(_ fetchedProfile: FetchedProfile) -> Promise<URL?> {
        guard let newAvatarUrlPath = fetchedProfile.profile.avatarUrlPath else {
            // If profile has no avatar, we don't need to download the avatar.
            return Promise.value(nil)
        }
        guard let profileKey = fetchedProfile.profileKey else {
            // If we don't have a profile key for this user, don't bother downloading
            // their avatar - we can't decrypt it.
            return Promise.value(nil)
        }
        let profileAddress = fetchedProfile.profile.address
        let didAlreadyDownloadAvatar = databaseStorage.read { transaction -> Bool in
            let oldAvatarUrlPath = profileManager.profileAvatarURLPath(for: profileAddress, downloadIfMissing: false, transaction: transaction)
            return (
                oldAvatarUrlPath == newAvatarUrlPath
                && profileManager.hasProfileAvatarData(profileAddress, transaction: transaction)
            )
        }
        if didAlreadyDownloadAvatar {
            Logger.verbose("Skipping avatar data download; already downloaded.")
            return Promise.value(nil)
        }
        return firstly {
            profileManager.downloadAndDecryptProfileAvatar(
                forProfileAddress: profileAddress, avatarUrlPath: newAvatarUrlPath, profileKey: profileKey
            )
        }.map(on: Self.queueCluster.next()) { (anyAvatarData: Any?) in
            guard let avatarData = anyAvatarData as? Data else {
                throw OWSAssertionError("Unexpected result.")
            }
            return avatarData
        }.map(on: DispatchQueue.global()) { (avatarData: Data) -> URL? in
            if avatarData.isEmpty {
                return nil
            } else {
                return self.profileManager.writeAvatarDataToFile(avatarData)
            }
        }.recover(on: Self.queueCluster.next()) { error -> Promise<URL?> in
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
            return Promise.value(nil)
        }
    }

    // TODO: This method can cause many database writes.
    //       Perhaps we can use a single transaction?
    private func updateProfile(fetchedProfile: FetchedProfile, localAvatarUrlIfDownloaded: URL?) -> Promise<Void> {
        let profile = fetchedProfile.profile
        let address = profile.address

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
                "address: \(address), " +
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

        // This calls databaseStorage.asyncWrite { }
        Self.updateUnidentifiedAccess(
            address: address,
            verifier: profile.unidentifiedAccessVerifier,
            hasUnrestrictedAccess: profile.hasUnrestrictedUnidentifiedAccess
        )

        return databaseStorage.write(.promise) { transaction in
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
                for: address,
                givenName: givenName,
                familyName: familyName,
                bio: bio,
                bioEmoji: bioEmoji,
                isStoriesCapable: profile.isStoriesCapable,
                avatarUrlPath: profile.avatarUrlPath,
                optionalAvatarFileUrl: localAvatarUrlIfDownloaded,
                profileBadges: profileBadgeMetadata,
                canReceiveGiftBadges: profile.canReceiveGiftBadges,
                lastFetch: Date(),
                userProfileWriter: .profileFetch,
                transaction: transaction
            )

            self.verifyIdentityUpToDate(
                address: address,
                latestIdentityKey: profile.identityKey,
                transaction: transaction
            )

            self.paymentsHelper.setArePaymentsEnabled(
                for: address,
                hasPaymentsEnabled: paymentAddress != nil,
                transaction: transaction
            )

            if address.isLocalAddress {
                ChangePhoneNumber.setLocalUserSupportsChangePhoneNumber(
                    profile.supportsChangeNumber,
                    transaction: transaction
                )
            }
        }
    }

    public static func clearProfileState(address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {

        // TODO: We could immediately discard profile state for this address as well.

        self.profileManager.updateProfile(
            for: address,
            givenName: nil,
            familyName: nil,
            bio: nil,
            bioEmoji: nil,
            isStoriesCapable: false,
            avatarUrlPath: nil,
            optionalAvatarFileUrl: nil,
            profileBadges: nil,
            canReceiveGiftBadges: false,
            lastFetch: Date.distantPast,
            userProfileWriter: .profileFetch,
            transaction: transaction
        )

        self.paymentsHelper.setArePaymentsEnabled(for: address,
                                                     hasPaymentsEnabled: false,
                                                     transaction: transaction)
    }

    private static func updateUnidentifiedAccess(address: SignalServiceAddress,
                                                 verifier: Data?,
                                                 hasUnrestrictedAccess: Bool) {
        guard let verifier = verifier else {
            // If there is no verifier, at least one of this user's devices
            // do not support UD.
            udManager.setUnidentifiedAccessMode(.disabled, address: address)
            return
        }

        if hasUnrestrictedAccess {
            udManager.setUnidentifiedAccessMode(.unrestricted, address: address)
            return
        }

        guard let udAccessKey = udManager.udAccessKey(forAddress: address) else {
            udManager.setUnidentifiedAccessMode(.disabled, address: address)
            return
        }

        let dataToVerify = Data(count: 32)
        guard let expectedVerifier = Cryptography.computeSHA256HMAC(dataToVerify, key: udAccessKey.keyData) else {
            owsFailDebug("could not compute verification")
            udManager.setUnidentifiedAccessMode(.disabled, address: address)
            return
        }

        guard expectedVerifier.ows_constantTimeIsEqual(to: verifier) else {
            Logger.verbose("verifier mismatch, new profile key?")
            udManager.setUnidentifiedAccessMode(.disabled, address: address)
            return
        }

        udManager.setUnidentifiedAccessMode(.enabled, address: address)
    }

    private func verifyIdentityUpToDate(address: SignalServiceAddress,
                                        latestIdentityKey: Data,
                                        transaction: SDSAnyWriteTransaction) {
        if self.identityManager.saveRemoteIdentity(latestIdentityKey, address: address, transaction: transaction) {
            Logger.info("updated identity key with fetched profile for recipient: \(address)")
        }
    }

    private func lastFetchDate() -> Date? {
        ProfileFetcherJob.fetchDateMap[subject]
    }

    private func recordLastFetchDate() {
        ProfileFetcherJob.fetchDateMap[subject] = Date()
    }

    private func addBackgroundTask() {
        backgroundTask = OWSBackgroundTask(label: "\(#function)", completionBlock: { [weak self] status in
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
    public let publicIdentityKey: Data
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
        if let profileNameEncrypted = profile.profileNameEncrypted,
           let profileNameComponents = OWSUserProfile.decrypt(profileNameData: profileNameEncrypted,
                                                              profileKey: profileKey,
                                                              address: profile.address) {
            givenName = profileNameComponents.givenName?.ows_stripped()
            familyName = profileNameComponents.familyName?.ows_stripped()
        }
        if let bioEncrypted = profile.bioEncrypted {
            bio = OWSUserProfile.decrypt(profileStringData: bioEncrypted,
                                         profileKey: profileKey)
        }
        if let bioEmojiEncrypted = profile.bioEmojiEncrypted {
            bioEmoji = OWSUserProfile.decrypt(profileStringData: bioEmojiEncrypted,
                                              profileKey: profileKey)
        }
        if let paymentAddressEncrypted = profile.paymentAddressEncrypted {
            paymentAddressData = OWSUserProfile.decrypt(profileData: paymentAddressEncrypted,
                                                        profileKey: profileKey)
        }
        let publicIdentityKey = profile.identityKey
        return DecryptedProfile(givenName: givenName,
                                familyName: familyName,
                                bio: bio,
                                bioEmoji: bioEmoji,
                                paymentAddressData: paymentAddressData,
                                publicIdentityKey: publicIdentityKey)
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
            let paymentAddress = try TSPaymentAddress.fromProto(proto, publicIdentityKey: publicIdentityKey)
            return paymentAddress
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }
}

// MARK: -

// A simple mechanism for distributing workload across multiple serial queues.
// Allows concurrency while avoiding thread explosion.
//
// TODO: Move this to DispatchQueue+OWS.swift if we adopt it elsewhere.
public class GCDQueueCluster {
    private static let unfairLock = UnfairLock()

    private let queues: [DispatchQueue]

    private let counter = AtomicUInt(0)

    public required init(label: String, concurrency: UInt) {
        if concurrency < 1 {
            owsFailDebug("Invalid concurrency.")
        }
        let concurrency = max(1, concurrency)
        var queues = [DispatchQueue]()
        for index in 0..<concurrency {
            queues.append(DispatchQueue(label: label + ".\(index)"))
        }
        self.queues = queues
    }

    public func next() -> DispatchQueue {
        Self.unfairLock.withLock {
            let index = Int(counter.increment() % UInt(queues.count))
            return queues[index]
        }
    }
}
