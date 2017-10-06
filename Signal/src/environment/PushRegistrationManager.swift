//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import PushKit

/**
 * Singleton used to integrate with push notification services - registration and routing received remote notifications.
 */
@objc class PushRegistrationManager: NSObject, PKPushRegistryDelegate {

    let TAG = "[PushRegistrationManager]"

    // MARK - Dependencies
    private var pushManager: PushManager {
        return PushManager.shared()
    }

    // MARK - Singleton class

    @objc(sharedManager)
    static let shared = PushRegistrationManager()
    private override init() {
        super.init()
    }

    private enum PushRegistrationManagerError: Error {
        case assertionError(description: String)
    }

    private var voipRegistry: PKPushRegistry?
    private var fulfillVanillaTokenPromise: ((Data) -> Void)?
    private var rejectVanillaTokenPromise: ((Error) -> Void)?
    private var fulfillVoipTokenPromise: ((Data) -> Void)?
    private var fulfillRegisterUserNotificationSettingsPromise: (() -> Void)?

    // MARK: Public interface

    public func requestPushTokens() -> Promise<(pushToken: String, voipToken: String)> {
        Logger.info("\(self.TAG) in \(#function)")

        return self.registerUserNotificationSettings().then {
            guard !Platform.isSimulator else {
                Logger.warn("\(self.TAG) Using fake push tokens for simulator")
                return Promise(value: (pushToken: "fakePushToken", voipToken: "fakeVoipToken"))
            }

            return self.registerForVanillaPushToken().then { vanillaPushToken in
                self.registerForVoipPushToken().then { voipPushToken in
                    (pushToken: vanillaPushToken, voipToken: voipPushToken)
                }
            }
        }
    }

    // Notification registration is confirmed via AppDelegate
    // Before this occurs, it is not safe to assume push token requests will be acknowledged.
    // 
    // e.g. in the case that Background Fetch is disabled, token requests will be ignored until
    // we register user notification settings.
    @objc
    public func didRegisterUserNotificationSettings() {
        guard let fulfillRegisterUserNotificationSettingsPromise = self.fulfillRegisterUserNotificationSettingsPromise else {
            owsFail("\(TAG) promise completion in \(#function) unexpectedly nil")
            return
        }

        fulfillRegisterUserNotificationSettingsPromise()
    }

    // MARK: Vanilla push token

    // Vanilla push token is obtained from the system via AppDelegate
    @objc
    public func didReceiveVanillaPushToken(_ tokenData: Data) {
        guard let fulfillVanillaTokenPromise = self.fulfillVanillaTokenPromise else {
            owsFail("\(TAG) promise completion in \(#function) unexpectedly nil")
            return
        }

        fulfillVanillaTokenPromise(tokenData)
    }

    // Vanilla push token is obtained from the system via AppDelegate    
    @objc
    public func didFailToReceiveVanillaPushToken(error: Error) {
        guard let rejectVanillaTokenPromise = self.rejectVanillaTokenPromise else {
            owsFail("\(TAG) promise completion in \(#function) unexpectedly nil")
            return
        }

        rejectVanillaTokenPromise(error)
    }

    // MARK: PKPushRegistryDelegate - voIP Push Token

    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, forType type: PKPushType) {
        Logger.info("\(self.TAG) in \(#function)")
        assert(type == .voIP)
        self.pushManager.application(UIApplication.shared, didReceiveRemoteNotification: payload.dictionaryPayload)
    }

    public func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, forType type: PKPushType) {
        Logger.info("\(self.TAG) in \(#function)")
        assert(type == .voIP)
        assert(credentials.type == .voIP)
        guard let fulfillVoipTokenPromise = self.fulfillVoipTokenPromise else {
            owsFail("\(TAG) fulfillVoipTokenPromise was unexpectedly nil")
            return
        }

        fulfillVoipTokenPromise(credentials.token)
    }

    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenForType type: PKPushType) {
        // It's not clear when this would happen. We've never previously handled it, but we should at
        // least start learning if it happens.
        owsFail("\(TAG) in \(#function)")
    }

    // MARK: helpers

    // User notification settings must be registered *before* AppDelegate will
    // return any requested push tokens. We don't consider the notifications settings registration
    // *complete*  until AppDelegate#didRegisterUserNotificationSettings is called.
    private func registerUserNotificationSettings() -> Promise<Void> {
        AssertIsOnMainThread()

        guard fulfillRegisterUserNotificationSettingsPromise == nil else {
            Logger.info("\(TAG) already registered user notification settings")
            return Promise(value: ())
        }

        let (promise, fulfill, _) = Promise<Void>.pending()
        self.fulfillRegisterUserNotificationSettingsPromise = fulfill

        Logger.info("\(TAG) registering user notification settings")

        UIApplication.shared.registerUserNotificationSettings(self.pushManager.userNotificationSettings)

        return promise
    }

    private func registerForVanillaPushToken() -> Promise<String> {
        Logger.info("\(self.TAG) in \(#function)")
        AssertIsOnMainThread()

        let (promise, fulfill, reject) = Promise<Data>.pending()
        self.fulfillVanillaTokenPromise = fulfill
        self.rejectVanillaTokenPromise = reject
        UIApplication.shared.registerForRemoteNotifications()

        return promise.then { (pushTokenData: Data) -> String in
            Logger.info("\(self.TAG) successfully registered for vanilla push notifications")
            return pushTokenData.hexEncodedString()
        }
    }

    private func registerForVoipPushToken() -> Promise<String> {
        AssertIsOnMainThread()
        Logger.info("\(self.TAG) in \(#function)")

        // Voip token not yet registered, assign promise.
        let (promise, fulfill, reject) = Promise<Data>.pending()
        self.fulfillVoipTokenPromise = fulfill

        if self.voipRegistry == nil {
            // We don't create the voip registry in init, because it immediately requests the voip token,
            // potentially before we're ready to handle it.
            let voipRegistry = PKPushRegistry(queue: nil)
            self.voipRegistry  = voipRegistry
            voipRegistry.desiredPushTypes = [.voIP]
            voipRegistry.delegate = self
        }

        guard let voipRegistry = self.voipRegistry else {
            owsFail("\(TAG) failed to initialize voipRegistry in \(#function)")
            reject(PushRegistrationManagerError.assertionError(description: "\(TAG) failed to initialize voipRegistry in \(#function)"))
            return promise.then { _ in
                // coerce expected type of returned promise - we don't really care about the value, since this promise has been rejected.
                // in practice this shouldn't happen
                String()
            }
        }

        // If we've already completed registering for a voip token, resolve it immediately,
        // rather than waiting for the delegate method to be called.
        if let voipTokenData = voipRegistry.pushToken(forType: .voIP) {
            Logger.info("\(self.TAG) using pre-registered voIP token")
            fulfill(voipTokenData)
        }

        return promise.then { (voipTokenData: Data) -> String in
            Logger.info("\(self.TAG) successfully registered for voip push notifications")
            return voipTokenData.hexEncodedString()
        }
    }
}

// We transmit pushToken data as hex encoded string to the server
fileprivate extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
