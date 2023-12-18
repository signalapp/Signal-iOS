//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit

public class AppSetup {
    public init() {}

    public func start(
        appContext: AppContext,
        appVersion: AppVersion,
        paymentsEvents: PaymentsEvents,
        mobileCoinHelper: MobileCoinHelper,
        webSocketFactory: WebSocketFactory,
        callMessageHandler: OWSCallMessageHandler,
        notificationPresenter: NotificationsProtocolSwift
    ) -> AppSetup.DatabaseContinuation {
        configureUnsatisfiableConstraintLogging()

        let sleepBlockObject = NSObject()
        DeviceSleepManager.shared.addBlock(blockObject: sleepBlockObject)

        let backgroundTask = OWSBackgroundTask(label: #function)

        // Order matters here.
        //
        // All of these "singletons" should have any dependencies used in their
        // initializers injected.
        OWSBackgroundTaskManager.shared().observeNotifications()

        let storageCoordinator = StorageCoordinator()
        let databaseStorage = storageCoordinator.nonGlobalDatabaseStorage

        // AFNetworking (via CFNetworking) spools its attachments in
        // NSTemporaryDirectory(). If you receive a media message while the device
        // is locked, the download will fail if the temporary directory is
        // NSFileProtectionComplete.
        let temporaryDirectory = NSTemporaryDirectory()
        owsAssert(OWSFileSystem.ensureDirectoryExists(temporaryDirectory))
        owsAssert(OWSFileSystem.protectFileOrFolder(atPath: temporaryDirectory, fileProtectionType: .completeUntilFirstUserAuthentication))

        let keyValueStoreFactory = SDSKeyValueStoreFactory()

        // MARK: DependenciesBridge

        let recipientDatabaseTable = RecipientDatabaseTableImpl()
        let recipientFetcher = RecipientFetcherImpl(recipientDatabaseTable: recipientDatabaseTable)
        let recipientIdFinder = RecipientIdFinder(recipientDatabaseTable: recipientDatabaseTable, recipientFetcher: recipientFetcher)

        let accountServiceClient = AccountServiceClient()
        let aciSignalProtocolStore = SignalProtocolStoreImpl(
            for: .aci,
            keyValueStoreFactory: keyValueStoreFactory,
            recipientIdFinder: recipientIdFinder
        )
        let blockingManager = BlockingManager()
        let dateProvider = Date.provider
        let groupsV2 = GroupsV2Impl()
        let messageProcessor = MessageProcessor()
        let messageSender = MessageSender()
        let messageSenderJobQueue = MessageSenderJobQueue()
        let modelReadCaches = ModelReadCaches(factory: ModelReadCacheFactory())
        let networkManager = NetworkManager()
        let ows2FAManager = OWS2FAManager()
        let pniSignalProtocolStore = SignalProtocolStoreImpl(
            for: .pni,
            keyValueStoreFactory: keyValueStoreFactory,
            recipientIdFinder: recipientIdFinder
        )
        let profileManager = OWSProfileManager(databaseStorage: databaseStorage)
        let reachabilityManager = SSKReachabilityManagerImpl()
        let receiptManager = OWSReceiptManager()
        let senderKeyStore = SenderKeyStore()
        let signalProtocolStoreManager = SignalProtocolStoreManagerImpl(
            aciProtocolStore: aciSignalProtocolStore,
            pniProtocolStore: pniSignalProtocolStore
        )
        let signalService = OWSSignalService()
        let signalServiceAddressCache = SignalServiceAddressCache()
        let storageServiceManager = StorageServiceManagerImpl.shared
        let syncManager = OWSSyncManager(default: ())
        let udManager = OWSUDManagerImpl()
        let versionedProfiles = VersionedProfilesImpl()

        let dependenciesBridge = DependenciesBridge.setUpSingleton(
            accountServiceClient: accountServiceClient,
            appContext: appContext,
            appVersion: appVersion,
            blockingManager: blockingManager,
            databaseStorage: databaseStorage,
            dateProvider: dateProvider,
            groupsV2: groupsV2,
            keyValueStoreFactory: keyValueStoreFactory,
            messageProcessor: messageProcessor,
            messageSender: messageSender,
            messageSenderJobQueue: messageSenderJobQueue,
            modelReadCaches: modelReadCaches,
            networkManager: networkManager,
            notificationsManager: notificationPresenter,
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

        // MARK: SignalMessaging environment properties

        let preferences = Preferences()
        let proximityMonitoringManager = OWSProximityMonitoringManagerImpl()
        let avatarBuilder = AvatarBuilder()
        let smJobQueues = SignalMessagingJobQueues(
            db: dependenciesBridge.db,
            reachabilityManager: reachabilityManager
        )

        // MARK: SSK environment properties

        let appExpiry = dependenciesBridge.appExpiry
        let contactsManager = OWSContactsManager(swiftValues: .makeWithValuesFromDependenciesBridge())
        let linkPreviewManager = OWSLinkPreviewManager()
        let pendingReceiptRecorder = MessageRequestPendingReceipts()
        let messageReceiver = MessageReceiver()
        let remoteConfigManager = RemoteConfigManagerImpl(
            appExpiry: appExpiry,
            db: dependenciesBridge.db,
            keyValueStoreFactory: dependenciesBridge.keyValueStoreFactory,
            tsAccountManager: dependenciesBridge.tsAccountManager,
            serviceClient: SignalServiceRestClient.shared
        )
        let messageDecrypter = OWSMessageDecrypter()
        let groupsV2MessageProcessor = GroupsV2MessageProcessor()
        let disappearingMessagesJob = OWSDisappearingMessagesJob()
        let outgoingReceiptManager = OWSOutgoingReceiptManager()
        let typingIndicators = TypingIndicatorsImpl()
        let attachmentDownloads = OWSAttachmentDownloads()
        let stickerManager = StickerManager()
        let sskPreferences = SSKPreferences()
        let groupV2Updates = GroupV2UpdatesImpl()
        let messageFetcherJob = MessageFetcherJob()
        let bulkProfileFetch = BulkProfileFetch(
            databaseStorage: databaseStorage,
            reachabilityManager: reachabilityManager,
            tsAccountManager: dependenciesBridge.tsAccountManager
        )
        let earlyMessageManager = EarlyMessageManager()
        let messagePipelineSupervisor = MessagePipelineSupervisor()
        let paymentsHelper = PaymentsHelperImpl()
        let paymentsCurrencies = PaymentsCurrenciesImpl()
        let spamChallengeResolver = SpamChallengeResolver()
        let phoneNumberUtil = PhoneNumberUtil()
        let legacyChangePhoneNumber = LegacyChangePhoneNumber()
        let subscriptionManager = SubscriptionManagerImpl()
        let systemStoryManager = SystemStoryManager()
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
        let messageSendLog = MessageSendLog(
            db: dependenciesBridge.db,
            dateProvider: { Date() }
        )
        let localUserLeaveGroupJobQueue = LocalUserLeaveGroupJobQueue()

        let smEnvironment = SMEnvironment(
            preferences: preferences,
            proximityMonitoringManager: proximityMonitoringManager,
            avatarBuilder: avatarBuilder,
            smJobQueues: smJobQueues
        )
        SMEnvironment.setShared(smEnvironment)

        let sskEnvironment = SSKEnvironment(
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
            contactDiscoveryManager: contactDiscoveryManager,
            callMessageHandler: callMessageHandler,
            notificationsManager: notificationPresenter,
            messageSendLog: messageSendLog,
            messageSenderJobQueue: messageSenderJobQueue,
            localUserLeaveGroupJobQueue: localUserLeaveGroupJobQueue
        )
        SSKEnvironment.setShared(sskEnvironment, isRunningTests: appContext.isRunningTests)

        // Register renamed classes.
        NSKeyedUnarchiver.setClass(OWSUserProfile.self, forClassName: OWSUserProfile.collection())
        NSKeyedUnarchiver.setClass(TSGroupModelV2.self, forClassName: "TSGroupModelV2")

        Sounds.performStartupTasks()

        return AppSetup.DatabaseContinuation(
            appContext: appContext,
            smEnvironment: smEnvironment,
            sskEnvironment: sskEnvironment,
            backgroundTask: backgroundTask
        )
    }

    private func configureUnsatisfiableConstraintLogging() {
        UserDefaults.standard.setValue(DebugFlags.internalLogging, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
    }
}

// MARK: - DatabaseContinuation

extension AppSetup {
    public class DatabaseContinuation {
        private let appContext: AppContext
        private let smEnvironment: SMEnvironment
        private let sskEnvironment: SSKEnvironment
        private let backgroundTask: OWSBackgroundTask

        fileprivate init(
            appContext: AppContext,
            smEnvironment: SMEnvironment,
            sskEnvironment: SSKEnvironment,
            backgroundTask: OWSBackgroundTask
        ) {
            self.appContext = appContext
            self.smEnvironment = smEnvironment
            self.sskEnvironment = sskEnvironment
            self.backgroundTask = backgroundTask
        }
    }
}

extension AppSetup.DatabaseContinuation {
    public func prepareDatabase() -> Guarantee<AppSetup.FinalContinuation> {
        let databaseStorage = sskEnvironment.databaseStorageRef

        let (guarantee, future) = Guarantee<AppSetup.FinalContinuation>.pending()
        DispatchQueue.global().async {
            if self.shouldTruncateGrdbWal() {
                // Try to truncate GRDB WAL before any readers or writers are active.
                do {
                    try databaseStorage.grdbStorage.syncTruncatingCheckpoint()
                } catch {
                    owsFailDebug("Failed to truncate database: \(error)")
                }
            }
            databaseStorage.runGrdbSchemaMigrationsOnMainDatabase {
                self.sskEnvironment.warmCaches()
                self.smEnvironment.didLoadDatabase()
                self.backgroundTask.end()
                future.resolve(AppSetup.FinalContinuation(sskEnvironment: self.sskEnvironment))
            }
        }
        return guarantee
    }

    private func shouldTruncateGrdbWal() -> Bool {
        guard appContext.isMainApp else {
            return false
        }
        guard appContext.mainApplicationStateOnLaunch() != .background else {
            return false
        }
        return true
    }
}

// MARK: - FinalContinuation

extension AppSetup {
    public class FinalContinuation {
        private let sskEnvironment: SSKEnvironment

        fileprivate init(sskEnvironment: SSKEnvironment) {
            self.sskEnvironment = sskEnvironment
        }
    }
}

extension AppSetup.FinalContinuation {
    public enum SetupError: Error {
        case corruptRegistrationState
    }

    public func finish(willResumeInProgressRegistration: Bool) -> SetupError? {
        AssertIsOnMainThread()

        guard setUpLocalIdentifiers(willResumeInProgressRegistration: willResumeInProgressRegistration) else {
            return .corruptRegistrationState
        }

        return nil
    }

    private func setUpLocalIdentifiers(willResumeInProgressRegistration: Bool) -> Bool {
        let databaseStorage = sskEnvironment.databaseStorageRef
        let storageServiceManager = sskEnvironment.storageServiceManagerRef
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        let updateLocalIdentifiers: (LocalIdentifiersObjC) -> Void = { [weak storageServiceManager] localIdentifiers in
            storageServiceManager?.setLocalIdentifiers(localIdentifiers)
        }

        if
            tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
            && !willResumeInProgressRegistration
        {
            let localIdentifiers = databaseStorage.read { tsAccountManager.localIdentifiers(tx: $0.asV2Read) }
            guard let localIdentifiers else {
                return false
            }
            updateLocalIdentifiers(LocalIdentifiersObjC(localIdentifiers))
            // We are fully registered, and we're not in the middle of registration, so
            // ensure discoverability is configured.
            setUpDefaultDiscoverability()
        }

        return true
    }

    private func setUpDefaultDiscoverability() {
        let databaseStorage = sskEnvironment.databaseStorageRef
        let phoneNumberDiscoverabilityManager = DependenciesBridge.shared.phoneNumberDiscoverabilityManager
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        if databaseStorage.read(block: { tsAccountManager.phoneNumberDiscoverability(tx: $0.asV2Read) }) != nil {
            return
        }

        databaseStorage.write { tx in
            phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                PhoneNumberDiscoverabilityManager.Constants.discoverabilityDefault,
                updateAccountAttributes: true,
                updateStorageService: true,
                authedAccount: .implicit(),
                tx: tx.asV2Write
            )
        }
    }
}
