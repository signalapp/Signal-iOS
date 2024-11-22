//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreGraphics
import Foundation
import UIKit

public typealias BackgroundTaskExpirationHandler = () -> Void
public typealias AppActiveBlock = () -> Void

public enum AppContextType: CaseIterable, CustomStringConvertible {
    case main
    case nse
    case share

    public var description: String {
        // This appears to be the default behavior but it's not actually specified by the swift documentation
        // so we make it explicit just to be sure.
        switch self {
        case .main:
            return "main"
        case .nse:
            return "nse"
        case .share:
            return "share"
        }
    }
}

public protocol AppContext {
    var type: AppContextType { get }
    var isMainApp: Bool { get }
    var isMainAppAndActive: Bool { get }
    @MainActor
    var isMainAppAndActiveIsolated: Bool { get }
    var isNSE: Bool { get }
    /// Whether the user is using a right-to-left language like Arabic.
    var isRTL: Bool { get }
    var isRunningTests: Bool { get }
    var mainWindow: UIWindow? { get set }
    var frame: CGRect { get }

    /// Unlike UIApplication.applicationState, this is thread-safe.
    /// It contains the "last known" application state.
    ///
    /// Because it is updated in response to "will/did-style" events, it is
    /// conservative and skews toward less-active and not-foreground:
    ///
    /// * It doesn't report "is active" until the app is active
    ///   and reports "inactive" as soon as it _will become_ inactive.
    /// * It doesn't report "is foreground (but inactive)" until the app is
    ///   foreground & inactive and reports "background" as soon as it _will
    ///   enter_ background.
    ///
    /// This conservatism is useful, since we want to err on the side of
    /// caution when, for example, we do work that should only be done
    /// when the app is foreground and active.
    var reportedApplicationState: UIApplication.State { get }

    /// A convenience accessor for reportedApplicationState.
    ///
    /// This method is thread-safe.
    func isInBackground() -> Bool

    /// A convenience accessor for reportedApplicationState.
    ///
    /// This method is thread-safe.
    func isAppForegroundAndActive() -> Bool

    /// Should start a background task if isMainApp is YES.
    /// Should just return UIBackgroundTaskInvalid if isMainApp is NO.
    func beginBackgroundTask(with expirationHandler: @escaping BackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier

    /// Should be a NOOP if isMainApp is NO.
    func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier)

    /// Should be a NOOP if isMainApp is NO.
    func ensureSleepBlocking(_ shouldBeBlocking: Bool, blockingObjectsDescription: String)

    /// Returns the VC that should be used to present alerts, modals, etc.
    func frontmostViewController() -> UIViewController?
    func openSystemSettings()
    func open(_ url: URL, completion: ((_ success: Bool) -> Void)?)
    func runNowOrWhenMainAppIsActive(_ block: @escaping AppActiveBlock)

    var appLaunchTime: Date { get }

    /// Will be updated every time the app is foregrounded.
    var appForegroundTime: Date { get }

    func appDocumentDirectoryPath() -> String

    func appSharedDataDirectoryPath() -> String

    func appDatabaseBaseDirectoryPath() -> String
    func appUserDefaults() -> UserDefaults

    /// This method should only be called by the main app.
    func mainApplicationStateOnLaunch() -> UIApplication.State
    func canPresentNotifications() -> Bool
    var shouldProcessIncomingMessages: Bool { get }
    var hasUI: Bool { get }
    var debugLogsDirPath: String { get }

    /// WARNING: Resets all persisted app data. (main app only).
    ///
    /// App becomes unuseable. As of time of writing, the only option
    /// after doing this is to terminate the app and relaunch.
    @MainActor
    func resetAppDataAndExit() -> Never
}

@objcMembers
public final class AppContextObjCBridge: NSObject {
    @available(swift, obsoleted: 1)
    public static let shared = AppContextObjCBridge()

    public static let owsApplicationWillResignActiveNotification = Notification.Name.OWSApplicationWillResignActive
    public static let owsApplicationDidBecomeActiveNotification = Notification.Name.OWSApplicationDidBecomeActive

    private var appContext: any AppContext {
        SignalServiceKit.CurrentAppContext()
    }

    private override init() {}

    public var appDocumentDirectoryPath: String {
        appContext.appDocumentDirectoryPath()
    }

    public var appSharedDataDirectoryPath: String {
        appContext.appSharedDataDirectoryPath()
    }

    public var appLaunchTime: Date {
        appContext.appLaunchTime
    }

    public var isMainApp: Bool {
        appContext.isMainApp
    }

    public var isMainAppAndActive: Bool {
        appContext.isMainAppAndActive
    }

    public var isRunningTests: Bool {
        appContext.isRunningTests
    }

    public func beginBackgroundTask(expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        appContext.beginBackgroundTask(with: expirationHandler)
    }

    public func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        appContext.endBackgroundTask(identifier)
    }
}

// These are fired whenever the corresponding "main app" or "app extension"
// notification is fired.
//
// 1. This saves you the work of observing both.
// 2. This allows us to ensure that any critical work (e.g. re-opening
//    databases) has been done before app re-enters foreground, etc.
public extension Notification.Name {
    // TODO: Rename this to a more swift style name
    static let OWSApplicationDidEnterBackground = Notification.Name("OWSApplicationDidEnterBackgroundNotification")
    static let OWSApplicationWillEnterForeground = Notification.Name("OWSApplicationWillEnterForegroundNotification")
    static let OWSApplicationWillResignActive = Notification.Name("OWSApplicationWillResignActiveNotification")
    static let OWSApplicationDidBecomeActive = Notification.Name("OWSApplicationDidBecomeActiveNotification")
}

private var currentAppContext: (any AppContext)?

public func CurrentAppContext() -> any AppContext {
    // Yuck, but the objc function that came before this function lied about
    // not being able to return nil so the entire app is already written
    // assuming this can't be nil though it always could have been.
    currentAppContext!
}

public func SetCurrentAppContext(_ appContext: any AppContext) {
    currentAppContext = appContext
}

extension AppContext {
    public var isMainApp: Bool {
        type == .main
    }

    public var isNSE: Bool {
        type == .nse
    }
}
