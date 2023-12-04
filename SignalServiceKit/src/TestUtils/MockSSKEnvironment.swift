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
        let keyValueStoreFactory = InMemoryKeyValueStoreFactory()

        // Set up DependenciesBridge

        let recipientDatabaseTable = RecipientDatabaseTableImpl()
        let recipientFetcher = RecipientFetcherImpl(recipientDatabaseTable: recipientDatabaseTable)
        let recipientIdFinder = RecipientIdFinder(recipientDatabaseTable: recipientDatabaseTable, recipientFetcher: recipientFetcher)

        let accountServiceClient = FakeAccountServiceClient()
        let aciSignalProtocolStore = SignalProtocolStoreImpl(
            for: .aci,
            keyValueStoreFactory: keyValueStoreFactory,
            recipientIdFinder: recipientIdFinder
        )
        let blockingManager = BlockingManager()
        let dateProvider = Date.provider
        let groupsV2 = MockGroupsV2()
        let messageProcessor = MessageProcessor()
        let messageSender = FakeMessageSender()
        let modelReadCaches = ModelReadCaches(factory: TestableModelReadCacheFactory())
        let networkManager = OWSFakeNetworkManager()
        let notificationsManager = NoopNotificationsManager()
        let ows2FAManager = OWS2FAManager()
        let paymentsEvents = PaymentsEventsNoop()
        let pniSignalProtocolStore = SignalProtocolStoreImpl(
            for: .pni,
            keyValueStoreFactory: keyValueStoreFactory,
            recipientIdFinder: recipientIdFinder
        )
        let profileManager = OWSFakeProfileManager()
        let receiptManager = OWSReceiptManager()
        let senderKeyStore = SenderKeyStore()
        let signalProtocolStoreManager = SignalProtocolStoreManagerImpl(
            aciProtocolStore: aciSignalProtocolStore,
            pniProtocolStore: pniSignalProtocolStore
        )
        let signalService = OWSSignalServiceMock()
        let signalServiceAddressCache = SignalServiceAddressCache()
        let storageServiceManager = FakeStorageServiceManager()
        let syncManager = OWSMockSyncManager()
        let udManager = OWSUDManagerImpl()
        let versionedProfiles = MockVersionedProfiles()
        let webSocketFactory = WebSocketFactoryMock()
        let sskJobQueues = SSKJobQueues()

        let dependenciesBridge = DependenciesBridge.setUpSingleton(
            accountServiceClient: accountServiceClient,
            appContext: TestAppContext(),
            appVersion: AppVersionImpl.shared,
            blockingManager: blockingManager,
            databaseStorage: databaseStorage,
            dateProvider: dateProvider,
            groupsV2: groupsV2,
            jobQueues: sskJobQueues,
            keyValueStoreFactory: keyValueStoreFactory,
            messageProcessor: messageProcessor,
            messageSender: messageSender,
            modelReadCaches: modelReadCaches,
            networkManager: networkManager,
            notificationsManager: notificationsManager,
            ows2FAManager: ows2FAManager,
            paymentsEvents: paymentsEvents,
            profileManager: profileManager,
            receiptManager: receiptManager,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            recipientIdFinder: recipientIdFinder,
            senderKeyStore: senderKeyStore,
            signalProtocolStoreManager: signalProtocolStoreManager,
            signalService: signalService,
            signalServiceAddressCache: signalServiceAddressCache,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            udManager: udManager,
            versionedProfiles: versionedProfiles,
            websocketFactory: webSocketFactory
        )

        // Set up ourselves
        let appExpiry = dependenciesBridge.appExpiry
        let contactsManager = FakeContactsManager()
        let linkPreviewManager = OWSLinkPreviewManager()
        let pendingReceiptRecorder = NoopPendingReceiptRecorder()
        let messageReceiver = MessageReceiver()
        let remoteConfigManager = StubbableRemoteConfigManager()
        let messageDecrypter = OWSMessageDecrypter()
        let groupsV2MessageProcessor = GroupsV2MessageProcessor()
        let disappearingMessagesJob = OWSDisappearingMessagesJob()
        let outgoingReceiptManager = OWSOutgoingReceiptManager()
        let reachabilityManager = MockSSKReachabilityManager()
        let typingIndicators = TypingIndicatorsImpl()
        let attachmentDownloads = OWSAttachmentDownloads()
        let stickerManager = StickerManager()
        let sskPreferences = SSKPreferences()
        let groupV2Updates = MockGroupV2Updates()
        let messageFetcherJob = MessageFetcherJob()
        let bulkProfileFetch = BulkProfileFetch(
            databaseStorage: databaseStorage,
            reachabilityManager: reachabilityManager,
            tsAccountManager: dependenciesBridge.tsAccountManager
        )
        let earlyMessageManager = EarlyMessageManager()
        let messagePipelineSupervisor = MessagePipelineSupervisor()
        let paymentsHelper = MockPaymentsHelper()
        let paymentsCurrencies = MockPaymentsCurrencies()
        let mobileCoinHelper = MobileCoinHelperMock()
        let spamChallengeResolver = SpamChallengeResolver()
        let phoneNumberUtil = PhoneNumberUtil()
        let legacyChangePhoneNumber = LegacyChangePhoneNumber()
        let subscriptionManager = MockSubscriptionManager()
        let systemStoryManager = SystemStoryManagerMock()
        let remoteMegaphoneFetcher = RemoteMegaphoneFetcher()
        let contactDiscoveryManager = ContactDiscoveryManagerImpl(
            db: dependenciesBridge.db,
            recipientDatabaseTable: dependenciesBridge.recipientDatabaseTable,
            recipientFetcher: dependenciesBridge.recipientFetcher,
            recipientMerger: dependenciesBridge.recipientMerger,
            tsAccountManager: dependenciesBridge.tsAccountManager,
            udManager: udManager,
            websocketFactory: webSocketFactory
        )
        let messageSendLog = MessageSendLog(db: dependenciesBridge.db, dateProvider: { Date() })

        super.init(
            contactsManager: contactsManager,
            linkPreviewManager: linkPreviewManager,
            messageSender: messageSender,
            pendingReceiptRecorder: pendingReceiptRecorder,
            profileManager: profileManager,
            networkManager: networkManager,
            messageReceiver: messageReceiver,
            blockingManager: blockingManager,
            remoteConfigManager: remoteConfigManager,
            aciSignalProtocolStore: aciSignalProtocolStore,
            pniSignalProtocolStore: pniSignalProtocolStore,
            udManager: udManager,
            messageDecrypter: messageDecrypter,
            groupsV2MessageProcessor: groupsV2MessageProcessor,
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
