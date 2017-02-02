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
    let redPhoneAccountManager: RPAccountManager

    required init(textSecureAccountManager: TSAccountManager, redPhoneAccountManager: RPAccountManager) {
        self.networkManager = textSecureAccountManager.networkManager
        self.textSecureAccountManager = textSecureAccountManager
        self.redPhoneAccountManager = redPhoneAccountManager
    }

    // MARK: registration

    @objc func register(verificationCode: String) -> AnyPromise {
        return AnyPromise(register(verificationCode: verificationCode))
    }

    func register(verificationCode: String) -> Promise<Void> {
        return firstly {
            Promise { fulfill, reject in
                if verificationCode.characters.count == 0 {
                    let error = OWSErrorWithCodeDescription(.userError,
                                                            NSLocalizedString("REGISTRATION_ERROR_BLANK_VERIFICATION_CODE",
                                                                              comment: "alert body during registration"))
                    reject(error)
                }
                fulfill()
            }
        }.then {
            Logger.debug("\(self.TAG) verification code looks well formed.")
            return self.registerForTextSecure(verificationCode: verificationCode)
        }.then {
            Logger.debug("\(self.TAG) successfully registered for TextSecure")
            return self.fetchRedPhoneToken()
        }.then { (redphoneToken: String) in
            Logger.debug("\(self.TAG) successfully fetched redPhone token")
            return self.registerForRedPhone(tsToken:redphoneToken)
        }.then {
            Logger.debug("\(self.TAG) successfully registered with RedPhone")
        }
    }

    private func registerForTextSecure(verificationCode: String) -> Promise<Void> {
        return Promise { fulfill, reject in
            let isWebRTCEnabled = Environment.preferences().isWebRTCEnabled()
            self.textSecureAccountManager.verifyAccount(withCode:verificationCode,
                                                        isWebRTCEnabled:isWebRTCEnabled,
                                                        success:fulfill,
                                                        failure:reject)
        }
    }

    private func fetchRedPhoneToken() -> Promise<String> {
        return Promise { fulfill, reject in
            self.textSecureAccountManager.obtainRPRegistrationToken(success:fulfill,
                                                                    failure:reject)
        }
    }

    private func registerForRedPhone(tsToken: String) -> Promise<Void> {
        return Promise { fulfill, reject in
            self.redPhoneAccountManager.register(withTsToken:tsToken,
                                                 success:fulfill,
                                                 failure:reject)
        }
    }

    // MARK: Push Tokens

    func updatePushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        return firstly {
            return self.updateTextSecurePushTokens(pushToken: pushToken, voipToken: voipToken)
        }.then {
            Logger.info("\(self.TAG) Successfully updated text secure push tokens.")
            // TODO should be possible to do these in parallel. 
            // We want to make sure that either can complete independently of the other.
            return self.updateRedPhonePushTokens(pushToken:pushToken, voipToken:voipToken)
        }.then {
            Logger.info("\(self.TAG) Successfully updated red phone push tokens.")
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

    private func updateRedPhonePushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        return Promise { fulfill, reject in
            self.redPhoneAccountManager.registerForPushNotifications(pushToken:pushToken,
                                                                     voipToken:voipToken,
                                                                     success:fulfill,
                                                                     failure:reject)
        }
    }

    // MARK: Turn Server

    func getTurnServerInfo() -> Promise<TurnServerInfo> {
        return Promise { fulfill, reject in
            self.networkManager.makeRequest(TurnServerInfoRequest(),
                                            success: { (task: URLSessionDataTask, responseObject: Any?) in
                                                guard responseObject != nil else {
                                                    return reject(OWSErrorMakeUnableToProcessServerResponseError())
                                                }

                                                if let responseDictionary = responseObject as? [String: AnyObject] {
                                                    if let turnServerInfo = TurnServerInfo(attributes:responseDictionary) {
                                                        Logger.debug("\(self.TAG) got valid turnserver info")
                                                        return fulfill(turnServerInfo)
                                                    }
                                                    Logger.error("\(self.TAG) unexpected server response:\(responseDictionary)")
                                                }
                                                return reject(OWSErrorMakeUnableToProcessServerResponseError())
            },
                                            failure: { (task: URLSessionDataTask, error: Error) in
                                                    return reject(error)
            })
        }
    }

}
