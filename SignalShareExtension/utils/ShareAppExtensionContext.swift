//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// This is _NOT_ a singleton and will be instantiated each time that the SAE is used.
final class ShareAppExtensionContext: NSObject {

    private let rootViewController: UIViewController

    var mainWindow: UIWindow?

    @Atomic private var internalReportedApplicationState: UIApplication.State = .active

    let appLaunchTime = Date()

    let appForegroundTime = Date()

    private var notificationCenterObservers = [NSObjectProtocol]()

    static private let isRTL: Bool = {
        // Borrowed from PureLayout's AppExtension compatible RTL support.
        // App Extensions may not access UIApplication.sharedApplication.
        // Fall back to checking the bundle's preferred localization character direction
        guard let language = Bundle.main.preferredLocalizations.first else { return false }
        return NSLocale.characterDirection(forLanguage: language) == .rightToLeft
    }()

    init(rootViewController: UIViewController) {
        self.rootViewController = rootViewController

        super.init()

        let mainQueue = OperationQueue.main
        notificationCenterObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSExtensionHostDidBecomeActive,
            object: nil,
            queue: mainQueue) { [weak self] notification in
                Logger.info("")
                self?.internalReportedApplicationState = .active
                BenchManager.bench(
                    title: "Slow post DidBecomeActive",
                    logIfLongerThan: 0.01,
                    logInProduction: true) {
                        NotificationCenter.default.post(name: NSNotification.Name.OWSApplicationDidBecomeActive, object: nil)
                    }
            }
        )
        notificationCenterObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSExtensionHostWillResignActive,
            object: nil,
            queue: mainQueue) { [weak self] notification in
                Logger.info("")
                self?.internalReportedApplicationState = .inactive
                BenchManager.bench(
                    title: "Slow post WillResignActive",
                    logIfLongerThan: 0.01,
                    logInProduction: true) {
                        NotificationCenter.default.post(name: NSNotification.Name.OWSApplicationWillResignActive, object: nil)
                    }
            }
        )
        notificationCenterObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSExtensionHostDidEnterBackground,
            object: nil,
            queue: mainQueue) { [weak self] notification in
                Logger.info("")
                self?.internalReportedApplicationState = .background
                BenchManager.bench(
                    title: "Slow post DidEnterBackground",
                    logIfLongerThan: 0.01,
                    logInProduction: true) {
                        NotificationCenter.default.post(name: NSNotification.Name.OWSApplicationDidEnterBackground, object: nil)
                    }
            }
        )
        notificationCenterObservers.append(NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSExtensionHostWillEnterForeground,
            object: nil,
            queue: mainQueue) { [weak self] notification in
                Logger.info("")
                self?.internalReportedApplicationState = .inactive
                BenchManager.bench(
                    title: "Slow post WillEnterForeground",
                    logIfLongerThan: 0.01,
                    logInProduction: true) {
                        NotificationCenter.default.post(name: NSNotification.Name.OWSApplicationWillEnterForeground, object: nil)
                    }
            }
        )
    }

    deinit {
        notificationCenterObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

extension ShareAppExtensionContext: AppContext {

    var isMainApp: Bool { false }

    var isMainAppAndActive: Bool { false }

    var isNSE: Bool { false }

    var isRTL: Bool { Self.isRTL }

    var isRunningTests: Bool { false }

    var frame: CGRect { rootViewController.view.frame }

    var interfaceOrientation: UIInterfaceOrientation { .portrait }

    var reportedApplicationState: UIApplication.State {
        internalReportedApplicationState
    }

    func isInBackground() -> Bool {
        return reportedApplicationState == .background
    }

    func isAppForegroundAndActive() -> Bool {
        return reportedApplicationState == .active
    }

    func beginBackgroundTask(expirationHandler: @escaping BackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier {
        return .invalid
    }

    func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier) {
        owsAssertBeta(backgroundTaskIdentifier == .invalid)
    }

    func ensureSleepBlocking(_ shouldBeBlocking: Bool, blockingObjectsDescription: String) {
        Logger.debug("Ignoring request to block sleep.")
    }

    var statusBarHeight: CGFloat { 20 }

    func frontmostViewController() -> UIViewController? {
        return rootViewController.findFrontmostViewController(ignoringAlerts: true)
    }

    func openSystemSettings() { }

    func open(_ url: URL, completion: ((Bool) -> Void)? = nil) { }

    func runNowOr(whenMainAppIsActive block: @escaping AppActiveBlock) {
        owsFailBeta("Cannot run main app active blocks in share extension.")
    }

    func keychainStorage() -> SignalServiceKit.SSKKeychainStorage {
        SSKDefaultKeychainStorage.shared
    }

    func appDocumentDirectoryPath() -> String {
        guard let documentDirectoryURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).last
        else {
            owsFail("Could not find documents directory.")
        }
        return documentDirectoryURL.path
    }

    func appSharedDataDirectoryPath() -> String {
        guard let groupContainerDirectoryURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup
        )
        else {
            owsFail("Could not find application group directory.")
        }
        return groupContainerDirectoryURL.path
    }

    func appDatabaseBaseDirectoryPath() -> String {
        appSharedDataDirectoryPath()
    }

    func appUserDefaults() -> UserDefaults {
        return UserDefaults(suiteName: TSConstants.applicationGroup)!
    }

    func mainApplicationStateOnLaunch() -> UIApplication.State {
        owsFailBeta("Not main app.")
        return .inactive
    }

    func canPresentNotifications() -> Bool { false }

    var shouldProcessIncomingMessages: Bool { false }

    var hasUI: Bool { true }

    var debugLogsDirPath: String { DebugLogger.shareExtensionDebugLogsDirPath }

    var hasActiveCall: Bool { false }

    func resetAppDataAndExit() {
        owsFailBeta("Not main app.")
    }
}
