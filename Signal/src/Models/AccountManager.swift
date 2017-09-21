//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

/**
 * Signal is actually two services - textSecure for messages and red phone (for calls). 
 * AccountManager delegates to both.
 */
class AccountManager: NSObject {
    let TAG = "[AccountManager]"
    let textSecureAccountManager: TSAccountManager
    let networkManager: TSNetworkManager
    let preferences: PropertyListPreferences

    var pushManager: PushManager {
        // dependency injection hack since PushManager has *alot* of dependencies, and would induce a cycle.
        return PushManager.shared()
    }

    required init(textSecureAccountManager: TSAccountManager, preferences: PropertyListPreferences) {
        self.networkManager = textSecureAccountManager.networkManager
        self.textSecureAccountManager = textSecureAccountManager
        self.preferences = preferences
    }

    // MARK: registration

    @objc func register(verificationCode: String) -> AnyPromise {
        return AnyPromise(register(verificationCode: verificationCode))
    }

    func register(verificationCode: String) -> Promise<Void> {
        guard verificationCode.characters.count > 0 else {
            let error = OWSErrorWithCodeDescription(.userError,
                                                    NSLocalizedString("REGISTRATION_ERROR_BLANK_VERIFICATION_CODE",
                                                                      comment: "alert body during registration"))
            return Promise(error: error)
        }

        Logger.debug("\(self.TAG) registering with signal server")
        let registrationPromise: Promise<Void> = firstly {
            self.registerForTextSecure(verificationCode: verificationCode)
        }.then {
            self.syncPushTokens()
        }.then {
            self.completeRegistration()
        }

        registrationPromise.retainUntilComplete()

        return registrationPromise
    }

    private func registerForTextSecure(verificationCode: String) -> Promise<Void> {
        return Promise { fulfill, reject in
            self.textSecureAccountManager.verifyAccount(withCode:verificationCode,
                                                        success:fulfill,
                                                        failure:reject)
        }
    }

    private func syncPushTokens() -> Promise<Void> {
        Logger.info("\(self.TAG) in \(#function)")
        return SyncPushTokensJob.run(pushManager: self.pushManager, accountManager: self, preferences: self.preferences)
    }

    private func completeRegistration() {
        Logger.info("\(self.TAG) in \(#function)")
        self.textSecureAccountManager.didRegister()
        TSSocketManager.requestSocketOpen()
    }

    // MARK: Push Tokens

    func updatePushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        return firstly {
            return self.updateTextSecurePushTokens(pushToken: pushToken, voipToken: voipToken)
        }.then {
            Logger.info("\(self.TAG) Successfully updated text secure push tokens.")
            // TODO code cleanup - convert to `return Promise(value: nil)` and test
            return Promise { fulfill, _ in
                fulfill()
            }
        }
    }

    private func updateTextSecurePushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        return Promise { fulfill, reject in
            self.textSecureAccountManager.registerForPushNotifications(pushToken:pushToken,
                                                                       voipToken:voipToken,
                                                                       success:fulfill,
                                                                       failure:reject)
        }
    }

    // MARK: Turn Server

    func getTurnServerInfo() -> Promise<TurnServerInfo> {
        return Promise { fulfill, reject in
            self.networkManager.makeRequest(TurnServerInfoRequest(),
                                            success: { (_: URLSessionDataTask, responseObject: Any?) in
                                                guard responseObject != nil else {
                                                    return reject(OWSErrorMakeUnableToProcessServerResponseError())
                                                }

                                                if let responseDictionary = responseObject as? [String: AnyObject] {
                                                    if let turnServerInfo = TurnServerInfo(attributes:responseDictionary) {
                                                        return fulfill(turnServerInfo)
                                                    }
                                                    Logger.error("\(self.TAG) unexpected server response:\(responseDictionary)")
                                                }
                                                return reject(OWSErrorMakeUnableToProcessServerResponseError())
            },
                                            failure: { (_: URLSessionDataTask, error: Error) in
                                                    return reject(error)
            })
        }
    }

}
