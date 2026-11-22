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
        messageSender: any MessageSender = FakeMessageSender(),
        notificationPresenter: any NotificationPresenter = NoopNotificationPresenterImpl(),
        testDependencies: AppSetup.TestDependencies? = nil,
    ) async {
        let sampleDatabase = await initializeSampleDatabase()
        _ = await _activate(
            appReadiness: appReadiness,
            callMessageHandler: callMessageHandler,
            currentCallProvider: currentCallProvider,
            messageSender: messageSender,
            notificationPresenter: notificationPresenter,
            testDependencies: testDependencies,
            sampleDatabase: sampleDatabase,
        )
    }

    @MainActor
    private static func _activate(
        appReadiness: any AppReadiness = AppReadinessImpl(),
        callMessageHandler: any CallMessageHandler = NoopCallMessageHandler(),
        currentCallProvider: any CurrentCallProvider = CurrentCallNoOpProvider(),
        keychainStorage: MockKeychainStorage = MockKeychainStorage(),
        messageSender: any MessageSender = FakeMessageSender(),
        notificationPresenter: any NotificationPresenter = NoopNotificationPresenterImpl(),
        testDependencies: AppSetup.TestDependencies? = nil,
        sampleDatabase: SampleDatabase?,
    ) async -> SampleDatabase {
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
        let databaseUrl = SDSDatabaseStorage.grdbDatabaseFileUrl

        let keychainStorage: MockKeychainStorage
        if let sampleDatabase {
            sampleDatabase.copyTo(databaseUrl)
            keychainStorage = sampleDatabase.keychainStorage.clone()
        } else {
            keychainStorage = MockKeychainStorage()
        }

        let finalContinuation = await AppSetup().start(
            appContext: testAppContext,
            databaseStorage: try! SDSDatabaseStorage(
                appReadiness: appReadiness,
                databaseFileUrl: databaseUrl,
                keychainStorage: keychainStorage,
            ),
        ).migrateDatabaseSchema().initGlobals(
            appContext: testAppContext,
            appReadiness: appReadiness,
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
                messageSender: messageSender,
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
                webSocketFactory: WebSocketFactoryMock(),
            ),
        ).migrateDatabaseData()
        finalContinuation.runLaunchTasksIfNeededAndReloadCaches()
        return SampleDatabase(fileUrl: databaseUrl, keychainStorage: keychainStorage)
    }

    struct SampleDatabase {
        var fileUrl: URL
        var keychainStorage: MockKeychainStorage

        func copyTo(_ databaseUrl: URL) {
            try! FileManager.default.copyItem(at: self.fileUrl, to: databaseUrl)
        }
    }

    @MainActor
    private static var sampleDatabase: SampleDatabase?

    @MainActor
    private static func initializeSampleDatabase() async -> SampleDatabase {
        if let sampleDatabase {
            return sampleDatabase
        }
        let oldContext = CurrentAppContext()
        let result = await MockSSKEnvironment._activate(sampleDatabase: nil)
        try! SSKEnvironment.shared.databaseStorageRef.grdbStorage.syncTruncatingCheckpoint()
        self.sampleDatabase = result
        await MockSSKEnvironment.deactivateAsync(oldContext: oldContext)
        return result
    }

    /// Flushes pending work in the active environment, then tears it down.
    public static func deactivateAsync(oldContext: any AppContext) async {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let messageProcessor = SSKEnvironment.shared.messageProcessorRef

        await drainMainQueue()

        // Wait for all pending readers/writers to finish.
        try! await databaseStorage.grdbStorage.pool.barrierWriteWithoutTransaction { _ in }

        // Wait for the MessageProcessor to finish.
        await withCheckedContinuation { continuation in
            messageProcessor.serialQueueForTests.async { continuation.resume() }
        }

        // Ensure late writes from one test don't trigger change-observer work
        // on the main queue that spills into the next test.
        try! databaseStorage.grdbStorage.testing_tearDownDatabaseChangeObserver()

        // Drain *again* in case more work was scheduled.
        await drainMainQueue()

        SetCurrentAppContext(oldContext, isRunningTests: true)
        SSKEnvironment.setShared(nil, isRunningTests: true)
        DependenciesBridge.setShared(nil, isRunningTests: true)
    }

    /// Synchronous wrapper around ``deactivateAsync(oldContext:)`` for
    /// non-async callers, like `XCTestCase.tearDown()`.
    @MainActor
    public static func deactivate(oldContext: any AppContext) {
        let isDone = AtomicBool(false, lock: .init())
        Task {
            await deactivateAsync(oldContext: oldContext)
            isDone.set(true)
        }
        while !isDone.get() {
            CFRunLoopRunInMode(.defaultMode, 0.0, true)
        }
    }

    private static func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

#endif
