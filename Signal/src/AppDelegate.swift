//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
enum LaunchFailure: UInt, CustomStringConvertible {
    case none
    case couldNotLoadDatabase
    case unknownDatabaseVersion
    case couldNotRestoreTransferredData
    case databaseCorruptedAndMightBeRecoverable
    case databaseUnrecoverablyCorrupted
    case lastAppLaunchCrashed
    case lowStorageSpaceAvailable

    public var description: String {
        switch self {
        case .none:
            return "LaunchFailure_None"
        case .couldNotLoadDatabase:
            return "LaunchFailure_CouldNotLoadDatabase"
        case .unknownDatabaseVersion:
            return "LaunchFailure_UnknownDatabaseVersion"
        case .couldNotRestoreTransferredData:
            return "LaunchFailure_CouldNotRestoreTransferredData"
        case .databaseCorruptedAndMightBeRecoverable:
            return "LaunchFailure_DatabaseCorruptedAndMightBeRecoverable"
        case .databaseUnrecoverablyCorrupted:
            return "LaunchFailure_DatabaseUnrecoverablyCorrupted"
        case .lastAppLaunchCrashed:
            return "LaunchFailure_LastAppLaunchCrashed"
        case .lowStorageSpaceAvailable:
            return "LaunchFailure_NoDiskSpaceAvailable"
        }
    }
}

extension AppDelegate {
    // MARK: - App launch

    static func setUpMainAppEnvironment() -> Promise<Void> {
        let (promise, future) = Promise<Void>.pending()
        AppSetup.setupEnvironment(
            paymentsEvents: PaymentsEventsMainApp(),
            mobileCoinHelper: MobileCoinHelperSDK(),
            webSocketFactory: WebSocketFactoryHybrid(),
            appSpecificSingletonBlock: {
                SUIEnvironment.shared.setup()
                AppEnvironment.shared.setup()
                SignalApp.shared().setup()
            },
            migrationCompletion: { error in
                if let error = error {
                    future.reject(error)
                } else {
                    future.resolve()
                }
            }
        )
        return promise
    }

    @objc(setUpMainAppEnvironmentWithCompletion:)
    static func setUpMainAppEnvironment(completion: @escaping (Error?) -> Void) {
        firstly(on: .main) {
            setUpMainAppEnvironment()
        }.done(on: .main) {
            completion(nil)
        }.catch(on: .main) { error in
            completion(error)
        }
    }

    func checkSomeDiskSpaceAvailable() -> Bool {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .path
        let succeededCreatingDir = OWSFileSystem.ensureDirectoryExists(tempDir)

        // Best effort at deleting temp dir, which shouldn't ever fail
        if succeededCreatingDir && !OWSFileSystem.deleteFile(tempDir) {
            owsFailDebug("Failed to delete temp dir used for checking disk space!")
        }

        return succeededCreatingDir
    }

    @objc
    func setupNSEInteroperation() {
        Logger.info("")

        // We immediately post a notification letting the NSE know the main app has launched.
        // If it's running it should take this as a sign to terminate so we don't unintentionally
        // try and fetch messages from two processes at once.
        DarwinNotificationCenter.post(.mainAppLaunched)

        // We listen to this notification for the lifetime of the application, so we don't
        // record the returned observer token.
        DarwinNotificationCenter.addObserver(
            for: .nseDidReceiveNotification,
            queue: DispatchQueue.global(qos: .userInitiated)
        ) { token in
            Logger.debug("Handling NSE received notification")

            // Immediately let the NSE know we will handle this notification so that it
            // does not attempt to process messages while we are active.
            DarwinNotificationCenter.post(.mainAppHandledNotification)

            AppReadiness.runNowOrWhenAppDidBecomeReadySync {
                self.messageFetcherJob.run()
            }
        }
    }

    @objc
    func versionMigrationsDidComplete() {
        AssertIsOnMainThread()
        Logger.info("versionMigrationsDidComplete")
        areVersionMigrationsComplete = true
        checkIfAppIsReady()
    }

    @objc
    func checkIfAppIsReady() {
        AssertIsOnMainThread()

        // If launch failed, the app will never be ready.
        guard !didAppLaunchFail else { return }

        // App isn't ready until storage is ready AND all version migrations are complete.
        guard areVersionMigrationsComplete else { return }
        guard storageCoordinator.isStorageReady else { return }

        // Only mark the app as ready once.
        guard !AppReadiness.isAppReady else { return }

        // If launch jobs need to run, return and call checkIfAppIsReady again when they're complete.
        let launchJobsAreComplete = launchJobs.ensureLaunchJobs {
            self.checkIfAppIsReady()
        }
        guard launchJobsAreComplete else { return }

        Logger.info("checkIfAppIsReady")

        // Note that this does much more than set a flag;
        // it will also run all deferred blocks.
        AppReadiness.setAppIsReadyUIStillPending()

        guard !CurrentAppContext().isRunningTests else {
            Logger.verbose("Skipping post-launch logic in tests.")
            AppReadiness.setUIIsReady()
            return
        }

        // If user is missing profile name, redirect to onboarding flow.
        if !SSKEnvironment.shared.profileManager.hasProfileName {
            databaseStorage.write { transaction in
                self.tsAccountManager.setIsOnboarded(false, transaction: transaction)
            }
        }

        if tsAccountManager.isRegistered {
            databaseStorage.read { transaction in
                let localAddress = self.tsAccountManager.localAddress(with: transaction)
                let deviceId = self.tsAccountManager.storedDeviceId(with: transaction)
                let deviceCount = OWSDevice.anyCount(transaction: transaction)
                let linkedDeviceMessage = deviceCount > 1 ? "\(deviceCount) devices including the primary" : "no linked devices"
                Logger.info("localAddress: \(String(describing: localAddress)), deviceId: \(deviceId) (\(linkedDeviceMessage))")
            }

            // This should happen at any launch, background or foreground.
            SyncPushTokensJob.run()
        }

        DebugLogger.shared().postLaunchLogCleanup()
        AppVersion.shared().mainAppLaunchDidComplete()

        Self.updateApplicationShortcutItems(isRegisteredAndReady: tsAccountManager.isRegisteredAndReady)

        if !Environment.shared.preferences.hasGeneratedThumbnails() {
            databaseStorage.asyncRead(
                block: { transaction in
                    TSAttachment.anyEnumerate(transaction: transaction, batched: true) { (_, _) in
                        // no-op. It's sufficient to initWithCoder: each object.
                    }
                },
                completion: {
                    Environment.shared.preferences.setHasGeneratedThumbnails(true)
                }
            )
        }

        SignalApp.shared().ensureRootViewController(launchStartedAt)
    }

    @objc
    func enableBackgroundRefreshIfNecessary() {
        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            let interval: TimeInterval
            if
                OWS2FAManager.shared.isRegistrationLockEnabled,
                self.tsAccountManager.isRegisteredAndReady {
                // Ping server once a day to keep-alive reglock clients.
                interval = 24 * 60 * 60
            } else {
                interval = UIApplication.backgroundFetchIntervalNever
            }
            UIApplication.shared.setMinimumBackgroundFetchInterval(interval)
        }
    }

    // MARK: - Launch failures

    @objc
    func launchFailure(didDeviceTransferRestoreSucceed: Bool) -> LaunchFailure {
        guard checkSomeDiskSpaceAvailable() else {
            return .lowStorageSpaceAvailable
        }

        guard didDeviceTransferRestoreSucceed else {
            return .couldNotRestoreTransferredData
        }

        // Prevent:
        // * Users with an unknown GRDB schema revert to using an earlier GRDB schema.
        guard !StorageCoordinator.hasInvalidDatabaseVersion else {
            return .unknownDatabaseVersion
        }

        let userDefaults = CurrentAppContext().appUserDefaults()

        let databaseCorruptionState = DatabaseCorruptionState(userDefaults: userDefaults)
        switch databaseCorruptionState.status {
        case .notCorrupted:
            break
        case .corrupted, .corruptedButAlreadyDumpedAndRestored:
            guard !UIDevice.current.isIPad else {
                // Database recovery theoretically works on iPad,
                // but we haven't built the UI for it.
                return .databaseUnrecoverablyCorrupted
            }
            guard databaseCorruptionState.count <= 3 else {
                return .databaseUnrecoverablyCorrupted
            }
            return .databaseCorruptedAndMightBeRecoverable
        }

        let appVersion = AppVersion.shared()
        let launchAttemptFailureThreshold = DebugFlags.betaLogging ? 2 : 3
        if
            appVersion.lastAppVersion == appVersion.currentAppReleaseVersion,
            userDefaults.integer(forKey: kAppLaunchesAttemptedKey) >= launchAttemptFailureThreshold
        {
            return .lastAppLaunchCrashed
        }

        return .none
    }

    @objc(showUIForLaunchFailure:)
    func showUI(forLaunchFailure launchFailure: LaunchFailure) {
        Logger.info("launchFailure: \(launchFailure)")

        // Disable normal functioning of app.
        didAppLaunchFail = true

        if launchFailure == .lowStorageSpaceAvailable {
            shouldKillAppWhenBackgrounded = true
        }

        // We perform a subset of the [application:didFinishLaunchingWithOptions:].
        let window: UIWindow
        if let existingWindow = self.window {
            window = existingWindow
        } else {
            window = OWSWindow()
            CurrentAppContext().mainWindow = window
            self.window = window
        }

        // Show the launch screen
        let storyboard = UIStoryboard(name: "Launch Screen", bundle: nil)
        guard let viewController = storyboard.instantiateInitialViewController() else {
            owsFail("No initial view controller")
        }

        window.rootViewController = viewController

        window.makeKeyAndVisible()

        switch launchFailure {
        case .couldNotLoadDatabase, .databaseUnrecoverablyCorrupted:
            presentLaunchFailureActionSheet(
                from: viewController,
                launchFailure: launchFailure,
                title: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_COULD_NOT_LOAD_DATABASE",
                    comment: "Error indicating that the app could not launch because the database could not be loaded."
                ),
                actions: [.submitDebugLogsWithDatabaseIntegrityCheckAndCrash]
            )
        case .unknownDatabaseVersion:
            presentLaunchFailureActionSheet(
                from: viewController,
                launchFailure: launchFailure,
                title: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_TITLE",
                    comment: "Error indicating that the app could not launch without reverting unknown database migrations."
                ),
                message: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_MESSAGE",
                    comment: "Error indicating that the app could not launch without reverting unknown database migrations."
                ),
                actions: [.submitDebugLogs(and: .crash)]
            )
        case .couldNotRestoreTransferredData:
            presentLaunchFailureActionSheet(
                from: viewController,
                launchFailure: launchFailure,
                title: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_RESTORE_FAILED_TITLE",
                    comment: "Error indicating that the app could not restore transferred data."
                ),
                message: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_RESTORE_FAILED_MESSAGE",
                    comment: "Error indicating that the app could not restore transferred data."
                ),
                actions: [.submitDebugLogs(and: .crash)]
            )
        case .databaseCorruptedAndMightBeRecoverable:
            let recoveryViewController = DatabaseRecoveryViewController(
                setupSskEnvironment: { () -> Promise<Void> in
                    firstly(on: .main) {
                        Self.setUpMainAppEnvironment()
                    }.catch(on: .main) { error in
                        owsFailDebug("Error: \(error)")
                        self.showUI(forLaunchFailure: .couldNotLoadDatabase)
                    }
                },
                launchApp: {
                    // Pretend we didn't fail!
                    self.didAppLaunchFail = false
                    self.versionMigrationsDidComplete()
                    self.launchToHomeScreen(launchOptions: nil, instrumentsMonitorId: 0, isEnvironmentAlreadySetUp: true)
                }
            )

            // Prevent dismissal.
            if #available(iOS 13, *) {
                recoveryViewController.isModalInPresentation = true
            } else {
                // This presents it fullscreen. Not ideal, but only affects old iOS versions, and prevents dismissal.
                recoveryViewController.modalPresentationStyle = .fullScreen
            }

            // Show as a half-sheet on iOS 15+. On older versions, the sheet fills the screen, which is okay.
            if
                #available(iOS 15, *),
                let presentationController = recoveryViewController.presentationController as? UISheetPresentationController {
                presentationController.detents = [.medium()]
                presentationController.prefersEdgeAttachedInCompactHeight = true
                presentationController.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            }

            viewController.present(recoveryViewController, animated: true)
        case .lastAppLaunchCrashed:
            presentLaunchFailureActionSheet(
                from: viewController,
                launchFailure: launchFailure,
                title: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_LAST_LAUNCH_CRASHED_TITLE",
                    comment: "Error indicating that the app crashed during the previous launch."
                ),
                message: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_LAST_LAUNCH_CRASHED_MESSAGE",
                    comment: "Error indicating that the app crashed during the previous launch."
                ),
                actions: [.submitDebugLogs(and: .launchApp), .launchApp]
            )
        case .lowStorageSpaceAvailable:
            presentLaunchFailureActionSheet(
                from: viewController,
                launchFailure: launchFailure,
                title: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_LOW_STORAGE_SPACE_AVAILABLE_TITLE",
                    comment: "Error title indicating that the app crashed because there was low storage space available on the device."
                ),
                message: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_LOW_STORAGE_SPACE_AVAILABLE_MESSAGE",
                    comment: "Error description indicating that the app crashed because there was low storage space available on the device."
                ),
                actions: []
            )
        case .none:
            owsFailDebug("Unknown launch failure.")
            presentLaunchFailureActionSheet(
                from: viewController,
                launchFailure: launchFailure,
                title: NSLocalizedString(
                    "APP_LAUNCH_FAILURE_ALERT_TITLE",
                    comment: "Title for the 'app launch failed' alert."
                ),
                actions: [.submitDebugLogs(and: .crash)]
            )
        }
    }

    private enum LaunchFailureActionSheetAction {
        enum ActionAfterSubmittingDebugLogs {
            case crash
            case launchApp
        }

        case submitDebugLogs(and: ActionAfterSubmittingDebugLogs)
        case submitDebugLogsWithDatabaseIntegrityCheckAndCrash
        case launchApp
    }

    private func presentLaunchFailureActionSheet(
        from viewController: UIViewController,
        launchFailure: LaunchFailure,
        title: String,
        message: String = NSLocalizedString(
            "APP_LAUNCH_FAILURE_ALERT_MESSAGE",
            comment: "Default message for the 'app launch failed' alert."
        ),
        actions: [LaunchFailureActionSheetAction]
    ) {
        let actionSheet = ActionSheetController(title: title, message: message)

        if DebugFlags.internalSettings {
            actionSheet.addAction(.init(title: "Export Database (internal)") { _ in
                SignalApp.showExportDatabaseUI(from: viewController) { [weak viewController] in
                    viewController?.presentActionSheet(actionSheet)
                }
            })
        }

        func addSubmitDebugLogsAction(handler: @escaping () -> Void) {
            let actionTitle = NSLocalizedString("SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", comment: "")
            actionSheet.addAction(.init(title: actionTitle) { _ in
                handler()
            })
        }

        lazy var supportTag = String(describing: launchFailure)

        func launchApp() {
            // Pretend we didn't fail!
            self.didAppLaunchFail = false
            self.checkIfAppIsReady()
            self.launchToHomeScreen(launchOptions: nil, instrumentsMonitorId: 0, isEnvironmentAlreadySetUp: false)
        }

        for action in actions {
            switch action {
            case let .submitDebugLogs(actionAfterSubmitting):
                addSubmitDebugLogsAction {
                    Pastelog.submitLogs(withSupportTag: supportTag) {
                        switch actionAfterSubmitting {
                        case .crash:
                            owsFail("Exiting after submitting debug logs")
                        case .launchApp:
                            launchApp()
                        }
                    }
                }
            case .submitDebugLogsWithDatabaseIntegrityCheckAndCrash:
                addSubmitDebugLogsAction {
                    SignalApp.showDatabaseIntegrityCheckUI(from: viewController) {
                        Pastelog.submitLogs(withSupportTag: supportTag) {
                            owsFail("Exiting after submitting debug logs")
                        }
                    }
                }
            case .launchApp:
                // Use a cancel-style button to draw attention.
                let title = NSLocalizedString(
                    "APP_LAUNCH_FAILURE_CONTINUE",
                    comment: "Button to try launching the app even though the last launch failed"
                )
                actionSheet.addAction(.init(title: title, style: .cancel) { _ in
                    launchApp()
                })
            }
        }

        viewController.presentActionSheet(actionSheet)
    }

    // MARK: - Remote notifications

    enum HandleSilentPushContentResult: UInt {
        case handled
        case notHandled
    }

    @objc
    func processRemoteNotification(_ remoteNotification: NSDictionary) {
        processRemoteNotification(remoteNotification) {}
    }

    @objc
    func processRemoteNotification(_ remoteNotification: NSDictionary, completion: @escaping () -> Void) {
        AssertIsOnMainThread()

        guard !didAppLaunchFail else {
            owsFailDebug("app launch failed")
            return
        }

        guard AppReadiness.isAppReady, tsAccountManager.isRegisteredAndReady else {
            Logger.info("Ignoring remote notification; app is not ready.")
            return
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            // TODO: NSE Lifecycle, is this invoked when the NSE wakes the main app?
            if
                let remoteNotification = remoteNotification as? [AnyHashable: Any],
                self.handleSilentPushContent(remoteNotification) == .notHandled {
                self.messageFetcherJob.run()
            }

            completion()
        }
    }

    func handleSilentPushContent(_ remoteNotification: [AnyHashable: Any]) -> HandleSilentPushContentResult {
        if let spamChallengeToken = remoteNotification["rateLimitChallenge"] as? String {
            spamChallengeResolver.handleIncomingPushChallengeToken(spamChallengeToken)
            return .handled
        }

        if let preAuthChallengeToken = remoteNotification["challenge"] as? String {
            pushRegistrationManager.didReceiveVanillaPreAuthChallengeToken(preAuthChallengeToken)
            return .handled
        }

        return .notHandled
    }

    // MARK: - Events

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        Logger.info("registrationStateDidChange")

        enableBackgroundRefreshIfNecessary()

        let isRegisteredAndReady = tsAccountManager.isRegisteredAndReady
        if isRegisteredAndReady {
            AppReadiness.runNowOrWhenAppDidBecomeReadySync {
                self.databaseStorage.write { transaction in
                    let localAddress = self.tsAccountManager.localAddress(with: transaction)
                    Logger.info("localAddress: \(String(describing: localAddress))")

                    ExperienceUpgradeFinder.markAllCompleteForNewUser(transaction: transaction.unwrapGrdbWrite)
                }

                // Start running the disappearing messages job in case the newly registered user
                // enables this feature
                self.disappearingMessagesJob.startIfNecessary()
            }
        }

        Self.updateApplicationShortcutItems(isRegisteredAndReady: isRegisteredAndReady)
    }

    // MARK: - Utilities

    @objc
    public static func updateApplicationShortcutItems(isRegisteredAndReady: Bool) {
        guard CurrentAppContext().isMainApp else { return }
        UIApplication.shared.shortcutItems = applicationShortcutItems(isRegisteredAndReady: isRegisteredAndReady)
    }

    static func applicationShortcutItems(isRegisteredAndReady: Bool) -> [UIApplicationShortcutItem] {
        guard isRegisteredAndReady else { return [] }
        return [.init(
            type: "\(Bundle.main.bundleIdPrefix).quickCompose",
            localizedTitle: NSLocalizedString(
                "APPLICATION_SHORTCUT_NEW_MESSAGE",
                value: "New Message",
                comment: "On the iOS home screen, if you tap and hold the Signal icon, this shortcut will appear. Tapping it will let users send a new message. You may want to refer to similar behavior in other iOS apps, such as Messages, for equivalent strings."
            ),
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(type: .compose)
        )]
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // The method will be called on the delegate only if the application is in the foreground. If the method is not
    // implemented or the handler is not called in a timely manner then the notification will not be presented. The
    // application can choose to have the notification presented as a sound, badge, alert and/or in the notification list.
    // This decision should be based on whether the information in the notification is otherwise visible to the user.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Logger.info("")

        // Capture just userInfo; we don't want to retain notification.
        let remoteNotification = notification.request.content.userInfo
        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            let options: UNNotificationPresentationOptions
            switch self.handleSilentPushContent(remoteNotification) {
            case .handled:
                options = []
            case .notHandled:
                // We need to respect the in-app notification sound preference. This method, which is called
                // for modern UNUserNotification users, could be a place to do that, but since we'd still
                // need to handle this behavior for legacy UINotification users anyway, we "allow" all
                // notification options here, and rely on the shared logic in NotificationPresenter to
                // honor notification sound preferences for both modern and legacy users.
                options = [.alert, .badge, .sound]
            }
            completionHandler(options)
        }
    }

    // The method will be called on the delegate when the user responded to the notification by opening the application,
    // dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application
    // returns from application:didFinishLaunchingWithOptions:.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Logger.info("")
        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            NotificationActionHandler.handleNotificationResponse(response, completionHandler: completionHandler)
        }
    }
}
