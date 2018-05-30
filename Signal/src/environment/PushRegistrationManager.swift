//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import PushKit
import SignalServiceKit
import SignalMessaging

public enum PushRegistrationError: Error {
    case assertionError(description: String)
    case pushNotSupported(description: String)
    case timeout
}

/**
 * Singleton used to integrate with push notification services - registration and routing received remote notifications.
 */
@objc public class PushRegistrationManager: NSObject, PKPushRegistryDelegate {

    // MARK - Dependencies
    private var pushManager: PushManager {
        return PushManager.shared()
    }

    // MARK - Singleton class

    @objc(sharedManager)
    public static let shared = PushRegistrationManager()

    private override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    private var userNotificationSettingsPromise: Promise<Void>?
    private var fulfillUserNotificationSettingsPromise: (() -> Void)?

    private var vanillaTokenPromise: Promise<Data>?
    private var fulfillVanillaTokenPromise: ((Data) -> Void)?
    private var rejectVanillaTokenPromise: ((Error) -> Void)?

    private var voipRegistry: PKPushRegistry?
    private var voipTokenPromise: Promise<Data>?
    private var fulfillVoipTokenPromise: ((Data) -> Void)?

    // MARK: Public interface

    public func requestPushTokens() -> Promise<(pushToken: String, voipToken: String)> {
        Logger.info("\(self.logTag) in \(#function)")

        return self.registerUserNotificationSettings().then {
            guard !Platform.isSimulator else {
                throw PushRegistrationError.pushNotSupported(description: "Push not supported on simulators")
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
        guard let fulfillUserNotificationSettingsPromise = self.fulfillUserNotificationSettingsPromise else {
            owsFail("\(self.logTag) promise completion in \(#function) unexpectedly nil")
            return
        }

        fulfillUserNotificationSettingsPromise()
    }

    // MARK: Vanilla push token

    // Vanilla push token is obtained from the system via AppDelegate
    @objc
    public func didReceiveVanillaPushToken(_ tokenData: Data) {
        guard let fulfillVanillaTokenPromise = self.fulfillVanillaTokenPromise else {
            owsFail("\(self.logTag) promise completion in \(#function) unexpectedly nil")
            return
        }

        fulfillVanillaTokenPromise(tokenData)
    }

    // Vanilla push token is obtained from the system via AppDelegate    
    @objc
    public func didFailToReceiveVanillaPushToken(error: Error) {
        guard let rejectVanillaTokenPromise = self.rejectVanillaTokenPromise else {
            owsFail("\(self.logTag) promise completion in \(#function) unexpectedly nil")
            return
        }

        rejectVanillaTokenPromise(error)
    }

    // MARK: PKPushRegistryDelegate - voIP Push Token

    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        Logger.info("\(self.logTag) in \(#function)")
        assert(type == .voIP)
        self.pushManager.application(UIApplication.shared, didReceiveRemoteNotification: payload.dictionaryPayload)
    }

    public func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        Logger.info("\(self.logTag) in \(#function)")
        assert(type == .voIP)
        assert(credentials.type == .voIP)
        guard let fulfillVoipTokenPromise = self.fulfillVoipTokenPromise else {
            owsFail("\(self.logTag) fulfillVoipTokenPromise was unexpectedly nil")
            return
        }

        fulfillVoipTokenPromise(credentials.token)
    }

    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        // It's not clear when this would happen. We've never previously handled it, but we should at
        // least start learning if it happens.
        owsFail("\(self.logTag) in \(#function)")
    }

    // MARK: helpers

    // User notification settings must be registered *before* AppDelegate will
    // return any requested push tokens. We don't consider the notifications settings registration
    // *complete*  until AppDelegate#didRegisterUserNotificationSettings is called.
    private func registerUserNotificationSettings() -> Promise<Void> {
        SwiftAssertIsOnMainThread(#function)

        guard self.userNotificationSettingsPromise == nil else {
            let promise = self.userNotificationSettingsPromise!
            Logger.info("\(self.logTag) already registered user notification settings")
            return promise
        }

        let (promise, fulfill, _) = Promise<Void>.pending()
        self.userNotificationSettingsPromise = promise
        self.fulfillUserNotificationSettingsPromise = {
            fulfill(())
        }

        Logger.info("\(self.logTag) registering user notification settings")

        UIApplication.shared.registerUserNotificationSettings(self.pushManager.userNotificationSettings)

        return promise
    }

    /**
     * When users have disabled notifications and background fetch, the system hangs when returning a push token.
     * More specifically, after registering for remote notification, the app delegate calls neither
     * `didFailToRegisterForRemoteNotificationsWithError` nor `didRegisterForRemoteNotificationsWithDeviceToken`
     * This behavior is identical to what you'd see if we hadn't previously registered for user notification settings, though
     * in this case we've verified that we *have* properly registered notification settings.
     */
    private var isSusceptibleToFailedPushRegistration: Bool {

        // Only affects users who have disabled both: background refresh *and* notifications
        guard UIApplication.shared.backgroundRefreshStatus == .denied else {
            return false
        }

        guard let notificationSettings = UIApplication.shared.currentUserNotificationSettings else {
            return false
        }

        guard notificationSettings.types == [] else {
            return false
        }

        return true
    }

    private func registerForVanillaPushToken() -> Promise<String> {
        Logger.info("\(self.logTag) in \(#function)")
        SwiftAssertIsOnMainThread(#function)

        guard self.vanillaTokenPromise == nil else {
            let promise = vanillaTokenPromise!
            assert(promise.isPending)
            Logger.info("\(self.logTag) alreay pending promise for vanilla push token")
            return promise.then { $0.hexEncodedString }
        }

        // No pending vanilla token yet. Create a new promise
        let (promise, fulfill, reject) = Promise<Data>.pending()
        self.vanillaTokenPromise = promise
        self.fulfillVanillaTokenPromise = fulfill
        self.rejectVanillaTokenPromise = reject
        UIApplication.shared.registerForRemoteNotifications()

        let kTimeout: TimeInterval = 10
        let timeout: Promise<Data> = after(seconds: kTimeout).then { throw PushRegistrationError.timeout }
        let promiseWithTimeout: Promise<Data> = race(promise, timeout)

        return promiseWithTimeout.recover { error -> Promise<Data> in
            switch error {
            case PushRegistrationError.timeout:
                if self.isSusceptibleToFailedPushRegistration {
                    // If we've timed out on a device known to be susceptible to failures, quit trying
                    // so the user doesn't remain indefinitely hung for no good reason.
                    throw PushRegistrationError.pushNotSupported(description: "Device configuration disallows push notifications")
                } else {
                    // Sometimes registration can just take a while.
                    // If we're not on a device known to be susceptible to push registration failure,
                    // just return the original promise.
                    return promise
                }
            default:
                throw error
            }
        }.then { (pushTokenData: Data) -> String in
            if self.isSusceptibleToFailedPushRegistration {
                // Sentinal in case this bug is fixed.
                owsFail("Device was unexpectedly able to complete push registration even though it was susceptible to failure.")
            }

            Logger.info("\(self.logTag) successfully registered for vanilla push notifications")
            return pushTokenData.hexEncodedString
        }.always {
            self.vanillaTokenPromise = nil
        }
    }

    private func registerForVoipPushToken() -> Promise<String> {
        SwiftAssertIsOnMainThread(#function)
        Logger.info("\(self.logTag) in \(#function)")

        guard self.voipTokenPromise == nil else {
            let promise = self.voipTokenPromise!
            assert(promise.isPending)
            return promise.then { $0.hexEncodedString }
        }

        // No pending voip token yet. Create a new promise
        let (promise, fulfill, reject) = Promise<Data>.pending()
        self.voipTokenPromise = promise
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
            owsFail("\(self.logTag) failed to initialize voipRegistry in \(#function)")
            reject(PushRegistrationError.assertionError(description: "\(self.logTag) failed to initialize voipRegistry in \(#function)"))
            return promise.then { _ in
                // coerce expected type of returned promise - we don't really care about the value,
                // since this promise has been rejected. In practice this shouldn't happen
                String()
            }
        }

        // If we've already completed registering for a voip token, resolve it immediately,
        // rather than waiting for the delegate method to be called.
        if let voipTokenData = voipRegistry.pushToken(for: .voIP) {
            Logger.info("\(self.logTag) using pre-registered voIP token")
            fulfill(voipTokenData)
        }

        return promise.then { (voipTokenData: Data) -> String in
            Logger.info("\(self.logTag) successfully registered for voip push notifications")
            return voipTokenData.hexEncodedString
        }.always {
            self.voipTokenPromise = nil
        }
    }
}

// We transmit pushToken data as hex encoded string to the server
fileprivate extension Data {
    var hexEncodedString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
