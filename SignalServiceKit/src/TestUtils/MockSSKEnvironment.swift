//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

#if TESTABLE_BUILD

public class MockSSKEnvironment: SSKEnvironment {
    /// Set up a mock SSK environment as well as ``DependenciesBridge``.
    @objc
    public static func activate() {
        let sskEnvironment = MockSSKEnvironment()
        MockSSKEnvironment.setShared(sskEnvironment, isRunningTests: true)

        sskEnvironment.configureGrdb()
        sskEnvironment.warmCaches()
    }

    @objc
    public static func flushAndWait() {
        AssertIsOnMainThread()

        waitForMainQueue()

        // Wait for all pending readers/writers to finish.
        grdbStorageAdapter.pool.barrierWriteWithoutTransaction { _ in }

        // Wait for the main queue *again* in case more work was scheduled.
        waitForMainQueue()
    }

    private static func waitForMainQueue() {
        // Spin the main run loop to flush any remaining async work.
        var done = false
        DispatchQueue.main.async { done = true }
        while !done {
            CFRunLoopRunInMode(.defaultMode, 0.0, true)
        }
    }

    public init() {
        // Ensure that OWSBackgroundTaskManager is created now.
        OWSBackgroundTaskManager.shared()

        let storageCoordinator = StorageCoordinator()
        let databaseStorage = storageCoordinator.nonGlobalDatabaseStorage

        // Set up DependenciesBridge

        let accountServiceClient = FakeAccountServiceClient()
        let aciSignalProtocolStore = SignalProtocolStore(for: .aci)
        let dateProvider = Date.provider
        let identityManager = OWSIdentityManager(databaseStorage: databaseStorage)
        let messageProcessor = MessageProcessor()
        let messageSender = FakeMessageSender()
        let modelReadCaches = ModelReadCaches(factory: TestableModelReadCacheFactory())
        let networkManager = OWSFakeNetworkManager()
        let notificationsManager = NoopNotificationsManager()
        let ows2FAManager = OWS2FAManager()
        let pniSignalProtocolStore = SignalProtocolStore(for: .pni)
        let profileManager = OWSFakeProfileManager()
        let signalService = OWSSignalServiceMock()
        let signalServiceAddressCache = SignalServiceAddressCache()
        let storageServiceManager = FakeStorageServiceManager()
        let syncManager = OWSMockSyncManager()
        let tsAccountManager = TSAccountManager()
        let webSocketFactory = WebSocketFactoryMock()

        let dependenciesBridge = DependenciesBridge.setupSingleton(
            accountServiceClient: accountServiceClient,
            aciProtocolStore: aciSignalProtocolStore,
            appVersion: AppVersion.shared,
            databaseStorage: databaseStorage,
            dateProvider: dateProvider,
            identityManager: identityManager,
            messageProcessor: messageProcessor,
            messageSender: messageSender,
            modelReadCaches: modelReadCaches,
            networkManager: networkManager,
            notificationsManager: notificationsManager,
            ows2FAManager: ows2FAManager,
            pniProtocolStore: pniSignalProtocolStore,
            profileManager: profileManager,
            signalService: signalService,
            signalServiceAddressCache: signalServiceAddressCache,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
            websocketFactory: webSocketFactory
        )

        // Set up ourselves

        let appExpiry = DependenciesBridge.shared.appExpiry
        let contactsManager = FakeContactsManager()
        let linkPreviewManager = OWSLinkPreviewManager()
        let pendingReceiptRecorder = NoopPendingReceiptRecorder()
        let messageManager = OWSMessageManager()
        let blockingManager = BlockingManager()
        let remoteConfigManager = StubbableRemoteConfigManager()
        let udManager = OWSUDManagerImpl()
        let messageDecrypter = OWSMessageDecrypter()
        let groupsV2MessageProcessor = GroupsV2MessageProcessor()
        let socketManager = SocketManager(appExpiry: appExpiry, db: DependenciesBridge.shared.db)
        let disappearingMessagesJob = OWSDisappearingMessagesJob()
        let receiptManager = OWSReceiptManager()
        let outgoingReceiptManager = OWSOutgoingReceiptManager()
        let reachabilityManager = MockSSKReachabilityManager()
        let typingIndicators = TypingIndicatorsImpl()
        let attachmentDownloads = OWSAttachmentDownloads()
        let stickerManager = StickerManager()
        let sskPreferences = SSKPreferences()
        let groupsV2 = MockGroupsV2()
        let groupV2Updates = MockGroupV2Updates()
        let messageFetcherJob = MessageFetcherJob()
        let bulkProfileFetch = BulkProfileFetch()
        let versionedProfiles = MockVersionedProfiles()
        let earlyMessageManager = EarlyMessageManager()
        let messagePipelineSupervisor = MessagePipelineSupervisor.createStandardSupervisor()
        let paymentsHelper = MockPaymentsHelper()
        let paymentsCurrencies = MockPaymentsCurrencies()
        let paymentsEvents = PaymentsEventsNoop()
        let mobileCoinHelper = MobileCoinHelperMock()
        let spamChallengeResolver = SpamChallengeResolver()
        let senderKeyStore = SenderKeyStore()
        let phoneNumberUtil = PhoneNumberUtil()
        let legacyChangePhoneNumber = LegacyChangePhoneNumber()
        let subscriptionManager = MockSubscriptionManager()
        let systemStoryManager = SystemStoryManagerMock()
        let remoteMegaphoneFetcher = RemoteMegaphoneFetcher()
        let sskJobQueues = SSKJobQueues()
        let contactDiscoveryManager = ContactDiscoveryManagerImpl(
            db: dependenciesBridge.db,
            recipientFetcher: dependenciesBridge.recipientFetcher,
            recipientMerger: dependenciesBridge.recipientMerger,
            tsAccountManager: tsAccountManager,
            websocketFactory: webSocketFactory
        )
        let messageSendLog = MessageSendLog(databaseStorage: databaseStorage, dateProvider: { Date() })

        super.init(
            contactsManager: contactsManager,
            linkPreviewManager: linkPreviewManager,
            messageSender: messageSender,
            pendingReceiptRecorder: pendingReceiptRecorder,
            profileManager: profileManager,
            networkManager: networkManager,
            messageManager: messageManager,
            blockingManager: blockingManager,
            identityManager: identityManager,
            remoteConfigManager: remoteConfigManager,
            aciSignalProtocolStore: aciSignalProtocolStore,
            pniSignalProtocolStore: pniSignalProtocolStore,
            udManager: udManager,
            messageDecrypter: messageDecrypter,
            groupsV2MessageProcessor: groupsV2MessageProcessor,
            socketManager: socketManager,
            tsAccountManager: tsAccountManager,
            ows2FAManager: ows2FAManager,
            disappearingMessagesJob: disappearingMessagesJob,
            receiptManager: receiptManager,
            outgoingReceiptManager: outgoingReceiptManager,
            reachabilityManager: reachabilityManager,
            syncManager: syncManager,
            typingIndicators: typingIndicators,
            attachmentDownloads: attachmentDownloads,
            stickerManager: stickerManager,
            databaseStorage: databaseStorage,
            signalServiceAddressCache: signalServiceAddressCache,
            signalService: signalService,
            accountServiceClient: accountServiceClient,
            storageServiceManager: storageServiceManager,
            storageCoordinator: storageCoordinator,
            sskPreferences: sskPreferences,
            groupsV2: groupsV2,
            groupV2Updates: groupV2Updates,
            messageFetcherJob: messageFetcherJob,
            bulkProfileFetch: bulkProfileFetch,
            versionedProfiles: versionedProfiles,
            modelReadCaches: modelReadCaches,
            earlyMessageManager: earlyMessageManager,
            messagePipelineSupervisor: messagePipelineSupervisor,
            appExpiry: appExpiry,
            messageProcessor: messageProcessor,
            paymentsHelper: paymentsHelper,
            paymentsCurrencies: paymentsCurrencies,
            paymentsEvents: paymentsEvents,
            mobileCoinHelper: mobileCoinHelper,
            spamChallengeResolver: spamChallengeResolver,
            senderKeyStore: senderKeyStore,
            phoneNumberUtil: phoneNumberUtil,
            webSocketFactory: webSocketFactory,
            legacyChangePhoneNumber: legacyChangePhoneNumber,
            subscriptionManager: subscriptionManager,
            systemStoryManager: systemStoryManager,
            remoteMegaphoneFetcher: remoteMegaphoneFetcher,
            sskJobQueues: sskJobQueues,
            contactDiscoveryManager: contactDiscoveryManager,
            callMessageHandler: FakeCallMessageHandler(),
            notificationsManager: notificationsManager,
            messageSendLog: messageSendLog
        )
    }

    @objc
    public func configureGrdb() {
        do {
            try GRDBSchemaMigrator.migrateDatabase(
                databaseStorage: databaseStorage,
                isMainDatabase: true,
                runDataMigrations: true
            )
        } catch {
            owsFail("\(error)")
        }
    }

}

#endif
