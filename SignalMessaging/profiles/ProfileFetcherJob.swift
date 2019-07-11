//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import SignalMetadataKit

@objc
public class ProfileFetcherJob: NSObject {

    // This property is only accessed on the main queue.
    static var fetchDateMap = [SignalServiceAddress: Date]()

    let ignoreThrottling: Bool

    var backgroundTask: OWSBackgroundTask?

    @objc
    public class func run(thread: TSThread) {
        guard CurrentAppContext().isMainApp else {
            return
        }

        ProfileFetcherJob().run(addresses: thread.recipientAddresses)
    }

    @objc
    public class func run(address: SignalServiceAddress, ignoreThrottling: Bool) {
        guard CurrentAppContext().isMainApp else {
            return
        }

        ProfileFetcherJob(ignoreThrottling: ignoreThrottling).run(addresses: [address])
    }

    public init(ignoreThrottling: Bool = false) {
        self.ignoreThrottling = ignoreThrottling
    }

    // MARK: - Dependencies

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private var socketManager: TSSocketManager {
        return TSSocketManager.shared
    }

    private var primaryStorage: OWSPrimaryStorage {
        return SSKEnvironment.shared.primaryStorage
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

    // MARK: -

    public func run(addresses: [SignalServiceAddress]) {
        AssertIsOnMainThread()

        guard CurrentAppContext().isMainApp else {
            // Only refresh profiles in the MainApp to decrease the chance of missed SN notifications
            // in the AppExtension for our users who choose not to verify contacts.
            owsFailDebug("Should only fetch profiles in the main app")
            return
        }

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

        DispatchQueue.global().async {
            for address in addresses {
                self.getAndUpdateProfile(address: address)
            }
        }
    }

    enum ProfileFetcherJobError: Error {
        case throttled(lastTimeInterval: TimeInterval)
    }

    public func getAndUpdateProfile(address: SignalServiceAddress, remainingRetries: Int = 3) {
        self.getProfile(address: address).map(on: DispatchQueue.global()) { profile in
            self.updateProfile(signalServiceProfile: profile)
        }.catch(on: DispatchQueue.global()) { error in
            switch error {
            case ProfileFetcherJobError.throttled:
                // skipping
                break
            case let error as SignalServiceProfile.ValidationError:
                Logger.warn("skipping updateProfile retry. Invalid profile for: \(address) error: \(error)")
            default:
                if remainingRetries > 0 {
                    self.getAndUpdateProfile(address: address, remainingRetries: remainingRetries - 1)
                } else {
                    Logger.error("failed to get profile with error: \(error)")
                }
            }
        }.retainUntilComplete()
    }

    public func getProfile(address: SignalServiceAddress) -> Promise<SignalServiceProfile> {
        if !ignoreThrottling {
            if let lastDate = ProfileFetcherJob.fetchDateMap[address] {
                let lastTimeInterval = fabs(lastDate.timeIntervalSinceNow)
                // Don't check a profile more often than every N seconds.
                //
                // Throttle less in debug to make it easier to test problems
                // with our fetching logic.
                let kGetProfileMaxFrequencySeconds = _isDebugAssertConfiguration() ? 60 : 60.0 * 5.0
                guard lastTimeInterval > kGetProfileMaxFrequencySeconds else {
                    return Promise(error: ProfileFetcherJobError.throttled(lastTimeInterval: lastTimeInterval))
                }
            }
        }
        ProfileFetcherJob.fetchDateMap[address] = Date()

        Logger.error("getProfile: \(address)")

        // Don't use UD for "self" profile fetches.
        var udAccess: OWSUDAccess?
        if !address.isLocalAddress {
            udAccess = udManager.udAccess(forAddress: address,
                                          requireSyncAccess: false)
        }

        return requestProfile(address: address,
                              udAccess: udAccess,
                              canFailoverUDAuth: true)
    }

    private func requestProfile(address: SignalServiceAddress,
                                udAccess: OWSUDAccess?,
                                canFailoverUDAuth: Bool) -> Promise<SignalServiceProfile> {
        let requestMaker = RequestMaker(label: "Profile Fetch",
                                        requestFactoryBlock: { (udAccessKeyForRequest) -> TSRequest in
            return OWSRequestFactory.getProfileRequest(address: address, udAccessKey: udAccessKeyForRequest)
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
        }
    }

    private func updateProfile(signalServiceProfile: SignalServiceProfile) {
        let address = signalServiceProfile.address
        verifyIdentityUpToDateAsync(address: address, latestIdentityKey: signalServiceProfile.identityKey)

        profileManager.updateProfile(for: address,
                                     profileNameEncrypted: signalServiceProfile.profileNameEncrypted,
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
        primaryStorage.newDatabaseConnection().asyncReadWrite { (transaction) in
            if self.identityManager.saveRemoteIdentity(latestIdentityKey, address: address, transaction: transaction.asAnyWrite) {
                Logger.info("updated identity key with fetched profile for recipient: \(address)")
                self.sessionStore.archiveAllSessions(for: address, transaction: transaction.asAnyWrite)
            } else {
                // no change in identity.
            }
        }
    }
}
