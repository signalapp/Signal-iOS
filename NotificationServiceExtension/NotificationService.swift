//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import UserNotifications
import SignalMessaging
import SignalServiceKit
import PromiseKit

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var areVersionMigrationsComplete = false

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    var messageProcessing: MessageProcessing {
        return SSKEnvironment.shared.messageProcessing
    }

    var messageFetcherJob: MessageFetcherJob {
        return SSKEnvironment.shared.messageFetcherJob
    }

    func completeSilenty() {
        contentHandler?(.init())
    }

    // The lifecycle of the NSE looks something like the following:
    //  1)  App receives notification
    //  2)  System creates an instance of the extension class
    //      and calls this method in the background
    //  3)  Extension processes messages / displays whatever
    //      notifications it needs to
    //  4)  Extension notifies its work is complete by calling
    //      the contentHandler and is terminated
    //  5)  If the extension takes too long to perform its work
    //      (more than 30s), it will be notified and immediately
    //      terminated
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        DispatchQueue.main.async { self.setup() }
    }

    // Called just before the extension will be terminated by the system.
    override func serviceExtensionTimeWillExpire() {
        Logger.error("NSE expired before messages could be processed")

        NotificationCenter.default.removeObserver(self)

        completeSilenty()
    }

    func setup() {
        AssertIsOnMainThread()

        // This should be the first thing we do.
        SetCurrentAppContext(NotificationServiceExtensionContext())

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if OWSPreferences.isLoggingEnabled() {
            DebugLogger.shared().enableFileLogging()
        }

        Logger.info("")

        _ = AppVersion.sharedInstance()

        Cryptography.seedRandom()

        // We should never receive a non-voip notification on an app that doesn't support
        // app extensions since we have to inform the service we wanted these, so in theory
        // this path should never occur. However, the service does have our push token
        // so it is possible that could change in the future. If it does, do nothing
        // and don't disturb the user. Messages will be processed when they open the app.
        guard OWSPreferences.isReadyForAppExtensions() else { return completeSilenty() }

        AppSetup.setupEnvironment(
            appSpecificSingletonBlock: {
                // TODO: calls..
                SSKEnvironment.shared.callMessageHandler = NoopCallMessageHandler()
                SSKEnvironment.shared.notificationsManager = NotificationPresenter()
            },
            migrationCompletion: { [weak self] in
                self?.versionMigrationsDidComplete()
            }
        )

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(storageIsReady),
                                               name: .StorageIsReady,
                                               object: nil)

        Logger.info("completed.")

        OWSAnalytics.appLaunchDidBegin()
    }

    @objc
    func versionMigrationsDidComplete() {
        AssertIsOnMainThread()

        Logger.debug("")

        areVersionMigrationsComplete = true

        checkIsAppReady()
    }

    @objc
    func storageIsReady() {
        AssertIsOnMainThread()

        Logger.debug("")

        checkIsAppReady()
    }

    @objc
    func checkIsAppReady() {
        AssertIsOnMainThread()

        // Only mark the app as ready once.
        guard !AppReadiness.isAppReady() else { return }

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard storageCoordinator.isStorageReady && areVersionMigrationsComplete else { return }

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        AppReadiness.setAppIsReady()

        AppVersion.sharedInstance().nseLaunchDidComplete()

        fetchAndProcessMessages()
    }

    func fetchAndProcessMessages() {
        guard !AppExpiry.isExpired else {
            Logger.info("Not processing notifications for expired application.")
            return completeSilenty()
        }

        messageFetcherJob.run().promise.then {
            return self.messageProcessing.flushMessageDecryptionAndProcessingPromise()
        }.ensure {
            self.completeSilenty()
        }.retainUntilComplete()
    }
}
