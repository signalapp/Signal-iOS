//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

@objc
public class OWS106EnsureProfileComplete: OWSDatabaseMigration {

    let TAG = "[OWS106EnsureProfileComplete]"

    private static var sharedCompleteRegistrationFixerJob: CompleteRegistrationFixerJob?

    // increment a similar constant for each migration.
    class func migrationId() -> String {
        return "106"
    }

    // Overriding runUp since we have some specific completion criteria which
    // is more likely to fail since it involves network requests.
    override public func runUp(completion:@escaping ((Void)) -> Void) {
        let job = CompleteRegistrationFixerJob(completionHandler: {
            Logger.info("\(self.TAG) Completed. Saving.")
            self.save()

            completion()
        })

        type(of: self).sharedCompleteRegistrationFixerJob = job

        job.start()
    }

    /**
     * A previous client bug made it possible for re-registering users to register their new account
     * but never upload new pre-keys. The symptom is that there will be accounts with no uploaded
     * identity key. We detect that here and fix the situation
     */
    private class CompleteRegistrationFixerJob {

        let TAG = "[CompleteRegistrationFixerJob]"

        // Duration between retries if update fails.
        static let kRetryInterval: TimeInterval = 5 * 60

        var timer: Timer?
        let completionHandler: () -> Void

        init(completionHandler: @escaping () -> Void) {
            self.completionHandler = completionHandler
        }

        func start() {
            assert(self.timer == nil)

            let timer = WeakTimer.scheduledTimer(timeInterval: CompleteRegistrationFixerJob.kRetryInterval, target: self, userInfo: nil, repeats: true) { [weak self] aTimer in
                guard let strongSelf = self else {
                    return
                }

                var isCompleted = false
                strongSelf.ensureProfileComplete().then { _ -> Void in
                    guard isCompleted == false else {
                        Logger.info("\(strongSelf.TAG) Already saved. Skipping redundant call.")
                        return
                    }
                    Logger.info("\(strongSelf.TAG) complete. Canceling timer and saving.")
                    isCompleted = true
                    aTimer.invalidate()
                    strongSelf.completionHandler()
                }.catch { error in
                    Logger.error("\(strongSelf.TAG) failed with \(error). We'll try again in \(CompleteRegistrationFixerJob.kRetryInterval) seconds.")
                }.retainUntilComplete()
            }
            self.timer = timer

            timer.fire()
        }

        func ensureProfileComplete() -> Promise<Void> {
            guard let localRecipientId = TSAccountManager.localNumber() else {
                // local app doesn't think we're registered, so nothing to worry about.
                return Promise(value: ())
            }

            let (promise, fulfill, reject) = Promise<Void>.pending()

            guard let networkManager = Environment.current().networkManager else {
                owsFail("\(TAG) network manager was unexpectedly not set")
                return Promise(error: OWSErrorMakeAssertionError())
            }

            ProfileFetcherJob(networkManager: networkManager).getProfile(recipientId: localRecipientId).then { _ -> Void in
                Logger.info("\(self.TAG) verified recipient profile is in good shape: \(localRecipientId)")

                fulfill()
            }.catch { error in
                switch error {
                case SignalServiceProfile.ValidationError.invalidIdentityKey(let description):
                    Logger.warn("\(self.TAG) detected incomplete profile for \(localRecipientId) error: \(description)")
                    // This is the error condition we're looking for. Update prekeys to properly set the identity key, completing registration.
                    TSPreKeyManager.registerPreKeys(with: .signedAndOneTime,
                                                    success: {
                                                        Logger.info("\(self.TAG) successfully uploaded pre-keys. Profile should be fixed.")
                                                        fulfill()
                    },
                                                    failure: { _ in
                                                        reject(OWSErrorWithCodeDescription(.signalServiceFailure, "\(self.TAG) Unknown error in \(#function)"))
                    })
                default:
                    reject(error)
                }
            }.retainUntilComplete()

            return promise
        }
    }
}
