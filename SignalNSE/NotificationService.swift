//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UserNotifications
import SignalServiceKit

// The lifecycle of the NSE looks something like the following:
//  1)  App receives notification
//  2)  System creates an instance of the extension class
//      and calls `didReceive` in the background
//  3)  Extension processes messages / displays whatever
//      notifications it needs to
//  4)  Extension notifies its work is complete by calling
//      the contentHandler
//  5)  If the extension takes too long to perform its work
//      (more than 30s), it will be notified and immediately
//      terminated
//
// Note that the NSE does *not* always spawn a new process to
// handle a new notification and will also try and process notifications
// in parallel. `didReceive` could be called twice for the same process,
// but it will always be called on different threads. It may or may not be
// called on the same instance of `NotificationService` as a previous
// notification.
//
// We keep a global `environment` singleton to ensure that our app context,
// database, logging, etc. are only ever setup once per *process*
private let globalEnvironment = NSEEnvironment()

@MainActor private var hasShownFirstUnlockError = false

class NotificationService: UNNotificationServiceExtension {
    private typealias ContentHandler = (UNNotificationContent) -> Void
    private let contentHandler = AtomicOptional<ContentHandler>(nil, lock: .init())
    private let fetchQueue = SerialTaskQueue()

    // MARK: -

    private static let unfairLock = UnfairLock()
    private static var _logTimer: OffMainThreadTimer?
    private static var _nseCounter: Int = 0

    private static func nseDidStart() -> Int {
        unfairLock.withLock {
            if DebugFlags.internalLogging, _logTimer == nil {
                _logTimer = OffMainThreadTimer(timeInterval: 1.0, repeats: true) { _ in
                    NSELogger.uncorrelated.info("... memoryUsage: \(LocalDevice.memoryUsageString)")
                }
            }

            _nseCounter += 1
            return _nseCounter
        }
    }

    private static func nseDidComplete() {
        unfairLock.withLock {
            _nseCounter = _nseCounter > 0 ? _nseCounter - 1 : 0

            if _nseCounter == 0, _logTimer != nil {
                _logTimer?.invalidate()
                _logTimer = nil
            }
        }
    }

    // MARK: -

    // This method is thread-safe.
    func completeSilently(content: UNNotificationContent, logger: NSELogger) {
        defer { logger.flush() }

        guard let contentHandler = contentHandler.swap(nil) else {
            return
        }

        Self.nseDidComplete()

        contentHandler(content)
    }

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let logger = NSELogger()
        _ = Self.nseDidStart()
        self.contentHandler.set(contentHandler)
        self.fetchQueue.enqueueCancellingPrevious {
            let content = await self._didReceive(request, logger: logger)
            self.completeSilently(content: content, logger: logger)
        }
    }

    @MainActor
    private func _didReceive(_ request: UNNotificationRequest, logger: NSELogger) async -> UNNotificationContent {
        globalEnvironment.setUp(logger: logger)
        let finalContinuation: AppSetup.FinalContinuation
        do {
            finalContinuation = try await globalEnvironment.setUpDatabase(logger: logger)
        } catch KeychainError.notAllowed {
            // Detect and handle "no GRDB file" and "no keychain access".
            if !hasShownFirstUnlockError {
                hasShownFirstUnlockError = true
                logger.error("DB Keys not accessible; showing error.")
                logger.flush()
                let content = UNMutableNotificationContent()
                let notificationFormat = OWSLocalizedString(
                    "NOTIFICATION_BODY_PHONE_LOCKED_FORMAT",
                    comment: "Lock screen notification text presented after user powers on their device without unlocking. Embeds {{device model}} (either 'iPad' or 'iPhone')"
                )
                content.body = String(format: notificationFormat, UIDevice.current.localizedModel)
                return content
            } else {
                // Only show a single error if we receive multiple pushes
                // before first device unlock.
                logger.error("DB Keys not accessible; completing silently.")
                logger.flush()
                let emptyContent = UNMutableNotificationContent()
                return emptyContent
            }
        } catch {
            owsFail("Couldn't load database: \(error.grdbErrorForLogging)")
        }

        // Re-warm the caches each time to pick up changes made by the main app.
        finalContinuation.runLaunchTasksIfNeededAndReloadCaches()
        // Re-set up the local identifiers to ensure they're propagated throughout the system.
        switch finalContinuation.setUpLocalIdentifiers(
            willResumeInProgressRegistration: false,
            canInitiateRegistration: false
        ) {
        case .corruptRegistrationState:
            Logger.warn("Ignoring request to process notifications when the user isn't registered.")
            return UNNotificationContent()
        case nil:
            globalEnvironment.setAppIsReady()
        }

        // Mark down that the APNS token is working since we got a push.
        // Do this as early as possible but after the app is ready and has run
        // GRDB migrations and such.
        async let didMarkApnsReceived: Void = SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            APNSRotationStore.didReceiveAPNSPush(transaction: transaction)
        }

        let result = await self.fetchAndProcessMessages(logger: logger)
        await didMarkApnsReceived
        return result
    }

    // Called just before the extension will be terminated by the system.
    override func serviceExtensionTimeWillExpire() {
        Logger.warn("Canceling fetchingQueue tasks because we ran out of time.")

        self.fetchQueue.cancelAll()

        // We complete silently here so that nothing is presented to the user.
        // By default the OS will present whatever the raw content of the original
        // notification is to the user otherwise.
        completeSilently(content: UNMutableNotificationContent(), logger: .uncorrelated)
    }

    private func startProxyIfEnabled() async throws(CancellationError) {
        if SignalProxy.isEnabled {
            Logger.info("Waiting for signal proxy to become ready for message fetch.")
            SignalProxy.startRelayServer()
            try await Preconditions([
                NotificationPrecondition(
                    notificationName: .isSignalProxyReadyDidChange,
                    isSatisfied: { SignalProxy.isEnabledAndReady }
                )
            ]).waitUntilSatisfied()
        }
    }

    @MainActor
    private func fetchAndProcessMessages(logger: NSELogger) async -> UNNotificationContent {
        if DependenciesBridge.shared.appExpiry.isExpired(now: Date()) {
            Logger.warn("Not processing notifications for expired application.")
            return UNMutableNotificationContent()
        }

        let cron = DependenciesBridge.shared.cron
        let cronCtx = CronContext(
            chatConnectionManager: DependenciesBridge.shared.chatConnectionManager,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )

        do {
            try await startProxyIfEnabled()
            defer { SignalProxy.stopRelayServer() }

            let backgroundMessageFetcher = DependenciesBridge.shared.backgroundMessageFetcherFactory.buildFetcher()

            await backgroundMessageFetcher.start()
            // Start Cron after we request a socket.
            async let cronResult: Void = cron.runOnce(ctx: cronCtx)
            let fetchResult = await Result(catching: {
                try await backgroundMessageFetcher.waitForFetchingProcessingAndSideEffects()
            })
            // Wait for Cron to finish executing before we release the socket.
            await cronResult
            await backgroundMessageFetcher.stopAndWaitBeforeSuspending()
            try fetchResult.get()
        } catch is CancellationError {
            Logger.warn("Message fetching & processing canceled.")
            return UNMutableNotificationContent()
        } catch {
            Logger.warn("\(error)")
        }

        logger.info("Message fetching & processing completed.")

        // If we're completing normally, try to update the badge on the app icon.
        let badgeCount: BadgeCount = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return DependenciesBridge.shared.badgeCountFetcher
                .fetchBadgeCount(tx: tx)
        }
        let content = UNMutableNotificationContent()
        content.badge = NSNumber(value: badgeCount.unreadTotalCount)
        return content
    }
}
