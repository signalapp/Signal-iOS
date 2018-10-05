//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

@objc
public class ProfileFetcherJob: NSObject {

    // This property is only accessed on the main queue.
    static var fetchDateMap = [String: Date]()

    let ignoreThrottling: Bool

    var backgroundTask: OWSBackgroundTask?

    @objc
    public class func run(thread: TSThread) {
        ProfileFetcherJob().run(recipientIds: thread.recipientIdentifiers)
    }

    @objc
    public class func run(recipientId: String, ignoreThrottling: Bool) {
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

    // MARK: -

    public func run(recipientIds: [String]) {
        AssertIsOnMainThread()

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

        if (!CurrentAppContext().isMainApp) {
            // Only refresh profiles in the MainApp to decrease the chance of missed SN notifications
            // in the AppExtension for our users who choose not to verify contacts.
            owsFailDebug("Should only fetch profiles in the main app")
            return
        }

        DispatchQueue.main.async {
            for recipientId in recipientIds {
                self.updateProfile(recipientId: recipientId)
            }
        }
    }

    enum ProfileFetcherJobError: Error {
        case throttled(lastTimeInterval: TimeInterval),
             unknownNetworkError
    }

    public func updateProfile(recipientId: String, remainingRetries: Int = 3) {
        self.getProfile(recipientId: recipientId).then { profile in
            self.updateProfile(signalServiceProfile: profile)
        }.catch { error in
            switch error {
            case ProfileFetcherJobError.throttled(let lastTimeInterval):
                Logger.info("skipping updateProfile: \(recipientId), lastTimeInterval: \(lastTimeInterval)")
            case let error as SignalServiceProfile.ValidationError:
                Logger.warn("skipping updateProfile retry. Invalid profile for: \(recipientId) error: \(error)")
            default:
                if remainingRetries > 0 {
                    self.updateProfile(recipientId: recipientId, remainingRetries: remainingRetries - 1)
                } else {
                    Logger.error("failed to get profile with error: \(error)")
                }
            }
        }.retainUntilComplete()
    }

    public func getProfile(recipientId: String) -> Promise<SignalServiceProfile> {
        AssertIsOnMainThread()
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

        let request = OWSRequestFactory.getProfileRequest(withRecipientId: recipientId)

        let (promise, fulfill, reject) = Promise<SignalServiceProfile>.pending()

        // TODO: Use UD socket for some profile gets.
        if socketManager.canMakeRequests(of: .default) {
            self.socketManager.make(request,
                                    webSocketType: .default,
                success: { (responseObject: Any?) -> Void in
                    do {
                        let profile = try SignalServiceProfile(recipientId: recipientId, responseObject: responseObject)
                        fulfill(profile)
                    } catch {
                        reject(error)
                    }
            },
                failure: { (_: NSInteger, _:Data?, error: Error) in
                    reject(error)
            })
        } else {
            self.networkManager.makeRequest(request,
                success: { (_: URLSessionDataTask?, responseObject: Any?) -> Void in
                    do {
                        let profile = try SignalServiceProfile(recipientId: recipientId, responseObject: responseObject)
                        fulfill(profile)
                    } catch {
                        reject(error)
                    }
            },
                failure: { (_: URLSessionDataTask?, error: Error?) in

                    if let error = error {
                        reject(error)
                    }

                    reject(ProfileFetcherJobError.unknownNetworkError)
            })
        }

        return promise
    }

    private func updateProfile(signalServiceProfile: SignalServiceProfile) {
        let recipientId = signalServiceProfile.recipientId
        verifyIdentityUpToDateAsync(recipientId: recipientId, latestIdentityKey: signalServiceProfile.identityKey)

        profileManager.updateProfile(forRecipientId: recipientId,
                                     profileNameEncrypted: signalServiceProfile.profileNameEncrypted,
                                     avatarUrlPath: signalServiceProfile.avatarUrlPath)

        var supportsUnidentifiedDelivery = false
        if let unidentifiedAccessVerifier = signalServiceProfile.unidentifiedAccessVerifier,
            let udAccessKey = udManager.udAccessKeyForRecipient(recipientId) {
            let dataToVerify = Data(count: 32)
            if let expectedVerfier = Cryptography.computeSHA256HMAC(dataToVerify, withHMACKey: udAccessKey.keyData) {
                supportsUnidentifiedDelivery = expectedVerfier == unidentifiedAccessVerifier
            } else {
                owsFailDebug("could not verify UD")
            }
        }

        // TODO: We may want to only call setSupportsUnidentifiedDelivery if
        // supportsUnidentifiedDelivery is true.
        udManager.setSupportsUnidentifiedDelivery(supportsUnidentifiedDelivery, recipientId: recipientId)

        udManager.setShouldAllowUnrestrictedAccess(recipientId: recipientId, shouldAllowUnrestrictedAccess: signalServiceProfile.hasUnrestrictedUnidentifiedAccess)
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

@objc
public class SignalServiceProfile: NSObject {

    public enum ValidationError: Error {
        case invalid(description: String)
        case invalidIdentityKey(description: String)
        case invalidProfileName(description: String)
    }

    public let recipientId: String
    public let identityKey: Data
    public let profileNameEncrypted: Data?
    public let avatarUrlPath: String?
    public let unidentifiedAccessVerifier: Data?
    public let hasUnrestrictedUnidentifiedAccess: Bool

    init(recipientId: String, responseObject: Any?) throws {
        self.recipientId = recipientId

        guard let params = ParamParser(responseObject: responseObject) else {
            throw ValidationError.invalid(description: "invalid response: \(String(describing: responseObject))")
        }

        let identityKeyWithType = try params.requiredBase64EncodedData(key: "identityKey")
        let kIdentityKeyLength = 33
        guard identityKeyWithType.count == kIdentityKeyLength else {
            throw ValidationError.invalidIdentityKey(description: "malformed identity key \(identityKeyWithType.hexadecimalString) with decoded length: \(identityKeyWithType.count)")
        }
        // `removeKeyType` is an objc category method only on NSData, so temporarily cast.
        self.identityKey = (identityKeyWithType as NSData).removeKeyType() as Data

        self.profileNameEncrypted = try params.optionalBase64EncodedData(key: "name")

        let avatarUrlPath: String? = try params.optional(key: "avatar")
        self.avatarUrlPath = avatarUrlPath

        self.unidentifiedAccessVerifier = try params.optionalBase64EncodedData(key: "unidentifiedAccess")

        self.hasUnrestrictedUnidentifiedAccess = try params.optional(key: "unrestrictedUnidentifiedAccess") ?? false
    }
}
