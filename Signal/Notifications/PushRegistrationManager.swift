//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import PushKit
public import SignalServiceKit

public enum PushRegistrationError: Error {
    case assertionError(description: String)
    case pushNotSupported(description: String)
    case timeout
}

/**
 * Singleton used to integrate with push notification services - registration and routing received remote notifications.
 */
public class PushRegistrationManager: NSObject, PKPushRegistryDelegate {

    private let appReadiness: AppReadiness

    init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        (preauthChallengeGuarantee, preauthChallengeFuture) = Guarantee<String>.pending()

        super.init()

        SwiftSingletons.register(self)
    }

    // Coordinates blocking of the calloutQueue while we wait for an incoming call
    private let incomingCallFuture = AtomicValue<GuaranteeFuture<Void>?>(nil, lock: .init())

    // Private callout queue that we can use to synchronously wait for our call to start
    // TODO: Rewrite call message routing to be able to synchronously report calls
    private static let calloutQueue = DispatchQueue(
        label: "org.signal.push-registration",
        autoreleaseFrequency: .workItem,
    )
    private var calloutQueue: DispatchQueue { Self.calloutQueue }

    private var vanillaTokenPromise: Promise<Data>?
    private var vanillaTokenFuture: Future<Data>?

    @MainActor
    private var voipRegistry: PKPushRegistry?

    private var preauthChallengeGuarantee: Guarantee<String>
    private var preauthChallengeFuture: GuaranteeFuture<String>

    // MARK: Public interface

    public func needsNotificationAuthorization() async -> Bool {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        return notificationSettings.authorizationStatus == .notDetermined
    }

    public typealias ApnRegistrationId = RegistrationRequestFactory.ApnRegistrationId

    /// - parameter timeOutEventually: If the OS fails to get back to us with the apns token after
    /// we have requested it and significant time has passed, do we time out or keep waiting? Default to keep waiting.
    @MainActor
    public func requestPushTokens(
        forceRotation: Bool,
        timeOutEventually: Bool = false,
    ) async throws -> ApnRegistrationId {
        Logger.info("")
        await self.registerUserNotificationSettings()

#if targetEnvironment(simulator)
        if TSConstants.isUsingProductionService {
            throw PushRegistrationError.pushNotSupported(description: "Production APNs isn't supported on simulators.")
        }
#endif

        let vanillaPushToken = try await registerForVanillaPushToken(forceRotation: forceRotation, timeOutEventually: timeOutEventually)

        // We need the voip registry to handle voip pushes relayed from the NSE.
        createVoipRegistryIfNecessary()

        return ApnRegistrationId(apnsToken: vanillaPushToken)
    }

    public func didFinishReportingIncomingCall() {
        incomingCallFuture.swap(nil)?.resolve()
    }

    // MARK: Vanilla push token

    /// Receives a pre-auth challenge token.
    ///
    /// Notably, this method is not responsible for requesting these tokens—that must be
    /// managed elsewhere. Before you request one, you should call this method.
    public func receivePreAuthChallengeToken() async -> String { await preauthChallengeGuarantee.awaitable() }

    /// Clears any existing pre-auth challenge token. If none exists, this method does nothing.
    public func clearPreAuthChallengeToken() {
        if preauthChallengeGuarantee.isSealed {
            (preauthChallengeGuarantee, preauthChallengeFuture) = Guarantee<String>.pending()
        }
    }

    @objc
    public func didReceiveVanillaPreAuthChallengeToken(_ challenge: String) {
        appReadiness.runNowOrWhenAppDidBecomeReadySync {
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
        owsAssertDebug(type == .voIP)

        // Synchronously wait until the app is ready.
        let appReady = DispatchSemaphore(value: 0)
        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            appReady.signal()
        }
        appReady.wait()

        // This branch MUST start a CallKit call before it returns or else we risk
        // a PushKit penalty that may prevent us from handling future calls.
        let callRelayPayload = CallMessagePushPayload(payload.dictionaryPayload)
        if let callRelayPayload {
            Logger.info("Received VoIP push from the NSE: \(callRelayPayload)")
            let (guarantee, future) = Guarantee<Void>.pending()
            incomingCallFuture.set(future)
            AppEnvironment.shared.callService.earlyRingNextIncomingCall.set(true)
            CallMessageRelay.handleVoipPayload(callRelayPayload)
            Logger.info("Waiting for call to start: \(callRelayPayload)")
            guarantee.timeout(
                on: DispatchQueue.global(qos: .userInitiated),
                seconds: 5,
                substituteValue: (),
            ).wait()
            Logger.info("Returning back to PushKit. Good luck! \(callRelayPayload)")
            return
        }

        owsFailDebug("Ignoring PKPush without a valid payload.")
    }

    public func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
        // voip tokens are no longer supported
    }

    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        // It's not clear when this would happen. We've never previously handled it, but we should at
        // least start learning if it happens.
        owsFailDebug("Invalid state")
    }

    // MARK: helpers

    // User notification settings must be registered *before* AppDelegate will
    // return any requested push tokens.
    public func registerUserNotificationSettings() async {
        await SSKEnvironment.shared.notificationPresenterRef.registerNotificationSettings()
    }

    /**
     * When users have disabled notifications and background fetch, the system hangs when returning a push token.
     * More specifically, after registering for remote notification, the app delegate calls neither
     * `didFailToRegisterForRemoteNotificationsWithError` nor `didRegisterForRemoteNotificationsWithDeviceToken`
     * This behavior is identical to what you'd see if we hadn't previously registered for user notification settings, though
     * in this case we've verified that we *have* properly registered notification settings.
     */
    @MainActor
    private func isSusceptibleToFailedPushRegistration() async -> Bool {

        if Platform.isSimulator {
            return true
        }

        // Only affects users who have disabled both: background refresh *and* notifications
        guard UIApplication.shared.backgroundRefreshStatus == .denied else {
            Logger.info("has backgroundRefreshStatus != .denied, not susceptible to push registration failure")
            return false
        }

        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()

        // This was ported from UIApplication.shared.currentUserNotificationSettings.types == [] so it only looks at these three settings.
        guard notificationSettings.alertSetting != .enabled, notificationSettings.badgeSetting != .enabled, notificationSettings.soundSetting != .enabled else {
            Logger.info("notificationSettings was not empty, not susceptible to push registration failure.")
            return false
        }

        Logger.warn("background refresh and notifications were disabled. Device is susceptible to push registration failure.")
        return true
    }

    @MainActor
    private func registerForVanillaPushToken(
        forceRotation: Bool,
        timeOutEventually: Bool,
    ) async throws -> String {
        Logger.info("")

        if let vanillaTokenPromise {
            Logger.info("already pending promise for vanilla push token")
            return try await vanillaTokenPromise.awaitable().toHex()
        }

        // No pending vanilla token yet. Create a new promise
        let (promise, future) = Promise<Data>.pending()
        self.vanillaTokenPromise = promise
        defer { self.vanillaTokenPromise = nil }
        self.vanillaTokenFuture = future

        if forceRotation {
            UIApplication.shared.unregisterForRemoteNotifications()
        }
        UIApplication.shared.registerForRemoteNotifications()

        if timeOutEventually {
            do {
                return try await withUncooperativeTimeout(seconds: 20, operation: {
                    return try await self._registerForVanillaPushToken(promise)
                })
            } catch is UncooperativeTimeoutError {
                throw PushRegistrationError.timeout
            }
        } else {
            return try await _registerForVanillaPushToken(promise)
        }
    }

    @MainActor
    private func _registerForVanillaPushToken(_ promise: Promise<Data>) async throws -> String {
        let pushTokenData: Data
        do {
            pushTokenData = try await withUncooperativeTimeout(seconds: 10, operation: {
                return try await promise.awaitable()
            })
        } catch is UncooperativeTimeoutError {
            if await self.isSusceptibleToFailedPushRegistration() {
                // If we've timed out on a device known to be susceptible to failures, quit trying
                // so the user doesn't remain indefinitely hung for no good reason.
                throw PushRegistrationError.pushNotSupported(description: "Device configuration disallows push notifications")
            } else {
                Logger.warn("Push registration is taking a while. Continuing to wait since this configuration is not known to fail push registration.")
                // Sometimes registration can just take a while.
                // If we're not on a device known to be susceptible to push registration failure,
                // just return the original promise.
                pushTokenData = try await promise.awaitable()
            }
        }
        if await self.isSusceptibleToFailedPushRegistration() {
            // Sentinel in case this bug is fixed.
            owsFailDebug("Device was unexpectedly able to complete push registration even though it was susceptible to failure.")
        }
        Logger.info("successfully registered for vanilla push notifications")
        return pushTokenData.toHex()
    }

    @MainActor
    private func createVoipRegistryIfNecessary() {
        guard voipRegistry == nil else { return }
        let voipRegistry = PKPushRegistry(queue: calloutQueue)
        self.voipRegistry = voipRegistry
        voipRegistry.desiredPushTypes = [.voIP]
        voipRegistry.delegate = self
    }
}
