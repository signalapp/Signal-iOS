//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

@objc
public class TestAppContext: NSObject, AppContext {
    public static var testDebugLogsDirPath: String {
        let dirPath = OWSTemporaryDirectory().appendingPathComponent("TestLogs")
        OWSFileSystem.ensureDirectoryExists(dirPath)
        return dirPath
    }

    private let mockAppDocumentDirectoryPath: String
    private let mockAppSharedDataDirectoryPath: String
    private let internalAppUserDefaults: UserDefaults
    public func appUserDefaults() -> UserDefaults { internalAppUserDefaults }

    // MARK: -

    public var mainWindow: UIWindow?
    public let appLaunchTime: Date
    public let appForegroundTime: Date

    public override init() {
        // Avoid using OWSTemporaryDirectory(); it can consult the current app context.
        let dirName = "ows_temp_\(UUID().uuidString)"
        let temporaryDirectory = NSTemporaryDirectory().appendingPathComponent(dirName)
        do {
            try FileManager.default.createDirectory(atPath: temporaryDirectory, withIntermediateDirectories: true)
        } catch {
            owsFail("Failed to create directory: \(temporaryDirectory), error: \(error)")
        }

        self.mockAppDocumentDirectoryPath = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.mockAppSharedDataDirectoryPath = temporaryDirectory.appendingPathComponent(UUID().uuidString)
        self.internalAppUserDefaults = UserDefaults()
        let launchDate = Date()
        self.appLaunchTime = launchDate
        self.appForegroundTime = launchDate

        super.init()
    }

    public var reportedApplicationState: UIApplication.State = .active

    // MARK: -

    public let type: SignalServiceKit.AppContextType = .main
    public let isMainAppAndActive: Bool = true
    public let isMainAppAndActiveIsolated: Bool = true
    public func mainApplicationStateOnLaunch() -> UIApplication.State { .inactive }
    public let isRTL: Bool = false
    public func isInBackground() -> Bool { false }
    public func isAppForegroundAndActive() -> Bool { true }
    public func beginBackgroundTask(with expirationHandler: BackgroundTaskExpirationHandler) -> UIBackgroundTaskIdentifier { .invalid }
    public func endBackgroundTask(_ backgroundTaskIdentifier: UIBackgroundTaskIdentifier) {}
    public func ensureSleepBlocking(_ shouldBeBlocking: Bool, blockingObjectsDescription: String) {}
    public func frontmostViewController() -> UIViewController? { nil }
    public func openSystemSettings() {}
    public func open(_ url: URL, completion: ((Bool) -> Void)?) {}
    public let isRunningTests: Bool = true
    /// Pretend to be a small device.
    public let frame: CGRect = CGRect(x: 0, y: 0, width: 300, height: 400)

    // MARK: -

    public func runNowOrWhenMainAppIsActive(_ block: AppActiveBlock) { block() }
    public func appDocumentDirectoryPath() -> String { mockAppDocumentDirectoryPath }
    public func appSharedDataDirectoryPath() -> String { mockAppSharedDataDirectoryPath }
    public func appDatabaseBaseDirectoryPath() -> String { appSharedDataDirectoryPath() }
    public func canPresentNotifications() -> Bool { false }
    public let shouldProcessIncomingMessages: Bool = true
    public let hasUI: Bool = true
    public let debugLogsDirPath: String = testDebugLogsDirPath

    @MainActor
    public func resetAppDataAndExit() -> Never {
        owsFail("resetAppDataAndExit called during tests")
    }
}

#endif
