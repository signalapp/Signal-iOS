//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

class NotificationServiceExtensionContext: NSObject, AppContext {
    let isMainApp = false
    let isMainAppAndActive = false

    func isInBackground() -> Bool { true }
    func isAppForegroundAndActive() -> Bool { false }
    func mainApplicationStateOnLaunch() -> UIApplication.State { .inactive }
    var shouldProcessIncomingMessages: Bool { true }
    var hasUI: Bool { false }
    func canPresentNotifications() -> Bool { true }
    var didLastLaunchNotTerminate: Bool { false }

    let appLaunchTime = Date()
    lazy var buildTime: Date = {
        guard let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "BuildTimestamp") as? TimeInterval, buildTimestamp > 0 else {
            Logger.debug("No build timestamp, assuming app never expires.")
            return .distantFuture
        }

        return .init(timeIntervalSince1970: buildTimestamp)
    }()

    func keychainStorage() -> SSKKeychainStorage {
        return SSKDefaultKeychainStorage.shared
    }

    func appDocumentDirectoryPath() -> String {
        guard let documentDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last else {
            owsFail("failed to query document directory")
        }
        return documentDirectoryURL.path
    }

    func appSharedDataDirectoryPath() -> String {
        guard let groupContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup) else {
            owsFail("failed to query group container")
        }
        return groupContainerURL.path
    }

    func appDatabaseBaseDirectoryPath() -> String {
        return appSharedDataDirectoryPath()
    }

    func appUserDefaults() -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: TSConstants.applicationGroup) else {
            owsFail("failed to initialize user defaults")
        }
        return userDefaults
    }

    override init() { super.init() }

    // MARK: - Unused in this extension

    let isRTL = false
    let isRunningTests = false

    var mainWindow: UIWindow?
    let frame: CGRect = .zero
    let interfaceOrientation: UIInterfaceOrientation = .unknown
    let reportedApplicationState: UIApplication.State = .background
    let statusBarHeight: CGFloat = .zero

    func beginBackgroundTask(expirationHandler: @escaping BackgroundTaskExpirationHandler) -> UInt { 0 }
    func endBackgroundTask(_ backgroundTaskIdentifier: UInt) {}

    func beginBackgroundTask(expirationHandler: @escaping BackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier { .invalid }
    func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier) {}

    func ensureSleepBlocking(_ shouldBeBlocking: Bool, blockingObjectsDescription: String) {}

    func setMainAppBadgeNumber(_ value: Int) {}
    func setStatusBarHidden(_ isHidden: Bool, animated isAnimated: Bool) {}

    func frontmostViewController() -> UIViewController? { nil }
    func openSystemSettings() {}
    func openSystemSettingsAction(completion: (() -> Void)? = nil) -> ActionSheetAction? { nil }

    func setNetworkActivityIndicatorVisible(_ value: Bool) {}

    func runNowOr(whenMainAppIsActive block: @escaping AppActiveBlock) {}

    var debugLogsDirPath: String {
        DebugLogger.nseDebugLogsDirPath
    }
}
