//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

import SignalMessaging
import PureLayout
import SignalServiceKit

@objc
public class ShareViewController: UINavigationController, SAELoadViewDelegate {

    private var contactsSyncing: OWSContactsSyncing?

    private var hasInitialRootViewController = false

    override open func loadView() {
        super.loadView()

        Logger.debug("\(self.logTag()) \(#function)")

        // This should be the first thing we do.
        SetCurrentAppContext(ShareAppExtensionContext(rootViewController:self))

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if (OWSPreferences.isLoggingEnabled()) {
            // TODO: Consult OWSPreferences.isLoggingEnabled.
            DebugLogger.shared().enableFileLogging()
        }

        _ = AppVersion()

        startupLogging()

        SetRandFunctionSeed()

        // We don't need to use DeviceSleepManager in the SAE.

        setupEnvironment()

        // TODO:
        //        [UIUtil applySignalAppearence];

        if CurrentAppContext().isRunningTests() {
            // TODO: Do we need to implement isRunningTests in the SAE context?
            return
        }

        // performUpdateCheck must be invoked after Environment has been initialized because
        // upgrade process may depend on Environment.
        VersionMigrations.performUpdateCheck()

        let loadViewController = SAELoadViewController(delegate:self)
        self.pushViewController(loadViewController, animated: false)
        self.isNavigationBarHidden = false

        // We don't need to use "screen protection" in the SAE.

        contactsSyncing = OWSContactsSyncing(contactsManager:Environment.current().contactsManager,
                                             identityManager:OWSIdentityManager.shared(),
                                             messageSender:Environment.current().messageSender,
                                             profileManager:OWSProfileManager.shared())

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(databaseViewRegistrationComplete),
                                               name: .DatabaseViewRegistrationComplete,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .RegistrationStateDidChange,
                                               object: nil)

        Logger.info("\(self.logTag) application: didFinishLaunchingWithOptions completed.")

        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.activate()
        }

        OWSAnalytics.appLaunchDidBegin()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func activate() {
        Logger.debug("\(self.logTag()) \(#function)")

        // We don't need to use "screen protection" in the SAE.

        ensureRootViewController()

        // Always check prekeys after app launches, and sometimes check on app activation.
        TSPreKeyManager.checkPreKeysIfNecessary()

        // We don't call RTCInitializeSSL() since we don't do calling in the SAE.

        if TSAccountManager.isRegistered() {
            // At this point, potentially lengthy DB locking migrations could be running.
            // Avoid blocking app launch by putting all further possible DB access in async block
            DispatchQueue.global().async { [weak self] in
                guard let strongSelf = self else { return }
                Logger.info("\(strongSelf.logTag) running post launch block for registered user: \(TSAccountManager.localNumber)")

                // We don't need to start OWSDisappearingMessagesJob since we
                // don't display messages in the SAE.

                // TODO remove this once we're sure our app boot process is coherent.
                // Currently this happens *before* db registration is complete when
                // launching the app directly, but *after* db registration is complete when
                // the app is launched in the background, e.g. from a voip notification.
                OWSProfileManager.shared().ensureLocalProfileCached()

                // We don't need to start OWSFailedMessagesJob since we
                // don't display messages in the SAE.

                // We don't need to start OWSFailedAttachmentDownloadsJob since we
                // don't display messages in the SAE.
            }
        } else {
            Logger.info("\(self.logTag) running post launch block for unregistered user.")

            // We don't need to update the app icon badge number.

            // We don't need to prod the TSSocketManager.
        }
        // end dispatchOnce for first time we become active

        // TODO: Move this logic into the notification handler for "SAE will appear".
        if TSAccountManager.isRegistered() {
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                Logger.info("\(strongSelf.logTag) running post launch block for registered user: \(TSAccountManager.localNumber)")

                // We don't need to prod the TSSocketManager.

                Environment.current().contactsManager.fetchSystemContactsOnceIfAlreadyAuthorized()

                // We don't need to fetch messages in the SAE.

                // We don't need to use OWSSyncPushTokensJob in the SAE.
            }
        }
    }

    //    - (void)applicationWillResignActive:(UIApplication *)application {
    //    DDLogWarn(@"%@ applicationWillResignActive.", self.logTag);
    //
    //    UIBackgroundTaskIdentifier bgTask = [application beginBackgroundTaskWithExpirationHandler:nil];
    //    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    //    if ([TSAccountManager isRegistered]) {
    //    dispatch_async(dispatch_get_main_queue(), ^{
    //    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
    //    // If app has not re-entered active, show screen protection if necessary.
    //    [self showScreenProtection];
    //    }
    //    [SignalApp.sharedApp.homeViewController updateInboxCountLabel];
    //    [application endBackgroundTask:bgTask];
    //    });
    //    }
    //    });
    //
    //    [DDLog flushLog];
    //    }

    @objc
    func databaseViewRegistrationComplete() {
        AssertIsOnMainThread()

        Logger.debug("\(self.logTag()) \(#function)")

        if TSAccountManager.isRegistered() {
            Logger.info("\(self.logTag) localNumber: \(TSAccountManager.localNumber)")

            // We don't need to use messageFetcherJob in the SAE.

            // We don't need to use SyncPushTokensJob in the SAE.
        }

        // We don't need to use DeviceSleepManager in the SAE.

        // TODO: Should we distinguish main app and SAE "completion"?
        AppVersion.instance().appLaunchDidComplete()

        ensureRootViewController()

        // We don't need to use OWSMessageReceiver in the SAE.
        // We don't need to use OWSBatchMessageProcessor in the SAE.

        OWSProfileManager.shared().ensureLocalProfileCached()

        // TODO:
        //    self.isEnvironmentSetup = YES;

        // We don't need to use OWSOrphanedDataCleaner in the SAE.

        //[OWSProfileManager.sharedManager fetchLocalUsersProfile];
        //[[OWSReadReceiptManager sharedManager] prepareCachedValues];
        //[[Environment current].contactsManager loadLastKnownContactRecipientIds];
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        Logger.debug("\(self.logTag()) \(#function)")

        if TSAccountManager.isRegistered() {
            Logger.info("\(self.logTag) localNumber: \(TSAccountManager.localNumber)")

            // We don't need to use ExperienceUpgradeFinder in the SAE.

            // We don't need to use OWSDisappearingMessagesJob in the SAE.

            OWSProfileManager.shared().ensureLocalProfileCached()
        }
    }

    private func ensureRootViewController() {
        Logger.debug("\(self.logTag()) \(#function)")

        guard !TSDatabaseView.hasPendingViewRegistrations() else {
            return
        }
        guard !hasInitialRootViewController else {
            return
        }
        hasInitialRootViewController = true

        Logger.info("Presenting initial root view controller")

        if TSAccountManager.isRegistered() {
            //                HomeViewController *homeView = [HomeViewController new];
            //                SignalsNavigationController *navigationController =
            //                    [[SignalsNavigationController alloc] initWithRootViewController:homeView];
            //                self.window.rootViewController = navigationController;
        } else {
            //                RegistrationViewController *viewController = [RegistrationViewController new];
            //                OWSNavigationController *navigationController =
            //                    [[OWSNavigationController alloc] initWithRootViewController:viewController];
            //                navigationController.navigationBarHidden = YES;
            //                self.window.rootViewController = navigationController;
        }

        // We don't use the AppUpdateNag in the SAE.
    }

    func startupLogging() {
        Logger.info("iOS Version: \(UIDevice.current.systemVersion)}")

        let locale = NSLocale.current as NSLocale
        if let localeIdentifier = locale.object(forKey:NSLocale.Key.identifier) as? String,
            localeIdentifier.count > 0 {
            Logger.info("Locale Identifier: \(localeIdentifier)")
        } else {
            owsFail("Locale Identifier: Unknown")
        }
        if let countryCode = locale.object(forKey:NSLocale.Key.countryCode) as? String,
            countryCode.count > 0 {
            Logger.info("Country Code: \(countryCode)")
        } else {
            owsFail("Country Code: Unknown")
        }
        if let languageCode = locale.object(forKey:NSLocale.Key.languageCode) as? String,
            languageCode.count > 0 {
            Logger.info("Language Code: \(languageCode)")
        } else {
            owsFail("Language Code: Unknown")
        }
    }

    func setupEnvironment() {
        let environment = Release.releaseEnvironment()
        Environment.setCurrent(environment)

        // Encryption/Decryption mutates session state and must be synchronized on a serial queue.
        SessionCipher.setSessionCipherDispatchQueue(OWSDispatch.sessionStoreQueue())

        let sharedEnv = TextSecureKitEnv(callMessageHandler:SAECallMessageHandler(),
                                         contactsManager:Environment.current().contactsManager,
                                         messageSender:Environment.current().messageSender,
                                         notificationsManager:SAENotificationsManager(),
                                         profileManager:OWSProfileManager.shared())
        TextSecureKitEnv.setShared(sharedEnv)

        TSStorageManager.shared().setupDatabase(safeBlockingMigrations: {
            VersionMigrations.runSafeBlockingMigrations()
        })

        Environment.current().contactsManager.startObserving()
    }

    // MARK: View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()

        Logger.debug("\(self.logTag()) \(#function)")
    }

    override open func viewWillAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewWillAppear(animated)
    }

    override open func viewDidAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewDidAppear(animated)
    }

    // MARK: SAELoadViewDelegate

    public func shareExtensionWasCancelled() {
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }
}
