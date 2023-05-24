//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UserNotifications
import SignalMessaging
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

private let hasShownFirstUnlockError = AtomicBool(false)

class NotificationService: UNNotificationServiceExtension {
    private typealias ContentHandler = (UNNotificationContent) -> Void
    private let contentHandler = AtomicOptional<ContentHandler>(nil)

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
    func completeSilently(timeHasExpired: Bool = false, badgeValue: UInt? = nil, logger: NSELogger) {
        defer { logger.flush() }

        guard let contentHandler = contentHandler.swap(nil) else {
            return
        }

        Self.nseDidComplete()

        let content = UNMutableNotificationContent()
        content.badge = badgeValue.map { NSNumber(value: $0) }

        if timeHasExpired {
            contentHandler(content)
        } else {
            // If we have some time left, query current notification state
            logger.info("Querying existing notifications")

            let notificationCenter = UNUserNotificationCenter.current()
            notificationCenter.getPendingNotificationRequests { requests in
                defer { logger.flush() }
                logger.info("Found \(requests.count) pending notification requests with identifiers: \(requests.map { $0.identifier }.joined(separator: ", "))")

                notificationCenter.getDeliveredNotifications { notifications in
                    defer { logger.flush() }
                    logger.info("Found \(notifications.count) delivered notifications with identifiers: \(notifications.map { $0.request.identifier }.joined(separator: ", "))")

                    contentHandler(content)
                }
            }
        }
    }

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let logger = NSELogger()

        DispatchQueue.main.sync { globalEnvironment.setUpBeforeCheckingForFirstDeviceUnlock(logger: logger) }

        // Detect and handle "no GRDB file" and "no keychain access; device
        // not yet unlocked for first time" cases _before_ calling
        // setupIfNecessary().
        if let errorContent = globalEnvironment.verifyDBKeysAvailable(logger: logger) {
            if hasShownFirstUnlockError.tryToSetFlag() {
                logger.error("DB Keys not accessible; showing error.", flushImmediately: true)
                contentHandler(errorContent)
            } else {
                // Only show a single error if we receive multiple pushes
                // before first device unlock.
                logger.error("DB Keys not accessible; completing silently.", flushImmediately: true)
                let emptyContent = UNMutableNotificationContent()
                contentHandler(emptyContent)
            }
            return
        }

        DispatchQueue.main.sync { globalEnvironment.setUpAfterCheckingForFirstDeviceUnlock(logger: logger) }

        self.contentHandler.set(contentHandler)

        let nseCount = Self.nseDidStart()

        logger.info(
            "Received notification in pid: \(ProcessInfo.processInfo.processIdentifier), memoryUsage: \(LocalDevice.memoryUsageString), nseCount: \(nseCount)"
        )

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            // Mark down that the APNS token is working since we got a push.
            // Do this as early as possible but after the app is ready and has run
            // GRDB migrations and such. (therefore, willBecomeReady, which actually runs
            // after the app is ready but just before any didBecomeReady blocks)
            Self.databaseStorage.asyncWrite { transaction in
                APNSRotationStore.didReceiveAPNSPush(transaction: transaction)
            }
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            globalEnvironment.askMainAppToHandleReceipt(logger: logger) { [weak self] mainAppHandledReceipt in
                guard !mainAppHandledReceipt else {
                    logger.info("Received notification handled by main application, memoryUsage: \(LocalDevice.memoryUsageString).")
                    self?.completeSilently(logger: logger)
                    return
                }

                logger.info("Processing received notification, memoryUsage: \(LocalDevice.memoryUsageString).")

                self?.fetchAndProcessMessages(logger: logger)
            }
        }
    }

    // Called just before the extension will be terminated by the system.
    override func serviceExtensionTimeWillExpire() {
        owsFailDebug("NSE expired before messages could be processed")

        // We complete silently here so that nothing is presented to the user.
        // By default the OS will present whatever the raw content of the original
        // notification is to the user otherwise.
        completeSilently(timeHasExpired: true, logger: .uncorrelated)
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

        logger.info("Beginning message fetch.")

        firstly {
            messageFetcherJob.run().promise
        }.then(on: DispatchQueue.global()) { [weak self] () -> Promise<Void> in
            logger.info("Waiting for processing to complete.")
            guard let self = self else { return Promise.value(()) }

            let runningAndCompletedPromises = AtomicArray<(String, Promise<Void>)>()

            return firstly { () -> Promise<Void> in
                let promise = self.messageProcessor.processingCompletePromise()
                runningAndCompletedPromises.append(("MessageProcessorCompletion", promise))
                return promise
            }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
                logger.info("Initial message processing complete.")
                // Wait until all async side effects of message processing are complete.
                let completionPromises: [(String, Promise<Void>)] = [
                    // Wait until all ACKs are complete.
                    ("Pending messageFetch ack", Self.messageFetcherJob.pendingAcksPromise()),
                    // Wait until all outgoing receipt sends are complete.
                    ("Pending receipt sends", Self.outgoingReceiptManager.pendingSendsPromise()),
                    // Wait until all outgoing messages are sent.
                    ("Pending outgoing message", Self.messageSender.pendingSendsPromise()),
                    // Wait until all sync requests are fulfilled.
                    ("Pending sync request", OWSMessageManager.pendingTasksPromise())
                ]
                let joinedPromise = Promise.when(resolved: completionPromises.map { (name, promise) in
                    promise.done(on: DispatchQueue.global()) {
                        logger.info("\(name) complete")
                    }
                })
                completionPromises.forEach { runningAndCompletedPromises.append($0) }
                return joinedPromise.asVoid()
            }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
                // Finally, wait for any notifications to finish posting
                let promise = NotificationPresenter.pendingNotificationsPromise()
                runningAndCompletedPromises.append(("Pending notification post", promise))
                return promise
            }
        }.ensure(on: DispatchQueue.global()) { [weak self] in
            logger.info("Message fetch completed.")
            SignalProxy.stopRelayServer()
            globalEnvironment.processingMessageCounter.decrementOrZero()
            // If we're completing normally, try to update the badge on the app icon.
            let badgeValue = Self.databaseStorage.read { tx in
                InteractionFinder.unreadCountInAllThreads(transaction: tx.unwrapGrdbRead)
            }
            self?.completeSilently(badgeValue: badgeValue, logger: logger)
        }.catch(on: DispatchQueue.global()) { error in
            logger.error("Error: \(error)")
        }
    }
}
