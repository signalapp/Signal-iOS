//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class NSEEnvironment {
    let appReadiness: AppReadinessSetter
    let appContext: NSEContext

    init() {
        self.appContext = NSEContext()
        SetCurrentAppContext(self.appContext, isRunningTests: false)
        appReadiness = AppReadinessImpl()
    }

    // MARK: - Setup

    @MainActor private var didStartAppSetup = false
    @MainActor private var finalContinuation: AppSetup.FinalContinuation?

    /// Called for each notification the NSE receives.
    ///
    /// Will be invoked multiple times in the same NSE process.
    @MainActor
    func setUp(logger: NSELogger) {
        let debugLogger = DebugLogger.shared

        if !didStartAppSetup {
            debugLogger.enableFileLogging(appContext: appContext, canLaunchInBackground: true)
            debugLogger.enableTTYLoggingIfNeeded()
            DebugLogger.registerLibsignal()
            DebugLogger.registerRingRTC(appContext: appContext)
            didStartAppSetup = true
        }

        logger.info("pid: \(ProcessInfo.processInfo.processIdentifier), memoryUsage: \(LocalDevice.memoryUsageString)")
        logger.flush()
    }

    @MainActor
    func setUpDatabase(logger: NSELogger) async throws -> AppSetup.FinalContinuation {
        if let finalContinuation {
            return finalContinuation
        }

        let keychainStorage = KeychainStorageImpl(isUsingProductionService: TSConstants.isUsingProductionService)
        let databaseStorage = try SDSDatabaseStorage(
            appReadiness: appReadiness,
            databaseFileUrl: SDSDatabaseStorage.grdbDatabaseFileUrl,
            keychainStorage: keychainStorage,
        )
        databaseStorage.grdbStorage.setUpDatabasePathKVO()

        let finalContinuation = await AppSetup()
            .start(
                appContext: CurrentAppContext(),
                databaseStorage: databaseStorage,
            )
            .migrateDatabaseSchema()
            .initGlobals(
                appReadiness: appReadiness,
                backupArchiveErrorPresenterFactory: NoOpBackupArchiveErrorPresenterFactory(),
                deviceBatteryLevelManager: nil,
                deviceSleepManager: nil,
                paymentsEvents: PaymentsEventsAppExtension(),
                mobileCoinHelper: MobileCoinHelperMinimal(),
                callMessageHandler: NSECallMessageHandler(),
                currentCallProvider: CurrentCallNoOpProvider(),
                notificationPresenter: NotificationPresenterImpl(),
            )
            .migrateDatabaseData()

        self.finalContinuation = finalContinuation
        return finalContinuation
    }

    @MainActor
    func setAppIsReady() {
        if appReadiness.isAppReady {
            return
        }

        // Note that this does much more than set a flag; it will also run all deferred blocks.
        appReadiness.setAppIsReady()

        let appVersion = AppVersionImpl.shared
        appVersion.dumpToLog()
        appVersion.updateFirstVersionIfNeeded()
        appVersion.nseLaunchDidComplete()
    }
}
