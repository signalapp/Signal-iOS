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
    private let contentHandler = AtomicOptional<ContentHandler>(nil, lock: .sharedGlobal)

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
    func completeSilently(badgeCount: BadgeCount? = nil, logger: NSELogger) {
        defer { logger.flush() }

        guard let contentHandler = contentHandler.swap(nil) else {
            return
        }

        Self.nseDidComplete()

        let content = UNMutableNotificationContent()
        content.badge = badgeCount.map { NSNumber(value: $0.unreadTotalCount) }

        contentHandler(content)
    }

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let logger = NSELogger()

        do {
            try DispatchQueue.main.sync(execute: { try globalEnvironment.setUp(logger: logger) })
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
                contentHandler(content)
            } else {
                // Only show a single error if we receive multiple pushes
                // before first device unlock.
                logger.error("DB Keys not accessible; completing silently.", flushImmediately: true)
                let emptyContent = UNMutableNotificationContent()
                contentHandler(emptyContent)
            }
            return
        } catch {
            owsFail("Couldn't load database: \(error.grdbErrorForLogging)")
        }

        self.contentHandler.set(contentHandler)

        _ = Self.nseDidStart()

        globalEnvironment.appReadiness.runNowOrWhenAppWillBecomeReady {
            // Mark down that the APNS token is working since we got a push.
            // Do this as early as possible but after the app is ready and has run
            // GRDB migrations and such. (therefore, willBecomeReady, which actually runs
            // after the app is ready but just before any didBecomeReady blocks)
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { transaction in
                APNSRotationStore.didReceiveAPNSPush(transaction: transaction)
            }
        }

        globalEnvironment.appReadiness.runNowOrWhenAppDidBecomeReadySync {
            SSKEnvironment.shared.messageFetcherJobRef.prepareToFetchViaREST()
        }

        globalEnvironment.appReadiness.runNowOrWhenAppDidBecomeReadySync {
            globalEnvironment.askMainAppToHandleReceipt(logger: logger) { [weak self] mainAppHandledReceipt in
                guard !mainAppHandledReceipt else {
                    logger.info("Received notification handled by main application, memoryUsage: \(LocalDevice.memoryUsageString).")
                    self?.completeSilently(logger: logger)
                    return
                }

                DispatchQueue.main.async {
                    self?.fetchAndProcessMessages(logger: logger)
                }
            }
        }
    }

    // Called just before the extension will be terminated by the system.
    override func serviceExtensionTimeWillExpire() {
        owsFailDebug("NSE expired before messages could be processed")

        // We complete silently here so that nothing is presented to the user.
        // By default the OS will present whatever the raw content of the original
        // notification is to the user otherwise.
        completeSilently(logger: .uncorrelated)
    }

    // This method is thread-safe.
    private func fetchAndProcessMessages(logger: NSELogger) {
        if DependenciesBridge.shared.appExpiry.isExpired {
            owsFailDebug("Not processing notifications for expired application.")
            return completeSilently(logger: logger)
        }

        if SignalProxy.isEnabled {
            if !SignalProxy.isEnabledAndReady {
                Logger.info("Waiting for signal proxy to become ready for message fetch.")
                NotificationCenter.default.observe(once: .isSignalProxyReadyDidChange)
                    .done { [weak self] _ in
                        self?.fetchAndProcessMessages(logger: logger)
                    }
                SignalProxy.startRelayServer()
                return
            }

            Logger.info("Using signal proxy for message fetch.")
        }

        globalEnvironment.processingMessageCounter.increment()

        firstly {
            SSKEnvironment.shared.messageFetcherJobRef.run()
        }.then(on: DispatchQueue.global()) { () -> Promise<Void> in

            return firstly { () -> Promise<Void> in
                return SSKEnvironment.shared.messageProcessorRef.waitForProcessingComplete().asPromise()
            }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
                return Promise.when(on: SyncScheduler(), resolved: [
                    // Wait until all ACKs are complete.
                    SSKEnvironment.shared.messageFetcherJobRef.pendingAcksPromise(),
                    // Wait until all outgoing receipt sends are complete.
                    SSKEnvironment.shared.receiptSenderRef.pendingSendsPromise(),
                    // Wait until all outgoing messages are sent.
                    SSKEnvironment.shared.messageSenderRef.pendingSendsPromise(),
                    // Wait until all sync requests are fulfilled.
                    MessageReceiver.pendingTasksPromise(),
                ]).asVoid()
            }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
                // Finally, wait for any notifications to finish posting
                return NotificationPresenterImpl.pendingNotificationsPromise()
            }
        }.ensure(on: DispatchQueue.global()) { [weak self] in
            logger.info("Message fetching & processing completed.")
            SignalProxy.stopRelayServer()
            globalEnvironment.processingMessageCounter.decrementOrZero()
            // If we're completing normally, try to update the badge on the app icon.
            let badgeCount: BadgeCount = SSKEnvironment.shared.databaseStorageRef.read { tx in
                return DependenciesBridge.shared.badgeCountFetcher
                    .fetchBadgeCount(tx: tx.asV2Read)
            }
            self?.completeSilently(badgeCount: badgeCount, logger: logger)
        }.catch(on: DispatchQueue.global()) { error in
            logger.error("Error: \(error)")
        }
    }
}
