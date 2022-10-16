//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import PushKit
import SignalUtilitiesKit
import GRDB

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
    private var voipTokenPromise: Promise<Data?>?
    private var voipTokenResolver: Resolver<Data?>?

    // MARK: Public interface

    public func requestPushTokens() -> Promise<(pushToken: String, voipToken: String)> {
        Logger.info("")

        return firstly { () -> Promise<Void> in
            self.registerUserNotificationSettings()
        }.then { (_) -> Promise<(pushToken: String, voipToken: String)> in
            #if targetEnvironment(simulator)
            throw PushRegistrationError.pushNotSupported(description: "Push not supported on simulators")
            #endif
            
            return self.registerForVanillaPushToken().then { vanillaPushToken -> Promise<(pushToken: String, voipToken: String)> in
                self.registerForVoipPushToken().map { voipPushToken in
                    (pushToken: vanillaPushToken, voipToken: voipPushToken ?? "")
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

    // MARK: helpers

    // User notification settings must be registered *before* AppDelegate will
    // return any requested push tokens.
    public func registerUserNotificationSettings() -> Promise<Void> {
        AssertIsOnMainThread()
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
        AssertIsOnMainThread()

        guard self.vanillaTokenPromise == nil else {
            let promise = vanillaTokenPromise!
            assert(promise.isPending)
            return promise.map { $0.hexEncodedString }
        }

        // No pending vanilla token yet; create a new promise
        let (promise, resolver) = Promise<Data>.pending()
        self.vanillaTokenPromise = promise
        self.vanillaTokenResolver = resolver

        UIApplication.shared.registerForRemoteNotifications()

        let kTimeout: TimeInterval = 10
        let timeout: Promise<Data> = after(seconds: kTimeout).map { throw PushRegistrationError.timeout }
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
        }.map { (pushTokenData: Data) -> String in
            if self.isSusceptibleToFailedPushRegistration {
                // Sentinal in case this bug is fixed
                OWSLogger.debug("Device was unexpectedly able to complete push registration even though it was susceptible to failure.")
            }

            return pushTokenData.hexEncodedString
        }.ensure {
            self.vanillaTokenPromise = nil
        }
    }
    
    public func createVoipRegistryIfNecessary() {
        AssertIsOnMainThread()

        guard voipRegistry == nil else { return }
        let voipRegistry = PKPushRegistry(queue: nil)
        self.voipRegistry  = voipRegistry
        voipRegistry.desiredPushTypes = [.voIP]
        voipRegistry.delegate = self
    }
    
    private func registerForVoipPushToken() -> Promise<String?> {
        AssertIsOnMainThread()

        guard self.voipTokenPromise == nil else {
            let promise = self.voipTokenPromise!
            return promise.map { $0?.hexEncodedString }
        }

        // No pending voip token yet. Create a new promise
        let (promise, resolver) = Promise<Data?>.pending()
        self.voipTokenPromise = promise
        self.voipTokenResolver = resolver

        // We don't create the voip registry in init, because it immediately requests the voip token,
        // potentially before we're ready to handle it.
        createVoipRegistryIfNecessary()

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

        return promise.map { (voipTokenData: Data?) -> String? in
            Logger.info("successfully registered for voip push notifications")
            return voipTokenData?.hexEncodedString
        }.ensure {
            self.voipTokenPromise = nil
        }
    }
    
    // MARK: PKPushRegistryDelegate
    public func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        Logger.info("")
        owsAssertDebug(type == .voIP)
        owsAssertDebug(pushCredentials.type == .voIP)
        guard let voipTokenResolver = voipTokenResolver else { return }

        voipTokenResolver.fulfill(pushCredentials.token)
    }
    
    // NOTE: This function MUST report an incoming call.
    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        SNLog("[Calls] Receive new voip notification.")
        owsAssertDebug(CurrentAppContext().isMainApp)
        owsAssertDebug(type == .voIP)
        let payload = payload.dictionaryPayload
        
        guard
            let uuid: String = payload["uuid"] as? String,
            let caller: String = payload["caller"] as? String,
            let timestampMs: Int64 = payload["timestamp"] as? Int64
        else {
            SessionCallManager.reportFakeCall(info: "Missing payload data")
            return
        }
        
        // Resume database
        NotificationCenter.default.post(name: Database.resumeNotification, object: self)
        
        let maybeCall: SessionCall? = Storage.shared.write { db in
            let messageInfo: CallMessage.MessageInfo = CallMessage.MessageInfo(
                state: (caller == getUserHexEncodedPublicKey(db) ?
                    .outgoing :
                    .incoming
                )
            )
            
            let messageInfoString: String? = {
                if let messageInfoData: Data = try? JSONEncoder().encode(messageInfo) {
                   return String(data: messageInfoData, encoding: .utf8)
                } else {
                    return "Incoming call." // TODO: We can do better here.
                }
            }()
            
            let call: SessionCall = SessionCall(db, for: caller, uuid: uuid, mode: .answer)
            let thread: SessionThread = try SessionThread.fetchOrCreate(db, id: caller, variant: .contact)
            
            let interaction: Interaction = try Interaction(
                messageUuid: uuid,
                threadId: thread.id,
                authorId: caller,
                variant: .infoCall,
                body: messageInfoString,
                timestampMs: timestampMs
            ).inserted(db)
            call.callInteractionId = interaction.id
            
            return call
        }
        
        guard let call: SessionCall = maybeCall else {
            SessionCallManager.reportFakeCall(info: "Could not retrieve call from database")
            return
        }
        
        // NOTE: Just start 1-1 poller so that it won't wait for polling group messages
        (UIApplication.shared.delegate as? AppDelegate)?.startPollersIfNeeded(shouldStartGroupPollers: false)
        
        call.reportIncomingCallIfNeeded { error in
            if let error = error {
                SNLog("[Calls] Failed to report incoming call to CallKit due to error: \(error)")
            }
        }
    }
}

// We transmit pushToken data as hex encoded string to the server
fileprivate extension Data {
    var hexEncodedString: String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
