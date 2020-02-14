//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit

@objc
public enum ProfileFetchError: Int, Error {
    case missing
    case throttled
    case notMainApp
    case cantRequestVersionedProfile
}

// MARK: -

@objc
public enum ProfileFetchType: UInt {
    // .default fetches honor FeatureFlag.versionedProfiledFetches
    case `default`
    case unversioned
    case versioned
}

// MARK: -

@objc
public class ProfileFetchOptions: NSObject {
    fileprivate let mainAppOnly: Bool
    fileprivate let ignoreThrottling: Bool
    // TODO: Do we ever want to fetch but not update our local profile store?
    fileprivate let shouldUpdateProfile: Bool
    fileprivate let fetchType: ProfileFetchType

    fileprivate init(mainAppOnly: Bool = true,
                     ignoreThrottling: Bool = false,
                     shouldUpdateProfile: Bool = true,
                     fetchType: ProfileFetchType = .default) {
        self.mainAppOnly = mainAppOnly
        self.ignoreThrottling = ignoreThrottling
        self.shouldUpdateProfile = shouldUpdateProfile
        self.fetchType = fetchType
    }
}

// MARK: -

private enum ProfileRequestSubject {
    case address(address: SignalServiceAddress)
    case username(username: String)
}

extension ProfileRequestSubject: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(hashTypeConstant)
        switch self {
        case .address(let address):
            hasher.combine(address)
        case .username(let username):
            hasher.combine(username)
        }
    }

    var hashTypeConstant: String {
        switch self {
        case .address:
            return "address"
        case .username:
            return "username"
        }
    }
}

// MARK: -

extension ProfileRequestSubject: CustomStringConvertible {
    public var description: String {
        switch self {
        case .address(let address):
            return "[address:\(address)]"
        case .username:
            // TODO: Could we redact username for logging?
            return "[username]"
        }
    }
}

// MARK: -

@objc
public class ProfileFetcherJob: NSObject {

    // This property is only accessed on the serial queue.
    private static var fetchDateMap = [ProfileRequestSubject: Date]()
    private static let serialQueue = DispatchQueue(label: "org.signal.profileFetcherJob")

    private let subject: ProfileRequestSubject
    private let options: ProfileFetchOptions

    private var backgroundTask: OWSBackgroundTask?

    public class func fetchAndUpdateProfilePromise(address: SignalServiceAddress,
                                                   mainAppOnly: Bool = true,
                                                   ignoreThrottling: Bool = false,
                                                   shouldUpdateProfile: Bool = true,
                                                   fetchType: ProfileFetchType = .default) -> Promise<SignalServiceProfile> {
        let subject = ProfileRequestSubject.address(address: address)
        let options = ProfileFetchOptions(mainAppOnly: mainAppOnly,
                                          ignoreThrottling: ignoreThrottling,
                                          shouldUpdateProfile: shouldUpdateProfile,
                                          fetchType: fetchType)
        return ProfileFetcherJob(subject: subject, options: options).runAsPromise()
    }

    @objc
    public class func fetchAndUpdateProfile(address: SignalServiceAddress, ignoreThrottling: Bool) {
        let subject = ProfileRequestSubject.address(address: address)
        let options = ProfileFetchOptions(ignoreThrottling: ignoreThrottling)
        ProfileFetcherJob(subject: subject, options: options).runAsPromise()
            .retainUntilComplete()
    }

    @objc
    public class func fetchAndUpdateProfile(username: String,
                                            success: @escaping (_ address: SignalServiceAddress) -> Void,
                                            notFound: @escaping () -> Void,
                                            failure: @escaping (_ error: Error?) -> Void) {
        let subject = ProfileRequestSubject.username(username: username)
        let options = ProfileFetchOptions(ignoreThrottling: true)
        ProfileFetcherJob(subject: subject, options: options).runAsPromise()
            .done { profile in
                success(profile.address)
            }.catch { error in
                switch error {
                case ProfileFetchError.missing:
                    notFound()
                default:
                    failure(error)
                }
            }
            .retainUntilComplete()
    }

    @objc(fetchAndUpdateProfilesWithThread:)
    public class func fetchAndUpdateProfiles(thread: TSThread) {
        let addresses = thread.recipientAddresses
        let subjects = addresses.map { ProfileRequestSubject.address(address: $0) }
        let options = ProfileFetchOptions()
        var promises = [Promise<SignalServiceProfile>]()
        for subject in subjects {
            let job = ProfileFetcherJob(subject: subject, options: options)
            promises.append(job.runAsPromise())
        }
        when(fulfilled: promises).retainUntilComplete()
    }

    private init(subject: ProfileRequestSubject,
                 options: ProfileFetchOptions) {
        self.subject = subject
        self.options = options
    }

    // MARK: - Dependencies

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private var socketManager: TSSocketManager {
        return TSSocketManager.shared
    }

    private var udManager: OWSUDManager {
        return SSKEnvironment.shared.udManager
    }

    private var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private var identityManager: OWSIdentityManager {
        return SSKEnvironment.shared.identityManager
    }

    private var signalServiceClient: SignalServiceClient {
        // TODO hang on SSKEnvironment
        return SignalServiceRestClient()
    }

    private var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    private var sessionStore: SSKSessionStore {
        return SSKSessionStore()
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    private func runAsPromise() -> Promise<SignalServiceProfile> {
        return DispatchQueue.main.async(.promise) {
            self.addBackgroundTask()
        }.then(on: DispatchQueue.global()) { _ in
            return self.requestProfile()
        }.map(on: DispatchQueue.global()) { profile in
            if self.options.shouldUpdateProfile {
                self.updateProfile(signalServiceProfile: profile)
            }
            return profile
        }
    }

    private func requestProfile() -> Promise<SignalServiceProfile> {

        guard !options.mainAppOnly || CurrentAppContext().isMainApp else {
            // We usually only refresh profiles in the MainApp to decrease the
            // chance of missed SN notifications in the AppExtension for our users
            // who choose not to verify contacts.
            return Promise(error: ProfileFetchError.notMainApp)
        }

        // Check throttling _before_ possible retries.
        if !options.ignoreThrottling {
            if let lastDate = lastFetchDate(for: subject) {
                let lastTimeInterval = fabs(lastDate.timeIntervalSinceNow)
                // Don't check a profile more often than every N seconds.
                //
                // Throttle less in debug to make it easier to test problems
                // with our fetching logic.
                let kGetProfileMaxFrequencySeconds = _isDebugAssertConfiguration() ? 60 : 60.0 * 5.0
                guard lastTimeInterval > kGetProfileMaxFrequencySeconds else {
                    return Promise(error: ProfileFetchError.throttled)
                }
            }
        }

        recordLastFetchDate(for: subject)

        return requestProfileWithRetries()
    }

    private func requestProfileWithRetries(remainingRetries: Int = 3) -> Promise<SignalServiceProfile> {
        let subject = self.subject

        let (promise, resolver) = Promise<SignalServiceProfile>.pending()
        requestProfileAttempt()
            .done(on: DispatchQueue.global()) { profile in
                resolver.fulfill(profile)
            }.catch(on: DispatchQueue.global()) { error in
                if case .taskError(let task, _)? = error as? NetworkManagerError, task.statusCode() == 404 {
                    resolver.reject(ProfileFetchError.missing)
                    return
                }

                switch error {
                case ProfileFetchError.throttled, ProfileFetchError.notMainApp:
                    // These errors should only be thrown at a higher level.
                    owsFailDebug("Unexpected error: \(error)")
                    resolver.reject(error)
                    return
                case let error as SignalServiceProfile.ValidationError:
                    // This should not be retried.
                    owsFailDebug("skipping updateProfile retry. Invalid profile for: \(subject) error: \(error)")
                    resolver.reject(error)
                    return
                default:
                    guard remainingRetries > 0 else {
                        Logger.warn("failed to get profile with error: \(error)")
                        resolver.reject(error)
                        return
                    }

                    self.requestProfileWithRetries(remainingRetries: remainingRetries - 1)
                        .done(on: DispatchQueue.global()) { profile in
                            resolver.fulfill(profile)
                        }.catch(on: DispatchQueue.global()) { error in
                            resolver.reject(error)
                        }.retainUntilComplete()
                }
            }.retainUntilComplete()
        return promise
    }

    private func requestProfileAttempt() -> Promise<SignalServiceProfile> {
        switch subject {
        case .address(let address):
            return requestProfileAttempt(address: address)
        case .username(let username):
            return requestProfileAttempt(username: username)
        }
    }

    private func requestProfileAttempt(username: String) -> Promise<SignalServiceProfile> {
        Logger.info("username")

        guard options.fetchType != .versioned else {
            return Promise(error: ProfileFetchError.cantRequestVersionedProfile)
        }

        let request = OWSRequestFactory.getProfileRequest(withUsername: username)
        return networkManager.makePromise(request: request)
            .map(on: DispatchQueue.global()) { try SignalServiceProfile(address: nil, responseObject: $1)
        }
    }

    private var shouldUseVersionedFetchForUuids: Bool {
        switch options.fetchType {
        case .default:
            return FeatureFlags.versionedProfiledFetches
        case .versioned:
            return true
        case .unversioned:
            return false
        }
    }

    private func requestProfileAttempt(address: SignalServiceAddress) -> Promise<SignalServiceProfile> {
        Logger.verbose("address: \(address)")

        let shouldUseVersionedFetch = (shouldUseVersionedFetchForUuids
            && address.uuid != nil)

        // Don't use UD for "self" profile fetches.
        var udAccess: OWSUDAccess?
        if !address.isLocalAddress {
            udAccess = udManager.udAccess(forAddress: address,
                                          requireSyncAccess: false)
        }

        let canFailoverUDAuth = true
        var currentVersionedProfileRequest: VersionedProfileRequest?
        let requestMaker = RequestMaker(label: "Profile Fetch",
                                        requestFactoryBlock: { (udAccessKeyForRequest) -> TSRequest? in
                                            // Clear out any existing request.
                                            currentVersionedProfileRequest = nil

                                            if shouldUseVersionedFetch {
                                                do {
                                                    let request = try VersionedProfiles.versionedProfileRequest(address: address, udAccessKey: udAccessKeyForRequest)
                                                    currentVersionedProfileRequest = request
                                                    return request.request
                                                } catch {
                                                    owsFailDebug("Error: \(error)")
                                                    return nil
                                                }
                                            } else {
                                                return OWSRequestFactory.getUnversionedProfileRequest(address: address, udAccessKey: udAccessKeyForRequest)
                                            }
        }, udAuthFailureBlock: {
            // Do nothing
        }, websocketFailureBlock: {
            // Do nothing
        }, address: address,
           udAccess: udAccess,
           canFailoverUDAuth: canFailoverUDAuth)
        return requestMaker.makeRequest()
            .map(on: DispatchQueue.global()) { (result: RequestMakerResult) -> SignalServiceProfile in
                try SignalServiceProfile(address: address, responseObject: result.responseObject)
        }.map(on: DispatchQueue.global()) { (profile: SignalServiceProfile) -> SignalServiceProfile in
            if let profileRequest = currentVersionedProfileRequest {
                VersionedProfiles.didFetchProfile(profile: profile, profileRequest: profileRequest)
            }
            return profile
        }
    }

    private func updateProfile(signalServiceProfile: SignalServiceProfile) {
        let address = signalServiceProfile.address
        verifyIdentityUpToDateAsync(address: address, latestIdentityKey: signalServiceProfile.identityKey)

        profileManager.updateProfile(for: address,
                                     profileNameEncrypted: signalServiceProfile.profileNameEncrypted,
                                     username: signalServiceProfile.username,
                                     avatarUrlPath: signalServiceProfile.avatarUrlPath)

        updateUnidentifiedAccess(address: address,
                                 verifier: signalServiceProfile.unidentifiedAccessVerifier,
                                 hasUnrestrictedAccess: signalServiceProfile.hasUnrestrictedUnidentifiedAccess)
    }

    private func updateUnidentifiedAccess(address: SignalServiceAddress, verifier: Data?, hasUnrestrictedAccess: Bool) {
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
        guard let expectedVerifier = Cryptography.computeSHA256HMAC(dataToVerify, withHMACKey: udAccessKey.keyData) else {
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

    private func verifyIdentityUpToDateAsync(address: SignalServiceAddress, latestIdentityKey: Data) {
        databaseStorage.asyncWrite { (transaction) in
            if self.identityManager.saveRemoteIdentity(latestIdentityKey, address: address, transaction: transaction) {
                Logger.info("updated identity key with fetched profile for recipient: \(address)")
                self.sessionStore.archiveAllSessions(for: address, transaction: transaction)
            } else {
                // no change in identity.
            }
        }
    }

    private func lastFetchDate(for subject: ProfileRequestSubject) -> Date? {
        return ProfileFetcherJob.serialQueue.sync {
            return ProfileFetcherJob.fetchDateMap[subject]
        }
    }

    private func recordLastFetchDate(for subject: ProfileRequestSubject) {
        ProfileFetcherJob.serialQueue.sync {
            ProfileFetcherJob.fetchDateMap[subject] = Date()
        }
    }

    private func addBackgroundTask() {
        backgroundTask = OWSBackgroundTask(label: "\(#function)", completionBlock: { [weak self] status in
            AssertIsOnMainThread()

            guard status == .expired else {
                return
            }
            guard let _ = self else {
                return
            }
            Logger.error("background task time ran out before profile fetch completed.")
        })
    }
}
