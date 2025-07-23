//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import GRDB
import Intents
import SignalServiceKit
import SignalUI
import UIKit
import WebRTC

enum LaunchPreflightError {
    case unknownDatabaseVersion
    case couldNotRestoreTransferredData
    case databaseCorruptedAndMightBeRecoverable
    case databaseUnrecoverablyCorrupted
    case lastAppLaunchCrashed
    case incrementalTSAttachmentMigrationFailed
    case lowStorageSpaceAvailable
    case possibleReadCorruptionCrashed

    var supportTag: String {
        switch self {
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
        case .incrementalTSAttachmentMigrationFailed:
            return "LaunchFailure_incrementalTSAttachmentMigrationFailed"
        case .lowStorageSpaceAvailable:
            return "LaunchFailure_NoDiskSpaceAvailable"
        case .possibleReadCorruptionCrashed:
            return "LaunchFailure_PossibleReadCorruption"
        }
    }
}

private func uncaughtExceptionHandler(_ exception: NSException) {
    if DebugFlags.internalLogging {
        Logger.error("exception: \(exception)")
        Logger.error("name: \(exception.name)")
        Logger.error("reason: \(String(describing: exception.reason))")
        Logger.error("userInfo: \(String(describing: exception.userInfo))")
    } else {
        let reason = exception.reason ?? ""
        let reasonData = Data(reason.utf8)
        let reasonHash = Data(SHA256.hash(data: reasonData)).base64EncodedString()

        var truncatedReason = reason.prefix(20)
        if let spaceIndex = truncatedReason.lastIndex(of: " ") {
            truncatedReason = truncatedReason[..<spaceIndex]
        }
        let maybeEllipsis = (truncatedReason.endIndex < reason.endIndex) ? "..." : ""
        Logger.error("\(exception.name): \(truncatedReason)\(maybeEllipsis) (hash: \(reasonHash))")
    }
    Logger.error("callStackSymbols: \(exception.callStackSymbols.joined(separator: "\n"))")
    Logger.flush()
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: - Constants

    private enum Constants {
        static let appLaunchesAttemptedKey = "AppLaunchesAttempted"
    }

    // MARK: - Lifecycle

    func applicationWillEnterForeground(_ application: UIApplication) {
        Logger.info("")
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AssertIsOnMainThread()
        if CurrentAppContext().isRunningTests {
            return
        }

        Logger.warn("")

        if didAppLaunchFail {
            return
        }

        appReadiness.runNowOrWhenAppDidBecomeReadySync { self.handleActivation() }

        // Clear all notifications whenever we become active.
        // When opening the app from a notification,
        // AppDelegate.didReceiveLocalNotification will always
        // be called _before_ we become active.
        clearAppropriateNotificationsAndRestoreBadgeCount()

        // On every activation, clear old temp directories.
        ClearOldTemporaryDirectories()

        // Ensure that all windows have the correct frame.
        AppEnvironment.shared.windowManagerRef.updateWindowFrames()
    }

    private let flushQueue = DispatchQueue(label: "org.signal.flush", qos: .utility)

    func applicationWillResignActive(_ application: UIApplication) {
        AssertIsOnMainThread()

        Logger.warn("")

        if didAppLaunchFail {
            return
        }

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.refreshConnection(isAppActive: false)
        }

        clearAppropriateNotificationsAndRestoreBadgeCount()

        let backgroundTask = OWSBackgroundTask(label: #function)
        flushQueue.async {
            defer { backgroundTask.end() }
            Logger.flush()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.info("")

        if shouldKillAppWhenBackgrounded {
            Logger.flush()
            exit(0)
        }
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Logger.info("")
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Logger.info("")
        Logger.flush()
    }

    // MARK: - App Launch

    private lazy var appReadiness = AppReadinessImpl()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let launchStartedAt = CACurrentMediaTime()

        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler(_:))

        // This should be the first thing we do.
        let mainAppContext = MainAppContext()
        SetCurrentAppContext(mainAppContext, isRunningTests: false)

        let debugLogger = DebugLogger.shared
        debugLogger.enableTTYLoggingIfNeeded()
        DebugLogger.registerLibsignal()
        DebugLogger.registerRingRTC()

        if mainAppContext.isRunningTests {
            _ = initializeWindow(mainAppContext: mainAppContext, rootViewController: UIViewController())
            return true
        }

        debugLogger.enableFileLogging(appContext: mainAppContext, canLaunchInBackground: true)
        DebugLogger.configureSwiftLogging()
        if DebugFlags.audibleErrorLogging {
            debugLogger.enableErrorReporting()
        }

        Logger.warn("Launching…")
        defer { Logger.info("Launched.") }

        BenchEventStart(title: "Presenting HomeView", eventId: "AppStart", logInProduction: true)
        appReadiness.runNowOrWhenUIDidBecomeReadySync { BenchEventComplete(eventId: "AppStart") }

        MessageFetchBGRefreshTask.register(appReadiness: appReadiness)

        let deviceBatteryLevelManager = DeviceBatteryLevelManagerImpl()
        let deviceSleepManager = DeviceSleepManagerImpl()
        let keychainStorage = KeychainStorageImpl(isUsingProductionService: TSConstants.isUsingProductionService)
        let deviceTransferService = DeviceTransferService(
            appReadiness: appReadiness,
            deviceSleepManager: deviceSleepManager,
            keychainStorage: keychainStorage
        )

        AppEnvironment.setSharedEnvironment(AppEnvironment(
            appReadiness: appReadiness,
            deviceTransferService: deviceTransferService
        ))

        // This *must* happen before we try and access or verify the database,
        // since we may be in a state where the database has been partially
        // restored from transfer (e.g. the key was replaced, but the database
        // files haven't been moved into place)
        let didDeviceTransferRestoreSucceed = Bench(
            title: "Slow device transfer service launch",
            logIfLongerThan: 0.01,
            logInProduction: true,
            block: { deviceTransferService.launchCleanup() }
        )

        let databaseStorage: SDSDatabaseStorage
        do {
            databaseStorage = try SDSDatabaseStorage(
                appReadiness: appReadiness,
                databaseFileUrl: SDSDatabaseStorage.grdbDatabaseFileUrl,
                keychainStorage: keychainStorage
            )
        } catch KeychainError.notAllowed where application.applicationState == .background {
            notifyThatPhoneMustBeUnlocked()
        } catch {
            // It's so corrupt that we can't even try to repair it.
            didAppLaunchFail = true
            Logger.error("Couldn't launch with broken database: \(error.grdbErrorForLogging)")
            let viewController = terminalErrorViewController()
            _ = initializeWindow(mainAppContext: mainAppContext, rootViewController: viewController)
            presentDatabaseUnrecoverablyCorruptedError(from: viewController, action: .submitDebugLogsAndCrash)
            return true
        }

        // This must happen in appDidFinishLaunching or earlier to ensure we don't
        // miss notifications. Setting the delegate also seems to prevent us from
        // getting the legacy notification notification callbacks upon launch e.g.
        // 'didReceiveLocalNotification'
        UNUserNotificationCenter.current().delegate = self

        // If there's a notification, queue it up for processing. (This processing
        // may happen immediately, after a short delay, or never.)
        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Logger.info("Application was launched by tapping a push notification.")
            Task {
                try await processRemoteNotification(remoteNotification)
            }
        }

        // Do this even if `appVersion` isn't used -- there's side effects.
        let appVersion = AppVersionImpl.shared

        // Set up and register incremental migration for TSAttachment -> v2 Attachment.
        // TODO: remove this (and the incremental migrator itself) once we make this
        // migration a launch-blocking GRDB migration.
        let incrementalMessageTSAttachmentMigrationStore = IncrementalTSAttachmentMigrationStore(
            userDefaults: mainAppContext.appUserDefaults()
        )
        let incrementalMessageTSAttachmentMigratorFactory = IncrementalMessageTSAttachmentMigratorFactoryImpl(
            store: incrementalMessageTSAttachmentMigrationStore
        )

        let launchContext = LaunchContext(
            appContext: mainAppContext,
            databaseStorage: databaseStorage,
            deviceBatteryLevelManager: deviceBatteryLevelManager,
            deviceSleepManager: deviceSleepManager,
            keychainStorage: keychainStorage,
            launchStartedAt: launchStartedAt,
            incrementalMessageTSAttachmentMigrationStore: incrementalMessageTSAttachmentMigrationStore,
            incrementalMessageTSAttachmentMigratorFactory: incrementalMessageTSAttachmentMigratorFactory
        )

        // We need to do this _after_ we set up logging, when the keychain is unlocked,
        // but before we access the database or files on disk.
        let preflightError = checkIfAllowedToLaunch(
            mainAppContext: mainAppContext,
            appVersion: appVersion,
            incrementalTSAttachmentMigrationStore: incrementalMessageTSAttachmentMigrationStore,
            didDeviceTransferRestoreSucceed: didDeviceTransferRestoreSucceed
        )

        if let preflightError {
            didAppLaunchFail = true
            let viewController = terminalErrorViewController()
            let window = initializeWindow(mainAppContext: mainAppContext, rootViewController: viewController)
            showPreflightErrorUI(
                preflightError,
                launchContext: launchContext,
                window: window,
                viewController: viewController
            )
            return true
        }

        // If this is a regular launch, increment the "launches attempted" counter.
        // If repeatedly start launching but never finish them (ie the app is
        // crashing while launching), we'll notice in `checkIfAllowedToLaunch`.
        let userDefaults = mainAppContext.appUserDefaults()
        let appLaunchesAttempted = userDefaults.integer(forKey: Constants.appLaunchesAttemptedKey)
        userDefaults.set(appLaunchesAttempted + 1, forKey: Constants.appLaunchesAttemptedKey)

        // We _must_ register BGProcessingTask handlers synchronously in didFinishLaunching.
        // https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)
        // WARNING: Apple docs say we can only have 10 BGProcessingTasks registered.
        let attachmentMigrationRunner = IncrementalMessageTSAttachmentMigrationRunner(
            appContext: mainAppContext,
            db: databaseStorage,
            store: incrementalMessageTSAttachmentMigrationStore,
            migrator: { DependenciesBridge.shared.incrementalMessageTSAttachmentMigrator }
        )
        attachmentMigrationRunner.registerBGProcessingTask(appReadiness: appReadiness)

        let attachmentBackfillStore = AttachmentValidationBackfillStore()
        let attachmentValidationRunner = AttachmentValidationBackfillRunner(
            db: databaseStorage,
            store: attachmentBackfillStore,
            migrator: { DependenciesBridge.shared.attachmentValidationBackfillMigrator }
        )
        attachmentValidationRunner.registerBGProcessingTask(appReadiness: appReadiness)

        let backupSettingsStore = BackupSettingsStore()
        let backupRunner = BackupBGProcessingTaskRunner(
            backupSettingsStore: backupSettingsStore,
            db: databaseStorage,
            exportJob: { DependenciesBridge.shared.backupExportJob }
        )
        backupRunner.registerBGProcessingTask(appReadiness: appReadiness)

        let databaseMigratorRunner = LazyDatabaseMigratorRunner(
            backgroundMessageFetcherFactory: { DependenciesBridge.shared.backgroundMessageFetcherFactory },
            databaseStorage: databaseStorage,
            remoteConfigManager: { SSKEnvironment.shared.remoteConfigManagerRef },
            tsAccountManager: { DependenciesBridge.shared.tsAccountManager }
        )
        databaseMigratorRunner.registerBGProcessingTask(appReadiness: appReadiness)

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            if SSKEnvironment.shared.remoteConfigManagerRef.currentConfig().shouldRunTSAttachmentMigrationInBGProcessingTask {
                attachmentMigrationRunner.scheduleBGProcessingTaskIfNeeded()
            }
            attachmentValidationRunner.scheduleBGProcessingTaskIfNeeded()
            backupRunner.scheduleBGProcessingTaskIfNeeded()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task {
                databaseMigratorRunner.scheduleBGProcessingTaskIfNeeded()

                #if targetEnvironment(simulator)
                // The simulator won't run BGProcessingTasks, but we still want to run
                // these migrations for simulators. So, if they're needed, run them.
                //
                // In production, users might interrupt these migrations, and that might
                // mean they `run()` multiple times (even after they've all finished). To
                // add coverage for these rare scenarios, run them redundantly, sometimes.
                //
                // Lastly, these are one-off migrations, and most test devices will run
                // them immediately and never again, so running them redundantly will help
                // provide coverage for otherwise dead code.
                if databaseMigratorRunner.startCondition() != .never || databaseMigratorRunner.simulatePriorCancellation() {
                    try await databaseMigratorRunner.run()
                }
                #endif
            }
        }

        // Show LoadingViewController until the database migrations are complete.
        let loadingViewController = LoadingViewController()

        let window = initializeWindow(mainAppContext: mainAppContext, rootViewController: loadingViewController)
        self.launchApp(in: window, launchContext: launchContext, loadingViewController: loadingViewController)
        return true
    }

    var window: UIWindow?

    private func initializeWindow(mainAppContext: MainAppContext, rootViewController: UIViewController) -> UIWindow {
        let window = OWSWindow()
        self.window = window
        mainAppContext.mainWindow = window
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        return window
    }

    private struct LaunchContext {
        var appContext: MainAppContext
        var databaseStorage: SDSDatabaseStorage
        var deviceBatteryLevelManager: DeviceBatteryLevelManagerImpl
        var deviceSleepManager: DeviceSleepManagerImpl
        var keychainStorage: any KeychainStorage
        var launchStartedAt: CFTimeInterval
        var incrementalMessageTSAttachmentMigrationStore: IncrementalTSAttachmentMigrationStore
        var incrementalMessageTSAttachmentMigratorFactory: IncrementalMessageTSAttachmentMigratorFactory
    }

    private func launchApp(
        in window: UIWindow,
        launchContext: LaunchContext,
        loadingViewController: LoadingViewController
    ) {
        assert(window.rootViewController == loadingViewController)
        configureGlobalUI(in: window)
        Task {
            let (finalContinuation, sleepBlockObject) = await setUpMainAppEnvironment(launchContext: launchContext, loadingViewController: loadingViewController)
            self.didLoadDatabase(finalContinuation: finalContinuation, launchContext: launchContext, sleepBlockObject: sleepBlockObject, window: window)
        }
    }

    private lazy var screenLockUI = ScreenLockUI(appReadiness: appReadiness)

    private func configureGlobalUI(in window: UIWindow) {
        Theme.setupSignalAppearance()

        screenLockUI.setupWithRootWindow(window)
        AppEnvironment.shared.windowManagerRef.setupWithRootWindow(window, screenBlockingWindow: screenLockUI.screenBlockingWindow)
        screenLockUI.startObserving()
    }

    private func setUpMainAppEnvironment(
        launchContext: LaunchContext,
        loadingViewController: LoadingViewController?
    ) async -> (AppSetup.FinalContinuation, DeviceSleepBlockObject) {
        let sleepBlockObject = DeviceSleepBlockObject(blockReason: "app launch")
        launchContext.deviceSleepManager.addBlock(blockObject: sleepBlockObject)

        let _currentCall = AtomicValue<SignalCall?>(nil, lock: .init())
        let currentCall = CurrentCall(rawValue: _currentCall)

        let databaseContinuation = AppSetup().start(
            appContext: launchContext.appContext,
            appReadiness: appReadiness,
            backupArchiveErrorPresenterFactory: BackupArchiveErrorPresenterFactoryInternal(),
            databaseStorage: launchContext.databaseStorage,
            deviceBatteryLevelManager: launchContext.deviceBatteryLevelManager,
            deviceSleepManager: launchContext.deviceSleepManager,
            paymentsEvents: PaymentsEventsMainApp(),
            mobileCoinHelper: MobileCoinHelperSDK(),
            callMessageHandler: WebRTCCallMessageHandler(),
            currentCallProvider: currentCall,
            notificationPresenter: NotificationPresenterImpl(),
            incrementalMessageTSAttachmentMigratorFactory: launchContext.incrementalMessageTSAttachmentMigratorFactory
        )
        setupNSEInteroperation()
        SUIEnvironment.shared.setUp(
            appReadiness: appReadiness,
            authCredentialManager: databaseContinuation.authCredentialManager
        )
        AppEnvironment.shared.setUp(
            appReadiness: appReadiness,
            callService: CallService(
                appContext: launchContext.appContext,
                appReadiness: appReadiness,
                authCredentialManager: databaseContinuation.authCredentialManager,
                callLinkPublicParams: databaseContinuation.callLinkPublicParams,
                callLinkStore: DependenciesBridge.shared.callLinkStore,
                callRecordDeleteManager: DependenciesBridge.shared.callRecordDeleteManager,
                callRecordStore: DependenciesBridge.shared.callRecordStore,
                db: DependenciesBridge.shared.db,
                deviceSleepManager: launchContext.deviceSleepManager,
                mutableCurrentCall: _currentCall,
                networkManager: SSKEnvironment.shared.networkManagerRef,
                tsAccountManager: DependenciesBridge.shared.tsAccountManager
            )
        )
        let continuation = await databaseContinuation.prepareDatabase()
        continuation.runLaunchTasksIfNeededAndReloadCaches()
        guard FeatureFlags.runTSAttachmentMigrationBlockingOnLaunch else {
            return (continuation, sleepBlockObject)
        }

        let progressSink = OWSProgress.createSink { [weak loadingViewController] progress in
            await MainActor.run {
                loadingViewController?.updateProgress(progress)
            }
        }
        let migrateTask = Task {
            _ = await continuation.dependenciesBridge.incrementalMessageTSAttachmentMigrator
                .runInMainAppUntilFinished(ignorePastFailures: false, progress: progressSink)
        }
        Task {
            loadingViewController?.setCancellableTask(migrateTask)
        }
        await migrateTask.value
        return (continuation, sleepBlockObject)
    }

    private func checkEnoughDiskSpaceAvailable() -> Bool {
        guard let freeSpaceInBytes = try? OWSFileSystem.freeSpaceInBytes(
            forPath: SDSDatabaseStorage.grdbDatabaseFileUrl
        ) else {
            owsFailDebug("Failed to get free space: falling back to trying to create a temp dir.")

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

        // Require 100MB free in order to launch.
        return freeSpaceInBytes >= 100_000_000
    }

    private func setupNSEInteroperation() {
        // We immediately post a notification letting the NSE know the main app has launched.
        // If it's running it should take this as a sign to terminate so we don't unintentionally
        // try and fetch messages from two processes at once.
        DarwinNotificationCenter.postNotification(name: .mainAppLaunched)

        let appReadiness: AppReadiness = self.appReadiness

        // We listen to this notification for the lifetime of the application, so we don't
        // record the returned observer token.
        _ = DarwinNotificationCenter.addObserver(
            name: .nseDidReceiveNotification,
            queue: DispatchQueue.global(qos: .userInitiated)
        ) { token in
            appReadiness.runNowOrWhenAppDidBecomeReadySync {
                DispatchQueue.global(qos: .userInitiated).async {
                    let chatConnectionManager = DependenciesBridge.shared.chatConnectionManager
                    if chatConnectionManager.shouldSocketBeOpen_restOnly(connectionType: .identified) {
                        // Immediately let the NSE know we will handle this notification so that it
                        // does not attempt to process messages while we are active.
                        DarwinNotificationCenter.postNotification(name: .mainAppHandledNotification)
                    }
                }
            }
        }
    }

    private func didLoadDatabase(
        finalContinuation: AppSetup.FinalContinuation,
        launchContext: LaunchContext,
        sleepBlockObject: DeviceSleepBlockObject,
        window: UIWindow
    ) {
        AssertIsOnMainThread()

        // First thing; clean up any transfer state in case we are launching after a transfer.
        // This needs to happen before we check any registration state.
        DependenciesBridge.shared.registrationStateChangeManager.cleanUpTransferStateOnAppLaunchIfNeeded()

        let regLoader = RegistrationCoordinatorLoaderImpl(dependencies: .from(self))

        // Before we mark ready, block message processing on any pending change numbers.
        let hasPendingChangeNumber = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            regLoader.hasPendingChangeNumber(transaction: transaction)
        }
        if hasPendingChangeNumber {
            // The registration loader will clear the suspension later on.
            SSKEnvironment.shared.messagePipelineSupervisorRef.suspendMessageProcessingWithoutHandle(for: .pendingChangeNumber)
        }

        let launchInterface = buildLaunchInterface(regLoader: regLoader)

        let hasInProgressRegistration: Bool
        switch launchInterface {
        case .registration, .secondaryProvisioning:
            hasInProgressRegistration = true
        case .chatList:
            hasInProgressRegistration = false
        }

        switch finalContinuation.setUpLocalIdentifiers(
            willResumeInProgressRegistration: hasInProgressRegistration,
            canInitiateRegistration: true
        ) {
        case .corruptRegistrationState:
            let viewController = terminalErrorViewController()
            window.rootViewController = viewController
            presentLaunchFailureActionSheet(
                from: viewController,
                supportTag: "CorruptRegistrationState",
                logDumper: .fromGlobals(),
                title: OWSLocalizedString(
                    "APP_LAUNCH_FAILURE_CORRUPT_REGISTRATION_TITLE",
                    comment: "Title for an error indicating that the app couldn't launch because some unexpected error happened with the user's registration status."
                ),
                message: OWSLocalizedString(
                    "APP_LAUNCH_FAILURE_CORRUPT_REGISTRATION_MESSAGE",
                    comment: "Message for an error indicating that the app couldn't launch because some unexpected error happened with the user's registration status."
                ),
                actions: [.submitDebugLogsAndCrash]
            )
        case nil:
            let backgroundTask = OWSBackgroundTask(label: #function)
            Task { @MainActor in
                defer { backgroundTask.end() }
                if !hasInProgressRegistration {
                    await LaunchJobs.run(databaseStorage: SSKEnvironment.shared.databaseStorageRef)
                }
                DispatchQueue.main.async {
                    self.setAppIsReady(
                        launchInterface: launchInterface,
                        launchContext: launchContext
                    )
                    finalContinuation.dependenciesBridge.deviceSleepManager?.removeBlock(blockObject: sleepBlockObject)
                }
            }
        }
    }

    @MainActor
    private func setAppIsReady(
        launchInterface: LaunchInterface,
        launchContext: LaunchContext
    ) {
        owsPrecondition(!appReadiness.isAppReady)
        owsPrecondition(!CurrentAppContext().isRunningTests)

        let appContext = launchContext.appContext

        SignalApp.shared.performInitialSetup(appReadiness: appReadiness)

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            // This runs every 24 hours or so.
            let messageSendLog = SSKEnvironment.shared.messageSendLogRef
            messageSendLog.cleanUpAndScheduleNextOccurrence()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            OWSOrphanDataCleaner.auditOnLaunchIfNecessary()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task.detached(priority: .low) {
                await FullTextSearchOptimizer(
                    appContext: appContext,
                    db: DependenciesBridge.shared.db
                ).run()
            }
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task.detached(priority: .low) {
                await AuthorMergeHelperBuilder(
                    appContext: appContext,
                    authorMergeHelper: DependenciesBridge.shared.authorMergeHelper,
                    db: DependenciesBridge.shared.db,
                    modelReadCaches: AuthorMergeHelperBuilder.Wrappers.ModelReadCaches(SSKEnvironment.shared.modelReadCachesRef),
                    recipientDatabaseTable: DependenciesBridge.shared.recipientDatabaseTable
                ).buildTableIfNeeded()
            }
        }

        // Disable phone number sharing when rolling out PNP.
        //
        // TODO: Remove this once all builds are PNP-enabled.
        //
        // Once all builds are PNP enabled, we can remove this explicit migration
        // and simply treat the default as "nobody". The migration exists to ensure
        // old linked devices respect the setting before they upgrade.
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            let db = DependenciesBridge.shared.db
            guard db.read(block: SSKEnvironment.shared.udManagerRef.phoneNumberSharingMode(tx:)) == nil else {
                return
            }
            db.write { tx in
                guard SSKEnvironment.shared.udManagerRef.phoneNumberSharingMode(tx: tx) == nil else {
                    return
                }
                SSKEnvironment.shared.udManagerRef.setPhoneNumberSharingMode(
                    .nobody,
                    updateStorageServiceAndProfile: true,
                    tx: SDSDB.shimOnlyBridge(tx)
                )
            }
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            StaleProfileFetcher(
                db: DependenciesBridge.shared.db,
                profileFetcher: SSKEnvironment.shared.profileFetcherRef,
                tsAccountManager: DependenciesBridge.shared.tsAccountManager
            ).scheduleProfileFetches()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task.detached(priority: .low) {
                YDBStorage.deleteYDBStorage()
                SSKPreferences.clearLegacyDatabaseFlags(from: appContext.appUserDefaults())
                try? launchContext.keychainStorage.removeValue(service: "TSKeyChainService", key: "TSDatabasePass")
                try? launchContext.keychainStorage.removeValue(service: "TSKeyChainService", key: "OWSDatabaseCipherKeySpec")
            }
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Task {
                try? await RemoteMegaphoneFetcher(
                    databaseStorage: SSKEnvironment.shared.databaseStorageRef,
                    signalService: SSKEnvironment.shared.signalServiceRef
                ).syncRemoteMegaphonesIfNecessary()
            }
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            DependenciesBridge.shared.orphanedAttachmentCleaner.beginObserving()
        }

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            AttachmentDownloadRetryRunner.shared.beginObserving()
        }

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            let fetchJobRunner = CallLinkFetchJobRunner(
                callLinkStore: DependenciesBridge.shared.callLinkStore,
                callLinkStateUpdater: AppEnvironment.shared.callService.callLinkStateUpdater,
                db: DependenciesBridge.shared.db
            )
            fetchJobRunner.observeDatabase(DependenciesBridge.shared.databaseChangeObserver)
            fetchJobRunner.setMightHavePendingFetchAndFetch()
            AppEnvironment.shared.ownedObjects.append(fetchJobRunner)
        }

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            ViewOnceMessages.startExpiringWhenNecessary()
        }

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        appReadiness.setAppIsReadyUIStillPending()

        appContext.appUserDefaults().removeObject(forKey: Constants.appLaunchesAttemptedKey)

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        let tsRegistrationState: TSRegistrationState = SSKEnvironment.shared.databaseStorageRef.read { tx in
            let registrationState = tsAccountManager.registrationState(tx: tx)
            if registrationState.isRegistered, let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) {
                let deviceId = tsAccountManager.storedDeviceId(tx: tx)
                let localRecipient = recipientDatabaseTable.fetchRecipient(serviceId: localIdentifiers.aci, transaction: tx)
                let deviceCount = localRecipient?.deviceIds.count ?? 0
                let linkedDeviceMessage = deviceCount > 1 ? "\(deviceCount) devices including the primary" : "no linked devices"
                Logger.info("localAci: \(localIdentifiers.aci), deviceId: \(deviceId) (\(linkedDeviceMessage))")
            }
            return registrationState
        }

        // Fetch messages as soon as possible after launching. In particular, when
        // launching from the background, without this, we end up waiting some extra
        // seconds before receiving an actionable push notification.
        if !appContext.isMainAppAndActive {
            self.refreshConnection(isAppActive: false)
        }

        if tsRegistrationState.isRegistered {
            // This should happen at any launch, background or foreground.
            SyncPushTokensJob.run()
        }

        if tsRegistrationState.isRegistered {
            Task {
                do {
                    try await APNSRotationStore.rotateIfNeededOnAppLaunchAndReadiness(
                        waitForFetchingAndProcessing: { () async throws(CancellationError) -> Void in
                            try await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing()
                        },
                        performRotation: {
                            try await SyncPushTokensJob(mode: .rotateIfEligible).run()
                        }
                    )
                } catch {
                    Logger.warn("\(error)")
                }
            }
        }

        if tsRegistrationState.isRegistered {
            Task {
                do {
                    _ = try await SSKEnvironment.shared.profileManagerRef.fetchLocalUsersProfile(authedAccount: .implicit())
                    // Don't remove this -- fetching the local user's profile is special-cased
                    // and won't download the avatar via the normal mechanism.
                    try await SSKEnvironment.shared.profileManagerRef.downloadAndDecryptLocalUserAvatarIfNeeded(
                        authedAccount: .implicit()
                    )
                } catch {
                    Logger.warn("Couldn't fetch local user profile or avatar: \(error)")
                }
            }
        }

        DebugLogger.shared.postLaunchLogCleanup(appContext: appContext)
        AppVersionImpl.shared.mainAppLaunchDidComplete()

        scheduleBgAppRefresh()
        Self.updateApplicationShortcutItems(isRegistered: tsRegistrationState.isRegistered)

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil
        )

        checkDatabaseIntegrityIfNecessary(isRegistered: tsRegistrationState.isRegistered)

        SignalApp.shared.showLaunchInterface(
            launchInterface,
            appReadiness: appReadiness,
            launchStartedAt: launchContext.launchStartedAt
        )
    }

    private func scheduleBgAppRefresh() {
        MessageFetchBGRefreshTask.getShared(appReadiness: appReadiness)?.scheduleTask()
    }

    /// The user must unlock the device once after reboot before the database encryption key can be accessed.
    private func notifyThatPhoneMustBeUnlocked() -> Never {
        Logger.warn("Exiting because we are in the background and the database password is not accessible.")

        let notificationContent = UNMutableNotificationContent()
        notificationContent.body = String(
            format: OWSLocalizedString(
                "NOTIFICATION_BODY_PHONE_LOCKED_FORMAT",
                comment: "Lock screen notification text presented after user powers on their device without unlocking. Embeds {{device model}} (either 'iPad' or 'iPhone')"
            ),
            UIDevice.current.localizedModel
        )

        let notificationRequest = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notificationContent,
            trigger: nil
        )

        let application: UIApplication = .shared
        let userNotificationCenter: UNUserNotificationCenter = .current()

        NotificationPresenterImpl.clearAllNotificationsExceptNewLinkedDevices()
        application.applicationIconBadgeNumber = 0

        userNotificationCenter.add(notificationRequest)
        application.applicationIconBadgeNumber = 1

        // Wait a few seconds for XPC calls to finish and for rate limiting purposes.
        Thread.sleep(forTimeInterval: 3)
        Logger.flush()
        exit(0)
    }

    // MARK: - Registration

    private func buildLaunchInterface(regLoader: RegistrationCoordinatorLoader) -> LaunchInterface {
        let (
            tsRegistrationState,
            lastMode
        ) = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return (
                DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx),
                regLoader.restoreLastMode(transaction: tx)
            )
        }

        if let lastMode {
            Logger.info("Found ongoing registration; continuing")
            return .registration(regLoader, lastMode)
        }
        switch tsRegistrationState {
        case .registered, .provisioned:
            // We're already registered.
            return .chatList

        case .reregistering(let reregNumber, let reregAci):
            if let reregE164 = E164(reregNumber), let reregAci {
                Logger.info("Found legacy re-registration; continuing in new registration")
                // A user who started re-registration before the new
                // registration flow shipped; kick them to new re-reg.
                return .registration(regLoader, .reRegistering(.init(e164: reregE164, aci: reregAci)))
            } else {
                // If we're missing the e164 or aci, drop into normal reg.
                Logger.info("Found legacy initial registration; continuing in new registration")
                return .registration(regLoader, .registering)
            }

        case .relinking:
            return .secondaryProvisioning

        case .deregistered:
            // If we are deregistered, go to the chat list in the deregistered state.
            // The user can kick of re-registration from there, which will set the
            // 'lastMode' var and short circuit before we get here next time around.
            return .chatList

        case .delinked:
            // If we are delinked, go to the chat list in the delinked state.
            // The user can kick of re-linking from there.
            return .chatList

        case
                .transferringIncoming,
                .transferringPrimaryOutgoing,
                .transferringLinkedOutgoing,
                .transferred:
            fallthrough

        case .unregistered:
            if UIDevice.current.isIPad {
                return .secondaryProvisioning
            } else {
                return .registration(regLoader, .registering)
            }
        }
    }

    // MARK: - Launch Failures

    private var didAppLaunchFail: Bool = false {
        didSet {
            if !didAppLaunchFail {
                self.shouldKillAppWhenBackgrounded = false
            }
        }
    }

    private var shouldKillAppWhenBackgrounded: Bool = false

    private func checkIfAllowedToLaunch(
        mainAppContext: MainAppContext,
        appVersion: AppVersion,
        incrementalTSAttachmentMigrationStore: IncrementalTSAttachmentMigrationStore,
        didDeviceTransferRestoreSucceed: Bool
    ) -> LaunchPreflightError? {
        guard checkEnoughDiskSpaceAvailable() else {
            return .lowStorageSpaceAvailable
        }

        guard didDeviceTransferRestoreSucceed else {
            return .couldNotRestoreTransferredData
        }

        // Prevent:
        // * Users with an unknown GRDB schema revert to using an earlier GRDB schema.
        if SSKPreferences.hasUnknownGRDBSchema() {
            return .unknownDatabaseVersion
        }

        let userDefaults = mainAppContext.appUserDefaults()

        let databaseCorruptionState = DatabaseCorruptionState(userDefaults: userDefaults)
        switch databaseCorruptionState.status {
        case .notCorrupted, .readCorrupted:
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

        let launchAttemptFailureThreshold = DebugFlags.betaLogging ? 2 : 3
        if
            appVersion.lastAppVersion == appVersion.currentAppVersion,
            userDefaults.integer(forKey: Constants.appLaunchesAttemptedKey) >= launchAttemptFailureThreshold
        {
            if case .readCorrupted = databaseCorruptionState.status {
                return .possibleReadCorruptionCrashed
            }
            return .lastAppLaunchCrashed
        }

        if incrementalTSAttachmentMigrationStore.shouldReportFailureInUI() {
            if let (logString, wasLoggedBefore) = incrementalTSAttachmentMigrationStore.consumeLastBGProcessingTaskError() {
                if wasLoggedBefore {
                    Logger.error("Previously failed TSAttachment migration in some BGProcessingTask: \(logString)")
                } else {
                    Logger.error("Failed TSAttachment migration in last BGProcessingTask: \(logString)")
                }
            } else if let checkpointString = incrementalTSAttachmentMigrationStore.getLastCheckpoint() {
                Logger.error("Previously failed TSAttachment migration, last checkpoint: \(checkpointString)")
            }
            return .incrementalTSAttachmentMigrationFailed
        }

        return nil
    }

    private func showPreflightErrorUI(
        _ preflightError: LaunchPreflightError,
        launchContext: LaunchContext,
        window: UIWindow,
        viewController: UIViewController
    ) {
        Logger.warn("preflightError: \(preflightError)")

        let title: String
        let message: String
        let actions: [LaunchFailureActionSheetAction]

        switch preflightError {
        case .databaseCorruptedAndMightBeRecoverable, .possibleReadCorruptionCrashed:
            presentDatabaseRecovery(
                from: viewController,
                launchContext: launchContext,
                window: window
            )
            return

        case .databaseUnrecoverablyCorrupted:
            presentDatabaseUnrecoverablyCorruptedError(
                from: viewController,
                action: .submitDebugLogsWithDatabaseIntegrityCheckAndCrash(databaseStorage: launchContext.databaseStorage)
            )
            return

        case .unknownDatabaseVersion:
            title = OWSLocalizedString(
                "APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_TITLE",
                comment: "Error indicating that the app could not launch without reverting unknown database migrations."
            )
            message = OWSLocalizedString(
                "APP_LAUNCH_FAILURE_INVALID_DATABASE_VERSION_MESSAGE",
                comment: "Error indicating that the app could not launch without reverting unknown database migrations."
            )
            actions = [.submitDebugLogsAndCrash]

        case .couldNotRestoreTransferredData:
            title = OWSLocalizedString(
                "APP_LAUNCH_FAILURE_RESTORE_FAILED_TITLE",
                comment: "Error indicating that the app could not restore transferred data."
            )
            message = OWSLocalizedString(
                "APP_LAUNCH_FAILURE_RESTORE_FAILED_MESSAGE",
                comment: "Error indicating that the app could not restore transferred data."
            )
            actions = [.submitDebugLogsAndCrash]

        case .lastAppLaunchCrashed, .incrementalTSAttachmentMigrationFailed:
            title = OWSLocalizedString(
                "APP_LAUNCH_FAILURE_LAST_LAUNCH_CRASHED_TITLE",
                comment: "Error indicating that the app crashed during the previous launch."
            )
            message = OWSLocalizedString(
                "APP_LAUNCH_FAILURE_LAST_LAUNCH_CRASHED_MESSAGE",
                comment: "Error indicating that the app crashed during the previous launch."
            )
            actions = [
                .submitDebugLogsAndLaunchApp(window: window, launchContext: launchContext),
                .launchApp(window: window, launchContext: launchContext)
            ]

        case .lowStorageSpaceAvailable:
            shouldKillAppWhenBackgrounded = true
            title = OWSLocalizedString(
                "APP_LAUNCH_FAILURE_LOW_STORAGE_SPACE_AVAILABLE_TITLE",
                comment: "Error title indicating that the app crashed because there was low storage space available on the device."
            )
            message = OWSLocalizedString(
                "APP_LAUNCH_FAILURE_LOW_STORAGE_SPACE_AVAILABLE_MESSAGE",
                comment: "Error description indicating that the app crashed because there was low storage space available on the device."
            )
            actions = []
        }

        presentLaunchFailureActionSheet(
            from: viewController,
            supportTag: preflightError.supportTag,
            logDumper: .preLaunch(),
            title: title,
            message: message,
            actions: actions
        )
    }

    private func presentDatabaseRecovery(
        from viewController: UIViewController,
        launchContext: LaunchContext,
        window: UIWindow
    ) {
        var launchContext = launchContext
        let recoveryViewController = DatabaseRecoveryViewController<(AppSetup.FinalContinuation, DeviceSleepBlockObject)>(
            appReadiness: appReadiness,
            corruptDatabaseStorage: launchContext.databaseStorage,
            deviceSleepManager: launchContext.deviceSleepManager,
            keychainStorage: launchContext.keychainStorage,
            setupSskEnvironment: { databaseStorage in
                return Task {
                    launchContext.databaseStorage = databaseStorage
                    return await self.setUpMainAppEnvironment(launchContext: launchContext, loadingViewController: nil)
                }
            },
            launchApp: { (finalContinuation, sleepBlockObject) in
                // Pretend we didn't fail!
                self.didAppLaunchFail = false
                self.configureGlobalUI(in: window)
                self.didLoadDatabase(
                    finalContinuation: finalContinuation,
                    launchContext: launchContext,
                    sleepBlockObject: sleepBlockObject,
                    window: window
                )
            }
        )

        // Prevent dismissal.
        recoveryViewController.isModalInPresentation = true

        if let presentationController = recoveryViewController.sheetPresentationController {
            presentationController.detents = [.medium()]
            presentationController.prefersEdgeAttachedInCompactHeight = true
            presentationController.widthFollowsPreferredContentSizeWhenEdgeAttached = true
        }

        viewController.present(recoveryViewController, animated: true)
    }

    private func presentDatabaseUnrecoverablyCorruptedError(
        from viewController: UIViewController,
        action: LaunchFailureActionSheetAction
    ) {
        presentLaunchFailureActionSheet(
            from: viewController,
            supportTag: LaunchPreflightError.databaseUnrecoverablyCorrupted.supportTag,
            logDumper: .preLaunch(),
            title: OWSLocalizedString(
                "APP_LAUNCH_FAILURE_COULD_NOT_LOAD_DATABASE",
                comment: "Error indicating that the app could not launch because the database could not be loaded."
            ),
            message: OWSLocalizedString(
                "APP_LAUNCH_FAILURE_ALERT_MESSAGE",
                comment: "Default message for the 'app launch failed' alert."
            ),
            actions: [action]
        )
    }

    private enum LaunchFailureActionSheetAction {
        case submitDebugLogsAndCrash
        case submitDebugLogsAndLaunchApp(window: UIWindow, launchContext: LaunchContext)
        case submitDebugLogsWithDatabaseIntegrityCheckAndCrash(databaseStorage: SDSDatabaseStorage)
        case launchApp(window: UIWindow, launchContext: LaunchContext)
    }

    private func presentLaunchFailureActionSheet(
        from viewController: UIViewController,
        supportTag: String,
        logDumper: DebugLogDumper,
        title: String,
        message: String,
        actions: [LaunchFailureActionSheetAction]
    ) {
        let actionSheet = ActionSheetController(title: title, message: message)

        if DebugFlags.internalSettings {
            actionSheet.addAction(.init(title: "Export Database (internal)") { [unowned viewController] _ in
                SignalApp.showExportDatabaseUI(from: viewController) {
                    self.presentLaunchFailureActionSheet(
                        from: viewController,
                        supportTag: supportTag,
                        logDumper: logDumper,
                        title: title,
                        message: message,
                        actions: actions
                    )
                }
            })
        }

        func addSubmitDebugLogsAction(handler: @escaping () -> Void) {
            let actionTitle = OWSLocalizedString("SETTINGS_ADVANCED_SUBMIT_DEBUGLOG", comment: "")
            actionSheet.addAction(.init(title: actionTitle) { _ in
                handler()
            })
        }

        func ignoreErrorAndLaunchApp(in window: UIWindow, launchContext: LaunchContext) {
            // Pretend we didn't fail!
            self.didAppLaunchFail = false
            launchContext.incrementalMessageTSAttachmentMigrationStore.didReportFailureInUI()
            let loadingViewController = LoadingViewController()
            window.rootViewController = loadingViewController
            self.launchApp(
                in: window,
                launchContext: launchContext,
                loadingViewController: loadingViewController
            )
        }

        for action in actions {
            switch action {
            case .submitDebugLogsAndCrash:
                addSubmitDebugLogsAction {
                    DebugLogs.submitLogs(supportTag: supportTag, dumper: logDumper) {
                        owsFail("Exiting after submitting debug logs")
                    }
                }
            case .submitDebugLogsAndLaunchApp(let window, let launchContext):
                addSubmitDebugLogsAction { [unowned window] in
                    DebugLogs.submitLogs(supportTag: supportTag, dumper: logDumper) {
                        ignoreErrorAndLaunchApp(in: window, launchContext: launchContext)
                    }
                }
            case .submitDebugLogsWithDatabaseIntegrityCheckAndCrash(let databaseStorage):
                addSubmitDebugLogsAction { [unowned viewController] in
                    SignalApp.showDatabaseIntegrityCheckUI(from: viewController, databaseStorage: databaseStorage) {
                        DebugLogs.submitLogs(supportTag: supportTag, dumper: logDumper) {
                            owsFail("Exiting after submitting debug logs")
                        }
                    }
                }
            case .launchApp(let window, let launchContext):
                actionSheet.addAction(.init(
                    title: OWSLocalizedString(
                        "APP_LAUNCH_FAILURE_CONTINUE",
                        comment: "Button to try launching the app even though the last launch failed"
                    ),
                    style: .cancel, // Use a cancel-style button to draw attention.
                    handler: { [unowned window] _ in
                        ignoreErrorAndLaunchApp(in: window, launchContext: launchContext)
                    }
                ))
            }
        }

        viewController.presentActionSheet(actionSheet)
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            // We need to respect the in-app notification sound preference. This method, which is called
            // for modern UNUserNotification users, could be a place to do that, but since we'd still
            // need to handle this behavior for legacy UINotification users anyway, we "allow" all
            // notification options here, and rely on the shared logic in NotificationPresenterImpl to
            // honor notification sound preferences for both modern and legacy users.
            let options: UNNotificationPresentationOptions = [.badge, .banner, .list, .sound]
            completionHandler(options)
        }
    }

    private func terminalErrorViewController() -> UIViewController {
        let storyboard = UIStoryboard(name: "Launch Screen", bundle: nil)
        guard let viewController = storyboard.instantiateInitialViewController() else {
            owsFail("No initial view controller")
        }
        return viewController
    }

    // MARK: - Activation

    private var hasActivated = false

    private func handleActivation() {
        AssertIsOnMainThread()

        defer {
            Logger.info("Activated.")
        }

        let tsRegistrationState: TSRegistrationState = DependenciesBridge.shared.db.read { tx in
            // Always check prekeys after app launches, and sometimes check on app activation.
            let registrationState = DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx)
            if registrationState.isRegistered {
                DependenciesBridge.shared.preKeyManager.checkPreKeysIfNecessary(tx: tx)
            }
            return registrationState
        }

        if !hasActivated {
            hasActivated = true

            RTCInitializeSSL()

            // Clean up any messages that expired since last launch and continue
            // cleaning in the background.
            SSKEnvironment.shared.disappearingMessagesJobRef.startIfNecessary()

            if !tsRegistrationState.isRegistered {
                // Unregistered user should have no unread messages. e.g. if you delete your account.
                SSKEnvironment.shared.notificationPresenterRef.clearAllNotifications()
            }
        }

        refreshConnection(isAppActive: true)

        // Every time we become active...
        if tsRegistrationState.isRegistered {
            // TODO: Should we run this immediately even if we would like to process already decrypted envelopes handed to us by the NSE?
            Task {
                await SSKEnvironment.shared.groupMessageProcessorManagerRef.startAllProcessors()
            }

            // At this point, potentially lengthy DB locking migrations could be running.
            // Avoid blocking app launch by putting all further possible DB access in async block
            DispatchQueue.main.async {
                SSKEnvironment.shared.contactManagerImplRef.fetchSystemContactsOnceIfAlreadyAuthorized()

                if !UIApplication.shared.isRegisteredForRemoteNotifications {
                    Logger.info("Retrying to register for remote notifications since user hasn't registered yet.")
                    // Push tokens don't normally change while the app is launched, so checking once during launch is
                    // usually sufficient, but e.g. on iOS11, users who have disabled "Allow Notifications" and disabled
                    // "Background App Refresh" will not be able to obtain an APN token. Enabling those settings does not
                    // restart the app, so we check every activation for users who haven't yet registered.
                    SyncPushTokensJob.run()
                }
            }
        }

        // We want to defer this so that we never call this method until
        // [UIApplicationDelegate applicationDidBecomeActive:] is complete.
        let identityManager = DependenciesBridge.shared.identityManager
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { identityManager.tryToSyncQueuedVerificationStates() }
    }

    // MARK: - Connections & Fetching

    /// Tokens to keep the web socket open when the app is in the foreground.
    private var activeConnectionTokens = [OWSChatConnection.ConnectionToken]()

    /// A background fetching task that keeps the web socket open while the app
    /// is in the background.
    private var backgroundFetchHandle: BackgroundTaskHandle?

    private func refreshConnection(isAppActive: Bool) {
        let chatConnectionManager = DependenciesBridge.shared.chatConnectionManager

        let oldActiveConnectionTokens = self.activeConnectionTokens
        if isAppActive {
            // If we're active, open a connection.
            self.activeConnectionTokens = chatConnectionManager.requestConnections(shouldReconnectIfConnectedElsewhere: true)
            oldActiveConnectionTokens.forEach { $0.releaseConnection() }

            // We're back in the foreground. We've passed off connection management to
            // the foreground logic, so just tear it down without waiting for anything.
            self.backgroundFetchHandle?.interrupt()
            self.backgroundFetchHandle = nil
        } else {
            let backgroundFetcher = DependenciesBridge.shared.backgroundMessageFetcherFactory.buildFetcher(useWebSocket: true)
            self.activeConnectionTokens = []
            self.backgroundFetchHandle?.interrupt()
            let startDate = MonotonicDate()
            self.backgroundFetchHandle = UIApplication.shared.beginBackgroundTask(
                backgroundBlock: {
                    do {
                        await backgroundFetcher.start()
                        oldActiveConnectionTokens.forEach { $0.releaseConnection() }
                        // This will usually be limited to 30 seconds rather than 3 minutes.
                        try await backgroundFetcher.waitUntil(deadline: startDate.adding(180))
                    } catch {
                        // We were canceled, either because we entered the foreground or our
                        // background execution time expired.
                    }
                },
                completionHandler: { result in
                    switch result {
                    case .finished, .interrupted:
                        await backgroundFetcher.reset()
                    case .expired:
                        await backgroundFetcher.stopAndWaitBeforeSuspending()
                    }
                },
            )
        }
    }

    // MARK: - Orientation

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        if CurrentAppContext().isRunningTests || didAppLaunchFail {
            return .portrait
        }

        // The call-banner window is only suitable for portrait display on iPhone
        if appReadiness.isAppReady, AppEnvironment.shared.callService.callServiceState.currentCall != nil, !UIDevice.current.isIPad {
            return .portrait
        }

        guard let rootViewController = self.window?.rootViewController else {
            return UIDevice.current.defaultSupportedOrientations
        }

        return rootViewController.supportedInterfaceOrientations
    }

    // MARK: - Notifications

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        AssertIsOnMainThread()

        if didAppLaunchFail {
            return
        }

        Logger.info("")
        AppEnvironment.shared.pushRegistrationManagerRef.didReceiveVanillaPushToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AssertIsOnMainThread()

        if didAppLaunchFail {
            return
        }

        Logger.warn("")
        #if DEBUG
        AppEnvironment.shared.pushRegistrationManagerRef.didReceiveVanillaPushToken(Data(count: 32))
        #else
        AppEnvironment.shared.pushRegistrationManagerRef.didFailToReceiveVanillaPushToken(error: error)
        #endif
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        AssertIsOnMainThread()

        if DebugFlags.verboseNotificationLogging {
            Logger.info("")
        }

        Task {
            defer {
                // TODO: Report the actual outcome.
                completionHandler(.newData)
            }
            try await withCooperativeTimeout(seconds: 27) {
                try await self.appReadiness.waitForAppReady()

                // Mark down that the APNS token is working because we got a push.
                let databaseStorage = SSKEnvironment.shared.databaseStorageRef
                async let _ = databaseStorage.awaitableWrite { tx in
                    APNSRotationStore.didReceiveAPNSPush(transaction: tx)
                }

                try await self.processRemoteNotification(userInfo)
            }
        }
    }

    private enum HandleSilentPushContentResult {
        case handled
        case notHandled
    }

    // TODO: NSE Lifecycle, is this invoked when the NSE wakes the main app?
    private nonisolated func processRemoteNotification(_ remoteNotification: [AnyHashable: Any]) async throws {
        try await self.appReadiness.waitForAppReady()
        switch try await self.handleSilentPushContent(remoteNotification) {
        case .handled:
            break
        case .notHandled:
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                Logger.info("Ignoring remote notification; user is not registered.")
                return
            }
            let backgroundMessageFetcher = DependenciesBridge.shared.backgroundMessageFetcherFactory.buildFetcher(useWebSocket: true)
            await backgroundMessageFetcher.start()

            // If we get canceled, we want to ignore the contact sync in this method
            // and return control to the caller.
            let syncContacts = CancellableContinuation<Void>()
            Task {
                // If the main app gets woken to process messages in the background, check
                // for any pending NSE requests to fulfill.
                let result = await Result(catching: {
                    try await SSKEnvironment.shared.syncManagerRef.syncAllContactsIfFullSyncRequested().awaitable()
                })
                syncContacts.resume(with: result)
            }

            let result = await Result(catching: {
                // If the contact sync fails, ignore it. In this method, we care about the
                // result of fetching messages, not sending opportunistic contact syncs.
                try? await syncContacts.wait()
                try await backgroundMessageFetcher.waitForFetchingProcessingAndSideEffects()
            })
            await backgroundMessageFetcher.stopAndWaitBeforeSuspending()
            try result.get()
        }
    }

    private nonisolated func handleSilentPushContent(_ remoteNotification: [AnyHashable: Any]) async throws -> HandleSilentPushContentResult {
        if let spamChallengeToken = remoteNotification["rateLimitChallenge"] as? String {
            SSKEnvironment.shared.spamChallengeResolverRef.handleIncomingPushChallengeToken(spamChallengeToken)
            // TODO: Wait only until the token has been submitted.
            try await Task.sleep(nanoseconds: 20.clampedNanoseconds)
            return .handled
        }

        if let preAuthChallengeToken = remoteNotification["challenge"] as? String {
            AppEnvironment.shared.pushRegistrationManagerRef.didReceiveVanillaPreAuthChallengeToken(preAuthChallengeToken)
            // TODO: Wait only until the token has been submitted.
            try await Task.sleep(nanoseconds: 20.clampedNanoseconds)
            return .handled
        }

        return .notHandled
    }

    private func clearAppropriateNotificationsAndRestoreBadgeCount() {
        AssertIsOnMainThread()

        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            let oldBadgeValue = UIApplication.shared.applicationIconBadgeNumber
            SSKEnvironment.shared.notificationPresenterRef.clearAllNotificationsExceptNewLinkedDevices()
            UIApplication.shared.applicationIconBadgeNumber = oldBadgeValue
        }
    }

    // MARK: - Handoff

    /// Among other things, this is used by "call back" CallKit dialog and calling from the Contacts app.
    ///
    /// We always return true if we are going to try to handle the user activity
    /// since we never want iOS to contact us again using a URL.
    ///
    /// From https://developer.apple.com/documentation/uikit/uiapplicationdelegate/1623072-application?language=objc:
    ///
    /// If you do not implement this method or if your implementation returns
    /// false, iOS tries to create a document for your app to open using a URL.
    @available(iOS, deprecated: 13.0) // hack to mute deprecation warnings; this is not deprecated
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        AssertIsOnMainThread()

        if didAppLaunchFail {
            return false
        }

        Logger.info("\(userActivity.activityType)")

        switch userActivity.activityType {
        case "INSendMessageIntent":
            let intent = userActivity.interaction?.intent
            guard let intent = intent as? INSendMessageIntent else {
                owsFailDebug("Wrong type for intent: \(type(of: intent))")
                return false
            }
            guard let threadUniqueId = intent.conversationIdentifier else {
                owsFailDebug("Missing threadUniqueId for intent")
                return false
            }
            appReadiness.runNowOrWhenAppDidBecomeReadySync {
                let tsAccountManager = DependenciesBridge.shared.tsAccountManager
                guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                    Logger.warn("Ignoring user activity; not registered.")
                    return
                }
                SignalApp.shared.presentConversationAndScrollToFirstUnreadMessage(
                    threadUniqueId: threadUniqueId,
                    animated: false
                )
            }
            return true
        case "INStartVideoCallIntent":
            return handleStartCallIntent(
                INStartVideoCallIntent.self,
                userActivity: userActivity,
                contacts: \.contacts,
                isVideoCall: { _ in true }
            )
        case "INStartAudioCallIntent":
            return handleStartCallIntent(
                INStartAudioCallIntent.self,
                userActivity: userActivity,
                contacts: \.contacts,
                isVideoCall: { _ in false }
            )
        case "INStartCallIntent":
            return handleStartCallIntent(
                INStartCallIntent.self,
                userActivity: userActivity,
                contacts: \.contacts,
                isVideoCall: { $0.callCapability == .videoCall }
            )
        case NSUserActivityTypeBrowsingWeb:
            guard let webpageUrl = userActivity.webpageURL else {
                owsFailDebug("Missing webpageUrl.")
                return false
            }
            return handleOpenUrl(webpageUrl)
        default:
            return false
        }
    }

    private func handleStartCallIntent<T: INIntent>(
        _ intentType: T.Type,
        userActivity: NSUserActivity,
        contacts: KeyPath<T, [INPerson]?>,
        isVideoCall: (T) -> Bool
    ) -> Bool {
        let intent = userActivity.interaction?.intent
        guard let intent = intent as? T else {
            owsFailDebug("Wrong type for intent: \(type(of: intent))")
            return false
        }
        guard let handle = intent[keyPath: contacts]?.first?.personHandle?.value else {
            owsFailDebug("Missing handle for intent")
            return false
        }
        let isVideo = isVideoCall(intent)
        appReadiness.runNowOrWhenAppDidBecomeReadySync {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                Logger.warn("Ignoring user activity; not registered.")
                return
            }
            guard let callTarget = CallKitCallManager.callTargetForHandleWithSneakyTransaction(handle) else {
                Logger.warn("Ignoring user activity; unknown user.")
                return
            }
            // This intent can be received from more than one user interaction.
            //
            // * It can be received if the user taps the "video" button in the CallKit
            // UI for an an ongoing call. If so, the correct response is to try to
            // activate the local video for that call.
            //
            // * It can be received if the user taps the "video" button for a contact
            // in the contacts app. If so, the correct response is to try to initiate a
            // new call to that user - unless there is another call in progress.
            let callService = AppEnvironment.shared.callService!
            if let currentCall = callService.callServiceState.currentCall {
                if isVideo, case .individual = currentCall.mode, currentCall.mode.matches(callTarget) {
                    Logger.info("Upgrading existing call to video")
                    callService.updateIsLocalVideoMuted(isLocalVideoMuted: false)
                } else {
                    Logger.warn("Ignoring user activity; already on another call")
                }
                return
            }
            callService.initiateCall(to: callTarget, isVideo: isVideo)
        }
        return true
    }

    // MARK: - Events

    @objc
    private func registrationStateDidChange() {
        AssertIsOnMainThread()

        Logger.info("")

        scheduleBgAppRefresh()

        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let isRegistered = tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        if isRegistered {
            appReadiness.runNowOrWhenAppDidBecomeReadySync {
                SSKEnvironment.shared.databaseStorageRef.write { transaction in
                    let localAddress = tsAccountManager.localIdentifiers(tx: transaction)?.aciAddress
                    Logger.info("localAddress: \(String(describing: localAddress))")

                    ExperienceUpgradeFinder.markAllCompleteForNewUser(transaction: transaction)
                }
            }
            DependenciesBridge.shared.attachmentDownloadManager.beginDownloadingIfNecessary()
            Task {
                try await StickerManager.downloadPendingSickerPacks()
            }
        }

        Self.updateApplicationShortcutItems(isRegistered: isRegistered)
    }

    // MARK: - Shortcut Items

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        AssertIsOnMainThread()

        if didAppLaunchFail {
            completionHandler(false)
            return
        }

        appReadiness.runNowOrWhenUIDidBecomeReadySync {
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
                let controller = ActionSheetController(
                    title: OWSLocalizedString("REGISTER_CONTACTS_WELCOME", comment: ""),
                    message: OWSLocalizedString("REGISTRATION_RESTRICTED_MESSAGE", comment: "")
                )
                controller.addAction(ActionSheetAction(title: CommonStrings.okButton))
                UIApplication.shared.frontmostViewController?.present(controller, animated: true, completion: {
                    completionHandler(false)
                })
                return
            }
            SignalApp.shared.showNewConversationView()
            completionHandler(true)
        }
    }

    public static func updateApplicationShortcutItems(isRegistered: Bool) {
        guard CurrentAppContext().isMainApp else { return }
        UIApplication.shared.shortcutItems = applicationShortcutItems(isRegistered: isRegistered)
    }

    static func applicationShortcutItems(isRegistered: Bool) -> [UIApplicationShortcutItem] {
        guard isRegistered else { return [] }
        return [.init(
            type: "\(Bundle.main.bundleIdPrefix).quickCompose",
            localizedTitle: OWSLocalizedString(
                "APPLICATION_SHORTCUT_NEW_MESSAGE",
                comment: "On the iOS home screen, if you tap and hold the Signal icon, this shortcut will appear. Tapping it will let users send a new message. You may want to refer to similar behavior in other iOS apps, such as Messages, for equivalent strings."
            ),
            localizedSubtitle: nil,
            icon: UIApplicationShortcutIcon(type: .compose)
        )]
    }

    // MARK: - URL Handling

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        AssertIsOnMainThread()
        return handleOpenUrl(url)
    }

    private func handleOpenUrl(_ url: URL) -> Bool {
        AssertIsOnMainThread()

        if didAppLaunchFail {
            return false
        }

        guard let parsedUrl = UrlOpener.parseUrl(url) else {
            return false
        }
        let appReadiness: AppReadinessSetter = self.appReadiness
        appReadiness.runNowOrWhenUIDidBecomeReadySync {
            let urlOpener = UrlOpener(
                appReadiness: appReadiness,
                databaseStorage: SSKEnvironment.shared.databaseStorageRef,
                tsAccountManager: DependenciesBridge.shared.tsAccountManager
            )

            urlOpener.openUrl(parsedUrl, in: self.window!)
        }
        return true
    }

    // MARK: - Database integrity checks

    private func checkDatabaseIntegrityIfNecessary(
        isRegistered: Bool
    ) {
        guard isRegistered, FeatureFlags.periodicallyCheckDatabaseIntegrity else { return }

        let appReadiness: AppReadiness = self.appReadiness
        DispatchQueue.sharedUtility.async {
            switch GRDBDatabaseStorageAdapter.checkIntegrity(databaseStorage: SSKEnvironment.shared.databaseStorageRef) {
            case .ok: break
            case .notOk:
                appReadiness.runNowOrWhenUIDidBecomeReadySync {
                    OWSActionSheets.showActionSheet(
                        title: "Database corrupted!",
                        message: "We have detected database corruption on your device. Please submit debug logs to the iOS team."
                    )
                }
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // The method will be called on the delegate when the user responded to the notification by opening the application,
    // dismissing the notification or choosing a UNNotificationAction. The delegate must be set before the application
    // returns from application:didFinishLaunchingWithOptions:.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor [appReadiness] () -> Void in
            defer { completionHandler() }

            try await self.appReadiness.waitForAppReady()

            let backgroundMessageFetcherFactory = DependenciesBridge.shared.backgroundMessageFetcherFactory
            let backgroundMessageFetcher = backgroundMessageFetcherFactory.buildFetcher(useWebSocket: true)
            // So that we open up a connection for replies.
            await backgroundMessageFetcher.start()
            await NotificationActionHandler.handleNotificationResponse(response, appReadiness: appReadiness)
            let result = await Result(catching: {
                // So that we wait for any enqueued messages to be sent.
                try await backgroundMessageFetcher.waitForFetchingProcessingAndSideEffects()
            })
            // So that we tear down gracefully.
            await backgroundMessageFetcher.stopAndWaitBeforeSuspending()
            try result.get()
        }
    }
}
