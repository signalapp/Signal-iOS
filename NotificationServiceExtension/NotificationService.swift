//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UserNotifications
import SignalMessaging
import SignalServiceKit
import PromiseKit

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

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var areVersionMigrationsComplete = false

    func completeSilenty() {
        let content = UNMutableNotificationContent()
        content.badge = NSNumber(value: databaseStorage.read { InteractionFinder.unreadCountInAllThreads(transaction: $0.unwrapGrdbRead) })
        contentHandler?(content)
    }

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler

        environment.setupIfNecessary()

        owsAssertDebug(FeatureFlags.notificationServiceExtension)

        Logger.info("Received notification in class: \(self), thread: \(Thread.current), pid: \(ProcessInfo.processInfo.processIdentifier)")

        environment.askMainAppToHandleReceipt { [weak self] mainAppHandledReceipt in
            guard !mainAppHandledReceipt else {
                Logger.info("Received notification handled by main application.")
                self?.completeSilenty()
                return
            }

            Logger.info("Processing received notification.")

            AppReadiness.runNowOrWhenAppDidBecomeReadySync { self?.fetchAndProcessMessages() }
        }
    }

    // Called just before the extension will be terminated by the system.
    override func serviceExtensionTimeWillExpire() {
        owsFailDebug("NSE expired before messages could be processed")

        // We complete silently here so that nothing is presented to the user.
        // By default the OS will present whatever the raw content of the original
        // notification is to the user otherwise.
        completeSilenty()
    }

    func fetchAndProcessMessages() {
        AssertIsOnMainThread()

        guard !AppExpiry.shared.isExpired else {
            owsFailDebug("Not processing notifications for expired application.")
            return completeSilenty()
        }

        environment.isProcessingMessages.set(true)

        Logger.info("Beginning message fetch.")

        messageFetcherJob.run().promise.then { [weak self] () -> Promise<Void> in
            Logger.info("Waiting for processing to complete.")
            guard let self = self else { return Promise.value(()) }
            return self.messageProcessor.processingCompletePromise()
        }.ensure { [weak self] in
            Logger.info("Message fetch completed.")
            environment.isProcessingMessages.set(false)
            self?.completeSilenty()
        }.catch { error in
            Logger.warn("Error: \(error)")
        }
    }
}
