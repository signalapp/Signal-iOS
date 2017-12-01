//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

import SignalMessaging
import PureLayout
import SignalServiceKit

class ShareViewController: UINavigationController, SAELoadViewDelegate {

    override func loadView() {
        super.loadView()

        // This should be the first thing we do.
        SetCurrentAppContext(ShareAppExtensionContext())

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

        // XXX - careful when moving this. It must happen before we initialize TSStorageManager.
        TSStorageManager.verifyDBKeysAvailableBeforeBackgroundLaunch()

//        // Prevent the device from sleeping during database view async registration
//        // (e.g. long database upgrades).
//        //
//        // This block will be cleared in databaseViewRegistrationComplete.
//        [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];
//
//        [self setupEnvironment];
//
//        [UIUtil applySignalAppearence];
//
//        if (getenv("runningTests_dontStartApp")) {
//            return YES;
//        }
//
//        self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
//
//        // Show the launch screen until the async database view registrations are complete.
//        self.window.rootViewController = [self loadingRootViewController];
//
//        [self.window makeKeyAndVisible];
//
//        // performUpdateCheck must be invoked after Environment has been initialized because
//        // upgrade process may depend on Environment.
//        [VersionMigrations performUpdateCheck];
//
//        // Accept push notification when app is not open
//        NSDictionary *remoteNotif = launchOptions[UIApplicationLaunchOptionsRemoteNotificationKey];
//        if (remoteNotif) {
//            DDLogInfo(@"Application was launched by tapping a push notification.");
//            [self application:application didReceiveRemoteNotification:remoteNotif];
//        }
//
//        [self prepareScreenProtection];
//
//        self.contactsSyncing = [[OWSContactsSyncing alloc] initWithContactsManager:[Environment getCurrent].contactsManager
//            identityManager:[OWSIdentityManager sharedManager]
//            messageSender:[Environment getCurrent].messageSender
//            profileManager:[OWSProfileManager sharedManager]];
//
//        [[NSNotificationCenter defaultCenter] addObserver:self
//            selector:@selector(databaseViewRegistrationComplete)
//            name:kNSNotificationName_DatabaseViewRegistrationComplete
//            object:nil];
//        [[NSNotificationCenter defaultCenter] addObserver:self
//            selector:@selector(registrationStateDidChange)
//            name:kNSNotificationName_RegistrationStateDidChange
//            object:nil];
//
//        DDLogInfo(@"%@ application: didFinishLaunchingWithOptions completed.", self.logTag);
//
//        [OWSAnalytics appLaunchDidBegin];
//
//        return YES;

        Logger.debug("\(self.logTag()) \(#function)")

        let loadViewController = SAELoadViewController(delegate:self)
        self.pushViewController(loadViewController, animated: false)
        self.isNavigationBarHidden = false
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
        [Environment setCurrent:[Release releaseEnvironment]]

//        // Encryption/Descryption mutates session state and must be synchronized on a serial queue.
//        [SessionCipher setSessionCipherDispatchQueue:[OWSDispatch sessionStoreQueue]];
//
//        TextSecureKitEnv *sharedEnv =
//            [[TextSecureKitEnv alloc] initWithCallMessageHandler:[Environment getCurrent].callMessageHandler
//                contactsManager:[Environment getCurrent].contactsManager
//                messageSender:[Environment getCurrent].messageSender
//                notificationsManager:[Environment getCurrent].notificationsManager
//                profileManager:OWSProfileManager.sharedManager];
//        [TextSecureKitEnv setSharedEnv:sharedEnv];
//
//        [[TSStorageManager sharedManager] setupDatabaseWithSafeBlockingMigrations:^{
//            [VersionMigrations runSafeBlockingMigrations];
//            }];
//        [[Environment getCurrent].contactsManager startObserving];
    }

    // MARK: View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        let proofOfSharedFramework = StorageCoordinator.shared.path
        let proofOfSSK = textSecureServerURL

        // TODO: Shared Storage via app container
        //let proofOfSharedStorage = TSAccountManager.localNumber()
        let proofOfSharedStorage = "TODO"

        Logger.debug("shared framework: \(proofOfSharedFramework) \n sharedStorage: \(proofOfSharedStorage) \n proof of ssk: \(proofOfSSK)")

        Logger.debug("\(self.logTag()) \(#function)")
    }

    override func viewWillAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewDidAppear(animated)
    }

    // MARK: SAELoadViewDelegate

    public func shareExtensionWasCancelled() {
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }
}
