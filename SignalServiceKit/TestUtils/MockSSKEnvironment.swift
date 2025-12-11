//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

#if TESTABLE_BUILD

public class MockSSKEnvironment {
    /// Set up a mock SSK environment as well as ``DependenciesBridge``.
    @MainActor
    public static func activate(
        appReadiness: any AppReadiness = AppReadinessImpl(),
        callMessageHandler: any CallMessageHandler = NoopCallMessageHandler(),
        currentCallProvider: any CurrentCallProvider = CurrentCallNoOpProvider(),
        notificationPresenter: any NotificationPresenter = NoopNotificationPresenterImpl(),
        testDependencies: AppSetup.TestDependencies? = nil
    ) async {
        owsPrecondition(!(CurrentAppContext() is TestAppContext))
        owsPrecondition(!SSKEnvironment.hasShared)
        owsPrecondition(!DependenciesBridge.hasShared)

        let testAppContext = TestAppContext()
        SetCurrentAppContext(testAppContext, isRunningTests: true)

        /// Note that ``SDSDatabaseStorage/grdbDatabaseFileUrl``, through a few
        /// layers of abstraction, uses the "current app context" to decide
        /// where to put the database,
        ///
        /// For a ``TestAppContext`` as configured above, this will be a
        /// subdirectory of our temp directory unique to the instantiation of
        /// the app context.

        let finalContinuation = await AppSetup().start(
            appContext: testAppContext,
            databaseStorage: try! SDSDatabaseStorage(
                appReadiness: appReadiness,
                databaseFileUrl: SDSDatabaseStorage.grdbDatabaseFileUrl,
                keychainStorage: MockKeychainStorage()
            ),
        ).migrateDatabaseSchema().initGlobals(
            appReadiness: appReadiness,
            backupArchiveErrorPresenterFactory: NoOpBackupArchiveErrorPresenterFactory(),
            deviceBatteryLevelManager: nil,
            deviceSleepManager: nil,
            paymentsEvents: PaymentsEventsNoop(),
            mobileCoinHelper: MobileCoinHelperMock(),
            callMessageHandler: callMessageHandler,
            currentCallProvider: currentCallProvider,
            notificationPresenter: notificationPresenter,
            testDependencies: testDependencies ?? AppSetup.TestDependencies(
                contactManager: FakeContactsManager(),
                groupV2Updates: MockGroupV2Updates(),
                groupsV2: MockGroupsV2(),
                messageSender: { FakeMessageSender(accountChecker: $0) },
                networkManager: OWSFakeNetworkManager(appReadiness: appReadiness, libsignalNet: nil),
                paymentsCurrencies: MockPaymentsCurrencies(),
                paymentsHelper: MockPaymentsHelper(),
                pendingReceiptRecorder: NoopPendingReceiptRecorder(),
                profileManager: OWSFakeProfileManager(),
                reachabilityManager: MockSSKReachabilityManager(),
                remoteConfigManager: StubbableRemoteConfigManager(),
                signalService: OWSSignalServiceMock(),
                storageServiceManager: FakeStorageServiceManager(),
                syncManager: OWSMockSyncManager(),
                systemStoryManager: SystemStoryManagerMock(),
                versionedProfiles: MockVersionedProfiles(),
                webSocketFactory: WebSocketFactoryMock()
            )
        ).migrateDatabaseData()
        finalContinuation.runLaunchTasksIfNeededAndReloadCaches()
    }

    @MainActor
    private static func flushAndWait() {
        AssertIsOnMainThread()

        waitForMainQueue()

        // Wait for all pending readers/writers to finish.
        SSKEnvironment.shared.databaseStorageRef.grdbStorage.pool.barrierWriteWithoutTransaction { _ in }

        // Wait for the MessageProcessor to finish.
        SSKEnvironment.shared.messageProcessorRef.serialQueueForTests.sync {}

        // Wait for the main queue *again* in case more work was scheduled.
        waitForMainQueue()
    }

    public static func deactivateAsync(oldContext: any AppContext) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                SSKEnvironment.shared.databaseStorageRef.grdbStorage.pool.barrierWriteWithoutTransaction { _ in }
                SSKEnvironment.shared.messageProcessorRef.serialQueueForTests.async {
                    DispatchQueue.main.async {
                        continuation.resume()
                    }
                }
            }
        }
        _deactivate(oldContext: oldContext)
    }

    @MainActor
    public static func deactivate(oldContext: any AppContext) {
        flushAndWait()
        _deactivate(oldContext: oldContext)
    }

    private static func _deactivate(oldContext: any AppContext) {
        SetCurrentAppContext(oldContext, isRunningTests: true)
        SSKEnvironment.setShared(nil, isRunningTests: true)
        DependenciesBridge.setShared(nil, isRunningTests: true)
    }

    private static func waitForMainQueue() {
        // Spin the main run loop to flush any remaining async work.
        var done = false
        DispatchQueue.main.async { done = true }
        while !done {
            CFRunLoopRunInMode(.defaultMode, 0.0, true)
        }
    }
}

#endif
