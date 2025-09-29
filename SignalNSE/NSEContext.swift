//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

final class NSEContext: NSObject, AppContext {
    let type: SignalServiceKit.AppContextType = .nse
    let isMainAppAndActive = false
    let isMainAppAndActiveIsolated = false

    func isInBackground() -> Bool { true }
    func isAppForegroundAndActive() -> Bool { false }
    func mainApplicationStateOnLaunch() -> UIApplication.State { .inactive }
    var shouldProcessIncomingMessages: Bool { true }
    var hasUI: Bool { false }
    func canPresentNotifications() -> Bool { true }

    let appLaunchTime = Date()
    // In NSE foreground and launch are the same.
    var appForegroundTime: Date { return appLaunchTime }

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
            guard let self else { return }

            let logger: NSELogger = .uncorrelated
            logger.warn("Memory pressure event: \(self.memoryPressureSource.memoryEventDescription)")
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
    let reportedApplicationState: UIApplication.State = .background

    func beginBackgroundTask(with expirationHandler: BackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier { .invalid }
    func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier) {}

    func frontmostViewController() -> UIViewController? { nil }
    func openSystemSettings() {}
    func open(_ url: URL, completion: ((Bool) -> Void)? = nil) {}

    func runNowOrWhenMainAppIsActive(_ block: () -> Void) {}

    @MainActor
    func resetAppDataAndExit() -> Never {
        owsFail("Should not reset app data from NSE")
    }

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
