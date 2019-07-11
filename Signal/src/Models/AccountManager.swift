//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

    // MARK: - Dependencies

    var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    private var networkManager: TSNetworkManager {
        return SSKEnvironment.shared.networkManager
    }

    private var preferences: OWSPreferences {
        return Environment.shared.preferences
    }

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var accountServiceClient: AccountServiceClient {
        return AccountServiceClient.shared
    }

    var pushRegistrationManager: PushRegistrationManager {
        return AppEnvironment.shared.pushRegistrationManager
    }

    // MARK: -

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            if self.tsAccountManager.isRegistered {
                self.recordUuidIfNecessary()
            }
        }
    }

    // MARK: registration

    @objc
    func requestAccountVerificationObjC(recipientId: String, captchaToken: String?, isSMS: Bool) -> AnyPromise {
        return AnyPromise(requestAccountVerification(recipientId: recipientId, captchaToken: captchaToken, isSMS: isSMS))
    }

    func requestAccountVerification(recipientId: String, captchaToken: String?, isSMS: Bool) -> Promise<Void> {
        let transport: TSVerificationTransport = isSMS ? .SMS : .voice

        return firstly { () -> Promise<String?> in
            guard !self.tsAccountManager.isRegistered else {
                throw OWSErrorMakeAssertionError("requesting account verification when already registered")
            }

            self.tsAccountManager.phoneNumberAwaitingVerification = recipientId

            return self.getPreauthChallenge(recipientId: recipientId)
        }.then { (preauthChallenge: String?) -> Promise<Void> in
            self.accountServiceClient.requestVerificationCode(recipientId: recipientId,
                                                              preauthChallenge: preauthChallenge,
                                                              captchaToken: captchaToken,
                                                              transport: transport)
        }
    }

    func getPreauthChallenge(recipientId: String) -> Promise<String?> {
        return firstly {
            return self.pushRegistrationManager.requestPushTokens()
        }.then { (_: String, voipToken: String) -> Promise<String?> in
            let (pushPromise, pushResolver) = Promise<String>.pending()
            self.pushRegistrationManager.preauthChallengeResolver = pushResolver

            return self.accountServiceClient.requestPreauthChallenge(recipientId: recipientId, pushToken: voipToken).then { () -> Promise<String?> in
                let timeout: TimeInterval
                if OWSIsDebugBuild() && IsUsingProductionService() {
                    // won't receive production voip in debug build, don't wait for long
                    timeout = 0.5
                } else {
                    timeout = 5
                }

                return pushPromise.nilTimeout(seconds: timeout)
            }
        }.recover { (error: Error) -> Promise<String?> in
            switch error {
            case PushRegistrationError.pushNotSupported(description: let description):
                Logger.warn("Push not supported: \(description)")
            case let networkError as NetworkManagerError:
                // not deployed to production yet.
                if networkError.statusCode == 404, IsUsingProductionService() {
                    Logger.warn("404 while requesting preauthChallenge: \(error)")
                } else {
                    fallthrough
                }
            default:
                owsFailDebug("error while requesting preauthChallenge: \(error)")
            }
            return Promise.value(nil)
        }
    }

    func register(verificationCode: String, pin: String?) -> Promise<Void> {
        guard verificationCode.count > 0 else {
            let error = OWSErrorWithCodeDescription(.userError,
                                                    NSLocalizedString("REGISTRATION_ERROR_BLANK_VERIFICATION_CODE",
                                                                      comment: "alert body during registration"))
            return Promise(error: error)
        }

        Logger.debug("registering with signal server")
        let registrationPromise: Promise<Void> = firstly { () -> Promise<UUID?> in
            self.registerForTextSecure(verificationCode: verificationCode, pin: pin)
        }.then { (uuid: UUID?) -> Promise<Void> in
            assert(!FeatureFlags.allowUUIDOnlyContacts || uuid != nil)
            TSAccountManager.sharedInstance().uuidAwaitingVerification = uuid
            return self.accountServiceClient.updateAttributes()
        }.then {
            self.createPreKeys()
        }.done {
            self.profileManager.fetchLocalUsersProfile()
        }.then { _ -> Promise<Void> in
            return self.syncPushTokens().recover { (error) -> Promise<Void> in
                switch error {
                case PushRegistrationError.pushNotSupported(let description):
                    // This can happen with:
                    // - simulators, none of which support receiving push notifications
                    // - on iOS11 devices which have disabled "Allow Notifications" and disabled "Enable Background Refresh" in the system settings.
                    Logger.info("Recovered push registration error. Registering for manual message fetcher because push not supported: \(description)")
                    return self.enableManualMessageFetching()
                default:
                    throw error
                }
            }
        }.done { (_) -> Void in
            self.completeRegistration()
        }

        registrationPromise.retainUntilComplete()

        return registrationPromise
    }

    private func registerForTextSecure(verificationCode: String, pin: String?) -> Promise<UUID?> {
        let promise = Promise<Any?> { resolver in
            tsAccountManager.verifyAccount(withCode: verificationCode,
                                           pin: pin,
                                           success: { responseObject in resolver.fulfill((responseObject)) },
                                           failure: resolver.reject)
        }

        // TODO UUID: this UUID param should be non-optional when the production service is updated
        return promise.map { responseObject throws -> UUID? in
            guard let responseObject = responseObject else {
                return nil
            }

            guard let params = ParamParser(responseObject: responseObject) else {
                owsFailDebug("params was unexpectedly nil")
                throw OWSErrorMakeUnableToProcessServerResponseError()
            }

            guard let uuidString: String = try params.optional(key: "uuid") else {
                return nil
            }

            guard let uuid = UUID(uuidString: uuidString) else {
                owsFailDebug("invalid uuidString: \(uuidString)")
                throw OWSErrorMakeUnableToProcessServerResponseError()
            }

            return uuid
        }
    }

    private func createPreKeys() -> Promise<Void> {
        return Promise { resolver in
            TSPreKeyManager.createPreKeys(success: { resolver.fulfill(()) },
                                          failure: resolver.reject)
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
        tsAccountManager.didRegister()
    }

    // MARK: Message Delivery

    func updatePushTokens(pushToken: String, voipToken: String) -> Promise<Void> {
        return Promise { resolver in
            tsAccountManager.registerForPushNotifications(pushToken: pushToken,
                                                          voipToken: voipToken,
                                                          success: { resolver.fulfill(()) },
                                                          failure: resolver.reject)
        }
    }

    func enableManualMessageFetching() -> Promise<Void> {
        tsAccountManager.setIsManualMessageFetchEnabled(true)
        return Promise(tsAccountManager.performUpdateAccountAttributes()).asVoid()
    }

    // MARK: Turn Server

    func getTurnServerInfo() -> Promise<TurnServerInfo> {
        return Promise { resolver in
            self.networkManager.makeRequest(OWSRequestFactory.turnServerInfoRequest(),
                                            success: { (_: URLSessionDataTask, responseObject: Any?) in
                                                guard responseObject != nil else {
                                                    return resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
                                                }

                                                if let responseDictionary = responseObject as? [String: AnyObject] {
                                                    if let turnServerInfo = TurnServerInfo(attributes: responseDictionary) {
                                                        return resolver.fulfill(turnServerInfo)
                                                    }
                                                    Logger.error("unexpected server response:\(responseDictionary)")
                                                }
                                                return resolver.reject(OWSErrorMakeUnableToProcessServerResponseError())
            },
                                            failure: { (_: URLSessionDataTask, error: Error) in
                                                    return resolver.reject(error)
            })
        }
    }

    func recordUuidIfNecessary() {
        DispatchQueue.global().async {
            _ = self.ensureUuid().catch { error in
                owsFailDebug("error: \(error)")
                Logger.error("error: \(error)")
            }.retainUntilComplete()
        }
    }

    func ensureUuid() -> Promise<UUID> {
        if let existingUuid = tsAccountManager.uuid {
            return Promise.value(existingUuid)
        }

        return accountServiceClient.getUuid().map { uuid in
            // It's possible this method could be called multiple times, so we check
            // again if it's been set. We dont bother serializing access since it should
            // be idempotent.
            if let existingUuid = self.tsAccountManager.uuid {
                assert(existingUuid == uuid)
                return existingUuid
            }
            Logger.info("Recording UUID for legacy user")
            self.tsAccountManager.recordUuidForLegacyUser(uuid)
            return uuid
        }
    }
}

extension Promise {
    func nilTimeout(seconds: TimeInterval) -> Promise<T?> {
        let timeout: Promise<T?> = after(seconds: seconds).map {
            return nil
        }

        return race(self.map { $0 }, timeout)
    }
}
