//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

class NSEEnvironment: Dependencies {
    var processingMessageCounter = AtomicUInt(0)
    var isProcessingMessages: Bool {
        processingMessageCounter.get() > 0
    }

    // MARK: - Main App Comms

    private static var mainAppDarwinQueue: DispatchQueue { .global(qos: .userInitiated) }

    func askMainAppToHandleReceipt(
        logger: NSELogger,
        handledCallback: @escaping (_ mainAppHandledReceipt: Bool) -> Void
    ) {
        Self.mainAppDarwinQueue.async {
            // We track whether we've ever handled the call back to ensure
            // we only notify the caller once and avoid any races that may
            // occur between the notification observer and the dispatch
            // after block.
            let hasCalledBack = AtomicBool(false)

            if DebugFlags.internalLogging {
                logger.info("Requesting main app to handle incoming message.")
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
                    logger.info("Main app ack'd.")
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
                    logger.info("Did timeout.")
                }

                // If we haven't called back yet and removed the observer token,
                // the main app is not running and will not handle receipt of this
                // notification.
                handledCallback(false)
            }
        }
    }

    private var mainAppLaunchObserverToken = DarwinNotificationInvalidObserver
    func listenForMainAppLaunch(logger: NSELogger) {
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
            logger.warn("Main app launched.")
            guard self.isProcessingMessages else { return }
            logger.warn("Exiting because main app launched while we were processing messages.")
            logger.flush()
            exit(0)
        })
    }

    // MARK: - Global state

    private let globalStateLock = UnfairLock()
    private var isGlobalStateConfigured = false

    /// Ensures we have all required global state configured, such as an app
    /// context and logging.
    func ensureGlobalState() {
        globalStateLock.withLock {
            if isGlobalStateConfigured {
                return
            }

            SetCurrentAppContext(NSEContext(), false)

            DebugLogger.shared().enableTTYLogging()
            if OWSPreferences.isLoggingEnabled() || _isDebugAssertConfiguration() {
                DebugLogger.shared().enableFileLogging()
            }

            NSELogger.uncorrelated.info("Logging is now configured and available!", flushImmediately: true)

            isGlobalStateConfigured = true
        }
    }

    // MARK: - Setup

    private var isSetup = AtomicBool(false)

    func setupIfNecessary(logger: NSELogger) -> UNNotificationContent? {
        guard isSetup.tryToSetFlag() else { return nil }
        logger.info("Running NSEEnvironment setup!", flushImmediately: true)
        return DispatchQueue.main.sync { setup(logger: logger) }
    }

    private var areVersionMigrationsComplete = false
    private func setup(logger: NSELogger) -> UNNotificationContent? {
        AssertIsOnMainThread()

        logger.info("NSEEnvironment setup()", flushImmediately: true)

        Cryptography.seedRandom()

        if let errorContent = Self.verifyDBKeysAvailable(logger: logger) {
            return errorContent
        }

        AppSetup.setUpEnvironment(
            paymentsEvents: PaymentsEventsAppExtension(),
            mobileCoinHelper: MobileCoinHelperMinimal(),
            webSocketFactory: WebSocketFactoryNative(),
            extensionSpecificSingletonBlock: {
                SSKEnvironment.shared.callMessageHandlerRef = NSECallMessageHandler()
                SSKEnvironment.shared.notificationsManagerRef = NotificationPresenter()
                Environment.shared.lightweightCallManagerRef = LightweightCallManager()
            }
        ).done(on: DispatchQueue.main) { error in
            if let error {
                // TODO: Maybe notify that you should open the main app.
                return owsFailDebug("Couldn't launch NSE: \(error)")
            }
            self.versionMigrationsDidComplete(logger: logger)
        }

        logger.info("completed.")

        OWSAnalytics.appLaunchDidBegin()

        listenForMainAppLaunch(logger: logger)

        return nil
    }

    public static func verifyDBKeysAvailable(logger: NSELogger) -> UNNotificationContent? {
        guard !StorageCoordinator.hasGrdbFile || !GRDBDatabaseStorageAdapter.isKeyAccessible else { return nil }

        logger.info("Database password is not accessible, posting generic notification.")

        let content = UNMutableNotificationContent()
        let notificationFormat = OWSLocalizedString(
            "NOTIFICATION_BODY_PHONE_LOCKED_FORMAT",
            comment: "Lock screen notification text presented after user powers on their device without unlocking. Embeds {{device model}} (either 'iPad' or 'iPhone')"
        )
        content.body = String(format: notificationFormat, UIDevice.current.localizedModel)
        return content
    }

    private func versionMigrationsDidComplete(logger: NSELogger) {
        AssertIsOnMainThread()

        logger.debug("")

        areVersionMigrationsComplete = true

        checkIsAppReady()
    }

    @objc
    private func checkIsAppReady() {
        AssertIsOnMainThread()

        // Only mark the app as ready once.
        guard !AppReadiness.isAppReady else { return }

        // App isn't ready until all version migrations are complete.
        guard areVersionMigrationsComplete else { return }

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        AppReadiness.setAppIsReady()

        AppVersion.shared.nseLaunchDidComplete()
    }
}
