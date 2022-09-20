// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SignalUtilitiesKit
import SessionUtilitiesKit
import SessionMessagingKit

/// This is _NOT_ a singleton and will be instantiated each time that the SAE is used.
final class ShareAppExtensionContext: NSObject, AppContext {
    var rootViewController: UIViewController
    var reportedApplicationState: UIApplication.State
    
    let appLaunchTime = Date()
    let isMainApp = false
    let isMainAppAndActive = false
    var isShareExtension: Bool = true
    
    var mainWindow: UIWindow?
    var wasWokenUpByPushNotification: Bool = false
    
    private static var _isRTL: Bool = {
        // Borrowed from PureLayout's AppExtension compatible RTL support.
        // App Extensions may not access -[UIApplication sharedApplication]; fall back
        // to checking the bundle's preferred localization character direction
        return (
            Locale.characterDirection(
                forLanguage: (Bundle.main.preferredLocalizations.first ?? "")
            ) == Locale.LanguageDirection.rightToLeft
        )
    }()

    var isRTL: Bool { return ShareAppExtensionContext._isRTL }
    var isRunningTests: Bool { return false } // We don't need to distinguish this in the SAE
    
    var statusBarHeight: CGFloat { return 20 }
    var openSystemSettingsAction: UIAlertAction?
    
    // MARK: - Initialization

    init(rootViewController: UIViewController) {
        self.rootViewController = rootViewController
        self.reportedApplicationState = .active
        
        super.init()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(extensionHostDidBecomeActive(notification:)),
            name: .NSExtensionHostDidBecomeActive,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(extensionHostWillResignActive(notification:)),
            name: .NSExtensionHostWillResignActive,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(extensionHostDidEnterBackground(notification:)),
            name: .NSExtensionHostDidEnterBackground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(extensionHostWillEnterForeground(notification:)),
            name: .NSExtensionHostWillEnterForeground,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Notifications
    
    @objc private func extensionHostDidBecomeActive(notification: NSNotification) {
        AssertIsOnMainThread()
        OWSLogger.info("")

        self.reportedApplicationState = .active
        
        NotificationCenter.default.post(
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
    }
    
    @objc private func extensionHostWillResignActive(notification: NSNotification) {
        AssertIsOnMainThread()

        self.reportedApplicationState = .inactive
        
        OWSLogger.info("")
        DDLog.flushLog()

        NotificationCenter.default.post(
            name: .OWSApplicationWillResignActive,
            object: nil
        )
    }

    @objc private func extensionHostDidEnterBackground(notification: NSNotification) {
        AssertIsOnMainThread()
        
        OWSLogger.info("")
        DDLog.flushLog()

        self.reportedApplicationState = .background

        NotificationCenter.default.post(
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
    }

    @objc private func extensionHostWillEnterForeground(notification: NSNotification) {
        AssertIsOnMainThread()
        
        OWSLogger.info("")

        self.reportedApplicationState = .inactive

        NotificationCenter.default.post(
            name: .OWSApplicationWillEnterForeground,
            object: nil
        )
    }
    
    // MARK: - AppContext Functions
    
    func isAppForegroundAndActive() -> Bool {
        return (reportedApplicationState == .active)
    }
    
    func isInBackground() -> Bool {
        return (reportedApplicationState == .background)
    }
    
    func frontmostViewController() -> UIViewController? {
        return rootViewController.findFrontmostViewController(ignoringAlerts: true)
    }
    
    func appDocumentDirectoryPath() -> String {
        let targetPath: String? = FileManager.default
            .urls(
                for: .documentDirectory,
                in: .userDomainMask
            )
            .last?
            .path
        owsAssertDebug(targetPath != nil)
        
        return (targetPath ?? "")
    }
    
    func appSharedDataDirectoryPath() -> String {
        let targetPath: String? = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SignalApplicationGroup)?
            .path
        owsAssertDebug(targetPath != nil)
        
        return (targetPath ?? "")
    }
    
    func appUserDefaults() -> UserDefaults {
        let targetUserDefaults: UserDefaults? = UserDefaults(suiteName: SignalApplicationGroup)
        owsAssertDebug(targetUserDefaults != nil)
        
        return (targetUserDefaults ?? UserDefaults.standard)
    }
    
    func setStatusBarHidden(_ isHidden: Bool, animated isAnimated: Bool) {
        OWSLogger.info("Ignoring request to show/hide status bar since we're in an app extension")
    }
    
    func beginBackgroundTask(expirationHandler: @escaping BackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier {
        return .invalid
    }
    
    func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier) {
        owsAssertDebug(backgroundTaskIdentifier == .invalid)
    }
    
    func ensureSleepBlocking(_ shouldBeBlocking: Bool, blockingObjects: [Any]) {
        OWSLogger.debug("Ignoring request to block sleep.")
    }
    
    func setMainAppBadgeNumber(_ value: Int) {
        owsFailDebug("")
    }
    
    func setNetworkActivityIndicatorVisible(_ value: Bool) {
        owsFailDebug("")
    }
    
    func runNowOr(whenMainAppIsActive block: @escaping AppActiveBlock) {
        owsFailDebug("cannot run main app active blocks in share extension.")
    }
}
