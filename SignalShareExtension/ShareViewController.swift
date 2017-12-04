//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

import SignalMessaging
import PureLayout
import SignalServiceKit

@objc
public class ShareViewController: UINavigationController, SAELoadViewDelegate {

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

        // XXX - careful when moving this. It must happen before we initialize TSStorageManager.
        TSStorageManager.verifyDBKeysAvailableBeforeBackgroundLaunch()

        // TODO:
//        // Prevent the device from sleeping during database view async registration
//        // (e.g. long database upgrades).
//        //
//        // This block will be cleared in databaseViewRegistrationComplete.
//        [DeviceSleepManager.sharedInstance addBlockWithBlockObject:self];

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

        // TODO:
//        [self prepareScreenProtection];

        // TODO:
//        self.contactsSyncing = [[OWSContactsSyncing alloc] initWithContactsManager:[Environment current].contactsManager
//            identityManager:[OWSIdentityManager sharedManager]
//            messageSender:[Environment current].messageSender
//            profileManager:[OWSProfileManager sharedManager]];

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(databaseViewRegistrationComplete),
                                               name: .DatabaseViewRegistrationComplete,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .RegistrationStateDidChange,
                                               object: nil)

        Logger.info("\(self.logTag) application: didFinishLaunchingWithOptions completed.")

        OWSAnalytics.appLaunchDidBegin()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc
    func databaseViewRegistrationComplete() {
        AssertIsOnMainThread()

        Logger.debug("\(self.logTag()) \(#function)")

        // TODO:
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        Logger.debug("\(self.logTag()) \(#function)")

        // TODO:
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

        let proofOfSharedFramework = StorageCoordinator.shared.path
        let proofOfSSK = textSecureServerURL

        // TODO: Shared Storage via app container
        //let proofOfSharedStorage = TSAccountManager.localNumber()
        let proofOfSharedStorage = "TODO"

        Logger.debug("shared framework: \(proofOfSharedFramework) \n sharedStorage: \(proofOfSharedStorage) \n proof of ssk: \(proofOfSSK)")

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
