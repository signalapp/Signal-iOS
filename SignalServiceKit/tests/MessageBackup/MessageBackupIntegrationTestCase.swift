//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class MessageBackupIntegrationTestCase: XCTestCase {
    override func setUp() {
        DDLog.add(DDTTYLogger.sharedInstance!)
    }

    // MARK: -

    private var messageBackupManager: MessageBackupManager {
        DependenciesBridge.shared.messageBackupManager
    }

    private var localIdentifiers: LocalIdentifiers {
        /// A backup doesn't contain our own local identifiers. Rather, those
        /// are determined as part of registration for a backup import, and are
        /// already-known for a backup export.
        ///
        /// Consequently, we can use any local identifiers for our test
        /// purposes without worrying about the contents of each test case's
        /// backup file.
        return .forUnitTests
    }

    func runTest(
        backupName: String,
        assertionsBlock: (SDSAnyReadTransaction, DBReadTransaction) throws -> Void
    ) async throws {
        try await importAndAssert(
            localIdentifiers: localIdentifiers,
            backupUrl: backupFileUrl(named: backupName),
            assertionsBlock: assertionsBlock
        )

        let exportedBackupUrl = try await messageBackupManager
            .exportPlaintextBackup(localIdentifiers: localIdentifiers)

        try await importAndAssert(
            localIdentifiers: localIdentifiers,
            backupUrl: exportedBackupUrl,
            assertionsBlock: assertionsBlock
        )
    }

    private func backupFileUrl(named backupName: String) -> URL {
        let testBundle = Bundle(for: type(of: self))
        return testBundle.url(forResource: backupName, withExtension: "binproto")!
    }

    private func importAndAssert(
        localIdentifiers: LocalIdentifiers,
        backupUrl: URL,
        assertionsBlock: (SDSAnyReadTransaction, DBReadTransaction) throws -> Void
    ) async throws {
        await initializeApp()

        try await messageBackupManager.importPlaintextBackup(
            fileUrl: backupUrl,
            localIdentifiers: localIdentifiers
        )

        try NSObject.databaseStorage.read { tx in
            try assertionsBlock(tx, tx.asV2Read)
        }
    }

    // MARK: -

    @MainActor
    final func initializeApp() async {
        let testAppContext = TestAppContext()
        SetCurrentAppContext(testAppContext)

        /// Note that ``SDSDatabaseStorage/grdbDatabaseFileUrl``, through a few
        /// layers of abstraction, uses the "current app context" to decide
        /// where to put the database,
        ///
        /// For a ``TestAppContext`` as configured above, this will be a
        /// subdirectory of our temp directory unique to the instantiation of
        /// the app context.
        let databaseStorage = try! SDSDatabaseStorage(
            databaseFileUrl: SDSDatabaseStorage.grdbDatabaseFileUrl,
            keychainStorage: MockKeychainStorage()
        )

        /// We use crashy versions of dependencies that should never be called
        /// during backups, and no-op implementations of payments because those
        /// are bound to the SignalUI target.
        _ = await AppSetup().start(
            appContext: testAppContext,
            databaseStorage: databaseStorage,
            paymentsEvents: PaymentsEventsNoop(),
            mobileCoinHelper: MobileCoinHelperMock(),
            callMessageHandler: CrashyMocks.MockCallMessageHandler(),
            currentCallProvider: CrashyMocks.MockCurrentCallThreadProvider(),
            notificationPresenter: CrashyMocks.MockNotificationPresenter(),
            testDependencies: AppSetup.TestDependencies(
                networkManager: CrashyMocks.MockNetworkManager(libsignalNet: nil),
                webSocketFactory: CrashyMocks.MockWebSocketFactory()
            )
        ).prepareDatabase().awaitable()
    }
}

// MARK: -

private func failTest<T>(
    _ type: T.Type,
    _ function: StaticString = #function
) -> Never {
    let message = "Unexpectedly called \(type)#\(function)!"
    XCTFail(message)
    owsFail(message)
}

/// As a rule, integration tests for message backup should not mock out their
/// dependencies as their goal is to validate how the real, production app will
/// behave with respect to Backups.
///
/// These mocks are the exceptions to that rule, and encompass managers that
/// should never be invoked during Backup import or export.
private enum CrashyMocks {
    final class MockNetworkManager: NetworkManager {
        override func makePromise(request: TSRequest, canUseWebSocket: Bool = false) -> Promise<any HTTPResponse> { failTest(Self.self) }
    }

    final class MockWebSocketFactory: WebSocketFactory {
        var canBuildWebSocket: Bool { failTest(Self.self) }
        func buildSocket(request: WebSocketRequest, callbackScheduler: any Scheduler) -> (any SSKWebSocket)? { failTest(Self.self) }
    }

    final class MockCallMessageHandler: CallMessageHandler {
        func action(for envelope: SSKProtoEnvelope, callMessage: SSKProtoCallMessage, serverDeliveryTimestamp: UInt64) -> CallMessageAction { failTest(Self.self) }
        func receivedOffer(_ offer: SSKProtoCallMessageOffer, from caller: (aci: Aci, deviceId: UInt32), sentAtTimestamp: UInt64, serverReceivedTimestamp: UInt64, serverDeliveryTimestamp: UInt64, tx: SDSAnyWriteTransaction) { failTest(Self.self) }
        func receivedAnswer(_ answer: SSKProtoCallMessageAnswer, from caller: (aci: Aci, deviceId: UInt32), tx: SDSAnyReadTransaction) { failTest(Self.self) }
        func receivedIceUpdate(_ iceUpdate: [SSKProtoCallMessageIceUpdate], from caller: (aci: Aci, deviceId: UInt32)) { failTest(Self.self) }
        func receivedHangup(_ hangup: SSKProtoCallMessageHangup, from caller: (aci: Aci, deviceId: UInt32)) { failTest(Self.self) }
        func receivedBusy(_ busy: SSKProtoCallMessageBusy, from caller: (aci: Aci, deviceId: UInt32)) { failTest(Self.self) }
        func receivedOpaque(_ opaque: SSKProtoCallMessageOpaque, from caller: (aci: Aci, deviceId: UInt32), serverReceivedTimestamp: UInt64, serverDeliveryTimestamp: UInt64, tx: SDSAnyReadTransaction) { failTest(Self.self) }
        func receivedGroupCallUpdateMessage(_ updateMessage: SSKProtoDataMessageGroupCallUpdate, for thread: TSGroupThread, serverReceivedTimestamp: UInt64) async { failTest(Self.self) }
        func externallyHandleCallMessage(envelope: SSKProtoEnvelope, plaintextData: Data, wasReceivedByUD: Bool, serverDeliveryTimestamp: UInt64, tx: SDSAnyWriteTransaction) { failTest(Self.self) }
    }

    final class MockCurrentCallThreadProvider: CurrentCallProvider {
        var hasCurrentCall: Bool { failTest(Self.self) }
        var currentGroupCallThread: TSGroupThread? { failTest(Self.self) }
    }

    final class MockNotificationPresenter: NotificationPresenter {
        func notifyUser(forIncomingMessage: TSIncomingMessage, thread: TSThread, transaction: SDSAnyReadTransaction) { failTest(Self.self) }
        func notifyUser(forIncomingMessage: TSIncomingMessage, editTarget: TSIncomingMessage, thread: TSThread, transaction: SDSAnyReadTransaction) { failTest(Self.self) }
        func notifyUser(forReaction: OWSReaction, onOutgoingMessage: TSOutgoingMessage, thread: TSThread, transaction: SDSAnyReadTransaction) { failTest(Self.self) }
        func notifyUser(forErrorMessage: TSErrorMessage, thread: TSThread, transaction: SDSAnyWriteTransaction) { failTest(Self.self) }
        func notifyUser(forTSMessage: TSMessage, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction) { failTest(Self.self) }
        func notifyUser(forPreviewableInteraction: any TSInteraction & OWSPreviewText, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction) { failTest(Self.self) }
        func notifyTestPopulation(ofErrorMessage errorString: String) { failTest(Self.self) }
        func notifyUser(forFailedStorySend: StoryMessage, to: TSThread, transaction: SDSAnyWriteTransaction) { failTest(Self.self) }
        func notifyUserToRelaunchAfterTransfer(completion: (() -> Void)?) { failTest(Self.self) }
        func notifyUserOfDeregistration(transaction: SDSAnyWriteTransaction) { failTest(Self.self) }
        func clearAllNotifications() { failTest(Self.self) }
        func cancelNotifications(threadId: String) { failTest(Self.self) }
        func cancelNotifications(messageIds: [String]) { failTest(Self.self) }
        func cancelNotifications(reactionId: String) { failTest(Self.self) }
        func cancelNotificationsForMissedCalls(threadUniqueId: String) { failTest(Self.self) }
        func cancelNotifications(for storyMessage: StoryMessage) { failTest(Self.self) }
        func notifyUserOfDeregistration(tx: any DBWriteTransaction) { failTest(Self.self) }
    }
}
