//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

/**
 * Signal is actually two services - textSecure for messages and red phone (for calls). 
 * AccountManager delegates to both.
 */
@objc
public class AccountManager: NSObject {

    let textSecureAccountManager: TSAccountManager
    let networkManager: TSNetworkManager
    let preferences: OWSPreferences

    var pushManager: PushManager {
        // dependency injection hack since PushManager has *alot* of dependencies, and would induce a cycle.
        return PushManager.shared()
    }

    @objc
    public required init(textSecureAccountManager: TSAccountManager, preferences: OWSPreferences) {
        self.networkManager = textSecureAccountManager.networkManager
        self.textSecureAccountManager = textSecureAccountManager
        self.preferences = preferences

        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: registration

    @objc func register(verificationCode: String,
                        pin: String?) -> AnyPromise {
        return AnyPromise(register(verificationCode: verificationCode, pin: pin))
    }

    func register(verificationCode: String,
                  pin: String?) -> Promise<Void> {
        guard verificationCode.count > 0 else {
            let error = OWSErrorWithCodeDescription(.userError,
                                                    NSLocalizedString("REGISTRATION_ERROR_BLANK_VERIFICATION_CODE",
                                                                      comment: "alert body during registration"))
            return Promise(error: error)
        }

        Logger.debug("registering with signal server")
        let registrationPromise: Promise<Void> = firstly {
            return self.registerForTextSecure(verificationCode: verificationCode, pin: pin)
        }.then {
            return self.syncPushTokens()
        }.recover { (error) -> Promise<Void> in
            switch error {
            case PushRegistrationError.pushNotSupported(let description):
                // This can happen with:
                // - simulators, none of which support receiving push notifications
                // - on iOS11 devices which have disabled "Allow Notifications" and disabled "Enable Background Refresh" in the system settings.
                Logger.info("Recovered push registration error. Registering for manual message fetcher because push not supported: \(description)")
                return self.registerForManualMessageFetching()
            default:
                throw error
            }
        }.then {
            self.completeRegistration()
        }

        registrationPromise.retainUntilComplete()

        return registrationPromise
    }

    private func registerForTextSecure(verificationCode: String,
                                       pin: String?) -> Promise<Void> {
        return Promise { fulfill, reject in
            self.textSecureAccountManager.verifyAccount(withCode: verificationCode,
                                                        pin: pin,
                                                        success: fulfill,
                                                        failure: reject)
        }
    }

    private func syncPushTokens() -> Promise<Void> {
        Logger.info("")
        let job = SyncPushTokensJob(accountManager: self, preferences: self.preferences)
        job.uploadOnlyIfStale = false
        return job.run()
    }

    private func completeRegistration() {
        Logger.info("")
        self.textSecureAccountManager.didRegister()
    }

    // MARK: Message Delivery

    func updatePushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        return Promise { fulfill, reject in
            self.textSecureAccountManager.registerForPushNotifications(pushToken: pushToken,
                                                                       voipToken: voipToken,
                                                                       success: fulfill,
                                                                       failure: reject)
        }
    }

    func registerForManualMessageFetching() -> Promise<Void> {
        return Promise { fulfill, reject in
            self.textSecureAccountManager.registerForManualMessageFetching(success: fulfill, failure: reject)
        }
    }

    // MARK: Turn Server

    func getTurnServerInfo() -> Promise<TurnServerInfo> {
        return Promise { fulfill, reject in
            self.networkManager.makeRequest(OWSRequestFactory.turnServerInfoRequest(),
                                            success: { (_: URLSessionDataTask, responseObject: Any?) in
                                                guard responseObject != nil else {
                                                    return reject(OWSErrorMakeUnableToProcessServerResponseError())
                                                }

                                                if let responseDictionary = responseObject as? [String: AnyObject] {
                                                    if let turnServerInfo = TurnServerInfo(attributes: responseDictionary) {
                                                        return fulfill(turnServerInfo)
                                                    }
                                                    Logger.error("unexpected server response:\(responseDictionary)")
                                                }
                                                return reject(OWSErrorMakeUnableToProcessServerResponseError())
            },
                                            failure: { (_: URLSessionDataTask, error: Error) in
                                                    return reject(error)
            })
        }
    }

}
