// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import PromiseKit
import WebRTC
import SessionUIKit
import UIKit
import SessionMessagingKit
import SessionUtilitiesKit
import SessionUIKit
import UserNotifications
import UIKit
import SignalUtilitiesKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate, AppModeManagerDelegate {
    var window: UIWindow?
    var backgroundSnapshotBlockerWindow: UIWindow?
    var appStartupWindow: UIWindow?
    var hasInitialRootViewController: Bool = false
    private var loadingViewController: LoadingViewController?
    
    /// This needs to be a lazy variable to ensure it doesn't get initialized before it actually needs to be used
    lazy var poller: Poller = Poller()
    
    // MARK: - Lifecycle

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // These should be the first things we do (the startup process can fail without them)
        SetCurrentAppContext(MainAppContext())
        verifyDBKeysAvailableBeforeBackgroundLaunch()

        AppModeManager.configure(delegate: self)
        Cryptography.seedRandom()
        AppVersion.sharedInstance()

        // Prevent the device from sleeping during database view async registration
        // (e.g. long database upgrades).
        //
        // This block will be cleared in storageIsReady.
        DeviceSleepManager.sharedInstance.addBlock(blockObject: self)
        
        let mainWindow: UIWindow = UIWindow(frame: UIScreen.main.bounds)
        self.loadingViewController = LoadingViewController()
        
        AppSetup.setupEnvironment(
            appSpecificBlock: {
                // Create AppEnvironment
                AppEnvironment.shared.setup()
                
                // Note: Intentionally dispatching sync as we want to wait for these to complete before
                // continuing
                DispatchQueue.main.sync {
                    OWSScreenLockUI.sharedManager().setup(withRootWindow: mainWindow)
                    OWSWindowManager.shared().setup(
                        withRootWindow: mainWindow,
                        screenBlockingWindow: OWSScreenLockUI.sharedManager().screenBlockingWindow
                    )
                    OWSScreenLockUI.sharedManager().startObserving()
                }
            },
            migrationProgressChanged: { [weak self] progress, minEstimatedTotalTime in
                self?.loadingViewController?.updateProgress(
                    progress: progress,
                    minEstimatedTotalTime: minEstimatedTotalTime
                )
            },
            migrationsCompletion: { [weak self] error, needsConfigSync in
                guard error == nil else {
                    self?.showFailedMigrationAlert(error: error)
                    return
                }
                
                self?.completePostMigrationSetup(needsConfigSync: needsConfigSync)
            }
        )
        
        SNAppearance.switchToSessionAppearance()
        
        if Environment.shared?.callManager.wrappedValue?.currentCall == nil {
            UserDefaults.sharedLokiProject?.set(false, forKey: "isCallOngoing")
        }
        
        // No point continuing if we are running tests
        guard !CurrentAppContext().isRunningTests else { return true }

        self.window = mainWindow
        CurrentAppContext().mainWindow = mainWindow
        
        // Show LoadingViewController until the async database view registrations are complete.
        mainWindow.rootViewController = self.loadingViewController
        mainWindow.makeKeyAndVisible()

        adapt(appMode: AppModeManager.getAppModeOrSystemDefault())

        // This must happen in appDidFinishLaunching or earlier to ensure we don't
        // miss notifications.
        // Setting the delegate also seems to prevent us from getting the legacy notification
        // notification callbacks upon launch e.g. 'didReceiveLocalNotification'
        UNUserNotificationCenter.current().delegate = self
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(registrationStateDidChange),
            name: .registrationStateDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showMissedCallTipsIfNeeded(_:)),
            name: .missedCall,
            object: nil
        )
        
        Logger.info("application: didFinishLaunchingWithOptions completed.")

        return true
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        /// **Note:** We _shouldn't_ need to call this here but for some reason the OS doesn't seems to
        /// be calling the `userNotificationCenter(_:,didReceive:withCompletionHandler:)`
        /// method when the device is locked while the app is in the foreground (or if the user returns to the
        /// springboard without swapping to another app) - adding this here in addition to the one in
        /// `appDidFinishLaunching` seems to fix this odd behaviour (even though it doesn't match
        /// Apple's documentation on the matter)
        UNUserNotificationCenter.current().delegate = self
        
        // Resume database
        NotificationCenter.default.post(name: Database.resumeNotification, object: self)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        DDLog.flushLog()
        
        // NOTE: Fix an edge case where user taps on the callkit notification
        // but answers the call on another device
        stopPollers(shouldStopUserPoller: !self.hasCallOngoing())
        
        // Stop all jobs except for message sending and when completed suspend the database
        JobRunner.stopAndClearPendingJobs(exceptForVariant: .messageSend) {
            if !self.hasCallOngoing() {
                NotificationCenter.default.post(name: Database.suspendNotification, object: self)
            }
        }
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !CurrentAppContext().isRunningTests else { return }
        
        UserDefaults.sharedLokiProject?[.isMainAppActive] = true
        
        ensureRootViewController()
        adapt(appMode: AppModeManager.getAppModeOrSystemDefault())

        AppReadiness.runNowOrWhenAppDidBecomeReady { [weak self] in
            self?.handleActivation()
            
            /// Clear all notifications whenever we become active once the app is ready
            ///
            /// **Note:** It looks like when opening the app from a notification, `userNotificationCenter(didReceive)` is
            /// no longer always called before `applicationDidBecomeActive` we need to trigger the "clear notifications" logic
            /// within the `runNowOrWhenAppDidBecomeReady` callback and dispatch to the next run loop to ensure it runs after
            /// the notification has actually been handled
            DispatchQueue.main.async { [weak self] in
                self?.clearAllNotificationsAndRestoreBadgeCount()
            }
        }

        // On every activation, clear old temp directories.
        ClearOldTemporaryDirectories()
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        clearAllNotificationsAndRestoreBadgeCount()
        
        UserDefaults.sharedLokiProject?[.isMainAppActive] = false

        DDLog.flushLog()
    }
    
    // MARK: - Orientation

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
    
    // MARK: - Background Fetching
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Resume database
        NotificationCenter.default.post(name: Database.resumeNotification, object: self)
        
        // Background tasks only last for a certain amount of time (which can result in a crash and a
        // prompt appearing for the user), we want to avoid this and need to make sure to suspend the
        // database again before the background task ends so we start a timer that expires 1 second
        // before the background task is due to expire in order to do so
        let cancelTimer: Timer = Timer.scheduledTimerOnMainThread(
            withTimeInterval: (application.backgroundTimeRemaining - 1),
            repeats: false
        ) { timer in
            timer.invalidate()
            
            guard BackgroundPoller.isValid else { return }
            
            BackgroundPoller.isValid = false
            
            // Suspend database
            NotificationCenter.default.post(name: Database.suspendNotification, object: self)
            
            SNLog("Background poll failed due to manual timeout")
            completionHandler(.failed)
        }
        
        // Flag the background poller as valid first and then trigger it to poll once the app is
        // ready (we do this here rather than in `BackgroundPoller.poll` to avoid the rare edge-case
        // that could happen when the timeout triggers before the app becomes ready which would have
        // incorrectly set this 'isValid' flag to true after it should have timed out)
        BackgroundPoller.isValid = true
        
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            BackgroundPoller.poll { result in
                guard BackgroundPoller.isValid else { return }
                
                BackgroundPoller.isValid = false
                
                // Suspend database
                NotificationCenter.default.post(name: Database.suspendNotification, object: self)
                
                cancelTimer.invalidate()
                completionHandler(result)
            }
        }
    }
    
    // MARK: - App Readiness
    
    private func completePostMigrationSetup(needsConfigSync: Bool) {
        Configuration.performMainSetup()
        JobRunner.add(executor: SyncPushTokensJob.self, for: .syncPushTokens)
        
        // Trigger any launch-specific jobs and start the JobRunner
        JobRunner.appDidFinishLaunching()
        
        /// Setup the UI
        ///
        /// **Note:** This **MUST** be run before calling `AppReadiness.setAppIsReady()` otherwise if
        /// we are launching the app from a push notification the HomeVC won't be setup yet and it won't open the
        /// related thread
        self.ensureRootViewController(isPreAppReadyCall: true)
        
        // Note that this does much more than set a flag;
        // it will also run all deferred blocks (including the JobRunner
        // 'appDidBecomeActive' method)
        AppReadiness.setAppIsReady()
        
        DeviceSleepManager.sharedInstance.removeBlock(blockObject: self)
        AppVersion.sharedInstance().mainAppLaunchDidComplete()
        Environment.shared?.audioSession.setup()
        Environment.shared?.reachabilityManager.setup()
        
        Storage.shared.writeAsync { db in
            // Disable the SAE until the main app has successfully completed launch process
            // at least once in the post-SAE world.
            db[.isReadyForAppExtensions] = true
            
            if Identity.userExists(db) {
                let appVersion: AppVersion = AppVersion.sharedInstance()
                
                // If the device needs to sync config or the user updated to a new version
                if
                    needsConfigSync || (
                        (appVersion.lastAppVersion?.count ?? 0) > 0 &&
                        appVersion.lastAppVersion != appVersion.currentAppVersion
                    )
                {
                    try MessageSender.syncConfiguration(db, forceSyncNow: true).retainUntilComplete()
                }
            }
        }
    }
    
    private func showFailedMigrationAlert(error: Error?) {
        let alert = UIAlertController(
            title: "Session",
            message: "DATABASE_MIGRATION_FAILED".localized(),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "modal_share_logs_title".localized(), style: .default) { _ in
            ShareLogsModal.shareLogs(from: alert) { [weak self] in
                self?.showFailedMigrationAlert(error: error)
            }
        })
        alert.addAction(UIAlertAction(title: "vc_restore_title".localized(), style: .destructive) { _ in
            // Remove the legacy database and any message hashes that have been migrated to the new DB
            try? SUKLegacy.deleteLegacyDatabaseFilesAndKey()
            
            Storage.shared.write { db in
                try SnodeReceivedMessageInfo.deleteAll(db)
            }
            
            // The re-run the migration (should succeed since there is no data)
            AppSetup.runPostSetupMigrations(
                migrationProgressChanged: { [weak self] progress, minEstimatedTotalTime in
                    self?.loadingViewController?.updateProgress(
                        progress: progress,
                        minEstimatedTotalTime: minEstimatedTotalTime
                    )
                },
                migrationsCompletion: { [weak self] error, needsConfigSync in
                    guard error == nil else {
                        self?.showFailedMigrationAlert(error: error)
                        return
                    }
                    
                    self?.completePostMigrationSetup(needsConfigSync: needsConfigSync)
                }
            )
        })
        
        alert.addAction(UIAlertAction(title: "Close", style: .default) { _ in
            DDLog.flushLog()
            exit(0)
        })
        
        self.window?.rootViewController?.present(alert, animated: true, completion: nil)
    }
    
    /// The user must unlock the device once after reboot before the database encryption key can be accessed.
    private func verifyDBKeysAvailableBeforeBackgroundLaunch() {
        guard UIApplication.shared.applicationState == .background else { return }
        
        guard !Storage.isDatabasePasswordAccessible else { return }    // All good
        
        Logger.info("Exiting because we are in the background and the database password is not accessible.")
        
        let notificationContent: UNMutableNotificationContent = UNMutableNotificationContent()
        notificationContent.body = String(
            format: NSLocalizedString("NOTIFICATION_BODY_PHONE_LOCKED_FORMAT", comment: ""),
            UIDevice.current.localizedModel
        )
        let notificationRequest: UNNotificationRequest = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: notificationContent,
            trigger: nil
        )
        
        // Make sure we clear any existing notifications so that they don't start stacking up
        // if the user receives multiple pushes.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UIApplication.shared.applicationIconBadgeNumber = 0
        
        UNUserNotificationCenter.current().add(notificationRequest, withCompletionHandler: nil)
        UIApplication.shared.applicationIconBadgeNumber = 1
        
        DDLog.flushLog()
        exit(0)
    }
    
    private func enableBackgroundRefreshIfNecessary() {
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
        }
    }

    private func handleActivation() {
        guard Identity.userExists() else { return }
        
        enableBackgroundRefreshIfNecessary()
        JobRunner.appDidBecomeActive()
        
        startPollersIfNeeded()
        
        if CurrentAppContext().isMainApp {
            syncConfigurationIfNeeded()
            handleAppActivatedWithOngoingCallIfNeeded()
        }
    }
    
    private func ensureRootViewController(isPreAppReadyCall: Bool = false) {
        guard (AppReadiness.isAppReady() || isPreAppReadyCall) && Storage.shared.isValid && !hasInitialRootViewController else {
            return
        }
        
        self.hasInitialRootViewController = true
        self.window?.rootViewController = OWSNavigationController(
            rootViewController: (Identity.userExists() ?
                HomeVC() :
                LandingVC()
            )
        )
        UIViewController.attemptRotationToDeviceOrientation()
        
        /// **Note:** There is an annoying case when starting the app by interacting with a push notification where
        /// the `HomeVC` won't have completed loading it's view which means the `SessionApp.homeViewController`
        /// won't have been set - we set the value directly here to resolve this edge case
        if let homeViewController: HomeVC = (self.window?.rootViewController as? UINavigationController)?.viewControllers.first as? HomeVC {
            SessionApp.homeViewController.mutate { $0 = homeViewController }
        }
    }
    
    // MARK: - Notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrationManager.shared.didReceiveVanillaPushToken(deviceToken)
        Logger.info("Registering for push notifications with token: \(deviceToken).")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger.error("Failed to register push token with error: \(error).")
        
        #if DEBUG
        Logger.warn("We're in debug mode. Faking success for remote registration with a fake push identifier.")
        PushRegistrationManager.shared.didReceiveVanillaPushToken(Data(count: 32))
        #else
        PushRegistrationManager.shared.didFailToReceiveVanillaPushToken(error: error)
        #endif
    }
    
    private func clearAllNotificationsAndRestoreBadgeCount() {
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            AppEnvironment.shared.notificationPresenter.clearAllNotifications()
            
            guard CurrentAppContext().isMainApp else { return }
            
            CurrentAppContext().setMainAppBadgeNumber(
                Storage.shared
                    .read { db in
                        let userPublicKey: String = getUserHexEncodedPublicKey(db)
                        let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
                        
                        return try Interaction
                            .filter(Interaction.Columns.wasRead == false)
                            .filter(
                                // Exclude outgoing and deleted messages from the count
                                Interaction.Columns.variant != Interaction.Variant.standardOutgoing &&
                                Interaction.Columns.variant != Interaction.Variant.standardIncomingDeleted
                            )
                            .filter(
                                // Only count mentions if 'onlyNotifyForMentions' is set
                                thread[.onlyNotifyForMentions] == false ||
                                Interaction.Columns.hasMention == true
                            )
                            .joining(
                                required: Interaction.thread
                                    .aliased(thread)
                                    .joining(optional: SessionThread.contact)
                                    .filter(
                                        // Ignore muted threads
                                        SessionThread.Columns.mutedUntilTimestamp == nil ||
                                        SessionThread.Columns.mutedUntilTimestamp < Date().timeIntervalSince1970
                                    )
                                    .filter(
                                        // Ignore message request threads
                                        SessionThread.Columns.variant != SessionThread.Variant.contact ||
                                        !SessionThread.isMessageRequest(userPublicKey: userPublicKey)
                                    )
                            )
                            .fetchCount(db)
                    }
                    .defaulting(to: 0)
            )
        }
    }
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            guard Identity.userExists() else { return }
            
            SessionApp.homeViewController.wrappedValue?.createNewDM()
            completionHandler(true)
        }
    }

    /// The method will be called on the delegate only if the application is in the foreground. If the method is not implemented or the
    /// handler is not called in a timely manner then the notification will not be presented. The application can choose to have the
    /// notification presented as a sound, badge, alert and/or in the notification list.
    ///
    /// This decision should be based on whether the information in the notification is otherwise visible to the user.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.userInfo["remote"] != nil {
            Logger.info("[Loki] Ignoring remote notifications while the app is in the foreground.")
            return
        }
        
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            // We need to respect the in-app notification sound preference. This method, which is called
            // for modern UNUserNotification users, could be a place to do that, but since we'd still
            // need to handle this behavior for legacy UINotification users anyway, we "allow" all
            // notification options here, and rely on the shared logic in NotificationPresenter to
            // honor notification sound preferences for both modern and legacy users.
            completionHandler([.alert, .badge, .sound])
        }
    }

    /// The method will be called on the delegate when the user responded to the notification by opening the application, dismissing
    /// the notification or choosing a UNNotificationAction. The delegate must be set before the application returns from
    /// application:didFinishLaunchingWithOptions:.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            AppEnvironment.shared.userNotificationActionHandler.handleNotificationResponse(response, completionHandler: completionHandler)
        }
    }

    /// The method will be called on the delegate when the application is launched in response to the user's request to view in-app
    /// notification settings. Add UNAuthorizationOptionProvidesAppNotificationSettings as an option in
    /// requestAuthorizationWithOptions:completionHandler: to add a button to inline notification settings view and the notification
    /// settings view in Settings. The notification will be nil when opened from Settings.
    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
    }
    
    // MARK: - Notification Handling
    
    @objc private func registrationStateDidChange() {
        handleActivation()
    }
    
    @objc public func showMissedCallTipsIfNeeded(_ notification: Notification) {
        guard !UserDefaults.standard[.hasSeenCallMissedTips] else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                self.showMissedCallTipsIfNeeded(notification)
            }
            return
        }
        guard let callerId: String = notification.userInfo?[Notification.Key.senderId.rawValue] as? String else {
            return
        }
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() }
        
        let callMissedTipsModal: CallMissedTipsModal = CallMissedTipsModal(
            caller: Profile.displayName(id: callerId)
        )
        presentingVC.present(callMissedTipsModal, animated: true, completion: nil)
        
        UserDefaults.standard[.hasSeenCallMissedTips] = true
    }
    
    // MARK: - Polling
    
    public func startPollersIfNeeded(shouldStartGroupPollers: Bool = true) {
        guard Identity.userExists() else { return }
        
        poller.startIfNeeded()
        
        guard shouldStartGroupPollers else { return }
        
        ClosedGroupPoller.shared.start()
        OpenGroupManager.shared.startPolling()
    }
    
    public func stopPollers(shouldStopUserPoller: Bool = true) {
        if shouldStopUserPoller {
            poller.stop()
        }
        
        ClosedGroupPoller.shared.stopAllPollers()
        OpenGroupManager.shared.stopPolling()
    }
    
    // MARK: - App Mode

    private func adapt(appMode: AppMode) {
        // FIXME: Need to update this when an appropriate replacement is added (see https://teng.pub/technical/2021/11/9/uiapplication-key-window-replacement)
        guard let window: UIWindow = UIApplication.shared.keyWindow else { return }
        
        switch (appMode) {
            case .light:
                window.overrideUserInterfaceStyle = .light
                window.backgroundColor = .white
            
            case .dark:
                window.overrideUserInterfaceStyle = .dark
                window.backgroundColor = .black
        }
        
        if LKAppModeUtilities.isSystemDefault {
            window.overrideUserInterfaceStyle = .unspecified
        }
        
        NotificationCenter.default.post(name: .appModeChanged, object: nil)
    }
    
    func setCurrentAppMode(to appMode: AppMode) {
        UserDefaults.standard[.appMode] = appMode.rawValue
        adapt(appMode: appMode)
    }
    
    func setAppModeToSystemDefault() {
        UserDefaults.standard.removeObject(forKey: SNUserDefaults.Int.appMode.rawValue)
        adapt(appMode: AppModeManager.getAppModeOrSystemDefault())
    }
    
    // MARK: - App Link

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        guard let components: URLComponents = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return false
        }
        
        // URL Scheme is sessionmessenger://DM?sessionID=1234
        // We can later add more parameters like message etc.
        if components.host == "DM" {
            let matches: [URLQueryItem] = (components.queryItems ?? [])
                .filter { item in item.name == "sessionID" }
            
            if let sessionId: String = matches.first?.value {
                createNewDMFromDeepLink(sessionId: sessionId)
                return true
            }
        }
        
        return false
    }

    private func createNewDMFromDeepLink(sessionId: String) {
        guard let homeViewController: HomeVC = (window?.rootViewController as? OWSNavigationController)?.visibleViewController as? HomeVC else {
            return
        }
        
        homeViewController.createNewDMFromDeepLink(sessionID: sessionId)
    }
        
    // MARK: - Call handling
        
    func hasIncomingCallWaiting() -> Bool {
        guard let call = AppEnvironment.shared.callManager.currentCall else { return false }
        
        return !call.hasStartedConnecting
    }
    
    func hasCallOngoing() -> Bool {
        guard let call = AppEnvironment.shared.callManager.currentCall else { return false }
        
        return !call.hasEnded
    }
    
    func handleAppActivatedWithOngoingCallIfNeeded() {
        guard
            let call: SessionCall = (AppEnvironment.shared.callManager.currentCall as? SessionCall),
            MiniCallView.current == nil
        else { return }
        
        if let callVC = CurrentAppContext().frontmostViewController() as? CallVC, callVC.call.uuid == call.uuid {
            return
        }
        
        // FIXME: Handle more gracefully
        guard let presentingVC = CurrentAppContext().frontmostViewController() else { preconditionFailure() }
        
        let callVC: CallVC = CallVC(for: call)
        
        if let conversationVC: ConversationVC = presentingVC as? ConversationVC, conversationVC.viewModel.threadData.threadId == call.sessionId {
            callVC.conversationVC = conversationVC
            conversationVC.inputAccessoryView?.isHidden = true
            conversationVC.inputAccessoryView?.alpha = 0
        }
        
        presentingVC.present(callVC, animated: true, completion: nil)
    }
    
    // MARK: - Config Sync
    
    func syncConfigurationIfNeeded() {
        let lastSync: Date = (UserDefaults.standard[.lastConfigurationSync] ?? .distantPast)
        
        guard Date().timeIntervalSince(lastSync) > (7 * 24 * 60 * 60) else { return } // Sync every 2 days
        
        Storage.shared
            .writeAsync { db in try MessageSender.syncConfiguration(db, forceSyncNow: false) }
            .done {
                // Only update the 'lastConfigurationSync' timestamp if we have done the
                // first sync (Don't want a new device config sync to override config
                // syncs from other devices)
                if UserDefaults.standard[.hasSyncedInitialConfiguration] {
                    UserDefaults.standard[.lastConfigurationSync] = Date()
                }
            }
            .retainUntilComplete()
    }
}
