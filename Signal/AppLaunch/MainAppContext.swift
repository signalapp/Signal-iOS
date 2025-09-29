//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

final class MainAppContext: NSObject, AppContext {
    let type: SignalServiceKit.AppContextType = .main

    let appLaunchTime: Date

    private(set) var appForegroundTime: Date

    override init() {
        _reportedApplicationState = AtomicValue(.inactive, lock: .init())

        let launchDate = Date()
        appLaunchTime = launchDate
        appForegroundTime = launchDate
        _mainApplicationStateOnLaunch = UIApplication.shared.applicationState

        super.init()

        let notificationCenter = NotificationCenter.default

        notificationCenter.addObserver(
            self,
            selector: #selector(applicationWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    private let _mainApplicationStateOnLaunch: UIApplication.State
    func mainApplicationStateOnLaunch() -> UIApplication.State { _mainApplicationStateOnLaunch }

    private let _reportedApplicationState: AtomicValue<UIApplication.State>
    var reportedApplicationState: UIApplication.State {
        get { _reportedApplicationState.get() }
        set {
            AssertIsOnMainThread()
            _reportedApplicationState.set(newValue)
        }
    }

    @objc
    private func applicationWillEnterForeground(_ notification: Notification) {
        AssertIsOnMainThread()

        self.reportedApplicationState = .inactive
        self.appForegroundTime = Date()

        BenchManager.bench(title: "Slow WillEnterForeground", logIfLongerThan: 0.2, logInProduction: true) {
            NotificationCenter.default.post(name: .OWSApplicationWillEnterForeground, object: nil)
        }
    }

    @objc
    private func applicationDidEnterBackground(_ notification: Notification) {
        AssertIsOnMainThread()

        self.reportedApplicationState = .background

        BenchManager.bench(title: "Slow DidEnterBackground", logIfLongerThan: 0.1, logInProduction: true) {
            NotificationCenter.default.post(name: .OWSApplicationDidEnterBackground, object: nil)
        }
    }

    @objc
    private func applicationWillResignActive(_ notification: Notification) {
        AssertIsOnMainThread()

        self.reportedApplicationState = .inactive

        BenchManager.bench(title: "Slow WillResignActive", logIfLongerThan: 0.1, logInProduction: true) {
            NotificationCenter.default.post(name: .OWSApplicationWillResignActive, object: nil)
        }
    }

    @objc
    private func applicationDidBecomeActive(_ notification: Notification) {
        AssertIsOnMainThread()

        self.reportedApplicationState = .active

        BenchManager.bench(title: "Slow DidBecomeActive", logIfLongerThan: 0.1, logInProduction: true) {
            NotificationCenter.default.post(name: .OWSApplicationDidBecomeActive, object: nil)
        }

        runAppActiveBlocks()
    }

    var isMainAppAndActive: Bool { UIApplication.shared.applicationState == .active }

    @MainActor
    var isMainAppAndActiveIsolated: Bool { UIApplication.shared.applicationState == .active }

    let isRTL: Bool = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft

    func isInBackground() -> Bool { reportedApplicationState == .background }

    func isAppForegroundAndActive() -> Bool { reportedApplicationState == .active }

    func beginBackgroundTask(with expirationHandler: @escaping BackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(expirationHandler: expirationHandler)
    }

    func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
    }

    func frontmostViewController() -> UIViewController? { UIApplication.shared.frontmostViewControllerIgnoringAlerts }

    func openSystemSettings() { UIApplication.shared.openSystemSettings() }

    func open(_ url: URL, completion: ((Bool) -> Void)? = nil) { UIApplication.shared.open(url, completionHandler: completion) }

    var isRunningTests: Bool {
        #if TESTABLE_BUILD
        return getenv("runningTests_dontStartApp") != nil
        #else
        return false
        #endif
    }

    var frame: CGRect { self.mainWindow?.frame ?? .zero }

    var mainWindow: UIWindow?

    private var appActiveBlocks = [AppActiveBlock]()

    func runNowOrWhenMainAppIsActive(_ block: @escaping AppActiveBlock) {
        DispatchMainThreadSafe {
            if self.isMainAppAndActive {
                block()
                return
            }
            self.appActiveBlocks.append(block)
        }
    }

    private func runAppActiveBlocks() {
        AssertIsOnMainThread()
        let appActiveBlocks = self.appActiveBlocks
        self.appActiveBlocks = []
        for block in appActiveBlocks { block() }
    }

    func appDocumentDirectoryPath() -> String {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!.path
    }

    func appSharedDataDirectoryPath() -> String {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup)!.path
    }

    func appDatabaseBaseDirectoryPath() -> String { appSharedDataDirectoryPath() }

    func appUserDefaults() -> UserDefaults { UserDefaults(suiteName: TSConstants.applicationGroup)! }

    func canPresentNotifications() -> Bool { true }

    let shouldProcessIncomingMessages: Bool = true

    let hasUI: Bool = true

    var debugLogsDirPath: String { DebugLogger.mainAppDebugLogsDirPath }

    @MainActor
    func resetAppDataAndExit() -> Never {
        SignalApp.resetAppDataAndExit(keyFetcher: SSKEnvironment.shared.databaseStorageRef.keyFetcher)
    }
}
