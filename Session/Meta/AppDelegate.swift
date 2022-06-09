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
        let loadingViewController: LoadingViewController = LoadingViewController()
        
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
            migrationProgressChanged: { progress, minEstimatedTotalTime in
                loadingViewController.updateProgress(
                    progress: progress,
                    minEstimatedTotalTime: minEstimatedTotalTime
                )
            },
            migrationsCompletion: { [weak self] successful, needsConfigSync in
                guard let strongSelf = self else { return }
                guard successful else {
                    self?.showFailedMigrationAlert()
                    return
                }
                
                Configuration.performMainSetup()
                JobRunner.add(executor: SyncPushTokensJob.self, for: .syncPushTokens)
                
                // Trigger any launch-specific jobs and start the JobRunner
                JobRunner.appDidFinishLaunching()
                
                // Note that this does much more than set a flag;
                // it will also run all deferred blocks (including the JobRunner
                // 'appDidBecomeActive' method)
                AppReadiness.setAppIsReady()
                
                DeviceSleepManager.sharedInstance.removeBlock(blockObject: strongSelf)
                AppVersion.sharedInstance().mainAppLaunchDidComplete()
                Environment.shared.audioSession.setup()
                Environment.shared.reachabilityManager.setup()
                
                GRDBStorage.shared.writeAsync { db in
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
                
                // Setup the UI
                self?.ensureRootViewController()
            }
        )
        
        SNAppearance.switchToSessionAppearance()
        
        // No point continuing if we are running tests
        guard !CurrentAppContext().isRunningTests else { return true }

        self.window = mainWindow
        CurrentAppContext().mainWindow = mainWindow
        
        // Show LoadingViewController until the async database view registrations are complete.
        mainWindow.rootViewController = loadingViewController
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
            selector: #selector(handleDataNukeRequested),   // TODO: This differently???
            name: .dataNukeRequested,
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
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        DDLog.flushLog()
        
        // NOTE: Fix an edge case where user taps on the callkit notification
        // but answers the call on another device
        stopPollers(shouldStopUserPoller: !self.hasIncomingCallWaiting())
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Logger.info("applicationDidReceiveMemoryWarning")
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        DDLog.flushLog()
        
        stopPollers()
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !CurrentAppContext().isRunningTests else { return }
        
        UserDefaults.sharedLokiProject?[.isMainAppActive] = true
        
        ensureRootViewController()
        adapt(appMode: AppModeManager.getAppModeOrSystemDefault())

        AppReadiness.runNowOrWhenAppDidBecomeReady { [weak self] in
            self?.handleActivation()
        }

        // Clear all notifications whenever we become active.
        // When opening the app from a notification,
        // AppDelegate.didReceiveLocalNotification will always
        // be called _before_ we become active.
        clearAllNotificationsAndRestoreBadgeCount()

        // On every activation, clear old temp directories.
        ClearOldTemporaryDirectories();
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
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            BackgroundPoller.poll(completionHandler: completionHandler)
        }
    }
    
    // MARK: - App Readiness
    
    private func showFailedMigrationAlert() {
        let alert = UIAlertController(
            title: "Session",
            message: [
                "DATABASE_MIGRATION_FAILED".localized(),
                "modal_share_logs_explanation".localized()
            ].joined(separator: "\n\n"),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "modal_share_logs_title".localized(), style: .default) { _ in
            ShareLogsModal.shareLogs(from: alert) { [weak self] in
                self?.showFailedMigrationAlert()
            }
        })
        alert.addAction(UIAlertAction(title: "Close", style: .destructive) { _ in
            DDLog.flushLog()
            exit(0)
        })
        
        self.window?.rootViewController?.present(alert, animated: true, completion: nil)
    }
    
    /// The user must unlock the device once after reboot before the database encryption key can be accessed.
    private func verifyDBKeysAvailableBeforeBackgroundLaunch() {
        guard UIApplication.shared.applicationState == .background else { return }
        
        guard !GRDBStorage.isDatabasePasswordAccessible else { return }    // All good
        
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
    
    private func ensureRootViewController() {
        guard AppReadiness.isAppReady() && GRDBStorage.shared.isValid && !hasInitialRootViewController else {
            return
        }
        
        let navController: UINavigationController = OWSNavigationController(
            rootViewController: (Identity.userExists() ?
                HomeVC() :
                LandingVC()
            )
        )
        navController.isNavigationBarHidden = !(navController.viewControllers.first is HomeVC)
        self.window?.rootViewController = navController
        UIViewController.attemptRotationToDeviceOrientation()
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
                GRDBStorage.shared
                    .read { db in
                        let userPublicKey: String = getUserHexEncodedPublicKey(db)
                        let thread: TypedTableAlias<SessionThread> = TypedTableAlias()
                        
                        return try Interaction
                            .filter(Interaction.Columns.wasRead == false)
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
        enableBackgroundRefreshIfNecessary()

        guard Identity.userExists() else { return }
        
        startPollersIfNeeded()
    }
    
    @objc public func handleDataNukeRequested() {
        let isUsingFullAPNs: Bool = UserDefaults.standard[.isUsingFullAPNs]
        let maybeDeviceToken: String? = UserDefaults.standard[.deviceToken]
        // TODO: Clean up how this works
        if isUsingFullAPNs, let deviceToken: String = maybeDeviceToken {
            let data: Data = Data(hex: deviceToken)
            PushNotificationAPI.unregister(data).retainUntilComplete()
        }
        
        GRDBStorage.shared.write { db in
            _ = try SessionThread.deleteAll(db)
            _ = try Identity.deleteAll(db)
        }
        
        SnodeAPI.clearSnodePool()
        stopPollers()
        
        let wasUnlinked: Bool = UserDefaults.standard[.wasUnlinked]
        SessionApp.resetAppData {
            // Resetting the data clears the old user defaults. We need to restore the unlink default.
            UserDefaults.standard[.wasUnlinked] = wasUnlinked
        }
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
        
        ClosedGroupPoller.shared.stop()
        OpenGroupManager.shared.stopPolling()
    }
    
    // MARK: - App Mode

    private func adapt(appMode: AppMode) {
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
        
        GRDBStorage.shared.write { db in
            try MessageSender.syncConfiguration(db, forceSyncNow: false)
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

}
