//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import PushKit
import SignalCoreKit
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
public class PushRegistrationManager: NSObject, PKPushRegistryDelegate {

    override init() {
        (preauthChallengeGuarantee, preauthChallengeFuture) = Guarantee<String>.pending()

        super.init()

        SwiftSingletons.register(self)
    }

    // Coordinates blocking of the calloutQueue while we wait for an incoming call
    private let pendingCallSignal = DispatchSemaphore(value: 0)
    private let isWaitingForSignal = AtomicBool(false)

    // Private callout queue that we can use to synchronously wait for our call to start
    // TODO: Rewrite call message routing to be able to synchronously report calls
    private static let calloutQueue = DispatchQueue(
        label: "org.signal.push-registration",
        autoreleaseFrequency: .workItem
    )
    private var calloutQueue: DispatchQueue { Self.calloutQueue }

    private var vanillaTokenPromise: Promise<Data>?
    private var vanillaTokenFuture: Future<Data>?

    private var voipRegistry: PKPushRegistry?
    private var voipTokenPromise: Promise<Data?>?
    private var voipTokenFuture: Future<Data?>?

    private var preauthChallengeGuarantee: Guarantee<String>
    private var preauthChallengeFuture: GuaranteeFuture<String>

    // MARK: Public interface

    public func needsNotificationAuthorization() -> Guarantee<Bool> {
        return Guarantee<Bool> { resolve in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                resolve(settings.authorizationStatus == .notDetermined)
            }
        }
    }

    public typealias ApnRegistrationId = RegistrationRequestFactory.ApnRegistrationId

    /// - parameter timeOutEventually: If the OS fails to get back to us with the apns token after
    /// we have requested it and significant time has passed, do we time out or keep waiting? Default to keep waiting.
    public func requestPushTokens(
        forceRotation: Bool,
        timeOutEventually: Bool = false
    ) -> Promise<ApnRegistrationId> {
        Logger.info("")

        return firstly {
            return self.registerUserNotificationSettings()
        }.then { (_) -> Promise<ApnRegistrationId> in
            guard !Platform.isSimulator else {
                throw PushRegistrationError.pushNotSupported(description: "Push not supported on simulators")
            }

            return self
                .registerForVanillaPushToken(
                    forceRotation: forceRotation,
                    timeOutEventually: timeOutEventually
                ).then { vanillaPushToken -> Promise<ApnRegistrationId> in
                    self.registerForVoipPushToken().map { voipPushToken in
                        return ApnRegistrationId(apnsToken: vanillaPushToken, voipToken: voipPushToken)
                    }
                }
        }
    }

    public func didFinishReportingIncomingCall() {
        owsAssertDebug(CurrentAppContext().isMainApp)

        // If we successfully clear the flag, we know we have someone waiting on the calloutQueue
        // They may be blocked, in which case the signal will wake them up
        // They could also have timed out, in which case they'll detect the cleared flag and decrement
        // Either way, we should only signal if we can clear the flag, otherwise the extra increment will
        // prevent the calloutQueue from blocking in the future.
        if isWaitingForSignal.tryToClearFlag() {
            pendingCallSignal.signal()
        }
    }

    // MARK: Vanilla push token

    /// Receives a pre-auth challenge token.
    ///
    /// Notably, this method is not responsible for requesting these tokens—that must be
    /// managed elsewhere. Before you request one, you should call this method.
    public func receivePreAuthChallengeToken() -> Guarantee<String> { preauthChallengeGuarantee }

    /// Clears any existing pre-auth challenge token. If none exists, this method does nothing.
    public func clearPreAuthChallengeToken() {
        if preauthChallengeGuarantee.isSealed {
            (preauthChallengeGuarantee, preauthChallengeFuture) = Guarantee<String>.pending()
        }
    }

    @objc
    public func didReceiveVanillaPreAuthChallengeToken(_ challenge: String) {
        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            AssertIsOnMainThread()
            Logger.info("received vanilla preauth challenge")
            self.preauthChallengeFuture.resolve(challenge)
        }
    }

    // Vanilla push token is obtained from the system via AppDelegate
    @objc
    public func didReceiveVanillaPushToken(_ tokenData: Data) {
        guard let vanillaTokenFuture = self.vanillaTokenFuture else {
            Logger.warn("System volunteered a push token even though we didn't request one. Syncing.")
            Task {
                do {
                    try await SyncPushTokensJob(mode: .normal).run()
                    Logger.info("Done syncing push tokens after system volunteered one.")
                } catch {
                    Logger.error("Failed to sync push tokens after system volunteered one.")
                }
            }
            return
        }

        vanillaTokenFuture.resolve(tokenData)
    }

    // Vanilla push token is obtained from the system via AppDelegate    
    @objc
    public func didFailToReceiveVanillaPushToken(error: Error) {
        guard let vanillaTokenFuture = self.vanillaTokenFuture else {
            owsFailDebug("promise completion in \(#function) unexpectedly nil")
            return
        }

        vanillaTokenFuture.reject(error)
    }

    // MARK: PKPushRegistryDelegate - voIP Push Token

    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        assertOnQueue(calloutQueue)
        owsAssertDebug(CurrentAppContext().isMainApp)
        owsAssertDebug(type == .voIP)

        // Concurrency invariants:
        // At the start of this function: isWaitingForSignal: false. pendingCallSignal: +0.
        // During this function (if a call message): isWaitingForSignal: true. pendingCallSignal: +{0,1}.
        // Before returning: isWaitingForSignal: false. pendingCallSignal: +0.
        owsAssertDebug(isWaitingForSignal.get() == false)
        // owsAssertDebug(pendingCallSignal.count == 0)     // Not exposed so we can't actually assert this.

        let callRelayPayload = CallMessagePushPayload(payload.dictionaryPayload)
        if let callRelayPayload = callRelayPayload {
            Logger.info("Received VoIP push from the NSE: \(callRelayPayload)")
            owsAssertDebug(isWaitingForSignal.tryToSetFlag())
            callService.earlyRingNextIncomingCall = true
        }

        let isUnexpectedPush = AtomicBool(false)

        // One of the few places we dispatch_sync, this should be safe since we can only block our
        // private calloutQueue while waiting for a chance to run on the main thread.
        // This should be deadlock free since the only thing dispatching to our calloutQueue is PushKit.
        DispatchQueue.main.sync {
            AppReadiness.runNowOrWhenAppDidBecomeReadySync {
                AssertIsOnMainThread()
                if let callRelayPayload = callRelayPayload {
                    CallMessageRelay.handleVoipPayload(callRelayPayload)
                } else if let challenge = payload.dictionaryPayload["challenge"] as? String {
                    Logger.info("received preauth challenge")
                    self.preauthChallengeFuture.resolve(challenge)
                } else {
                    owsAssertDebug(!FeatureFlags.notificationServiceExtension)
                    Logger.info("Fetching messages.")
                    var backgroundTask: OWSBackgroundTask? = OWSBackgroundTask(label: "Push fetch.")
                    firstly { () -> Promise<Void> in
                        self.messageFetcherJob.run().promise
                    }.done(on: DispatchQueue.main) {
                        owsAssertDebug(backgroundTask != nil)
                        backgroundTask = nil
                    }.catch { error in
                        owsFailDebug("Error: \(error)")
                    }

                    if FeatureFlags.notificationServiceExtension {
                        isUnexpectedPush.set(true)
                    }
                }
            }
        }

        if isUnexpectedPush.get() {
            Self.handleUnexpectedVoipPush()
        }

        if let callRelayPayload = callRelayPayload {
            // iOS will kill our app and refuse to launch it again for an incoming call if we return from
            // this function without reporting an incoming call.
            //
            // You may see a crash here: -[PKPushRegistry _terminateAppIfThereAreUnhandledVoIPPushes]
            // Or a log message like:
            // > "Apps receiving VoIP pushes must post an incoming call via CallKit in the same run loop as
            //    pushRegistry:didReceiveIncomingPushWithPayload:forType:[withCompletionHandler:] without delay"
            // > "Killing app because it never posted an incoming call to the system after receiving a PushKit VoIP push."
            //
            // We should be better about handling these pushes faster and synchronously, but for now we
            // can get away with just block this thread and wait for a call to be reported to signal us.
            Logger.info("Waiting for call to start: \(callRelayPayload)")
            let waitInterval = DispatchTimeInterval.seconds(5)
            let didTimeout = (pendingCallSignal.wait(timeout: .now() + waitInterval) == .timedOut)
            if didTimeout {
                owsFailDebug("Call didn't start within \(waitInterval) seconds. Continuing anyway, expecting to be killed.")
            }

            // Three cases that we need to account for.
            // In all of these cases, we need to make sure that we return from this function with
            // Semaphore: +0. isWaitingForSignal: false.
            switch (didTimeout: didTimeout, didClearFlag: isWaitingForSignal.tryToClearFlag()) {

            // 1. We're successfully signaled by a reported call:
            case (didTimeout: false, let didClearFlag):
                // If we've been signaled, another thread must have called `didFinishReportingIncomingCall`
                // It should have already cleared the flag for us, so let's assert that we haven't:
                owsAssertDebug(didClearFlag == false)
                // It should have also signaled the semaphore to +1. Our successful wait would have decremented back to +0.
                // Invariant restored ✅: Semaphore: +0. isWaitingForSignal: false

            // 2. A call isn't reported in time, so we timeout before another thread calls `didFinishReportingIncomingCall`
            case (didTimeout: true, didClearFlag: true):
                // We successfully cleared the flag, so we know the semaphore cannot be incremented at this point.
                // Invariant restored ✅: Semaphore: +0. isWaitingForSignal: false
                break

            // 3. A race. We timeout at the same time that another thread tries to signal us
            case (didTimeout: true, didClearFlag: false):
                // We failed to clear the flag, so another thread beat us to clearing it by calling `didFinishReportingIncomingCall`
                // This means that the semaphore is either at a +1 count, or is about to be signaled to +1
                // We can safely wait to re-decrement the semaphore:

                // Semaphore: +1. isWaitingForSema: false
                pendingCallSignal.wait()
                // Invariant restored ✅: Semaphore: +0. isWaitingForSignal: false
            }

            owsAssertDebug(isWaitingForSignal.get() == false)
            // owsAssertDebug(pendingCallSignal.count == 0)     // Not exposed so we can't actually assert this.
            Logger.info("Returning back to PushKit. Good luck! \(callRelayPayload)")
        }
    }

    private static func handleUnexpectedVoipPush() {
        assertOnQueue(calloutQueue)

        Logger.info("")

        guard #available(iOS 15, *) else {
            owsFailDebug("Voip push is expected.")
            return
        }

        // If the main app receives an unexpected VOIP push on iOS 15,
        // we need to:
        //
        // * Post a generic incoming message notification.
        // * Try to sync push tokens.
        // * Block on completion of both activities to avoid
        //   being terminated by PKPush for not starting a call.
        let completionSignal = DispatchSemaphore(value: 0)
        firstly { () -> Promise<Void> in
            let notificationPromise = notificationPresenter.postGenericIncomingMessageNotification()
            let pushTokensPromise = Promise.wrapAsync { try await SyncPushTokensJob(mode: .forceUpload).run() }
            return Promise.when(resolved: [ notificationPromise, pushTokensPromise ]).asVoid()
        }.ensure(on: DispatchQueue.global()) {
            completionSignal.signal()
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebugUnlessNetworkFailure(error)
        }
        let waitInterval = DispatchTimeInterval.seconds(20)
        let didTimeout = (completionSignal.wait(timeout: .now() + waitInterval) == .timedOut)
        if didTimeout {
            owsFailDebug("Timed out.")
        } else {
            Logger.info("Complete.")
            Logger.flush()
        }
    }

    public func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        assertOnQueue(calloutQueue)
        Logger.info("")
        owsAssertDebug(type == .voIP)
        owsAssertDebug(credentials.type == .voIP)
        guard let voipTokenFuture = self.voipTokenFuture else { return }

        voipTokenFuture.resolve(credentials.token)
    }

    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        // It's not clear when this would happen. We've never previously handled it, but we should at
        // least start learning if it happens.
        assertOnQueue(calloutQueue)
        owsFailDebug("Invalid state")
    }

    // MARK: helpers

    // User notification settings must be registered *before* AppDelegate will
    // return any requested push tokens.
    public func registerUserNotificationSettings() -> Guarantee<Void> {
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

    private func registerForVanillaPushToken(
        forceRotation: Bool,
        timeOutEventually: Bool
    ) -> Promise<String> {
        AssertIsOnMainThread()
        Logger.info("")

        guard self.vanillaTokenPromise == nil else {
            let promise = vanillaTokenPromise!
            owsAssertDebug(!promise.isSealed)
            Logger.info("already pending promise for vanilla push token")
            return promise.map { $0.hexEncodedString }
        }

        // No pending vanilla token yet. Create a new promise
        let (promise, future) = Promise<Data>.pending()
        self.vanillaTokenPromise = promise
        self.vanillaTokenFuture = future

        if forceRotation {
            UIApplication.shared.unregisterForRemoteNotifications()
        }
        UIApplication.shared.registerForRemoteNotifications()

        let returnedPromise = firstly {
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
                // Sentinel in case this bug is fixed.
                owsFailDebug("Device was unexpectedly able to complete push registration even though it was susceptible to failure.")
            }

            Logger.info("successfully registered for vanilla push notifications")
            return pushTokenData.hexEncodedString
        }.ensure {
            self.vanillaTokenPromise = nil
        }
        guard timeOutEventually else {
            return returnedPromise
        }
        return returnedPromise.timeout(seconds: 20, timeoutErrorBlock: { return PushRegistrationError.timeout })
    }

    private func createVoipRegistryIfNecessary() {
        AssertIsOnMainThread()

        guard voipRegistry == nil else { return }
        let voipRegistry = PKPushRegistry(queue: calloutQueue)
        self.voipRegistry  = voipRegistry
        voipRegistry.desiredPushTypes = [.voIP]
        voipRegistry.delegate = self
    }

    private func registerForVoipPushToken() -> Promise<String?> {
        AssertIsOnMainThread()
        Logger.info("")

        // We never populate voip tokens with the service when
        // using the notification service extension.
        guard !FeatureFlags.notificationServiceExtension else {
            Logger.info("Not using VOIP token because NSE is enabled.")
            // We still must create the voip registry to handle voip
            // pushes relayed from the NSE.
            createVoipRegistryIfNecessary()
            return Promise.value(nil)
        }

        guard self.voipTokenPromise == nil else {
            let promise = self.voipTokenPromise!
            owsAssertDebug(!promise.isSealed)
            return promise.map { $0?.hexEncodedString }
        }

        // No pending voip token yet. Create a new promise
        let (promise, future) = Promise<Data?>.pending()
        self.voipTokenPromise = promise
        self.voipTokenFuture = future

        // We don't create the voip registry in init, because it immediately requests the voip token,
        // potentially before we're ready to handle it.
        createVoipRegistryIfNecessary()

        guard let voipRegistry = self.voipRegistry else {
            owsFailDebug("failed to initialize voipRegistry")
            future.reject(PushRegistrationError.assertionError(description: "failed to initialize voipRegistry"))
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
            future.resolve(voipTokenData)
        }

        return promise.map { (voipTokenData: Data?) -> String? in
            Logger.info("successfully registered for voip push notifications")
            return voipTokenData?.hexEncodedString
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
