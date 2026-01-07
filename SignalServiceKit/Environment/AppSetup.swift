//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient
import SDWebImage
import SDWebImageWebPCoder

public class AppSetup {
    private let backgroundTask: OWSBackgroundTask
    public init() {
        self.backgroundTask = OWSBackgroundTask(label: #function)
    }
}

extension AppSetup {
    public func start(
        appContext: any AppContext,
        databaseStorage: SDSDatabaseStorage,
    ) -> AppSetup.SchemaMigrationContinuation {
        return SchemaMigrationContinuation(
            appContext: appContext,
            backgroundTask: backgroundTask,
            databaseStorage: databaseStorage,
        )
    }

    public class SchemaMigrationContinuation {
        fileprivate let appContext: any AppContext
        fileprivate let backgroundTask: OWSBackgroundTask
        fileprivate let databaseStorage: SDSDatabaseStorage

        fileprivate init(
            appContext: any AppContext,
            backgroundTask: OWSBackgroundTask,
            databaseStorage: SDSDatabaseStorage,
        ) {
            self.appContext = appContext
            self.backgroundTask = backgroundTask
            self.databaseStorage = databaseStorage
        }
    }
}

// MARK: - SchemaMigrationContinuation

extension AppSetup.SchemaMigrationContinuation {
    public func migrateDatabaseSchema() async -> AppSetup.GlobalsContinuation {
        if self.shouldTruncateGrdbWal() {
            // Try to truncate GRDB WAL before any readers or writers are active.
            do {
                databaseStorage.logFileSizes()
                try databaseStorage.grdbStorage.syncTruncatingCheckpoint()
                databaseStorage.logFileSizes()
            } catch {
                owsFailDebug("Failed to truncate database: \(error)")
            }
        }
        databaseStorage.runGrdbSchemaMigrations()
        SSKPreferences.markGRDBSchemaAsLatest()
        return AppSetup.GlobalsContinuation(
            appContext: appContext,
            backgroundTask: backgroundTask,
            databaseStorage: databaseStorage,
        )
    }

    private func shouldTruncateGrdbWal() -> Bool {
        appContext.isMainApp && appContext.mainApplicationStateOnLaunch() != .background
    }
}

// MARK: - GlobalsContinuation

extension AppSetup {
    /// Injectable mocks for global singletons accessed by tests for components
    /// that cannot be isolated in tests.
    ///
    /// For example, many legacy tests rely on the globally-available singletons
    /// from ``Dependencies`` and its ``NSObject`` extension, and use this type
    /// to inject mock versions of those singletons to the global state.
    ///
    /// Additionally, the integration tests for message backup access these
    /// globals transitively through message backup's dependency on managers
    /// that use the global state, and similarly use this type to inject a
    /// limited set of mock singletons.
    public struct TestDependencies {
        let backupAttachmentCoordinator: BackupAttachmentCoordinator?
        let contactManager: (any ContactManager)?
        let dateProvider: DateProvider?
        let groupV2Updates: (any GroupV2Updates)?
        let groupsV2: (any GroupsV2)?
        let messageSender: (AccountChecker) -> MessageSender?
        let networkManager: NetworkManager?
        let paymentsCurrencies: (any PaymentsCurrenciesSwift)?
        let paymentsHelper: (any PaymentsHelperSwift)?
        let pendingReceiptRecorder: (any PendingReceiptRecorder)?
        let profileManager: (any ProfileManager)?
        let reachabilityManager: (any SSKReachabilityManager)?
        let remoteConfigManager: (any RemoteConfigManager)?
        let signalService: (any OWSSignalServiceProtocol)?
        let storageServiceManager: (any StorageServiceManager)?
        let syncManager: (any SyncManagerProtocol)?
        let systemStoryManager: (any SystemStoryManagerProtocol)?
        let versionedProfiles: (any VersionedProfiles)?
        let webSocketFactory: (any WebSocketFactory)?

        public init(
            backupAttachmentCoordinator: BackupAttachmentCoordinator? = nil,
            contactManager: (any ContactManager)? = nil,
            dateProvider: DateProvider? = nil,
            groupV2Updates: (any GroupV2Updates)? = nil,
            groupsV2: (any GroupsV2)? = nil,
            messageSender: @escaping ((AccountChecker) -> MessageSender?) = { _ in nil },
            networkManager: NetworkManager? = nil,
            paymentsCurrencies: (any PaymentsCurrenciesSwift)? = nil,
            paymentsHelper: (any PaymentsHelperSwift)? = nil,
            pendingReceiptRecorder: (any PendingReceiptRecorder)? = nil,
            profileManager: (any ProfileManager)? = nil,
            reachabilityManager: (any SSKReachabilityManager)? = nil,
            remoteConfigManager: (any RemoteConfigManager)? = nil,
            signalService: (any OWSSignalServiceProtocol)? = nil,
            storageServiceManager: (any StorageServiceManager)? = nil,
            syncManager: (any SyncManagerProtocol)? = nil,
            systemStoryManager: (any SystemStoryManagerProtocol)? = nil,
            versionedProfiles: (any VersionedProfiles)? = nil,
            webSocketFactory: (any WebSocketFactory)? = nil,
        ) {
            self.backupAttachmentCoordinator = backupAttachmentCoordinator
            self.contactManager = contactManager
            self.dateProvider = dateProvider
            self.groupV2Updates = groupV2Updates
            self.groupsV2 = groupsV2
            self.messageSender = messageSender
            self.networkManager = networkManager
            self.paymentsCurrencies = paymentsCurrencies
            self.paymentsHelper = paymentsHelper
            self.pendingReceiptRecorder = pendingReceiptRecorder
            self.profileManager = profileManager
            self.reachabilityManager = reachabilityManager
            self.remoteConfigManager = remoteConfigManager
            self.signalService = signalService
            self.storageServiceManager = storageServiceManager
            self.syncManager = syncManager
            self.systemStoryManager = systemStoryManager
            self.versionedProfiles = versionedProfiles
            self.webSocketFactory = webSocketFactory
        }
    }

    public class GlobalsContinuation {
        fileprivate let appContext: any AppContext
        fileprivate let backgroundTask: OWSBackgroundTask
        fileprivate let databaseStorage: SDSDatabaseStorage

        fileprivate init(
            appContext: any AppContext,
            backgroundTask: OWSBackgroundTask,
            databaseStorage: SDSDatabaseStorage,
        ) {
            self.appContext = appContext
            self.backgroundTask = backgroundTask
            self.databaseStorage = databaseStorage
        }
    }
}

extension AppSetup.GlobalsContinuation {
    @MainActor
    public func initGlobals(
        appReadiness: AppReadiness,
        backupArchiveErrorPresenterFactory: BackupArchiveErrorPresenterFactory,
        deviceBatteryLevelManager: (any DeviceBatteryLevelManager)?,
        deviceSleepManager: (any DeviceSleepManager)?,
        paymentsEvents: PaymentsEvents,
        mobileCoinHelper: MobileCoinHelper,
        callMessageHandler: CallMessageHandler,
        currentCallProvider: any CurrentCallProvider,
        notificationPresenter: any NotificationPresenter,
        testDependencies: AppSetup.TestDependencies = AppSetup.TestDependencies(),
    ) -> AppSetup.DataMigrationContinuation {
        configureUnsatisfiableConstraintLogging()

        // Order matters here.
        //
        // All of these "singletons" should have any dependencies used in their
        // initializers injected.
        OWSBackgroundTaskManager.shared.observeNotifications()

        let appVersion = AppVersionImpl.shared
        let webSocketFactory = testDependencies.webSocketFactory ?? WebSocketFactoryNative()

        // AFNetworking (via CFNetworking) spools its attachments in
        // NSTemporaryDirectory(). If you receive a media message while the device
        // is locked, the download will fail if the temporary directory is
        // NSFileProtectionComplete.
        let temporaryDirectory = NSTemporaryDirectory()
        owsPrecondition(OWSFileSystem.ensureDirectoryExists(temporaryDirectory))
        owsPrecondition(OWSFileSystem.protectFileOrFolder(atPath: temporaryDirectory, fileProtectionType: .completeUntilFirstUserAuthentication))

        let tsConstants = TSConstants.shared
        let dateProvider = testDependencies.dateProvider ?? Date.provider

        let tsAccountManager = TSAccountManagerImpl(
            appReadiness: appReadiness,
            dateProvider: dateProvider,
            databaseChangeObserver: databaseStorage.databaseChangeObserver,
            db: databaseStorage,
        )

        let remoteConfigProvider = RemoteConfigProviderImpl(tsAccountManager: tsAccountManager)
        let remoteConfig = databaseStorage.read { tx in
            tsAccountManager.warmCaches(tx: tx)
            return remoteConfigProvider.warmCaches(tx: tx)
        }

        let libsignalNet = Net(
            env: TSConstants.isUsingProductionService ? .production : .staging,
            userAgent: HttpHeaders.userAgentHeaderValueSignalIos,
            buildVariant: BuildFlags.netBuildVariant,
            remoteConfig: remoteConfig.netConfig(),
        )

        let cron = Cron(
            appVersion: appVersion.currentAppVersion4,
            db: databaseStorage,
        )

        let recipientDatabaseTable = RecipientDatabaseTable()
        let signalAccountStore = SignalAccountStoreImpl()
        let threadStore = ThreadStoreImpl()
        let userProfileStore = UserProfileStoreImpl()
        let usernameLookupRecordStore = UsernameLookupRecordStore()
        let nicknameRecordStore = NicknameRecordStoreImpl()
        let searchableNameIndexer = SearchableNameIndexerImpl(
            threadStore: threadStore,
            signalAccountStore: signalAccountStore,
            userProfileStore: userProfileStore,
            signalRecipientStore: recipientDatabaseTable,
            usernameLookupRecordStore: usernameLookupRecordStore,
            nicknameRecordStore: nicknameRecordStore,
        )
        let recipientFetcher = RecipientFetcher(
            recipientDatabaseTable: recipientDatabaseTable,
            searchableNameIndexer: searchableNameIndexer,
        )
        let recipientIdFinder = RecipientIdFinder(recipientDatabaseTable: recipientDatabaseTable, recipientFetcher: recipientFetcher)

        let dateProviderMonotonic = MonotonicDate.provider

        let avatarDefaultColorManager = AvatarDefaultColorManager()

        let appExpiry = AppExpiry(
            appVersion: appVersion,
        )

        let db = databaseStorage

        let networkManager = testDependencies.networkManager ?? NetworkManager(
            appReadiness: appReadiness,
            libsignalNet: libsignalNet,
        )
        let whoAmIManager = WhoAmIManagerImpl(networkManager: networkManager)

        let remoteConfigManager = testDependencies.remoteConfigManager ?? RemoteConfigManagerImpl(
            appExpiry: appExpiry,
            appReadiness: appReadiness,
            dateProvider: dateProvider,
            db: db,
            net: libsignalNet,
            networkManager: networkManager,
            remoteConfigProvider: remoteConfigProvider,
            tsAccountManager: tsAccountManager,
        )

        let preKeyStore = PreKeyStore()
        let sessionStore = SessionStore()

        let aciProtocolStore = SignalProtocolStore.build(
            dateProvider: dateProvider,
            identity: .aci,
            preKeyStore: preKeyStore,
            recipientIdFinder: recipientIdFinder,
            sessionStore: sessionStore,
        )
        let blockedRecipientStore = BlockedRecipientStore()
        let blockingManager = BlockingManager(
            blockedGroupStore: BlockedGroupStore(),
            blockedRecipientStore: blockedRecipientStore,
        )
        let earlyMessageManager = EarlyMessageManager(appReadiness: appReadiness)
        let messageProcessor = MessageProcessor(appReadiness: appReadiness)

        let groupSendEndorsementStore = GroupSendEndorsementStoreImpl()

        let messageSenderJobQueue = MessageSenderJobQueue(appReadiness: appReadiness)
        let modelReadCaches = ModelReadCaches(
            factory: ModelReadCacheFactory(appReadiness: appReadiness),
        )
        let ows2FAManager = OWS2FAManager()
        let paymentsHelper = testDependencies.paymentsHelper ?? PaymentsHelperImpl()
        let archivedPaymentStore = ArchivedPaymentStore()
        let pniProtocolStore = SignalProtocolStore.build(
            dateProvider: dateProvider,
            identity: .pni,
            preKeyStore: preKeyStore,
            recipientIdFinder: recipientIdFinder,
            sessionStore: sessionStore,
        )
        let profileManager = testDependencies.profileManager ?? OWSProfileManager(
            appReadiness: appReadiness,
            databaseStorage: databaseStorage,
        )
        let reachabilityManager = testDependencies.reachabilityManager ?? SSKReachabilityManagerImpl(
            appReadiness: appReadiness,
        )

        let receiptManager = OWSReceiptManager(appReadiness: appReadiness, databaseStorage: databaseStorage, messageSenderJobQueue: messageSenderJobQueue, notificationPresenter: notificationPresenter)
        let senderKeyStore = OldSenderKeyStore()
        let signalProtocolStoreManager = SignalProtocolStoreManager(
            aciProtocolStore: aciProtocolStore,
            pniProtocolStore: pniProtocolStore,
            preKeyStore: preKeyStore,
            sessionStore: sessionStore,
        )
        let signalService = testDependencies.signalService ?? OWSSignalService(libsignalNet: libsignalNet)
        let signalServiceAddressCache = SignalServiceAddressCache()
        let storageServiceManager = testDependencies.storageServiceManager ?? StorageServiceManagerImpl(
            appReadiness: appReadiness,
        )
        let syncManager = testDependencies.syncManager ?? OWSSyncManager(appReadiness: appReadiness)
        let udManager = OWSUDManagerImpl(
            cron: cron,
            db: databaseStorage,
            tsAccountManager: tsAccountManager,
        )
        let versionedProfiles = testDependencies.versionedProfiles ?? VersionedProfilesImpl(appReadiness: appReadiness)

        let lastVisibleInteractionStore = LastVisibleInteractionStore()
        let usernameLookupManager = UsernameLookupManagerImpl(
            searchableNameIndexer: searchableNameIndexer,
            usernameLookupRecordStore: usernameLookupRecordStore,
        )

        let nicknameManager = NicknameManagerImpl(
            nicknameRecordStore: nicknameRecordStore,
            searchableNameIndexer: searchableNameIndexer,
            storageServiceManager: storageServiceManager,
        )
        let contactManager = testDependencies.contactManager ?? OWSContactsManager(
            appReadiness: appReadiness,
            nicknameManager: nicknameManager,
            recipientDatabaseTable: recipientDatabaseTable,
            usernameLookupManager: usernameLookupManager,
        )

        let authCredentialStore = AuthCredentialStore(dateProvider: dateProvider)

        let callLinkPublicParams = try! GenericServerPublicParams(contents: tsConstants.callLinkPublicParams)
        let authCredentialManager = AuthCredentialManagerImpl(
            authCredentialStore: authCredentialStore,
            callLinkPublicParams: callLinkPublicParams,
            dateProvider: dateProvider,
            db: db,
        )

        let groupsV2 = testDependencies.groupsV2 ?? GroupsV2Impl(
            appReadiness: appReadiness,
            authCredentialStore: authCredentialStore,
            authCredentialManager: authCredentialManager,
            groupSendEndorsementStore: groupSendEndorsementStore,
        )

        let mediaBandwidthPreferenceStore = MediaBandwidthPreferenceStoreImpl(
            reachabilityManager: reachabilityManager,
        )

        let interactionStore = InteractionStoreImpl()
        let storyStore = StoryStoreImpl()

        let audioWaveformManager = AudioWaveformManagerImpl()

        let attachmentStore = AttachmentStore()

        let orphanedAttachmentCleaner = OrphanedAttachmentCleanerImpl(db: db)
        let attachmentContentValidator = AttachmentContentValidatorImpl(
            attachmentStore: attachmentStore,
            audioWaveformManager: audioWaveformManager,
            db: db,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
        )

        let backupNonceMetadataStore = BackupNonceMetadataStore()
        let backupSettingsStore = BackupSettingsStore()
        let accountKeyStore = AccountKeyStore(
            backupSettingsStore: backupSettingsStore,
        )
        let svrCredentialStorage = SVRAuthCredentialStorageImpl()
        let svrLocalStorage = SVRLocalStorageImpl()

        let accountAttributesUpdater = AccountAttributesUpdaterImpl(
            accountAttributesGenerator: AccountAttributesGenerator(
                accountKeyStore: accountKeyStore,
                ows2FAManager: ows2FAManager,
                profileManager: profileManager,
                svrLocalStorage: svrLocalStorage,
                tsAccountManager: tsAccountManager,
                udManager: udManager,
            ),
            appReadiness: appReadiness,
            appVersion: appVersion,
            cron: cron,
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager,
            profileManager: profileManager,
            svrLocalStorage: svrLocalStorage,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
        )

        let phoneNumberDiscoverabilityManager = PhoneNumberDiscoverabilityManagerImpl(
            accountAttributesUpdater: accountAttributesUpdater,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
        )

        let subscriptionConfigManager = SubscriptionConfigManager(
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager,
        )

        let svr = SecureValueRecovery2Impl(
            appContext: SVR2.Wrappers.AppContext(),
            appReadiness: appReadiness,
            appVersion: appVersion,
            connectionFactory: SgxWebsocketConnectionFactoryImpl(websocketFactory: webSocketFactory),
            credentialStorage: svrCredentialStorage,
            db: db,
            accountKeyStore: accountKeyStore,
            scheduler: DispatchQueue(label: "org.signal.svr2", qos: .userInitiated),
            storageServiceManager: storageServiceManager,
            svrLocalStorage: svrLocalStorage,
            tsAccountManager: tsAccountManager,
            tsConstants: tsConstants,
            twoFAManager: SVR2.Wrappers.OWS2FAManager(ows2FAManager),
        )

        let backupAttachmentDownloadStore = BackupAttachmentDownloadStore()
        let backupAttachmentUploadEraStore = BackupAttachmentUploadEraStore()
        let backupAttachmentUploadProgress = BackupAttachmentUploadProgressImpl(
            attachmentStore: attachmentStore,
            backupSettingsStore: backupSettingsStore,
            db: db,
        )
        let backupAttachmentUploadStore = BackupAttachmentUploadStore()
        let backupCDNCredentialStore = BackupCDNCredentialStore()

        let backupIdService = BackupIdServiceImpl(
            accountKeyStore: accountKeyStore,
            backupSettingsStore: backupSettingsStore,
            db: db,
            networkManager: networkManager,
            tsAccountManager: tsAccountManager,
        )

        let backupPlanManager = BackupPlanManagerImpl(
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupAttachmentUploadProgress: backupAttachmentUploadProgress,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            tsAccountManager: tsAccountManager,
        )

        let backupSubscriptionIssueStore = BackupSubscriptionIssueStore()
        let backupSubscriptionManager = BackupSubscriptionManagerImpl(
            backupPlanManager: backupPlanManager,
            backupSubscriptionIssueStore: backupSubscriptionIssueStore,
            backupSubscriptionRedeemer: BackupSubscriptionRedeemer(
                authCredentialStore: authCredentialStore,
                backupPlanManager: backupPlanManager,
                backupSubscriptionIssueStore: backupSubscriptionIssueStore,
                dateProvider: dateProvider,
                db: db,
                reachabilityManager: reachabilityManager,
                networkManager: networkManager,
            ),
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
            whoAmIManager: whoAmIManager,
        )
        let backupTestFlightEntitlementManager = BackupTestFlightEntitlementManagerImpl(
            backupPlanManager: backupPlanManager,
            backupSubscriptionIssueStore: backupSubscriptionIssueStore,
            backupSubscriptionManager: backupSubscriptionManager,
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager,
            tsAccountManager: tsAccountManager,
        )

        let backupRequestManager = BackupRequestManagerImpl(
            backupAuthCredentialManager: BackupAuthCredentialManagerImpl(
                authCredentialStore: authCredentialStore,
                backupIdService: backupIdService,
                backupSubscriptionManager: backupSubscriptionManager,
                backupTestFlightEntitlementManager: backupTestFlightEntitlementManager,
                dateProvider: dateProvider,
                db: db,
                networkManager: networkManager,
            ),
            backupCDNCredentialStore: backupCDNCredentialStore,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager,
        )

        let backupKeyService = BackupKeyServiceImpl(
            accountKeyStore: accountKeyStore,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            db: db,
            networkManager: networkManager,
        )

        let orphanedAttachmentStore = OrphanedAttachmentStore()
        let attachmentUploadStore = AttachmentUploadStoreImpl(attachmentStore: attachmentStore)
        let attachmentDownloadStore = AttachmentDownloadStoreImpl(dateProvider: dateProvider)

        let orphanedBackupAttachmentStore = OrphanedBackupAttachmentStoreImpl()
        let orphanedBackupAttachmentScheduler = OrphanedBackupAttachmentSchedulerImpl(
            accountKeyStore: accountKeyStore,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
        )

        let attachmentThumbnailService = AttachmentThumbnailServiceImpl()
        let attachmentUploadManager = AttachmentUploadManagerImpl(
            accountKeyStore: accountKeyStore,
            attachmentEncrypter: Upload.Wrappers.AttachmentEncrypter(),
            attachmentStore: attachmentStore,
            attachmentUploadStore: attachmentUploadStore,
            attachmentThumbnailService: attachmentThumbnailService,
            backupRequestManager: backupRequestManager,
            dateProvider: dateProvider,
            db: db,
            fileSystem: Upload.Wrappers.FileSystem(),
            interactionStore: interactionStore,
            networkManager: networkManager,
            remoteConfigProvider: remoteConfigManager,
            signalService: signalService,
            sleepTimer: Upload.Wrappers.SleepTimer(),
            storyStore: storyStore,
        )

        let backupAttachmentDownloadQueueStatusManager = BackupAttachmentDownloadQueueStatusManagerImpl(
            appContext: appContext,
            appReadiness: appReadiness,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            deviceBatteryLevelManager: deviceBatteryLevelManager,
            reachabilityManager: reachabilityManager,
            remoteConfigManager: remoteConfigManager,
            tsAccountManager: tsAccountManager,
        )
        let backupAttachmentUploadQueueStatusManager = BackupAttachmentUploadQueueStatusManagerImpl(
            appContext: appContext,
            appReadiness: appReadiness,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            deviceBatteryLevelManager: deviceBatteryLevelManager,
            reachabilityManager: reachabilityManager,
            remoteConfigManager: remoteConfigManager,
            tsAccountManager: tsAccountManager,
        )

        let backupAttachmentDownloadProgress = BackupAttachmentDownloadProgressImpl(
            appContext: appContext,
            appReadiness: appReadiness,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            remoteConfigProvider: remoteConfigManager,
        )

        let backupAttachmentUploadScheduler = BackupAttachmentUploadSchedulerImpl(
            attachmentStore: attachmentStore,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            dateProvider: dateProvider,
            interactionStore: interactionStore,
        )

        let backupListMediaStore = BackupListMediaStore()
        let backupListMediaManager = BackupListMediaManagerImpl(
            accountKeyStore: accountKeyStore,
            attachmentStore: attachmentStore,
            attachmentUploadStore: attachmentUploadStore,
            backupAttachmentDownloadProgress: backupAttachmentDownloadProgress,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupAttachmentUploadProgress: backupAttachmentUploadProgress,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupListMediaStore: backupListMediaStore,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            notificationPresenter: notificationPresenter,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            remoteConfigManager: remoteConfigManager,
            tsAccountManager: tsAccountManager,
        )

        let attachmentDownloadManager = AttachmentDownloadManagerImpl(
            accountKeyStore: accountKeyStore,
            appReadiness: appReadiness,
            attachmentDownloadStore: attachmentDownloadStore,
            attachmentStore: attachmentStore,
            attachmentUploadStore: attachmentUploadStore,
            attachmentValidator: attachmentContentValidator,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            currentCallProvider: currentCallProvider,
            dateProvider: dateProvider,
            db: db,
            interactionStore: interactionStore,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            orphanedBackupAttachmentScheduler: orphanedBackupAttachmentScheduler,
            profileManager: profileManager,
            reachabilityManager: reachabilityManager,
            remoteConfigManager: remoteConfigManager,
            signalService: signalService,
            stickerManager: AttachmentDownloadManagerImpl.Wrappers.StickerManager(),
            storyStore: storyStore,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager,
        )
        let backupAttachmentDownloadScheduler = BackupAttachmentDownloadSchedulerImpl(
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
        )
        let backupAttachmentCoordinator = testDependencies.backupAttachmentCoordinator ?? BackupAttachmentCoordinatorImpl(
            appContext: appContext,
            appReadiness: appReadiness,
            backupSettingsStore: backupSettingsStore,
            db: db,
            downloadRunner: BackupAttachmentDownloadQueueRunnerImpl(
                appContext: appContext,
                attachmentStore: attachmentStore,
                attachmentDownloadManager: attachmentDownloadManager,
                attachmentUploadStore: attachmentUploadStore,
                backupAttachmentDownloadStore: backupAttachmentDownloadStore,
                backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                backupListMediaManager: backupListMediaManager,
                backupSettingsStore: backupSettingsStore,
                dateProvider: dateProvider,
                db: db,
                mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
                progress: backupAttachmentDownloadProgress,
                remoteConfigProvider: remoteConfigManager,
                statusManager: backupAttachmentDownloadQueueStatusManager,
                tsAccountManager: tsAccountManager,
            ),
            listMediaManager: backupListMediaManager,
            offloadingManager: AttachmentOffloadingManagerImpl(
                attachmentStore: attachmentStore,
                attachmentThumbnailService: attachmentThumbnailService,
                backupAttachmentDownloadStore: backupAttachmentDownloadStore,
                backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
                backupSettingsStore: backupSettingsStore,
                dateProvider: dateProvider,
                db: db,
                listMediaManager: backupListMediaManager,
                orphanedAttachmentCleaner: orphanedAttachmentCleaner,
                orphanedAttachmentStore: orphanedAttachmentStore,
                tsAccountManager: tsAccountManager,
            ),
            orphanRunner: OrphanedBackupAttachmentQueueRunnerImpl(
                accountKeyStore: accountKeyStore,
                appReadiness: appReadiness,
                attachmentStore: attachmentStore,
                backupRequestManager: backupRequestManager,
                backupSettingsStore: backupSettingsStore,
                dateProvider: dateProvider,
                db: db,
                listMediaManager: backupListMediaManager,
                orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
                tsAccountManager: tsAccountManager,
            ),
            orphanStore: orphanedBackupAttachmentStore,
            tsAccountManager: tsAccountManager,
            uploadRunner: BackupAttachmentUploadQueueRunnerImpl(
                accountKeyStore: accountKeyStore,
                attachmentStore: attachmentStore,
                attachmentUploadManager: attachmentUploadManager,
                backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                backupAttachmentUploadStore: backupAttachmentUploadStore,
                backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
                backupListMediaManager: backupListMediaManager,
                backupRequestManager: backupRequestManager,
                backupSettingsStore: backupSettingsStore,
                dateProvider: dateProvider,
                db: db,
                notificationPresenter: notificationPresenter,
                orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
                progress: backupAttachmentUploadProgress,
                statusManager: backupAttachmentUploadQueueStatusManager,
                tsAccountManager: tsAccountManager,
            ),
        )

        let attachmentManager = AttachmentManagerImpl(
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentStore: attachmentStore,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            dateProvider: dateProvider,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            orphanedBackupAttachmentScheduler: orphanedBackupAttachmentScheduler,
            remoteConfigManager: remoteConfigManager,
            stickerManager: AttachmentManagerImpl.Wrappers.StickerManager(),
        )
        let attachmentValidationBackfillMigrator = AttachmentValidationBackfillMigratorImpl(
            attachmentStore: attachmentStore,
            attachmentValidationBackfillStore: AttachmentValidationBackfillStore(),
            databaseStorage: databaseStorage,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            validator: attachmentContentValidator,
        )

        let quotedReplyManager = QuotedReplyManagerImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
            db: db,
            tsAccountManager: tsAccountManager,
        )

        let phoneNumberVisibilityFetcher = PhoneNumberVisibilityFetcherImpl(
            contactsManager: contactManager,
            tsAccountManager: tsAccountManager,
            userProfileStore: userProfileStore,
        )

        let recipientManager = SignalRecipientManagerImpl(
            phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
            recipientDatabaseTable: recipientDatabaseTable,
            storageServiceManager: storageServiceManager,
        )

        let badgeCountFetcher = BadgeCountFetcherImpl()

        let identityManager = OWSIdentityManagerImpl(
            appReadiness: appReadiness,
            db: db,
            messageSenderJobQueue: messageSenderJobQueue,
            networkManager: networkManager,
            notificationPresenter: notificationPresenter,
            pniProtocolStore: pniProtocolStore,
            profileManager: profileManager,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            recipientIdFinder: recipientIdFinder,
            sessionStore: sessionStore,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
        )

        let linkPreviewSettingStore = LinkPreviewSettingStore(keyValueStore: SSKPreferences.store)
        let linkPreviewSettingManager = LinkPreviewSettingManagerImpl(
            linkPreviewSettingStore: linkPreviewSettingStore,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
        )

        let linkPreviewManager = LinkPreviewManagerImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
            db: db,
            linkPreviewSettingStore: linkPreviewSettingStore,
        )

        let editMessageStore = EditMessageStore()
        let editManager = EditManagerImpl(
            context: .init(
                attachmentContentValidator: attachmentContentValidator,
                attachmentStore: attachmentStore,
                editManagerAttachments: EditManagerAttachmentsImpl(
                    attachmentManager: attachmentManager,
                    attachmentStore: attachmentStore,
                    attachmentValidator: attachmentContentValidator,
                    linkPreviewManager: linkPreviewManager,
                ),
                editMessageStore: editMessageStore,
                receiptManagerShim: EditManagerImpl.Wrappers.ReceiptManager(receiptManager: receiptManager),
            ),
        )

        let groupUpdateItemBuilder = GroupUpdateItemBuilderImpl(
            contactsManager: contactManager,
            recipientDatabaseTable: recipientDatabaseTable,
        )

        let groupUpdateInfoMessageInserter = GroupUpdateInfoMessageInserterImpl(
            dateProvider: dateProvider,
            groupUpdateItemBuilder: groupUpdateItemBuilder,
            notificationPresenter: notificationPresenter,
        )

        let groupMemberStore = GroupMemberStoreImpl()
        let threadAssociatedDataStore = ThreadAssociatedDataStoreImpl()
        let threadReplyInfoStore = ThreadReplyInfoStore()

        let wallpaperImageStore = WallpaperImageStoreImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
            db: db,
        )
        let wallpaperStore = WallpaperStore(
            wallpaperImageStore: wallpaperImageStore,
        )
        let chatColorSettingStore = ChatColorSettingStore(
            wallpaperStore: wallpaperStore,
        )

        let groupMemberUpdater = GroupMemberUpdaterImpl(
            temporaryShims: GroupMemberUpdaterTemporaryShimsImpl(),
            groupMemberStore: groupMemberStore,
            signalServiceAddressCache: signalServiceAddressCache,
        )

        let messageSendLog = MessageSendLog(
            db: db,
            dateProvider: { Date() },
        )

        let callLinkStore = CallLinkRecordStoreImpl()
        let deletedCallRecordStore = DeletedCallRecordStoreImpl()
        let deletedCallRecordExpirationJob = DeletedCallRecordExpirationJob(
            callLinkStore: callLinkStore,
            dateProvider: dateProvider,
            db: db,
            deletedCallRecordStore: deletedCallRecordStore,
        )
        let callRecordStore = CallRecordStoreImpl(
            deletedCallRecordStore: deletedCallRecordStore,
        )
        let callRecordSyncMessageConversationIdAdapater = CallRecordSyncMessageConversationIdAdapterImpl(
            callLinkStore: callLinkStore,
            callRecordStore: callRecordStore,
            recipientDatabaseTable: recipientDatabaseTable,
            threadStore: threadStore,
        )
        let outgoingCallEventSyncMessageManager = OutgoingCallEventSyncMessageManagerImpl(
            appReadiness: appReadiness,
            databaseStorage: databaseStorage,
            messageSenderJobQueue: messageSenderJobQueue,
            callRecordConversationIdAdapter: callRecordSyncMessageConversationIdAdapater,
        )
        let adHocCallRecordManager = AdHocCallRecordManagerImpl(
            callRecordStore: callRecordStore,
            callLinkStore: callLinkStore,
            outgoingSyncMessageManager: outgoingCallEventSyncMessageManager,
        )
        let groupCallRecordManager = GroupCallRecordManagerImpl(
            callRecordStore: callRecordStore,
            interactionStore: interactionStore,
            outgoingSyncMessageManager: outgoingCallEventSyncMessageManager,
        )
        let individualCallRecordManager = IndividualCallRecordManagerImpl(
            callRecordStore: callRecordStore,
            interactionStore: interactionStore,
            outgoingSyncMessageManager: outgoingCallEventSyncMessageManager,
        )
        let callRecordQuerier = CallRecordQuerierImpl()
        let callRecordMissedCallManager = CallRecordMissedCallManagerImpl(
            callRecordConversationIdAdapter: callRecordSyncMessageConversationIdAdapater,
            callRecordQuerier: callRecordQuerier,
            callRecordStore: callRecordStore,
            syncMessageSender: CallRecordMissedCallManagerImpl.Wrappers.SyncMessageSender(messageSenderJobQueue),
        )
        let callRecordDeleteManager = CallRecordDeleteManagerImpl(
            callRecordStore: callRecordStore,
            outgoingCallEventSyncMessageManager: outgoingCallEventSyncMessageManager,
            deletedCallRecordExpirationJob: deletedCallRecordExpirationJob,
            deletedCallRecordStore: deletedCallRecordStore,
            threadStore: threadStore,
        )

        let deleteForMeOutgoingSyncMessageManager = DeleteForMeOutgoingSyncMessageManagerImpl(
            recipientDatabaseTable: recipientDatabaseTable,
            syncMessageSender: DeleteForMeOutgoingSyncMessageManagerImpl.Wrappers.SyncMessageSender(messageSenderJobQueue),
            threadStore: threadStore,
        )
        let interactionDeleteManager = InteractionDeleteManagerImpl(
            callRecordStore: callRecordStore,
            callRecordDeleteManager: callRecordDeleteManager,
            databaseStorage: databaseStorage,
            deleteForMeOutgoingSyncMessageManager: deleteForMeOutgoingSyncMessageManager,
            interactionReadCache: modelReadCaches.interactionReadCache,
            interactionStore: interactionStore,
            messageSendLog: messageSendLog,
            tsAccountManager: tsAccountManager,
        )

        let disappearingMessagesConfigurationStore = DisappearingMessagesConfigurationStoreImpl()
        let disappearingMessagesExpirationJob = DisappearingMessagesExpirationJob(
            dateProvider: dateProvider,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
        )

        let callRecordDeleteAllJobQueue = CallRecordDeleteAllJobQueue(
            callLinkStore: callLinkStore,
            callRecordConversationIdAdapter: callRecordSyncMessageConversationIdAdapater,
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordQuerier: callRecordQuerier,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
            messageSenderJobQueue: messageSenderJobQueue,
        )
        let incomingCallEventSyncMessageManager = IncomingCallEventSyncMessageManagerImpl(
            adHocCallRecordManager: adHocCallRecordManager,
            callLinkStore: callLinkStore,
            callRecordStore: callRecordStore,
            callRecordDeleteManager: callRecordDeleteManager,
            groupCallRecordManager: groupCallRecordManager,
            individualCallRecordManager: individualCallRecordManager,
            interactionDeleteManager: interactionDeleteManager,
            interactionStore: interactionStore,
            markAsReadShims: IncomingCallEventSyncMessageManagerImpl.ShimsImpl.MarkAsRead(
                notificationPresenter: notificationPresenter,
            ),
            recipientDatabaseTable: recipientDatabaseTable,
            threadStore: threadStore,
        )
        let incomingCallLogEventSyncMessageManager = IncomingCallLogEventSyncMessageManagerImpl(
            callRecordConversationIdAdapter: callRecordSyncMessageConversationIdAdapater,
            deleteAllCallsJobQueue: IncomingCallLogEventSyncMessageManagerImpl.Wrappers.DeleteAllCallsJobQueue(
                callRecordDeleteAllJobQueue,
            ),
            missedCallManager: callRecordMissedCallManager,
        )

        let threadSoftDeleteManager = ThreadSoftDeleteManagerImpl(
            deleteForMeOutgoingSyncMessageManager: deleteForMeOutgoingSyncMessageManager,
            intentsManager: ThreadSoftDeleteManagerImpl.Wrappers.IntentsManager(),
            interactionDeleteManager: interactionDeleteManager,
            recipientDatabaseTable: recipientDatabaseTable,
            storyManager: ThreadSoftDeleteManagerImpl.Wrappers.StoryManager(),
            threadReplyInfoStore: threadReplyInfoStore,
            tsAccountManager: tsAccountManager,
        )

        let deleteForMeAddressableMessageFinder = DeleteForMeAddressableMessageFinderImpl(
            tsAccountManager: tsAccountManager,
        )
        let bulkDeleteInteractionJobQueue = BulkDeleteInteractionJobQueue(
            addressableMessageFinder: deleteForMeAddressableMessageFinder,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
            threadSoftDeleteManager: threadSoftDeleteManager,
            threadStore: threadStore,
        )
        let deleteForMeIncomingSyncMessageManager = DeleteForMeIncomingSyncMessageManagerImpl(
            addressableMessageFinder: deleteForMeAddressableMessageFinder,
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            bulkDeleteInteractionJobQueue: bulkDeleteInteractionJobQueue,
            interactionDeleteManager: interactionDeleteManager,
            threadSoftDeleteManager: threadSoftDeleteManager,
        )

        let threadRemover = ThreadRemoverImpl(
            chatColorSettingStore: chatColorSettingStore,
            databaseStorage: ThreadRemoverImpl.Wrappers.DatabaseStorage(databaseStorage),
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            lastVisibleInteractionStore: lastVisibleInteractionStore,
            threadAssociatedDataStore: threadAssociatedDataStore,
            threadReadCache: ThreadRemoverImpl.Wrappers.ThreadReadCache(modelReadCaches.threadReadCache),
            threadReplyInfoStore: threadReplyInfoStore,
            threadSoftDeleteManager: threadSoftDeleteManager,
            threadStore: threadStore,
            wallpaperStore: wallpaperStore,
        )

        let pinnedThreadStore = PinnedThreadStoreImpl()
        let pinnedThreadManager = PinnedThreadManagerImpl(
            db: db,
            pinnedThreadStore: pinnedThreadStore,
            storageServiceManager: storageServiceManager,
            threadStore: threadStore,
        )

        let pinnedMessageExpirationJob = PinnedMessageExpirationJob(
            dateProvider: dateProvider,
            db: db,
        )

        let pinnedMessageManager = PinnedMessageManager(
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            interactionStore: interactionStore,
            accountManager: tsAccountManager,
            db: db,
            threadStore: threadStore,
            dateProvider: dateProvider,
            expirationJob: pinnedMessageExpirationJob,
        )

        let storyRecipientStore = StoryRecipientStore()
        let storyRecipientManager = StoryRecipientManager(
            recipientDatabaseTable: recipientDatabaseTable,
            storyRecipientStore: storyRecipientStore,
            storageServiceManager: storageServiceManager,
            threadStore: threadStore,
        )
        let storyMessageExpirationJob = StoryMessageExpirationJob(
            dateProvider: dateProvider,
            db: db,
        )

        let authorMergeHelper = AuthorMergeHelper()
        let recipientMerger = RecipientMergerImpl(
            blockedRecipientStore: blockedRecipientStore,
            identityManager: identityManager,
            observers: RecipientMergerImpl.buildObservers(
                authorMergeHelper: authorMergeHelper,
                callRecordStore: callRecordStore,
                chatColorSettingStore: chatColorSettingStore,
                deletedCallRecordStore: deletedCallRecordStore,
                disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
                groupMemberUpdater: groupMemberUpdater,
                groupMemberStore: groupMemberStore,
                interactionStore: interactionStore,
                pinnedThreadManager: pinnedThreadManager,
                profileManager: profileManager,
                recipientMergeNotifier: RecipientMergeNotifier(),
                signalServiceAddressCache: signalServiceAddressCache,
                threadAssociatedDataStore: threadAssociatedDataStore,
                threadRemover: threadRemover,
                threadReplyInfoStore: threadReplyInfoStore,
                threadStore: threadStore,
                userProfileStore: userProfileStore,
                wallpaperImageStore: wallpaperImageStore,
                wallpaperStore: wallpaperStore,
            ),
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            searchableNameIndexer: searchableNameIndexer,
            sessionStore: sessionStore,
            storageServiceManager: storageServiceManager,
            storyRecipientStore: storyRecipientStore,
        )

        let accountEntropyPoolManager = AccountEntropyPoolManagerImpl(
            accountAttributesUpdater: accountAttributesUpdater,
            accountKeyStore: accountKeyStore,
            appContext: appContext,
            backupSettingsStore: backupSettingsStore,
            db: db,
            storageServiceManager: storageServiceManager,
            svr: svr,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
        )

        let backupDisablingManager = BackupDisablingManager(
            accountEntropyPoolManager: accountEntropyPoolManager,
            authCredentialStore: authCredentialStore,
            backupAttachmentCoordinator: backupAttachmentCoordinator,
            backupAttachmentDownloadQueueStatusManager: backupAttachmentDownloadQueueStatusManager,
            backupCDNCredentialStore: backupCDNCredentialStore,
            backupKeyService: backupKeyService,
            backupPlanManager: backupPlanManager,
            backupSettingsStore: backupSettingsStore,
            db: db,
            tsAccountManager: tsAccountManager,
        )

        let accountChecker = AccountChecker(
            db: db,
            networkManager: networkManager,
            recipientFetcher: recipientFetcher,
            recipientManager: recipientManager,
            recipientMerger: recipientMerger,
            recipientStore: recipientDatabaseTable,
            tsAccountManager: tsAccountManager,
        )

        let messageSender = testDependencies.messageSender(accountChecker) ?? MessageSender(
            accountChecker: accountChecker,
            groupSendEndorsementStore: groupSendEndorsementStore,
        )

        let pniDistributionParameterBuilder = PniDistributionParameterBuilderImpl(
            db: db,
            messageSender: PniDistributionParameterBuilderImpl.Wrappers.MessageSender(messageSender),
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            registrationIdGenerator: RegistrationIdGenerator(),
        )

        let registrationStateChangeManager = RegistrationStateChangeManagerImpl(
            authCredentialStore: authCredentialStore,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupCDNCredentialStore: backupCDNCredentialStore,
            backupSubscriptionManager: backupSubscriptionManager,
            backupTestFlightEntitlementManager: backupTestFlightEntitlementManager,
            blockedRecipientStore: blockedRecipientStore,
            cron: cron,
            db: db,
            dmConfigurationStore: disappearingMessagesConfigurationStore,
            identityManager: identityManager,
            networkManager: networkManager,
            notificationPresenter: notificationPresenter,
            paymentsEvents: paymentsEvents,
            recipientManager: recipientManager,
            recipientMerger: recipientMerger,
            senderKeyStore: senderKeyStore,
            signalProtocolStoreManager: signalProtocolStoreManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
            udManager: udManager,
            versionedProfiles: versionedProfiles,
        )

        let identityKeyChecker = IdentityKeyCheckerImpl(
            db: db,
            identityManager: identityManager,
            profileFetcher: IdentityKeyCheckerImpl.Wrappers.ProfileFetcher(networkManager: networkManager),
        )
        let identityKeyMismatchManager = IdentityKeyMismatchManagerImpl(
            db: db,
            identityKeyChecker: identityKeyChecker,
            messageProcessor: IdentityKeyMismatchManagerImpl.Wrappers.MessageProcessor(messageProcessor),
            registrationStateChangeManager: registrationStateChangeManager,
            tsAccountManager: tsAccountManager,
            whoAmIManager: whoAmIManager,
        )

        let inactivePrimaryDeviceStore = InactivePrimaryDeviceStore()

        let chatConnectionManager = ChatConnectionManagerImpl(
            accountManager: tsAccountManager,
            appContext: appContext,
            appExpiry: appExpiry,
            appReadiness: appReadiness,
            db: db,
            inactivePrimaryDeviceStore: inactivePrimaryDeviceStore,
            libsignalNet: libsignalNet,
            registrationStateChangeManager: registrationStateChangeManager,
        )

        let preKeyTaskAPIClient = PreKeyTaskAPIClientImpl(networkManager: networkManager)
        let preKeyManager = PreKeyManagerImpl(
            dateProvider: dateProvider,
            db: db,
            identityKeyMismatchManager: identityKeyMismatchManager,
            identityManager: identityManager,
            messageProcessor: messageProcessor,
            preKeyTaskAPIClient: preKeyTaskAPIClient,
            protocolStoreManager: signalProtocolStoreManager,
            remoteConfigProvider: remoteConfigManager,
            chatConnectionManager: chatConnectionManager,
            tsAccountManager: tsAccountManager,
        )

        let changePhoneNumberPniManager = ChangePhoneNumberPniManagerImpl(
            db: db,
            identityManager: identityManager,
            pniDistributionParameterBuilder: pniDistributionParameterBuilder,
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            preKeyManager: preKeyManager,
            registrationIdGenerator: RegistrationIdGenerator(),
            tsAccountManager: tsAccountManager,
        )

        let registrationSessionManager = RegistrationSessionManagerImpl(
            dateProvider: dateProvider,
            db: db,
            signalService: signalService,
        )

        let recipientHidingManager = RecipientHidingManagerImpl(
            profileManager: profileManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
            messageSenderJobQueue: messageSenderJobQueue,
        )

        let donationReceiptCredentialResultStore = DonationReceiptCredentialResultStore()

        let usernameApiClient = UsernameApiClientImpl(
            networkManager: networkManager,
        )
        let usernameEducationManager = UsernameEducationManagerImpl()
        let usernameLinkManager = UsernameLinkManagerImpl(
            db: db,
            apiClient: usernameApiClient,
        )
        let localUsernameManager = LocalUsernameManagerImpl(
            db: db,
            reachabilityManager: reachabilityManager,
            storageServiceManager: storageServiceManager,
            usernameApiClient: usernameApiClient,
            usernameLinkManager: usernameLinkManager,
        )
        let usernameValidationManager = UsernameValidationManagerImpl(context: .init(
            database: db,
            localUsernameManager: localUsernameManager,
            messageProcessor: Usernames.Validation.Wrappers.MessageProcessor(messageProcessor),
            storageServiceManager: Usernames.Validation.Wrappers.StorageServiceManager(storageServiceManager),
            usernameLinkManager: usernameLinkManager,
            whoAmIManager: whoAmIManager,
        ))

        let incomingPniChangeNumberProcessor = IncomingPniChangeNumberProcessorImpl(
            identityManager: identityManager,
            pniProtocolStore: pniProtocolStore,
            preKeyManager: preKeyManager,
            registrationStateChangeManager: registrationStateChangeManager,
            tsAccountManager: tsAccountManager,
        )

        let masterKeySyncManager = MasterKeySyncManagerImpl(
            dateProvider: dateProvider,
            svr: svr,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
        )

        let messageStickerManager = MessageStickerManagerImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
        )

        let contactShareManager = ContactShareManagerImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
        )

        let pollMessageManager = PollMessageManager(
            pollStore: PollStore(),
            recipientDatabaseTable: recipientDatabaseTable,
            interactionStore: interactionStore,
            accountManager: tsAccountManager,
            messageSenderJobQueue: messageSenderJobQueue,
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            attachmentContentValidator: attachmentContentValidator,
            db: db,
        )

        let sentMessageTranscriptReceiver = SentMessageTranscriptReceiverImpl(
            attachmentDownloads: attachmentDownloadManager,
            attachmentManager: attachmentManager,
            disappearingMessagesExpirationJob: disappearingMessagesExpirationJob,
            earlyMessageManager: SentMessageTranscriptReceiverImpl.Wrappers.EarlyMessageManager(earlyMessageManager),
            groupManager: SentMessageTranscriptReceiverImpl.Wrappers.GroupManager(),
            interactionDeleteManager: interactionDeleteManager,
            interactionStore: interactionStore,
            messageStickerManager: messageStickerManager,
            paymentsHelper: paymentsHelper,
            pollMessageManager: pollMessageManager,
            signalProtocolStoreManager: signalProtocolStoreManager,
            tsAccountManager: tsAccountManager,
            viewOnceMessages: SentMessageTranscriptReceiverImpl.Wrappers.ViewOnceMessages(),
        )

        let preferences = Preferences()
        let systemStoryManager = testDependencies.systemStoryManager ?? SystemStoryManager(
            appReadiness: appReadiness,
            messageProcessor: messageProcessor,
        )
        let typingIndicators = TypingIndicatorsImpl()

        let privateStoryThreadDeletionManager = PrivateStoryThreadDeletionManagerImpl(
            dateProvider: dateProvider,
            remoteConfigProvider: remoteConfigManager,
            storageServiceManager: storageServiceManager,
            threadRemover: threadRemover,
            threadStore: threadStore,
        )

        let reactionStore: any ReactionStore = ReactionStoreImpl()

        let storageServiceRecordIkmMigrator = StorageServiceRecordIkmMigratorImpl(
            db: db,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
        )

        let profileFetcher = ProfileFetcherImpl(
            accountChecker: accountChecker,
            db: db,
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            identityManager: identityManager,
            paymentsHelper: paymentsHelper,
            profileManager: profileManager,
            reachabilityManager: reachabilityManager,
            recipientDatabaseTable: recipientDatabaseTable,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
            udManager: udManager,
            versionedProfiles: versionedProfiles,
        )

        let messagePipelineSupervisor = MessagePipelineSupervisor()

        let backupChatStyleArchiver = BackupArchiveChatStyleArchiver(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            backupAttachmentDownloadScheduler: backupAttachmentDownloadScheduler,
            chatColorSettingStore: chatColorSettingStore,
            wallpaperStore: wallpaperStore,
        )

        let backupInteractionStore = BackupArchiveInteractionStore(interactionStore: interactionStore)
        let backupRecipientStore = BackupArchiveRecipientStore(
            recipientTable: recipientDatabaseTable,
            searchableNameIndexer: searchableNameIndexer,
        )
        let backupStickerPackDownloadStore = BackupStickerPackDownloadStoreImpl()
        let backupStoryStore = BackupArchiveStoryStore(
            storyStore: storyStore,
            storyRecipientStore: storyRecipientStore,
        )
        let backupThreadStore = BackupArchiveThreadStore(threadStore: threadStore)

        let backupArchiveErrorPresenter = backupArchiveErrorPresenterFactory.build(
            db: db,
            tsAccountManager: tsAccountManager,
        )
        let backupArchiveAvatarFetcher = BackupArchiveAvatarFetcher(
            appReadiness: appReadiness,
            dateProvider: dateProvider,
            db: db,
            groupsV2: groupsV2,
            profileFetcher: profileFetcher,
            profileManager: profileManager,
            reachabilityManager: reachabilityManager,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager,
        )
        let backupContactRecipientArchiver = BackupArchiveContactRecipientArchiver(
            avatarDefaultColorManager: avatarDefaultColorManager,
            avatarFetcher: backupArchiveAvatarFetcher,
            blockingManager: BackupArchive.Wrappers.BlockingManager(blockingManager),
            contactManager: BackupArchive.Wrappers.ContactManager(contactManager),
            nicknameManager: nicknameManager,
            profileManager: BackupArchive.Wrappers.ProfileManager(profileManager),
            recipientHidingManager: recipientHidingManager,
            recipientManager: recipientManager,
            recipientStore: backupRecipientStore,
            signalServiceAddressCache: signalServiceAddressCache,
            storyStore: backupStoryStore,
            threadStore: backupThreadStore,
            tsAccountManager: tsAccountManager,
            usernameLookupManager: usernameLookupManager,
        )

        let backupAttachmentsArchiver = BackupArchiveMessageAttachmentArchiver(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            backupAttachmentDownloadScheduler: backupAttachmentDownloadScheduler,
        )
        let backupsOversizeTextArchiver = BackupArchiveInlinedOversizeTextArchiver(
            attachmentsArchiver: backupAttachmentsArchiver,
            attachmentContentValidator: attachmentContentValidator,
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            db: db,
        )
        let backupReactionArchiver = BackupArchiveReactionArchiver(
            reactionStore: BackupArchiveReactionStore(),
        )
        let pollArchiver = BackupArchivePollArchiver(
            pollManager: pollMessageManager,
            db: db,
            recipientDatabaseTable: recipientDatabaseTable,
            reactionArchiver: backupReactionArchiver,
        )
        let backupArchiveManager = BackupArchiveManagerImpl(
            accountDataArchiver: BackupArchiveAccountDataArchiver(
                backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
                backupPlanManager: backupPlanManager,
                backupSubscriptionManager: backupSubscriptionManager,
                callServiceSettingsStore: CallServiceSettingsStore(),
                chatStyleArchiver: backupChatStyleArchiver,
                disappearingMessageConfigurationStore: disappearingMessagesConfigurationStore,
                donationSubscriptionManager: BackupArchive.Wrappers.DonationSubscriptionManager(),
                imageQuality: BackupArchive.Wrappers.ImageQuality(),
                linkPreviewSettingStore: linkPreviewSettingStore,
                localUsernameManager: localUsernameManager,
                mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
                ows2FAManager: BackupArchive.Wrappers.OWS2FAManager(ows2FAManager),
                phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManager,
                preferences: BackupArchive.Wrappers.Preferences(preferences: preferences),
                profileManager: BackupArchive.Wrappers.ProfileManager(profileManager),
                receiptManager: BackupArchive.Wrappers.ReceiptManager(receiptManager: receiptManager),
                reactionManager: BackupArchive.Wrappers.ReactionManager(),
                screenLock: BackupArchive.Wrappers.ScreenLock(),
                sskPreferences: BackupArchive.Wrappers.SSKPreferences(),
                storyManager: BackupArchive.Wrappers.StoryManager(),
                systemStoryManager: BackupArchive.Wrappers.SystemStoryManager(systemStoryManager: systemStoryManager),
                theme: ThemeDataStore(),
                typingIndicators: BackupArchive.Wrappers.TypingIndicators(typingIndicators: typingIndicators),
                udManager: BackupArchive.Wrappers.UDManager(udManager: udManager),
                usernameEducationManager: usernameEducationManager,
            ),
            adHocCallArchiver: BackupArchiveAdHocCallArchiver(
                callRecordStore: callRecordStore,
                callLinkRecordStore: callLinkStore,
                adHocCallRecordManager: adHocCallRecordManager,
            ),
            appVersion: appVersion,
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentUploadManager: attachmentUploadManager,
            avatarFetcher: backupArchiveAvatarFetcher,
            backupArchiveErrorPresenter: backupArchiveErrorPresenter,
            backupAttachmentCoordinator: backupAttachmentCoordinator,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupNonceMetadataStore: backupNonceMetadataStore,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            backupStickerPackDownloadStore: backupStickerPackDownloadStore,
            callLinkRecipientArchiver: BackupArchiveCallLinkRecipientArchiver(
                callLinkStore: callLinkStore,
            ),
            chatArchiver: BackupArchiveChatArchiver(
                chatStyleArchiver: backupChatStyleArchiver,
                contactRecipientArchiver: backupContactRecipientArchiver,
                dmConfigurationStore: disappearingMessagesConfigurationStore,
                pinnedThreadStore: pinnedThreadStore,
                threadStore: backupThreadStore,
            ),
            chatItemArchiver: BackupArchiveChatItemArchiver(
                archivedPaymentStore: archivedPaymentStore,
                attachmentsArchiver: backupAttachmentsArchiver,
                callRecordStore: callRecordStore,
                contactManager: BackupArchive.Wrappers.ContactManager(contactManager),
                editMessageStore: editMessageStore,
                groupCallRecordManager: groupCallRecordManager,
                groupUpdateItemBuilder: groupUpdateItemBuilder,
                individualCallRecordManager: individualCallRecordManager,
                interactionStore: backupInteractionStore,
                oversizeTextArchiver: backupsOversizeTextArchiver,
                pollArchiver: pollArchiver,
                reactionStore: reactionStore,
                threadStore: backupThreadStore,
                reactionArchiver: backupReactionArchiver,
                pinnedMessageManager: pinnedMessageManager,
            ),
            contactRecipientArchiver: backupContactRecipientArchiver,
            databaseChangeObserver: databaseStorage.databaseChangeObserver,
            dateProvider: dateProvider,
            dateProviderMonotonic: dateProviderMonotonic,
            db: db,
            disappearingMessagesExpirationJob: disappearingMessagesExpirationJob,
            distributionListRecipientArchiver: BackupArchiveDistributionListRecipientArchiver(
                privateStoryThreadDeletionManager: privateStoryThreadDeletionManager,
                storyStore: backupStoryStore,
                threadStore: backupThreadStore,
            ),
            encryptedStreamProvider: BackupArchiveEncryptedProtoStreamProvider(),
            fullTextSearchIndexer: BackupArchiveFullTextSearchIndexerImpl(
                appReadiness: appReadiness,
                dateProvider: dateProviderMonotonic,
                db: db,
                interactionStore: interactionStore,
                searchableNameIndexer: searchableNameIndexer,
            ),
            groupRecipientArchiver: BackupArchiveGroupRecipientArchiver(
                avatarDefaultColorManager: avatarDefaultColorManager,
                avatarFetcher: backupArchiveAvatarFetcher,
                blockingManager: BackupArchive.Wrappers.BlockingManager(blockingManager),
                disappearingMessageConfigStore: disappearingMessagesConfigurationStore,
                groupsV2: groupsV2,
                profileManager: BackupArchive.Wrappers.ProfileManager(profileManager),
                storyStore: backupStoryStore,
                threadStore: backupThreadStore,
            ),
            libsignalNet: libsignalNet,
            localStorage: accountKeyStore,
            localRecipientArchiver: BackupArchiveLocalRecipientArchiver(
                avatarDefaultColorManager: avatarDefaultColorManager,
                profileManager: BackupArchive.Wrappers.ProfileManager(profileManager),
                recipientStore: backupRecipientStore,
            ),
            messagePipelineSupervisor: messagePipelineSupervisor,
            oversizeTextArchiver: backupsOversizeTextArchiver,
            plaintextStreamProvider: BackupArchivePlaintextProtoStreamProvider(),
            postFrameRestoreActionManager: BackupArchivePostFrameRestoreActionManager(
                avatarFetcher: backupArchiveAvatarFetcher,
                dateProvider: dateProvider,
                interactionStore: backupInteractionStore,
                lastVisibleInteractionStore: lastVisibleInteractionStore,
                preferences: BackupArchive.Wrappers.Preferences(preferences: preferences),
                recipientDatabaseTable: recipientDatabaseTable,
                sskPreferences: BackupArchive.Wrappers.SSKPreferences(),
                threadStore: backupThreadStore,
            ),
            releaseNotesRecipientArchiver: BackupArchiveReleaseNotesRecipientArchiver(),
            remoteConfigManager: remoteConfigManager,
            stickerPackArchiver: BackupArchiveStickerPackArchiver(
                backupStickerPackDownloadStore: backupStickerPackDownloadStore,
            ),
            tsAccountManager: tsAccountManager,
        )

        let externalPendingIDEALDonationStore = ExternalPendingIDEALDonationStoreImpl()

        // TODO: Move this into ProfileFetcherJob.
        // Ideally, this would be a private implementation detail of that class.
        // However, that class is currently implemented mostly as static methods,
        // so there's no place to store it. Once it's protocolized, this type
        // should be initialized in its initializer.
        let localProfileChecker = LocalProfileChecker(
            db: db,
            messageProcessor: messageProcessor,
            profileManager: profileManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
            udManager: udManager,
        )

        let attachmentViewOnceManager = AttachmentViewOnceManagerImpl(
            attachmentStore: attachmentStore,
            db: db,
            interactionStore: interactionStore,
        )

        let deviceManager = OWSDeviceManagerImpl()
        let deviceStore = OWSDeviceStore()
        let deviceService = OWSDeviceServiceImpl(
            db: db,
            deviceManager: deviceManager,
            deviceStore: deviceStore,
            identityManager: identityManager,
            messageSenderJobQueue: messageSenderJobQueue,
            networkManager: networkManager,
            recipientFetcher: recipientFetcher,
            recipientManager: recipientManager,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager,
        )
        let inactiveLinkedDeviceFinder = InactiveLinkedDeviceFinderImpl(
            dateProvider: dateProvider,
            db: db,
            deviceService: deviceService,
            deviceStore: deviceStore,
            remoteConfigProvider: remoteConfigManager,
            tsAccountManager: tsAccountManager,
        )

        let linkAndSyncManager = LinkAndSyncManagerImpl(
            appContext: appContext,
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentUploadManager: attachmentUploadManager,
            backupArchiveManager: backupArchiveManager,
            dateProvider: dateProvider,
            db: db,
            deviceSleepManager: deviceSleepManager,
            messagePipelineSupervisor: messagePipelineSupervisor,
            networkManager: networkManager,
            tsAccountManager: tsAccountManager,
        )

        let groupMessageProcessorManager = GroupMessageProcessorManager()

        let receiptSender = ReceiptSender(
            appReadiness: appReadiness,
            recipientDatabaseTable: recipientDatabaseTable,
        )

        let messageFetcherJob = MessageFetcherJob()

        let backgroundMessageFetcherFactory = BackgroundMessageFetcherFactory(
            chatConnectionManager: chatConnectionManager,
            groupMessageProcessorManager: groupMessageProcessorManager,
            messageProcessor: messageProcessor,
            messageSenderJobQueue: messageSenderJobQueue,
            receiptSender: receiptSender,
        )

        let backupExportJob = BackupExportJobImpl(
            accountKeyStore: accountKeyStore,
            backupArchiveManager: backupArchiveManager,
            backupAttachmentCoordinator: backupAttachmentCoordinator,
            backupAttachmentDownloadQueueStatusManager: backupAttachmentDownloadQueueStatusManager,
            backupAttachmentUploadProgress: backupAttachmentUploadProgress,
            backupAttachmentUploadQueueStatusManager: backupAttachmentUploadQueueStatusManager,
            backupKeyService: backupKeyService,
            backupSettingsStore: backupSettingsStore,
            db: db,
            messagePipelineSupervisor: messagePipelineSupervisor,
            messageProcessor: messageProcessor,
            reachabilityManager: reachabilityManager,
            tsAccountManager: tsAccountManager,
        )
        let backupExportJobRunner = BackupExportJobRunnerImpl(
            backupExportJob: backupExportJob,
        )

        let backupFailureStateManager = BackupFailureStateManager(
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            tsAccountManager: tsAccountManager,
        )

        let dependenciesBridge = DependenciesBridge(
            accountAttributesUpdater: accountAttributesUpdater,
            accountEntropyPoolManager: accountEntropyPoolManager,
            adHocCallRecordManager: adHocCallRecordManager,
            appExpiry: appExpiry,
            attachmentContentValidator: attachmentContentValidator,
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentDownloadStore: attachmentDownloadStore,
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentThumbnailService: attachmentThumbnailService,
            attachmentUploadManager: attachmentUploadManager,
            attachmentValidationBackfillMigrator: attachmentValidationBackfillMigrator,
            attachmentViewOnceManager: attachmentViewOnceManager,
            audioWaveformManager: audioWaveformManager,
            authorMergeHelper: authorMergeHelper,
            avatarDefaultColorManager: avatarDefaultColorManager,
            backgroundMessageFetcherFactory: backgroundMessageFetcherFactory,
            backupArchiveErrorPresenter: backupArchiveErrorPresenter,
            backupArchiveManager: backupArchiveManager,
            backupAttachmentDownloadProgress: backupAttachmentDownloadProgress,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupAttachmentDownloadQueueStatusReporter: backupAttachmentDownloadQueueStatusManager,
            backupAttachmentCoordinator: backupAttachmentCoordinator,
            backupAttachmentUploadProgress: backupAttachmentUploadProgress,
            backupAttachmentUploadQueueStatusReporter: backupAttachmentUploadQueueStatusManager,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupDisablingManager: backupDisablingManager,
            backupExportJob: backupExportJob,
            backupExportJobRunner: backupExportJobRunner,
            backupFailureStateManager: backupFailureStateManager,
            backupIdService: backupIdService,
            backupKeyService: backupKeyService,
            backupListMediaManager: backupListMediaManager,
            backupListMediaStore: backupListMediaStore,
            backupRequestManager: backupRequestManager,
            backupPlanManager: backupPlanManager,
            backupSubscriptionManager: backupSubscriptionManager,
            backupTestFlightEntitlementManager: backupTestFlightEntitlementManager,
            badgeCountFetcher: badgeCountFetcher,
            blockedRecipientStore: blockedRecipientStore,
            callLinkStore: callLinkStore,
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordMissedCallManager: callRecordMissedCallManager,
            callRecordQuerier: callRecordQuerier,
            callRecordStore: callRecordStore,
            changePhoneNumberPniManager: changePhoneNumberPniManager,
            chatColorSettingStore: chatColorSettingStore,
            chatConnectionManager: chatConnectionManager,
            contactShareManager: contactShareManager,
            cron: cron,
            currentCallProvider: currentCallProvider,
            databaseChangeObserver: databaseStorage.databaseChangeObserver,
            db: db,
            deletedCallRecordExpirationJob: deletedCallRecordExpirationJob,
            deletedCallRecordStore: deletedCallRecordStore,
            deleteForMeIncomingSyncMessageManager: deleteForMeIncomingSyncMessageManager,
            deleteForMeOutgoingSyncMessageManager: deleteForMeOutgoingSyncMessageManager,
            deviceManager: deviceManager,
            deviceService: deviceService,
            deviceSleepManager: deviceSleepManager,
            deviceStore: deviceStore,
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            disappearingMessagesExpirationJob: disappearingMessagesExpirationJob,
            donationReceiptCredentialResultStore: donationReceiptCredentialResultStore,
            editManager: editManager,
            editMessageStore: editMessageStore,
            externalPendingIDEALDonationStore: externalPendingIDEALDonationStore,
            groupCallRecordManager: groupCallRecordManager,
            groupMemberStore: groupMemberStore,
            groupMemberUpdater: groupMemberUpdater,
            groupSendEndorsementStore: groupSendEndorsementStore,
            groupUpdateInfoMessageInserter: groupUpdateInfoMessageInserter,
            identityKeyMismatchManager: identityKeyMismatchManager,
            identityManager: identityManager,
            inactiveLinkedDeviceFinder: inactiveLinkedDeviceFinder,
            inactivePrimaryDeviceStore: inactivePrimaryDeviceStore,
            incomingCallEventSyncMessageManager: incomingCallEventSyncMessageManager,
            incomingCallLogEventSyncMessageManager: incomingCallLogEventSyncMessageManager,
            incomingPniChangeNumberProcessor: incomingPniChangeNumberProcessor,
            individualCallRecordManager: individualCallRecordManager,
            interactionDeleteManager: interactionDeleteManager,
            interactionStore: interactionStore,
            lastVisibleInteractionStore: lastVisibleInteractionStore,
            linkAndSyncManager: linkAndSyncManager,
            linkPreviewManager: linkPreviewManager,
            linkPreviewSettingStore: linkPreviewSettingStore,
            linkPreviewSettingManager: linkPreviewSettingManager,
            accountKeyStore: accountKeyStore,
            localProfileChecker: localProfileChecker,
            localUsernameManager: localUsernameManager,
            masterKeySyncManager: masterKeySyncManager,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            messageStickerManager: messageStickerManager,
            nicknameManager: nicknameManager,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            archivedPaymentStore: archivedPaymentStore,
            phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManager,
            phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
            pinnedMessageManager: pinnedMessageManager,
            pinnedMessageExpirationJob: pinnedMessageExpirationJob,
            pinnedThreadManager: pinnedThreadManager,
            pinnedThreadStore: pinnedThreadStore,
            pollMessageManager: pollMessageManager,
            preKeyManager: preKeyManager,
            privateStoryThreadDeletionManager: privateStoryThreadDeletionManager,
            quotedReplyManager: quotedReplyManager,
            reactionStore: reactionStore,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            recipientHidingManager: recipientHidingManager,
            recipientIdFinder: recipientIdFinder,
            recipientManager: recipientManager,
            recipientMerger: recipientMerger,
            registrationSessionManager: registrationSessionManager,
            registrationStateChangeManager: registrationStateChangeManager,
            searchableNameIndexer: searchableNameIndexer,
            sentMessageTranscriptReceiver: sentMessageTranscriptReceiver,
            signalProtocolStoreManager: signalProtocolStoreManager,
            storageServiceRecordIkmMigrator: storageServiceRecordIkmMigrator,
            storyMessageExpirationJob: storyMessageExpirationJob,
            storyRecipientManager: storyRecipientManager,
            storyRecipientStore: storyRecipientStore,
            subscriptionConfigManager: subscriptionConfigManager,
            svr: svr,
            svrCredentialStorage: svrCredentialStorage,
            svrLocalStorage: svrLocalStorage,
            threadAssociatedDataStore: threadAssociatedDataStore,
            threadRemover: threadRemover,
            threadReplyInfoStore: threadReplyInfoStore,
            threadSoftDeleteManager: threadSoftDeleteManager,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager,
            usernameApiClient: usernameApiClient,
            usernameEducationManager: usernameEducationManager,
            usernameLinkManager: usernameLinkManager,
            usernameLookupManager: usernameLookupManager,
            usernameValidationManager: usernameValidationManager,
            wallpaperImageStore: wallpaperImageStore,
            wallpaperStore: wallpaperStore,
        )
        DependenciesBridge.setShared(dependenciesBridge, isRunningTests: appContext.isRunningTests)

        let proximityMonitoringManager = OWSProximityMonitoringManagerImpl()
        let avatarBuilder = AvatarBuilder(appReadiness: appReadiness)
        let smJobQueues = SignalMessagingJobQueues(
            appReadiness: appReadiness,
            db: db,
            reachabilityManager: reachabilityManager,
        )

        let pendingReceiptRecorder = testDependencies.pendingReceiptRecorder
            ?? MessageRequestPendingReceipts(appReadiness: appReadiness)
        let messageReceiver = MessageReceiver(
            callMessageHandler: callMessageHandler,
            deleteForMeSyncMessageReceiver: DeleteForMeSyncMessageReceiverImpl(
                deleteForMeIncomingSyncMessageManager: deleteForMeIncomingSyncMessageManager,
                recipientDatabaseTable: recipientDatabaseTable,
                threadStore: threadStore,
                tsAccountManager: tsAccountManager,
            ),
        )
        let messageDecrypter = OWSMessageDecrypter(appReadiness: appReadiness)
        let stickerManager = StickerManager(
            appReadiness: appReadiness,
            dateProvider: dateProvider,
        )
        let sskPreferences = SSKPreferences()
        let groupV2Updates = testDependencies.groupV2Updates ?? GroupV2UpdatesImpl(appReadiness: appReadiness)
        let paymentsCurrencies = testDependencies.paymentsCurrencies ?? PaymentsCurrenciesImpl(appReadiness: appReadiness)
        let spamChallengeResolver = SpamChallengeResolver(appReadiness: appReadiness)
        let phoneNumberUtil = PhoneNumberUtil()
        let contactDiscoveryManager = ContactDiscoveryManagerImpl(
            db: db,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            recipientManager: recipientManager,
            recipientMerger: recipientMerger,
            tsAccountManager: tsAccountManager,
            udManager: udManager,
            libsignalNet: libsignalNet,
        )
        let localUserLeaveGroupJobQueue = LocalUserLeaveGroupJobQueue(
            db: db,
            reachabilityManager: reachabilityManager,
        )
        let donationReceiptCredentialRedemptionJobQueue = DonationReceiptCredentialRedemptionJobQueue(
            dateProvider: dateProvider,
            db: db,
            donationReceiptCredentialResultStore: donationReceiptCredentialResultStore,
            networkManager: networkManager,
            profileManager: profileManager,
            reachabilityManager: reachabilityManager,
            tsAccountManager: tsAccountManager,
        )

        let groupCallPeekClient = GroupCallPeekClient(db: db, groupsV2: groupsV2)
        let groupCallManager = GroupCallManager(
            currentCallProvider: currentCallProvider,
            groupCallPeekClient: groupCallPeekClient,
        )

        let paymentsLock = OWSPaymentsLock(appReadiness: appReadiness)

        let sskEnvironment = SSKEnvironment(
            contactManager: contactManager,
            messageSender: messageSender,
            pendingReceiptRecorder: pendingReceiptRecorder,
            profileManager: profileManager,
            networkManager: networkManager,
            messageReceiver: messageReceiver,
            blockingManager: blockingManager,
            remoteConfigManager: remoteConfigManager,
            aciSignalProtocolStore: aciProtocolStore,
            pniSignalProtocolStore: pniProtocolStore,
            udManager: udManager,
            messageDecrypter: messageDecrypter,
            groupMessageProcessorManager: groupMessageProcessorManager,
            ows2FAManager: ows2FAManager,
            receiptManager: receiptManager,
            receiptSender: receiptSender,
            reachabilityManager: reachabilityManager,
            syncManager: syncManager,
            typingIndicators: typingIndicators,
            stickerManager: stickerManager,
            databaseStorage: databaseStorage,
            signalServiceAddressCache: signalServiceAddressCache,
            signalService: signalService,
            storageServiceManager: storageServiceManager,
            sskPreferences: sskPreferences,
            groupsV2: groupsV2,
            groupV2Updates: groupV2Updates,
            messageFetcherJob: messageFetcherJob,
            versionedProfiles: versionedProfiles,
            modelReadCaches: modelReadCaches,
            earlyMessageManager: earlyMessageManager,
            messagePipelineSupervisor: messagePipelineSupervisor,
            appExpiry: appExpiry,
            messageProcessor: messageProcessor,
            paymentsHelper: paymentsHelper,
            paymentsCurrencies: paymentsCurrencies,
            paymentsEvents: paymentsEvents,
            paymentsLock: paymentsLock,
            mobileCoinHelper: mobileCoinHelper,
            spamChallengeResolver: spamChallengeResolver,
            senderKeyStore: senderKeyStore,
            phoneNumberUtil: phoneNumberUtil,
            webSocketFactory: webSocketFactory,
            systemStoryManager: systemStoryManager,
            contactDiscoveryManager: contactDiscoveryManager,
            notificationPresenter: notificationPresenter,
            messageSendLog: messageSendLog,
            messageSenderJobQueue: messageSenderJobQueue,
            localUserLeaveGroupJobQueue: localUserLeaveGroupJobQueue,
            callRecordDeleteAllJobQueue: callRecordDeleteAllJobQueue,
            bulkDeleteInteractionJobQueue: bulkDeleteInteractionJobQueue,
            donationReceiptCredentialRedemptionJobQueue: donationReceiptCredentialRedemptionJobQueue,
            preferences: preferences,
            proximityMonitoringManager: proximityMonitoringManager,
            avatarBuilder: avatarBuilder,
            smJobQueues: smJobQueues,
            groupCallManager: groupCallManager,
            profileFetcher: profileFetcher,
        )
        SSKEnvironment.setShared(sskEnvironment, isRunningTests: appContext.isRunningTests)

        // Register renamed classes.
        NSKeyedUnarchiver.setClass(OWSUserProfile.self, forClassName: "OWSUserProfile")
        NSKeyedUnarchiver.setClass(TSGroupModelV2.self, forClassName: "TSGroupModelV2")
        NSKeyedUnarchiver.setClass(PendingProfileUpdate.self, forClassName: "SignalMessaging.PendingProfileUpdate")

        Sounds.performStartupTasks(appReadiness: appReadiness)

        return AppSetup.DataMigrationContinuation(
            appContext: appContext,
            appReadiness: appReadiness,
            authCredentialStore: authCredentialStore,
            dependenciesBridge: dependenciesBridge,
            libsignalNet: libsignalNet,
            sskEnvironment: sskEnvironment,
            backgroundTask: backgroundTask,
            authCredentialManager: authCredentialManager,
            callLinkPublicParams: callLinkPublicParams,
            remoteConfigManager: remoteConfigManager,
        )
    }

    private func configureUnsatisfiableConstraintLogging() {
        UserDefaults.standard.setValue(DebugFlags.internalLogging, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
    }
}

// MARK: - DataMigrationContinuation

extension AppSetup {
    public class DataMigrationContinuation {
        fileprivate let appContext: AppContext
        fileprivate let appReadiness: AppReadiness
        fileprivate let authCredentialStore: AuthCredentialStore
        public let dependenciesBridge: DependenciesBridge
        fileprivate let libsignalNet: Net
        fileprivate let remoteConfigManager: RemoteConfigManager
        public let sskEnvironment: SSKEnvironment
        fileprivate let backgroundTask: OWSBackgroundTask

        // We need this in AppDelegate, but it doesn't need to be a global/attached
        // to DependenciesBridge.shared. We'll need some mechanism for this in the
        // future, but for now, just put it here so it's part of the result.
        public let authCredentialManager: any AuthCredentialManager
        public let callLinkPublicParams: GenericServerPublicParams

        fileprivate init(
            appContext: AppContext,
            appReadiness: AppReadiness,
            authCredentialStore: AuthCredentialStore,
            dependenciesBridge: DependenciesBridge,
            libsignalNet: Net,
            sskEnvironment: SSKEnvironment,
            backgroundTask: OWSBackgroundTask,
            authCredentialManager: any AuthCredentialManager,
            callLinkPublicParams: GenericServerPublicParams,
            remoteConfigManager: RemoteConfigManager,
        ) {
            self.appContext = appContext
            self.appReadiness = appReadiness
            self.authCredentialStore = authCredentialStore
            self.dependenciesBridge = dependenciesBridge
            self.libsignalNet = libsignalNet
            self.sskEnvironment = sskEnvironment
            self.backgroundTask = backgroundTask
            self.authCredentialManager = authCredentialManager
            self.callLinkPublicParams = callLinkPublicParams
            self.remoteConfigManager = remoteConfigManager
        }
    }
}

extension AppSetup.DataMigrationContinuation {
    public func migrateDatabaseData() async -> AppSetup.FinalContinuation {
        let databaseStorage = sskEnvironment.databaseStorageRef

        databaseStorage.runGrdbDataMigrations()
        do {
            try databaseStorage.grdbStorage.setupDatabaseChangeObserver()
        } catch {
            owsFail("Couldn't set up change observer: \(error.grdbErrorForLogging)")
        }

        self.backgroundTask.end()
        return AppSetup.FinalContinuation(
            appContext: self.appContext,
            appReadiness: self.appReadiness,
            authCredentialStore: self.authCredentialStore,
            dependenciesBridge: self.dependenciesBridge,
            libsignalNet: self.libsignalNet,
            sskEnvironment: self.sskEnvironment,
        )
    }
}

// MARK: - FinalContinuation

extension AppSetup {
    public class FinalContinuation {
        private let appContext: AppContext
        private let appReadiness: AppReadiness
        private let authCredentialStore: AuthCredentialStore
        public let dependenciesBridge: DependenciesBridge
        private let libsignalNet: Net
        private let sskEnvironment: SSKEnvironment

        @MainActor private var didRunLaunchTasks = false

        fileprivate init(
            appContext: AppContext,
            appReadiness: AppReadiness,
            authCredentialStore: AuthCredentialStore,
            dependenciesBridge: DependenciesBridge,
            libsignalNet: Net,
            sskEnvironment: SSKEnvironment,
        ) {
            self.appContext = appContext
            self.appReadiness = appReadiness
            self.authCredentialStore = authCredentialStore
            self.dependenciesBridge = dependenciesBridge
            self.libsignalNet = libsignalNet
            self.sskEnvironment = sskEnvironment
        }
    }
}

extension AppSetup.FinalContinuation {
    public enum SetupError: Error {
        case corruptRegistrationState
    }

    @MainActor
    public func runLaunchTasksIfNeededAndReloadCaches() {

        if !self.didRunLaunchTasks {
            // Coders are consulted in reverse order of adding, so add
            // the AWebPCoder last, which used the native ImageIO, if supported
            SDImageCodersManager.shared.addCoder(SDImageWebPCoder.shared)
            SDImageCodersManager.shared.addCoder(SDImageAWebPCoder.shared)
        }

        if self.didRunLaunchTasks {
            let remoteConfig = sskEnvironment.databaseStorageRef.read { tx in
                dependenciesBridge.tsAccountManager.warmCaches(tx: tx)
                return sskEnvironment.remoteConfigManagerRef.warmCaches(tx: tx)
            }
            libsignalNet.setRemoteConfig(remoteConfig.netConfig(), buildVariant: BuildFlags.netBuildVariant)
        }

        // Warm (or re-warm) all of the caches. In theory, every cache is
        // susceptible to diverging state between the Main App & NSE and should be
        // reloaded here. In practice, some caches exist but aren't used by the
        // NSE, or they are used but behave properly even if they're not reloaded.
        self.sskEnvironment.warmCaches(appReadiness: self.appReadiness, dependenciesBridge: self.dependenciesBridge)

        self.appReadiness.runNowOrWhenAppWillBecomeReady {
            self.dependenciesBridge.chatConnectionManager.updateCanOpenWebSocket()
        }

        self.appReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.dependenciesBridge.appExpiry.refreshExpirationTimer()
        }

        if self.didRunLaunchTasks {
            return
        }
        self.didRunLaunchTasks = true

        // See above.
        self.sskEnvironment.signalServiceAddressCacheRef.prepareCache()

        ZkParamsMigrator(
            appReadiness: appReadiness,
            authCredentialStore: authCredentialStore,
            db: dependenciesBridge.db,
            profileManager: sskEnvironment.profileManagerRef,
            tsAccountManager: dependenciesBridge.tsAccountManager,
            versionedProfiles: sskEnvironment.versionedProfilesRef,
        ).migrateIfNeeded()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { [appContext, dependenciesBridge, sskEnvironment] in
            sskEnvironment.localUserLeaveGroupJobQueueRef.start(appContext: appContext)
            sskEnvironment.callRecordDeleteAllJobQueueRef.start(appContext: appContext)
            sskEnvironment.bulkDeleteInteractionJobQueueRef.start(appContext: appContext)
            sskEnvironment.donationReceiptCredentialRedemptionJobQueue.start(appContext: appContext)
            sskEnvironment.smJobQueuesRef.incomingContactSyncJobQueue.start(appContext: appContext)
            sskEnvironment.smJobQueuesRef.sendGiftBadgeJobQueue.start(appContext: appContext)
            sskEnvironment.smJobQueuesRef.sessionResetJobQueue.start(appContext: appContext)

            let preKeyManager = dependenciesBridge.preKeyManager
            Task {
                // Rotate ACI keys first since PNI keys may block on incoming messages.
                // TODO: Don't block ACI operations if PNI operations are blocked.
                try await preKeyManager.rotatePreKeysOnUpgradeIfNecessary(for: .aci)
                try await preKeyManager.rotatePreKeysOnUpgradeIfNecessary(for: .pni)
            }
        }
    }

    @MainActor
    public func setUpLocalIdentifiers(
        willResumeInProgressRegistration: Bool,
        canInitiateRegistration: Bool,
    ) -> SetupError? {
        let storageServiceManager = sskEnvironment.storageServiceManagerRef
        let tsAccountManager = dependenciesBridge.tsAccountManager

        let registrationState = tsAccountManager.registrationStateWithMaybeSneakyTransaction
        let canInitiateReregistration = registrationState.isDeregistered && canInitiateRegistration

        if registrationState.isRegistered {
            // TODO: Enforce already-true invariant "registered means LocalIdentifiers" via the compiler.
            let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!
            storageServiceManager.setLocalIdentifiers(localIdentifiers)
        } else if !willResumeInProgressRegistration, !canInitiateReregistration {
            // We aren't registered, and we're not in the middle of registration, so
            // throw an error about corrupt registration.
            return .corruptRegistrationState
        }

        if !willResumeInProgressRegistration, !canInitiateReregistration {
            // We are fully registered, and we're not in the middle of registration, so
            // ensure discoverability is configured.
            setUpDefaultDiscoverability()
        }

        return nil
    }

    private func setUpDefaultDiscoverability() {
        let databaseStorage = sskEnvironment.databaseStorageRef
        let phoneNumberDiscoverabilityManager = DependenciesBridge.shared.phoneNumberDiscoverabilityManager
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        if databaseStorage.read(block: { tsAccountManager.phoneNumberDiscoverability(tx: $0) }) != nil {
            return
        }

        databaseStorage.write { tx in
            phoneNumberDiscoverabilityManager.setPhoneNumberDiscoverability(
                PhoneNumberDiscoverabilityManager.Constants.discoverabilityDefault,
                updateAccountAttributes: true,
                updateStorageService: true,
                authedAccount: .implicit(),
                tx: tx,
            )
        }
    }
}
