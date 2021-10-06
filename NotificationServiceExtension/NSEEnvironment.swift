//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

class NSEEnvironment: Dependencies {
    var processingMessageCounter = AtomicUInt(0)
    var isProcessingMessages {
        processingMessageCounter.get() > 0
    }

    // MARK: - Main App Comms

    private static var mainAppDarwinQueue: DispatchQueue { .global(qos: .userInitiated) }

    func askMainAppToHandleReceipt(handledCallback: @escaping (_ mainAppHandledReceipt: Bool) -> Void) {
        Self.mainAppDarwinQueue.async {
            // We track whether we've ever handled the call back to ensure
            // we only notify the caller once and avoid any races that may
            // occur between the notification observer and the dispatch
            // after block.
            let hasCalledBack = AtomicBool(false)

            if DebugFlags.internalLogging {
                Logger.info("Requesting main app to handle incoming message.")
            }

            // Listen for an indication that the main app is going to handle
            // this notification. If the main app is active we don't want to
            // process any messages here.
            let token = DarwinNotificationCenter.addObserver(for: .mainAppHandledNotification, queue: Self.mainAppDarwinQueue) { token in
                guard hasCalledBack.tryToSetFlag() else { return }

                if DarwinNotificationCenter.isValidObserver(token) {
                    DarwinNotificationCenter.removeObserver(token)
                }

                if DebugFlags.internalLogging {
                    Logger.info("Main app ack'd.")
                }

                handledCallback(true)
            }

            // Notify the main app that we received new content to process.
            // If it's running, it will notify us so we can bail out.
            DarwinNotificationCenter.post(.nseDidReceiveNotification)

            // The main app should notify us nearly instantaneously if it's
            // going to process this notification so we only wait a fraction
            // of a second to hear back from it.
            Self.mainAppDarwinQueue.asyncAfter(deadline: DispatchTime.now() + 0.010) {
                guard hasCalledBack.tryToSetFlag() else { return }

                if DarwinNotificationCenter.isValidObserver(token) {
                    DarwinNotificationCenter.removeObserver(token)
                }

                if DebugFlags.internalLogging {
                    Logger.info("Did timeout.")
                }

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
            Logger.warn("Main app launched.")
            guard self.isProcessingMessages else { return }
            Logger.warn("Exiting because main app launched while we were processing messages.")
            Logger.flush()
            exit(0)
        })
    }

    // MARK: - Setup

    private let unfairLock = UnfairLock()
    private var hasAppContext = false

    // This should be the first thing we do.
    public func ensureAppContext() {
        unfairLock.withLock {
            if hasAppContext {
                return
            }
            // This should be the first thing we do.
            SetCurrentAppContext(NSEContext())
            hasAppContext = true
        }
    }

    private var isSetup = AtomicBool(false)

    func setupIfNecessary() -> UNNotificationContent? {
        guard isSetup.tryToSetFlag() else { return nil }
        return DispatchQueue.main.sync { setup() }
    }

    private var areVersionMigrationsComplete = false
    private func setup() -> UNNotificationContent? {
        AssertIsOnMainThread()

        // This should be the first thing we do.
        ensureAppContext()

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if OWSPreferences.isLoggingEnabled() {
            DebugLogger.shared().enableFileLogging()
        }

        Logger.info("")

        _ = AppVersion.shared()

        Cryptography.seedRandom()

        if let errorContent = Self.verifyDBKeysAvailable() {
            return errorContent
        }

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

        return nil
    }

    public static func verifyDBKeysAvailable() -> UNNotificationContent? {
        guard !StorageCoordinator.hasGrdbFile || !GRDBDatabaseStorageAdapter.isKeyAccessible else { return nil }

        Logger.info("Database password is not accessible, posting generic notification.")

        let content = UNMutableNotificationContent()
        let notificationFormat = NSLocalizedString(
            "NOTIFICATION_BODY_PHONE_LOCKED_FORMAT",
            comment: "Lock screen notification text presented after user powers on their device without unlocking. Embeds {{device model}} (either 'iPad' or 'iPhone')"
        )
        content.body = String(format: notificationFormat, UIDevice.current.localizedModel)
        return content
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
