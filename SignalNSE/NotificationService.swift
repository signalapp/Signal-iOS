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
let environment = NSEEnvironment()

let hasShownFirstUnlockError = AtomicBool(false)

class NotificationService: UNNotificationServiceExtension {

    private typealias ContentHandler = (UNNotificationContent) -> Void
    private var contentHandler = AtomicOptional<ContentHandler>(nil)

    // MARK: -

    private static let unfairLock = UnfairLock()
    private static var _logTimer: OffMainThreadTimer?
    private static var _nseCounter: Int = 0

    private static func nseDidStart() -> Int {
        unfairLock.withLock {
            if DebugFlags.internalLogging,
               _logTimer == nil {
                _logTimer = OffMainThreadTimer(timeInterval: 1.0, repeats: true) { _ in
                    NSELogger.uncorrelated.info("... memoryUsage: \(LocalDevice.memoryUsageString)")
                }
            }

            _nseCounter += 1
            return _nseCounter
        }
    }

    private static func nseDidComplete() -> Int {
        unfairLock.withLock {
            _nseCounter = _nseCounter > 0 ? _nseCounter - 1 : 0

            if _nseCounter == 0, _logTimer != nil {
                _logTimer?.invalidate()
                _logTimer = nil
            }
            return _nseCounter
        }
    }

    // MARK: -

    // This method is thread-safe.
    func completeSilently(timeHasExpired: Bool = false, logger: NSELogger) {
        defer { logger.flush() }

        let nseCount = Self.nseDidComplete()

        guard let contentHandler = contentHandler.swap(nil) else {
            if DebugFlags.internalLogging {
                logger.warn("No contentHandler, memoryUsage: \(LocalDevice.memoryUsageString), nseCount: \(nseCount).")
            }
            return
        }

        let content = UNMutableNotificationContent()
        content.badge = {
            if let nseContext = CurrentAppContext() as? NSEContext {
                if !timeHasExpired {
                    // If we have time, we might as well get the current up-to-date badge count
                    let freshCount = databaseStorage.read { InteractionFinder.unreadCountInAllThreads(transaction: $0.unwrapGrdbRead) }
                    return NSNumber(value: freshCount)
                } else if let cachedBadgeCount = nseContext.desiredBadgeNumber.get() {
                    // If we don't have time to get a fresh count, let's use the cached count stored in our context
                    return NSNumber(value: cachedBadgeCount)
                } else {
                    // The context never set a badge count, let's leave things as-is:
                    return nil
                }
            } else {
                // We never set up an NSEContext. Let's leave things as-is:
                owsFailDebug("Missing NSE context!")
                return nil
            }
        }()

        if DebugFlags.internalLogging {
            logger.info("Invoking contentHandler, memoryUsage: \(LocalDevice.memoryUsageString), nseCount: \(nseCount).")
        }

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
        environment.ensureGlobalState()

        let logger = NSELogger()

        // Detect and handle "no GRDB file" and "no keychain access; device
        // not yet unlocked for first time" cases _before_ calling
        // setupIfNecessary().
        if let errorContent = NSEEnvironment.verifyDBKeysAvailable(logger: logger) {
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

        if let errorContent = environment.setupIfNecessary(logger: logger) {
            // This should not occur; see above.  If we've reached this
            // point, the NSEEnvironment.isSetup flag is already set,
            // but the environment has _not_ been setup successfully.
            // We need to terminate the NSE to return to a good state.
            logger.warn("Posting error notification and skipping processing.", flushImmediately: true)
            contentHandler(errorContent)
            fatalError("Posting error notification and skipping processing.")
        }

        self.contentHandler.set(contentHandler)

        owsAssertDebug(FeatureFlags.notificationServiceExtension)

        let nseCount = Self.nseDidStart()

        logger.info(
            "Received notification in class: \(self), thread: \(Thread.current), pid: \(ProcessInfo.processInfo.processIdentifier), memoryUsage: \(LocalDevice.memoryUsageString), nseCount: \(nseCount)"
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
            environment.askMainAppToHandleReceipt(logger: logger) { [weak self] mainAppHandledReceipt in
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
        guard !AppExpiry.shared.isExpired else {
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

        environment.processingMessageCounter.increment()

        logger.info("Beginning message fetch.")

        firstly {
            messageFetcherJob.run().promise
        }.then(on: .global()) { [weak self] () -> Promise<Void> in
            logger.info("Waiting for processing to complete.")
            guard let self = self else { return Promise.value(()) }

            let runningAndCompletedPromises = AtomicArray<(String, Promise<Void>)>()

            return firstly { () -> Promise<Void> in
                let promise = self.messageProcessor.processingCompletePromise()
                runningAndCompletedPromises.append(("MessageProcessorCompletion", promise))
                return promise
            }.then(on: .global()) { () -> Promise<Void> in
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
                    promise.done(on: .global()) {
                        logger.info("\(name) complete")
                    }
                })
                completionPromises.forEach { runningAndCompletedPromises.append($0) }
                return joinedPromise.asVoid()
            }.then(on: .global()) { () -> Promise<Void> in
                // Finally, wait for any notifications to finish posting
                let promise = NotificationPresenter.pendingNotificationsPromise()
                runningAndCompletedPromises.append(("Pending notification post", promise))
                return promise
            }
        }.ensure(on: .global()) { [weak self] in
            logger.info("Message fetch completed.")
            SignalProxy.stopRelayServer()
            environment.processingMessageCounter.decrementOrZero()
            self?.completeSilently(logger: logger)
        }.catch(on: .global()) { error in
            logger.error("Error: \(error)")
        }
    }
}
