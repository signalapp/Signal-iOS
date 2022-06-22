//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalUtilitiesKit

final class NotificationServiceExtensionContext : NSObject, AppContext {
    let appLaunchTime = Date()
    let isMainApp = false
    let isMainAppAndActive = false
    var isShareExtension: Bool = false

    var openSystemSettingsAction: UIAlertAction?
    var wasWokenUpByPushNotification = true

    var shouldProcessIncomingMessages: Bool { true }

    lazy var buildTime: Date = {
        guard let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "BuildTimestamp") as? TimeInterval, buildTimestamp > 0 else {
            SNLog("No build timestamp; assuming app never expires.")
            return .distantFuture
        }
        return .init(timeIntervalSince1970: buildTimestamp)
    }()

    override init() { super.init() }

    func canPresentNotifications() -> Bool { true }
    func isAppForegroundAndActive() -> Bool { false }
    func isInBackground() -> Bool { true }
    func mainApplicationStateOnLaunch() -> UIApplication.State { .inactive }

    func appDatabaseBaseDirectoryPath() -> String {
        return appSharedDataDirectoryPath()
    }

    func appDocumentDirectoryPath() -> String {
        guard let documentDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last else {
            preconditionFailure("Couldn't get document directory.")
        }
        return documentDirectoryURL.path
    }

    func appSharedDataDirectoryPath() -> String {
        guard let groupContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SignalApplicationGroup) else {
            preconditionFailure("Couldn't get shared data directory.")
        }
        return groupContainerURL.path
    }

    func appUserDefaults() -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: SignalApplicationGroup) else {
            preconditionFailure("Couldn't set up shared user defaults.")
        }
        return userDefaults
    }

    // MARK: - Currently Unused
    
    let frame = CGRect.zero
    let interfaceOrientation = UIInterfaceOrientation.unknown
    let isRTL = false
    let isRunningTests = false
    let reportedApplicationState = UIApplication.State.background
    let statusBarHeight = CGFloat.zero

    var mainWindow: UIWindow?

    func beginBackgroundTask(expirationHandler: @escaping BackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier { .invalid }
    func beginBackgroundTask(expirationHandler: @escaping BackgroundTaskExpirationHandler) -> UInt { 0 }
    func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier) { }
    func endBackgroundTask(_ backgroundTaskIdentifier: UInt) { }
    func ensureSleepBlocking(_ shouldBeBlocking: Bool, blockingObjects: [Any]) { }
    func ensureSleepBlocking(_ shouldBeBlocking: Bool, blockingObjectsDescription: String) { }
    func frontmostViewController() -> UIViewController? { nil }
    func runNowOr(whenMainAppIsActive block: @escaping AppActiveBlock) { }
    func setMainAppBadgeNumber(_ value: Int) { }
    func setNetworkActivityIndicatorVisible(_ value: Bool) { }
    func setStatusBarHidden(_ isHidden: Bool, animated isAnimated: Bool) { }
}
