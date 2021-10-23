//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
                    Logger.info("... memoryUsage: \(LocalDevice.memoryUsage)")
                }
            }

            _nseCounter = _nseCounter + 1
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
    func completeSilenty(timeHasExpired: Bool = false) {

        let nseCount = Self.nseDidComplete()

        guard let contentHandler = contentHandler.swap(nil) else {
            if DebugFlags.internalLogging {
                Logger.warn("No contentHandler, memoryUsage: \(LocalDevice.memoryUsage), nseCount: \(nseCount).")
            }
            Logger.flush()
            return
        }

        let content = UNMutableNotificationContent()

        // We cannot perform a database read when the NSE's time
        // has expired, we must exit immediately.
        if !timeHasExpired {
            let badgeCount = databaseStorage.read { InteractionFinder.unreadCountInAllThreads(transaction: $0.unwrapGrdbRead) }
            content.badge = NSNumber(value: badgeCount)
        }

        if DebugFlags.internalLogging {
            Logger.info("Invoking contentHandler, memoryUsage: \(LocalDevice.memoryUsage), nseCount: \(nseCount).")
        }
        Logger.flush()

        contentHandler(content)
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {

        // This should be the first thing we do.
        environment.ensureAppContext()

        // Detect and handle "no GRDB file" and "no keychain access; device
        // not yet unlocked for first time" cases _before_ calling
        // setupIfNecessary().
        if let errorContent = NSEEnvironment.verifyDBKeysAvailable() {
            if hasShownFirstUnlockError.tryToSetFlag() {
                NSLog("DB Keys not accessible; showing error.")
                contentHandler(errorContent)
            } else {
                // Only show a single error if we receive multiple pushes
                // before first device unlock.
                NSLog("DB Keys not accessible; completing silently.")
                let emptyContent = UNMutableNotificationContent()
                contentHandler(emptyContent)
            }
            return
        }

        if let errorContent = environment.setupIfNecessary() {
            // This should not occur; see above.  If we've reached this
            // point, the NSEEnvironment.isSetup flag is already set,
            // but the environment has _not_ been setup successfully.
            // We need to terminate the NSE to return to a good state.
            Logger.warn("Posting error notification and skipping processing.")
            Logger.flush()
            contentHandler(errorContent)
            fatalError("Posting error notification and skipping processing.")
        }

        self.contentHandler.set(contentHandler)

        owsAssertDebug(FeatureFlags.notificationServiceExtension)

        let nseCount = Self.nseDidStart()

        Logger.info("Received notification in class: \(self), thread: \(Thread.current), pid: \(ProcessInfo.processInfo.processIdentifier), memoryUsage: \(LocalDevice.memoryUsage), nseCount: \(nseCount)")

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            environment.askMainAppToHandleReceipt { [weak self] mainAppHandledReceipt in
                guard !mainAppHandledReceipt else {
                    Logger.info("Received notification handled by main application, memoryUsage: \(LocalDevice.memoryUsage).")
                    self?.completeSilenty()
                    return
                }

                Logger.info("Processing received notification, memoryUsage: \(LocalDevice.memoryUsage).")

                self?.fetchAndProcessMessages()
            }
        }
    }

    // Called just before the extension will be terminated by the system.
    override func serviceExtensionTimeWillExpire() {
        owsFailDebug("NSE expired before messages could be processed")

        // We complete silently here so that nothing is presented to the user.
        // By default the OS will present whatever the raw content of the original
        // notification is to the user otherwise.
        completeSilenty(timeHasExpired: true)
    }

    // This method is thread-safe.
    private func fetchAndProcessMessages() {
        guard !AppExpiry.shared.isExpired else {
            owsFailDebug("Not processing notifications for expired application.")
            return completeSilenty()
        }

        environment.processingMessageCounter.increment()

        Logger.info("Beginning message fetch.")

        let fetchPromise = messageFetcherJob.run().promise
        fetchPromise.timeout(seconds: 20, description: "Message Fetch Timeout.") {
            NotificationServiceError.timeout
        }.catch(on: .global()) { _ in
            // Do nothing, Promise.timeout() will log timeouts.
        }
        fetchPromise.then(on: .global()) { [weak self] () -> Promise<Void> in
            Logger.info("Waiting for processing to complete.")
            guard let self = self else { return Promise.value(()) }
            let processingCompletePromise = firstly {
                self.messageProcessor.processingCompletePromise()
            }.then(on: .global()) { () -> Promise<Void> in
                // Wait until all async side effects of
                // message processing are complete.
                let completionPromises: [Promise<Void>] = [
                    // Wait until all notifications are posted.
                    NotificationPresenter.pendingNotificationsPromise(),
                    // Wait until all ACKs are complete.
                    Self.messageFetcherJob.pendingAcksPromise(),
                    // Wait until all outgoing receipt sends are complete.
                    Self.outgoingReceiptManager.pendingSendsPromise(),
                    // Wait until all outgoing messages are sent.
                    Self.messageSender.pendingSendsPromise(),
                    // Wait until all sync requests are fulfilled.
                    OWSMessageManager.pendingTasksPromise()
                ]
                return Promise.when(resolved: completionPromises).asVoid()
            }
            processingCompletePromise.timeout(seconds: 20, description: "Message Processing Timeout.") {
                NotificationServiceError.timeout
            }.catch { _ in
                // Do nothing, Promise.timeout() will log timeouts.
            }
            return processingCompletePromise
        }.ensure(on: .global()) { [weak self] in
            Logger.info("Message fetch completed.")
            environment.processingMessageCounter.decrementOrZero()
            self?.completeSilenty()
        }.catch(on: .global()) { error in
            Logger.warn("Error: \(error)")
        }
    }

    private enum NotificationServiceError: Error {
        case timeout
    }
}
