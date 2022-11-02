//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

class NSEContext: NSObject, AppContext {
    let isMainApp = false
    let isMainAppAndActive = false
    let isNSE = true

    func isInBackground() -> Bool { true }
    func isAppForegroundAndActive() -> Bool { false }
    func mainApplicationStateOnLaunch() -> UIApplication.State { .inactive }
    var shouldProcessIncomingMessages: Bool { true }
    var hasUI: Bool { false }
    func canPresentNotifications() -> Bool { true }
    var didLastLaunchNotTerminate: Bool { false }
    var hasActiveCall: Bool { false }

    let appLaunchTime = Date()
    // In NSE foreground and launch are the same.
    var appForegroundTime: Date { return appLaunchTime }
    lazy var buildTime: Date = {
        guard let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "BuildTimestamp") as? TimeInterval, buildTimestamp > 0 else {
            NSELogger.uncorrelated.debug("No build timestamp, assuming app never expires.")
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

    let memoryPressureSource = DispatchSource.makeMemoryPressureSource(
        eventMask: .all,
        queue: .global()
    )

    override init() {
        super.init()

        memoryPressureSource.setEventHandler { [weak self] in
            let logger: NSELogger = .uncorrelated

            if let self = self {
                logger.warn("Memory pressure event: \(self.memoryPressureSource.memoryEventDescription)")
            } else {
                logger.warn("Memory pressure event.")
            }
            logger.warn("Current memory usage: \(LocalDevice.memoryUsageString)")
            logger.flush()
        }
        memoryPressureSource.resume()

    }

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

    // The NSE can't update UIApplication directly, so instead we cache our last desired badge number
    // and use it to update the modified notification content
    var desiredBadgeNumber: AtomicOptional<Int> = .init(nil)
    func setMainAppBadgeNumber(_ value: Int) {
        desiredBadgeNumber.set(value)
    }

    func frontmostViewController() -> UIViewController? { nil }
    func openSystemSettings() {}
    func open(_ url: URL, completion: ((Bool) -> Void)? = nil) {}

    func setNetworkActivityIndicatorVisible(_ value: Bool) {}

    func runNowOr(whenMainAppIsActive block: @escaping AppActiveBlock) {}

    var debugLogsDirPath: String {
        DebugLogger.nseDebugLogsDirPath
    }
}

fileprivate extension DispatchSourceMemoryPressure {
    var memoryEvent: DispatchSource.MemoryPressureEvent {
        DispatchSource.MemoryPressureEvent(rawValue: data)
    }

    var memoryEventDescription: String {
        switch memoryEvent {
        case .normal: return "Normal"
        case .warning: return "Warning!"
        case .critical: return "Critical!!"
        default: return "Unknown value: \(memoryEvent.rawValue)"
        }
    }
}
