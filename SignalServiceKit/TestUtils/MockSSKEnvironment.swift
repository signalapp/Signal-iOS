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
        incrementalMessageTSAttachmentMigratorFactory: any IncrementalMessageTSAttachmentMigratorFactory = IncrementalMessageTSAttachmentMigratorFactoryMock(),
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

        _ = await AppSetup().start(
            appContext: testAppContext,
            appReadiness: appReadiness,
            databaseStorage: try! SDSDatabaseStorage(
                appReadiness: appReadiness,
                databaseFileUrl: SDSDatabaseStorage.grdbDatabaseFileUrl,
                keychainStorage: MockKeychainStorage()
            ),
            paymentsEvents: PaymentsEventsNoop(),
            mobileCoinHelper: MobileCoinHelperMock(),
            callMessageHandler: callMessageHandler,
            currentCallProvider: currentCallProvider,
            notificationPresenter: notificationPresenter,
            incrementalMessageTSAttachmentMigratorFactory: incrementalMessageTSAttachmentMigratorFactory,
            messageBackupErrorPresenterFactory: NoOpMessageBackupErrorPresenterFactory(),
            testDependencies: testDependencies ?? AppSetup.TestDependencies(
                contactManager: FakeContactsManager(),
                groupV2Updates: MockGroupV2Updates(),
                groupsV2: MockGroupsV2(),
                messageSender: FakeMessageSender(),
                modelReadCaches: ModelReadCaches(
                    factory: TestableModelReadCacheFactory(appReadiness: appReadiness)
                ),
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
        ).prepareDatabase()
    }

    @MainActor
    private static func flushAndWait() {
        AssertIsOnMainThread()

        waitForMainQueue()

        // Wait for all pending readers/writers to finish.
        SSKEnvironment.shared.databaseStorageRef.grdbStorage.pool.barrierWriteWithoutTransaction { _ in }

        // Wait for the main queue *again* in case more work was scheduled.
        waitForMainQueue()
    }

    public static func deactivateAsync(oldContext: any AppContext) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                SSKEnvironment.shared.databaseStorageRef.grdbStorage.pool.barrierWriteWithoutTransaction { _ in }
                DispatchQueue.main.async {
                    continuation.resume()
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
