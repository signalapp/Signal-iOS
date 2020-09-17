//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

@objc
public class OWS106EnsureProfileComplete: YDBDatabaseMigration {

    private static var sharedCompleteRegistrationFixerJob: CompleteRegistrationFixerJob?

    // increment a similar constant for each migration.
    @objc
    public override class var migrationId: String {
        return "106"
    }

    // Overriding runUp since we have some specific completion criteria which
    // is more likely to fail since it involves network requests.
    override public func runUp(completion:@escaping () -> Void) {
        let job = CompleteRegistrationFixerJob(completionHandler: { (didSucceed) in

            if didSucceed {
                Logger.info("Completed. Saving.")

                self.markAsCompleteWithSneakyTransaction()
            } else {
                Logger.error("Failed.")
            }

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
    private class CompleteRegistrationFixerJob: NSObject {

        // MARK: - Dependencies

        private var tsAccountManager: TSAccountManager {
            return TSAccountManager.shared()
        }

        // MARK: -

        // Duration between retries if update fails.
        let kRetryInterval: TimeInterval = 5

        let completionHandler: (Bool) -> Void

        init(completionHandler: @escaping (Bool) -> Void) {
            self.completionHandler = completionHandler
        }

        func start() {
            guard tsAccountManager.isRegistered else {
                self.completionHandler(true)
                return
            }

            self.ensureProfileComplete().done {
                Logger.info("complete. Canceling timer and saving.")
                self.completionHandler(true)
            }.catch { error in
                let nserror = error as NSError
                if nserror.domain == TSNetworkManagerErrorDomain {
                    // Don't retry if we had an unrecoverable error.
                    // In particular, 401 (invalid auth) is unrecoverable.
                    let isUnrecoverableError = nserror.code == 401
                    if isUnrecoverableError {
                        Logger.error("failed due to unrecoverable error: \(error). Aborting.")
                        self.completionHandler(true)
                        return
                    }
                }

                Logger.error("failed with \(error).")
                self.completionHandler(false)
            }
        }

        func ensureProfileComplete() -> Promise<Void> {
            guard let localAddress = TSAccountManager.localAddress, localAddress.isValid else {
                // local app doesn't think we're registered, so nothing to worry about.
                return Promise.value(())
            }

            return firstly {
                return ProfileFetcherJob.fetchProfilePromise(address: localAddress,
                                                                      ignoreThrottling: true)
            }.done { _ in
                Logger.info("verified recipient profile is in good shape: \(localAddress)")
            }.recover { error -> Promise<Void> in
                switch error {
                case SignalServiceProfile.ValidationError.invalidIdentityKey(let description):
                    Logger.warn("detected incomplete profile for \(localAddress) error: \(description)")

                    let (promise, resolver) = Promise<Void>.pending()
                    // This is the error condition we're looking for. Update prekeys to properly set the identity key, completing registration.
                    TSPreKeyManager.createPreKeys(success: {
                        Logger.info("successfully uploaded pre-keys. Profile should be fixed.")
                        resolver.fulfill(())
                    },
                                                  failure: { _ in
                                                    resolver.reject(OWSErrorWithCodeDescription(.signalServiceFailure, "\(self.logTag) Unknown error"))
                    })

                    return promise
                default:
                    throw error
                }
            }
        }
    }
}
