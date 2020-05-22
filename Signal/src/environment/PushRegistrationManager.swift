//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

    // MARK: - Dependencies

    private var messageFetcherJob: MessageFetcherJob {
        return SSKEnvironment.shared.messageFetcherJob
    }

    private var notificationPresenter: NotificationPresenter {
        return AppEnvironment.shared.notificationPresenter
    }

    // MARK: - Singleton class

    @objc
    public static var shared: PushRegistrationManager {
        get {
            return AppEnvironment.shared.pushRegistrationManager
        }
    }

    override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    private var vanillaTokenPromise: Promise<Data>?
    private var vanillaTokenResolver: Resolver<Data>?

    private var voipRegistry: PKPushRegistry?
    private var voipTokenPromise: Promise<Data>?
    private var voipTokenResolver: Resolver<Data>?

    public var preauthChallengeResolver: Resolver<String>?

    // MARK: Public interface

    public func requestPushTokens() -> Promise<(pushToken: String, voipToken: String)> {
        Logger.info("")

        return firstly { () -> Promise<Void> in
            return self.registerUserNotificationSettings()
        }.then { (_) -> Promise<(pushToken: String, voipToken: String)> in
            guard !Platform.isSimulator else {
                throw PushRegistrationError.pushNotSupported(description: "Push not supported on simulators")
            }

            return self.registerForVanillaPushToken().then { vanillaPushToken -> Promise<(pushToken: String, voipToken: String)> in
                self.registerForVoipPushToken().map { voipPushToken in
                    (pushToken: vanillaPushToken, voipToken: voipPushToken)
                }
            }
        }
    }

    // MARK: Vanilla push token

    // Vanilla push token is obtained from the system via AppDelegate
    @objc
    public func didReceiveVanillaPushToken(_ tokenData: Data) {
        guard let vanillaTokenResolver = self.vanillaTokenResolver else {
            owsFailDebug("promise completion in \(#function) unexpectedly nil")
            return
        }

        vanillaTokenResolver.fulfill(tokenData)
    }

    // Vanilla push token is obtained from the system via AppDelegate    
    @objc
    public func didFailToReceiveVanillaPushToken(error: Error) {
        guard let vanillaTokenResolver = self.vanillaTokenResolver else {
            owsFailDebug("promise completion in \(#function) unexpectedly nil")
            return
        }

        vanillaTokenResolver.reject(error)
    }

    // MARK: PKPushRegistryDelegate - voIP Push Token

    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        Logger.info("")
        assert(type == .voIP)
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            AssertIsOnMainThread()
            if let preauthChallengeResolver = self.preauthChallengeResolver,
                let challenge = payload.dictionaryPayload["challenge"] as? String {
                Logger.info("received preauth challenge")
                preauthChallengeResolver.fulfill(challenge)
                self.preauthChallengeResolver = nil
            } else {
                self.messageFetcherJob.run()
            }
        }
    }

    public func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        Logger.info("")
        assert(type == .voIP)
        assert(credentials.type == .voIP)
        guard let voipTokenResolver = self.voipTokenResolver else {
            owsFailDebug("fulfillVoipTokenPromise was unexpectedly nil")
            return
        }

        voipTokenResolver.fulfill(credentials.token)
    }

    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        // It's not clear when this would happen. We've never previously handled it, but we should at
        // least start learning if it happens.
        owsFailDebug("Invalid state")
    }

    // MARK: helpers

    // User notification settings must be registered *before* AppDelegate will
    // return any requested push tokens.
    public func registerUserNotificationSettings() -> Promise<Void> {
        Logger.info("registering user notification settings")

        return notificationPresenter.registerNotificationSettings()
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
            Logger.info("has backgroundRefreshStatus != .denied, not susceptible to push registration failure")
            return false
        }

        guard let notificationSettings = UIApplication.shared.currentUserNotificationSettings else {
            owsFailDebug("notificationSettings was unexpectedly nil.")
            return false
        }

        guard notificationSettings.types == [] else {
            Logger.info("notificationSettings was not empty, not susceptible to push registration failure.")
            return false
        }

        Logger.info("background refresh and notifications were disabled. Device is susceptible to push registration failure.")
        return true
    }

    private func registerForVanillaPushToken() -> Promise<String> {
        AssertIsOnMainThread()
        Logger.info("")

        guard self.vanillaTokenPromise == nil else {
            let promise = vanillaTokenPromise!
            assert(promise.isPending)
            Logger.info("alreay pending promise for vanilla push token")
            return promise.map { $0.hexEncodedString }
        }

        // No pending vanilla token yet. Create a new promise
        let (promise, resolver) = Promise<Data>.pending()
        self.vanillaTokenPromise = promise
        self.vanillaTokenResolver = resolver

        UIApplication.shared.registerForRemoteNotifications()

        return firstly {
            promise.timeout(seconds: 10, description: "Register for vanilla push token") {
                PushRegistrationError.timeout
            }
        }.recover { error -> Promise<Data> in
            switch error {
            case PushRegistrationError.timeout:
                if self.isSusceptibleToFailedPushRegistration {
                    // If we've timed out on a device known to be susceptible to failures, quit trying
                    // so the user doesn't remain indefinitely hung for no good reason.
                    throw PushRegistrationError.pushNotSupported(description: "Device configuration disallows push notifications")
                } else {
                    Logger.info("Push registration is taking a while. Continuing to wait since this configuration is not known to fail push registration.")
                    // Sometimes registration can just take a while.
                    // If we're not on a device known to be susceptible to push registration failure,
                    // just return the original promise.
                    return promise
                }
            default:
                throw error
            }
        }.map { (pushTokenData: Data) -> String in
            if self.isSusceptibleToFailedPushRegistration {
                // Sentinal in case this bug is fixed.
                owsFailDebug("Device was unexpectedly able to complete push registration even though it was susceptible to failure.")
            }

            Logger.info("successfully registered for vanilla push notifications")
            return pushTokenData.hexEncodedString
        }.ensure {
            self.vanillaTokenPromise = nil
        }
    }

    private func registerForVoipPushToken() -> Promise<String> {
        AssertIsOnMainThread()
        Logger.info("")

        guard self.voipTokenPromise == nil else {
            let promise = self.voipTokenPromise!
            assert(promise.isPending)
            return promise.map { $0.hexEncodedString }
        }

        // No pending voip token yet. Create a new promise
        let (promise, resolver) = Promise<Data>.pending()
        self.voipTokenPromise = promise
        self.voipTokenResolver = resolver

        if self.voipRegistry == nil {
            // We don't create the voip registry in init, because it immediately requests the voip token,
            // potentially before we're ready to handle it.
            let voipRegistry = PKPushRegistry(queue: nil)
            self.voipRegistry  = voipRegistry
            voipRegistry.desiredPushTypes = [.voIP]
            voipRegistry.delegate = self
        }

        guard let voipRegistry = self.voipRegistry else {
            owsFailDebug("failed to initialize voipRegistry")
            resolver.reject(PushRegistrationError.assertionError(description: "failed to initialize voipRegistry"))
            return promise.map { _ in
                // coerce expected type of returned promise - we don't really care about the value,
                // since this promise has been rejected. In practice this shouldn't happen
                String()
            }
        }

        // If we've already completed registering for a voip token, resolve it immediately,
        // rather than waiting for the delegate method to be called.
        if let voipTokenData = voipRegistry.pushToken(for: .voIP) {
            Logger.info("using pre-registered voIP token")
            resolver.fulfill(voipTokenData)
        }

        return promise.map { (voipTokenData: Data) -> String in
            Logger.info("successfully registered for voip push notifications")
            return voipTokenData.hexEncodedString
        }.ensure {
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
