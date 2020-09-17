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
        return .shared
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
    //      the contentHandler
    //  5)  If the extension takes too long to perform its work
    //      (more than 30s), it will be notified and immediately
    //      terminated
    //
    // Note that the NSE does *not* always spawn a new process to
    // handle a new notification and will also try and process notifications
    // in parallel. `didReceive` could be called twice for the same process,
    // but will always be called on different threads. To deal with this we
    // ensure that we only do setup *once* per process and we dispatch to
    // the main queue to make sure the calls to the message fetcher job
    // run serially.
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler

        DispatchQueue.main.sync { self.setupIfNecessary() }

        // Until we want to use this extension, crash if this path is hit.
        guard FeatureFlags.notificationServiceExtension else {
            owsFail("NSE should never be called.")
        }

        listenForMainAppLaunch()

        askMainAppToHandleReceipt { mainAppHandledReceipt in
            guard !mainAppHandledReceipt else {
                Logger.info("Received notification handled by main application.")
                return self.completeSilenty()
            }

            Logger.info("Processing received notification.")

            AppReadiness.runNowOrWhenAppDidBecomeReady { self.fetchAndProcessMessages() }
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

    private var hasSetup = false
    func setupIfNecessary() {
        AssertIsOnMainThread()

        // The NSE will often re-use the same process, so if we're
        // already setup we want to do nothing. We're already ready
        // to process new messages.
        guard !hasSetup else { return }

        hasSetup = true

        // This should be the first thing we do.
        SetCurrentAppContext(NotificationServiceExtensionContext())

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if OWSPreferences.isLoggingEnabled() {
            DebugLogger.shared().enableFileLogging()
        }

        Logger.info("")

        _ = AppVersion.shared()

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
        guard !AppReadiness.isAppReady else { return }

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard storageCoordinator.isStorageReady && areVersionMigrationsComplete else { return }

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        AppReadiness.setAppIsReady()

        AppVersion.shared().nseLaunchDidComplete()
    }

    func askMainAppToHandleReceipt(handledCallback: @escaping (_ mainAppHandledReceipt: Bool) -> Void) {
        DispatchQueue.main.async {
            // We track whether we've ever handled the call back to ensure
            // we only notify the caller once and avoid any races that may
            // occur between the notification observer and the dispatch
            // after block.
            var hasCalledBack = false

            // Listen for an indication that the main app is going to handle
            // this notification. If the main app is active we don't want to
            // process any messages here.
            let token = DarwinNotificationCenter.addObserver(for: .mainAppHandledNotification, queue: .main) { token in
                guard !hasCalledBack else { return }

                hasCalledBack = true

                handledCallback(true)

                if DarwinNotificationCenter.isValidObserver(token) {
                    DarwinNotificationCenter.removeObserver(token)
                }
            }

            // Notify the main app that we received new content to process.
            // If it's running, it will notify us so we can bail out.
            DarwinNotificationCenter.post(.nseDidReceiveNotification)

            // The main app should notify us nearly instantaneously if it's
            // going to process this notification so we only wait a fraction
            // of a second to hear back from it.
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.001) {
                if DarwinNotificationCenter.isValidObserver(token) {
                    DarwinNotificationCenter.removeObserver(token)
                }

                guard !hasCalledBack else { return }

                hasCalledBack = true

                // If we haven't called back yet and removed the observer token,
                // the main app is not running and will not handle receipt of this
                // notification.
                handledCallback(false)
            }
        }
    }

    private var mainAppLaunchObserverToken = DarwinNotificationInvalidObserver
    func listenForMainAppLaunch() {
        guard !DarwinNotificationCenter.isValidObserver(mainAppLaunchObserverToken) else { return }
        mainAppLaunchObserverToken = DarwinNotificationCenter.addObserver(for: .mainAppLaunched, queue: .global(), using: { _ in
            // If we're currently processing messages we want to commit
            // suicide to ensure that we don't try and process messages
            // while the main app is running. If we're not processing
            // messages we keep alive since future notifications will
            // be passed off gracefully to the main app. We only kill
            // ourselves as a last resort.
            // TODO: We could eventually make the message fetch process
            // cancellable to never have to exit here.
            guard self.isProcessingMessages.get() else { return }
            Logger.info("Exiting because main app launched while we were processing messages.")
            exit(0)
        })
    }

    private let isProcessingMessages = AtomicBool(false)

    func fetchAndProcessMessages() {
        AssertIsOnMainThread()

        guard !AppExpiry.shared.isExpired else {
            owsFailDebug("Not processing notifications for expired application.")
            return completeSilenty()
        }

        isProcessingMessages.set(true)

        Logger.info("Beginning message fetch.")

        messageFetcherJob.run().promise.then {
            return self.messageProcessing.flushMessageDecryptionAndProcessingPromise().asVoid()
        }.ensure {
            Logger.info("Message fetch completed.")
            self.isProcessingMessages.set(false)
            self.completeSilenty()
        }.catch { error in
            Logger.warn("Error: \(error)")
        }
    }
}
