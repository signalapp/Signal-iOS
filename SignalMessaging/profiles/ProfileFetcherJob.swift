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
    static var fetchDateMap = [String: Date]()

    let ignoreThrottling: Bool

    var backgroundTask: OWSBackgroundTask?

    @objc
    public class func run(thread: TSThread) {
        guard CurrentAppContext().isMainApp else {
            return
        }

        ProfileFetcherJob().run(recipientIds: thread.recipientIdentifiers)
    }

    @objc
    public class func run(recipientId: String, ignoreThrottling: Bool) {
        guard CurrentAppContext().isMainApp else {
            return
        }

        ProfileFetcherJob(ignoreThrottling: ignoreThrottling).run(recipientIds: [recipientId])
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

    // MARK: -

    public func run(recipientIds: [String]) {
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
            for recipientId in recipientIds {
                self.getAndUpdateProfile(recipientId: recipientId)
            }
        }
    }

    enum ProfileFetcherJobError: Error {
        case throttled(lastTimeInterval: TimeInterval)
    }

    public func getAndUpdateProfile(recipientId: String, remainingRetries: Int = 3) {
        self.getProfile(recipientId: recipientId).map(on: DispatchQueue.global()) { profile in
            self.updateProfile(signalServiceProfile: profile)
        }.catch(on: DispatchQueue.global()) { error in
            switch error {
            case ProfileFetcherJobError.throttled(let lastTimeInterval):
                Logger.info("skipping updateProfile: \(recipientId), lastTimeInterval: \(lastTimeInterval)")
            case let error as SignalServiceProfile.ValidationError:
                Logger.warn("skipping updateProfile retry. Invalid profile for: \(recipientId) error: \(error)")
            default:
                if remainingRetries > 0 {
                    self.getAndUpdateProfile(recipientId: recipientId, remainingRetries: remainingRetries - 1)
                } else {
                    Logger.error("failed to get profile with error: \(error)")
                }
            }
        }.retainUntilComplete()
    }

    public func getProfile(recipientId: String) -> Promise<SignalServiceProfile> {
        if !ignoreThrottling {
            if let lastDate = ProfileFetcherJob.fetchDateMap[recipientId] {
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
        ProfileFetcherJob.fetchDateMap[recipientId] = Date()

        Logger.error("getProfile: \(recipientId)")

        // Don't use UD for "self" profile fetches.
        var udAccess: OWSUDAccess?
        if recipientId != tsAccountManager.localNumber() {
            udAccess = udManager.udAccess(forRecipientId: recipientId,
                                          requireSyncAccess: false)
        }

        return requestProfile(recipientId: recipientId,
                              udAccess: udAccess,
                              canFailoverUDAuth: true)
    }

    private func requestProfile(recipientId: String,
                                udAccess: OWSUDAccess?,
                                canFailoverUDAuth: Bool) -> Promise<SignalServiceProfile> {
        let requestMaker = RequestMaker(label: "Profile Fetch",
                                        requestFactoryBlock: { (udAccessKeyForRequest) -> TSRequest in
            return OWSRequestFactory.getProfileRequest(recipientId: recipientId, udAccessKey: udAccessKeyForRequest)
        }, udAuthFailureBlock: {
            // Do nothing
        }, websocketFailureBlock: {
            // Do nothing
        }, recipientId: recipientId,
           udAccess: udAccess,
           canFailoverUDAuth: canFailoverUDAuth)
        return requestMaker.makeRequest()
            .map(on: DispatchQueue.global()) { (result: RequestMakerResult) -> SignalServiceProfile in
                try SignalServiceProfile(recipientId: recipientId, responseObject: result.responseObject)
        }
    }

    private func updateProfile(signalServiceProfile: SignalServiceProfile) {
        let recipientId = signalServiceProfile.recipientId
        verifyIdentityUpToDateAsync(recipientId: recipientId, latestIdentityKey: signalServiceProfile.identityKey)

        profileManager.updateProfile(forRecipientId: recipientId,
                                     profileNameEncrypted: signalServiceProfile.profileNameEncrypted,
                                     avatarUrlPath: signalServiceProfile.avatarUrlPath)

        updateUnidentifiedAccess(recipientId: recipientId,
                                 verifier: signalServiceProfile.unidentifiedAccessVerifier,
                                 hasUnrestrictedAccess: signalServiceProfile.hasUnrestrictedUnidentifiedAccess)
    }

    private func updateUnidentifiedAccess(recipientId: String, verifier: Data?, hasUnrestrictedAccess: Bool) {
        guard let verifier = verifier else {
            // If there is no verifier, at least one of this user's devices
            // do not support UD.
            udManager.setUnidentifiedAccessMode(.disabled, recipientId: recipientId)
            return
        }

        if hasUnrestrictedAccess {
            udManager.setUnidentifiedAccessMode(.unrestricted, recipientId: recipientId)
            return
        }

        guard let udAccessKey = udManager.udAccessKey(forRecipientId: recipientId) else {
            udManager.setUnidentifiedAccessMode(.disabled, recipientId: recipientId)
            return
        }

        let dataToVerify = Data(count: 32)
        guard let expectedVerifier = Cryptography.computeSHA256HMAC(dataToVerify, withHMACKey: udAccessKey.keyData) else {
            owsFailDebug("could not compute verification")
            udManager.setUnidentifiedAccessMode(.disabled, recipientId: recipientId)
            return
        }

        guard expectedVerifier.ows_constantTimeIsEqual(to: verifier) else {
            Logger.verbose("verifier mismatch, new profile key?")
            udManager.setUnidentifiedAccessMode(.disabled, recipientId: recipientId)
            return
        }

        udManager.setUnidentifiedAccessMode(.enabled, recipientId: recipientId)
    }

    private func verifyIdentityUpToDateAsync(recipientId: String, latestIdentityKey: Data) {
        primaryStorage.newDatabaseConnection().asyncReadWrite { (transaction) in
            if self.identityManager.saveRemoteIdentity(latestIdentityKey, recipientId: recipientId, protocolContext: transaction) {
                Logger.info("updated identity key with fetched profile for recipient: \(recipientId)")
                self.primaryStorage.archiveAllSessions(forContact: recipientId, protocolContext: transaction)
            } else {
                // no change in identity.
            }
        }
    }
}
