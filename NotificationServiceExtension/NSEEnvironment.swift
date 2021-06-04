//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

class NSEEnvironment: Dependencies {
    var isProcessingMessages = AtomicBool(false)

    // MARK: - Main App Comms

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
            Logger.flush()
            exit(0)
        })
    }

    // MARK: - Setup

    private var isSetup = AtomicBool(false)
    func setupIfNecessary() {
        guard isSetup.tryToSetFlag() else { return }
        DispatchQueue.main.sync { setup() }
    }

    private var areVersionMigrationsComplete = false
    private func setup() {
        AssertIsOnMainThread()

        // This should be the first thing we do.
        SetCurrentAppContext(NSEContext())

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if OWSPreferences.isLoggingEnabled() {
            DebugLogger.shared().enableFileLogging()
        }

        Logger.info("")

        _ = AppVersion.shared()

        Cryptography.seedRandom()

        AppSetup.setupEnvironment(
            appSpecificSingletonBlock: {
                SSKEnvironment.shared.callMessageHandlerRef = NSECallMessageHandler()
                SSKEnvironment.shared.notificationsManagerRef = NotificationPresenter()
            },
            migrationCompletion: { [weak self] error in
                if let error = error {
                    // TODO: Maybe notify that you should open the main app.
                    owsFailDebug("Error \(error)")
                    return
                }
                self?.versionMigrationsDidComplete()
            }
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storageIsReady),
            name: .StorageIsReady,
            object: nil
        )

        Logger.info("completed.")

        OWSAnalytics.appLaunchDidBegin()

        listenForMainAppLaunch()
    }

    @objc
    private func versionMigrationsDidComplete() {
        AssertIsOnMainThread()

        Logger.debug("")

        areVersionMigrationsComplete = true

        checkIsAppReady()
    }

    @objc
    private func storageIsReady() {
        AssertIsOnMainThread()

        Logger.debug("")

        checkIsAppReady()
    }

    @objc
    private func checkIsAppReady() {
        AssertIsOnMainThread()

        // Only mark the app as ready once.
        guard !AppReadiness.isAppReady else { return }

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard storageCoordinator.isStorageReady && areVersionMigrationsComplete else { return }

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        AppReadiness.setAppIsReady()

        AppVersion.shared().nseLaunchDidComplete()
    }
}
