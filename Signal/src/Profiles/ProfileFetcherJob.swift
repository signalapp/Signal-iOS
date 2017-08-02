//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
class ProfileFetcherJob: NSObject {

    let TAG = "[ProfileFetcherJob]"

    let networkManager: TSNetworkManager
    let storageManager: TSStorageManager

    // This property is only accessed on the main queue.
    static var fetchDateMap = [String: Date]()

    public class func run(thread: TSThread, networkManager: TSNetworkManager) {
        ProfileFetcherJob(networkManager: networkManager).run(recipientIds: thread.recipientIdentifiers)
    }

    public class func run(recipientId: String, networkManager: TSNetworkManager) {
        ProfileFetcherJob(networkManager: networkManager).run(recipientIds: [recipientId])
    }

    init(networkManager: TSNetworkManager) {
        self.networkManager = networkManager
        self.storageManager = TSStorageManager.shared()
    }

    public func run(recipientIds: [String]) {
        AssertIsOnMainThread()

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
                Logger.info("\(self.TAG) skipping updateProfile: \(recipientId), lastTimeInterval: \(lastTimeInterval)")
            case let error as SignalServiceProfile.ValidationError:
                Logger.warn("\(self.TAG) skipping updateProfile retry. Invalid profile for: \(recipientId) error: \(error)")
            default:
                if remainingRetries > 0 {
                    self.updateProfile(recipientId: recipientId, remainingRetries: remainingRetries - 1)
                } else {
                    owsFail("\(self.TAG) in \(#function) failed to get profile with error: \(error)")
                }
            }
        }.retainUntilComplete()
    }

    public func getProfile(recipientId: String) -> Promise<SignalServiceProfile> {
        AssertIsOnMainThread()
        if let lastDate = ProfileFetcherJob.fetchDateMap[recipientId] {
            let lastTimeInterval = fabs(lastDate.timeIntervalSinceNow)
            // Don't check a profile more often than every N minutes.
            //
            // Only throttle profile fetch in production builds in order to
            // facilitate debugging.
            let kGetProfileMaxFrequencySeconds = _isDebugAssertConfiguration() ? 0 : 60.0 * 5.0
            guard lastTimeInterval > kGetProfileMaxFrequencySeconds else {
                return Promise(error: ProfileFetcherJobError.throttled(lastTimeInterval: lastTimeInterval))
            }
        }
        ProfileFetcherJob.fetchDateMap[recipientId] = Date()

        Logger.error("\(self.TAG) getProfile: \(recipientId)")

        let request = OWSGetProfileRequest(recipientId: recipientId)

        let (promise, fulfill, reject) = Promise<SignalServiceProfile>.pending()

        self.networkManager.makeRequest(
            request,
            success: { (_: URLSessionDataTask?, responseObject: Any?) -> Void in
                do {
                    let profile = try SignalServiceProfile(recipientId: recipientId, rawResponse: responseObject)
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

        return promise
    }

    private func updateProfile(signalServiceProfile: SignalServiceProfile) {
        verifyIdentityUpToDateAsync(recipientId: signalServiceProfile.recipientId, latestIdentityKey: signalServiceProfile.identityKey)

        // Eventually we'll want to do more things with new SignalServiceProfile fields here.
    }

    private func verifyIdentityUpToDateAsync(recipientId: String, latestIdentityKey: Data) {
        OWSDispatch.sessionStoreQueue().async {
            if OWSIdentityManager.shared().saveRemoteIdentity(latestIdentityKey, recipientId: recipientId) {
                Logger.info("\(self.TAG) updated identity key with fetched profile for recipient: \(recipientId)")
                self.storageManager.archiveAllSessions(forContact: recipientId)
            } else {
                // no change in identity.
            }
        }
    }
}

struct SignalServiceProfile {
    let TAG = "[SignalServiceProfile]"

    enum ValidationError: Error {
        case invalid(description: String)
        case invalidIdentityKey(description: String)
    }

    public let recipientId: String
    public let identityKey: Data

    init(recipientId: String, rawResponse: Any?) throws {
        self.recipientId = recipientId

        guard let responseDict = rawResponse as? [String: Any?] else {
            throw ValidationError.invalid(description: "\(TAG) unexpected type: \(String(describing: rawResponse))")
        }

        guard let identityKeyString = responseDict["identityKey"] as? String else {
            throw ValidationError.invalidIdentityKey(description: "\(TAG) missing identity key: \(String(describing: rawResponse))")
        }

        guard let identityKeyWithType = Data(base64Encoded: identityKeyString) else {
            throw ValidationError.invalidIdentityKey(description: "\(TAG) unable to parse identity key: \(identityKeyString)")
        }

        let kIdentityKeyLength = 33
        guard identityKeyWithType.count == kIdentityKeyLength else {
            throw ValidationError.invalidIdentityKey(description: "\(TAG) malformed key \(identityKeyString) with decoded length: \(identityKeyWithType.count)")
        }

        // `removeKeyType` is an objc category method only on NSData, so temporarily cast.
        self.identityKey = (identityKeyWithType as NSData).removeKeyType() as Data
    }
}
