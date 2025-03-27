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

private let hasShownFirstUnlockError = AtomicBool(false, lock: .sharedGlobal)

class NotificationService: UNNotificationServiceExtension {
    private typealias ContentHandler = (UNNotificationContent) -> Void
    private let contentHandler = AtomicOptional<ContentHandler>(nil, lock: .init())

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
        Task {
            let content = await _didReceive(request, logger: logger)
            self.completeSilently(content: content, logger: logger)
        }
    }

    @MainActor
    private func _didReceive(_ request: UNNotificationRequest, logger: NSELogger) async -> UNNotificationContent {
        do {
            try await globalEnvironment.setUp(logger: logger)
        } catch KeychainError.notAllowed {
            // Detect and handle "no GRDB file" and "no keychain access".
            if hasShownFirstUnlockError.tryToSetFlag() {
                logger.error("DB Keys not accessible; showing error.", flushImmediately: true)
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
                logger.error("DB Keys not accessible; completing silently.", flushImmediately: true)
                let emptyContent = UNMutableNotificationContent()
                return emptyContent
            }
        } catch {
            owsFail("Couldn't load database: \(error.grdbErrorForLogging)")
        }

        // Mark down that the APNS token is working since we got a push.
        // Do this as early as possible but after the app is ready and has run
        // GRDB migrations and such.
        async let didMarkApnsReceived: Void = SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            APNSRotationStore.didReceiveAPNSPush(transaction: transaction)
        }

        SSKEnvironment.shared.messageFetcherJobRef.prepareToFetchViaREST()

        if await globalEnvironment.askMainAppToHandleReceipt(logger: logger) {
            logger.info("Received notification handled by main application, memoryUsage: \(LocalDevice.memoryUsageString).")
            return UNMutableNotificationContent()
        }

        let result = await self.fetchAndProcessMessages(logger: logger)
        await didMarkApnsReceived
        return result
    }

    // Called just before the extension will be terminated by the system.
    override func serviceExtensionTimeWillExpire() {
        owsFailDebug("NSE expired before messages could be processed")

        // We complete silently here so that nothing is presented to the user.
        // By default the OS will present whatever the raw content of the original
        // notification is to the user otherwise.
        completeSilently(content: UNMutableNotificationContent(), logger: .uncorrelated)
    }

    @MainActor
    private func startProxyIfEnabled() async {
        // Runs on the main thread so that, if isEnabledAndReady is false, the
        // observe(...) is guaranteed to happen before the notification is posted.
        while SignalProxy.isEnabled, !SignalProxy.isEnabledAndReady {
            await withCheckedContinuation { continuation in
                Logger.info("Waiting for signal proxy to become ready for message fetch.")
                NotificationCenter.default.observe(once: .isSignalProxyReadyDidChange)
                    .done { _ in continuation.resume() }
                SignalProxy.startRelayServer()
            }
        }
    }

    @MainActor
    private func fetchAndProcessMessages(logger: NSELogger) async -> UNNotificationContent {
        if DependenciesBridge.shared.appExpiry.isExpired {
            Logger.warn("Not processing notifications for expired application.")
            return UNMutableNotificationContent()
        }

        await startProxyIfEnabled()
        defer { SignalProxy.stopRelayServer() }

        globalEnvironment.processingMessageCounter.increment()
        defer { globalEnvironment.processingMessageCounter.decrement() }

        do {
            try await SSKEnvironment.shared.messageFetcherJobRef.run().awaitable()

            await SSKEnvironment.shared.messageProcessorRef.waitForProcessingComplete().awaitable()

            // Wait for these in parallel.
            do {
                // Wait until all ACKs are complete.
                async let pendingAcks: Void = SSKEnvironment.shared.messageFetcherJobRef.pendingAcksPromise().awaitable()
                // Wait until all outgoing receipt sends are complete.
                async let pendingReceipts: Void = SSKEnvironment.shared.receiptSenderRef.pendingSendsPromise().awaitable()
                // Wait until all outgoing messages are sent.
                async let pendingMessages: Void = SSKEnvironment.shared.messageSenderRef.pendingSendsPromise().awaitable()
                // Wait until all sync requests are fulfilled.
                async let pendingOps: Void = MessageReceiver.pendingTasksPromise().awaitable()

                try await pendingAcks
                try await pendingReceipts
                try await pendingMessages
                try await pendingOps
            }

            // Finally, wait for any notifications to finish posting
            try await NotificationPresenterImpl.pendingNotificationsPromise().awaitable()
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
