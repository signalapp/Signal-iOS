//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public class AppSetup {
    public init() {}

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
        let backupAttachmentDownloadManager: BackupAttachmentDownloadManager?
        let contactManager: (any ContactManager)?
        let dateProvider: DateProvider?
        let groupV2Updates: (any GroupV2Updates)?
        let groupsV2: (any GroupsV2)?
        let messageSender: MessageSender?
        let modelReadCaches: ModelReadCaches?
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
            backupAttachmentDownloadManager: BackupAttachmentDownloadManager? = nil,
            contactManager: (any ContactManager)? = nil,
            dateProvider: DateProvider? = nil,
            groupV2Updates: (any GroupV2Updates)? = nil,
            groupsV2: (any GroupsV2)? = nil,
            messageSender: MessageSender? = nil,
            modelReadCaches: ModelReadCaches? = nil,
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
            webSocketFactory: (any WebSocketFactory)? = nil
        ) {
            self.backupAttachmentDownloadManager = backupAttachmentDownloadManager
            self.contactManager = contactManager
            self.dateProvider = dateProvider
            self.groupV2Updates = groupV2Updates
            self.groupsV2 = groupsV2
            self.messageSender = messageSender
            self.modelReadCaches = modelReadCaches
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

    @MainActor
    public func start(
        appContext: AppContext,
        appReadiness: AppReadiness,
        backupArchiveErrorPresenterFactory: BackupArchiveErrorPresenterFactory,
        databaseStorage: SDSDatabaseStorage,
        deviceBatteryLevelManager: (any DeviceBatteryLevelManager)?,
        deviceSleepManager: (any DeviceSleepManager)?,
        paymentsEvents: PaymentsEvents,
        mobileCoinHelper: MobileCoinHelper,
        callMessageHandler: CallMessageHandler,
        currentCallProvider: any CurrentCallProvider,
        notificationPresenter: any NotificationPresenter,
        incrementalMessageTSAttachmentMigratorFactory: IncrementalMessageTSAttachmentMigratorFactory,
        testDependencies: TestDependencies = TestDependencies()
    ) -> AppSetup.DatabaseContinuation {
        configureUnsatisfiableConstraintLogging()

        let backgroundTask = OWSBackgroundTask(label: #function)

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

        let remoteConfig: [String: String] = if LibsignalUserDefaults.readShouldEnforceMinTlsVersion(from: appContext.appUserDefaults()) {
            // The actual value does not matter as long as the key is present
            ["enforceMinimumTls": "true"]
        } else {
            [:]
        }
        let libsignalNet = Net(
            env: TSConstants.isUsingProductionService ? .production : .staging,
            userAgent: HttpHeaders.userAgentHeaderValueSignalIos,
            remoteConfig: remoteConfig
        )

        let recipientDatabaseTable = RecipientDatabaseTable()
        let signalAccountStore = SignalAccountStoreImpl()
        let threadStore = ThreadStoreImpl()
        let userProfileStore = UserProfileStoreImpl()
        let usernameLookupRecordStore = UsernameLookupRecordStoreImpl()
        let nicknameRecordStore = NicknameRecordStoreImpl()
        let searchableNameIndexer = SearchableNameIndexerImpl(
            threadStore: threadStore,
            signalAccountStore: signalAccountStore,
            userProfileStore: userProfileStore,
            signalRecipientStore: recipientDatabaseTable,
            usernameLookupRecordStore: usernameLookupRecordStore,
            nicknameRecordStore: nicknameRecordStore,
            dbForReadTx: { SDSDB.shimOnlyBridge($0).database },
            dbForWriteTx: { SDSDB.shimOnlyBridge($0).database }
        )
        let recipientFetcher = RecipientFetcherImpl(
            recipientDatabaseTable: recipientDatabaseTable,
            searchableNameIndexer: searchableNameIndexer,
        )
        let recipientIdFinder = RecipientIdFinder(recipientDatabaseTable: recipientDatabaseTable, recipientFetcher: recipientFetcher)

        let dateProvider = testDependencies.dateProvider ?? Date.provider
        let dateProviderMonotonic = MonotonicDate.provider

        let avatarDefaultColorManager = AvatarDefaultColorManager()

        let appExpiry = AppExpiry(
            appVersion: appVersion,
        )

        let db = databaseStorage
        let dbFileSizeProvider = SDSDBFileSizeProvider(databaseStorage: databaseStorage)

        let tsAccountManager = TSAccountManagerImpl(
            appReadiness: appReadiness,
            dateProvider: dateProvider,
            databaseChangeObserver: databaseStorage.databaseChangeObserver,
            db: db,
        )

        let networkManager = testDependencies.networkManager ?? NetworkManager(
            appReadiness: appReadiness,
            libsignalNet: libsignalNet
        )
        let whoAmIManager = WhoAmIManagerImpl(networkManager: networkManager)

        let remoteConfigManager = testDependencies.remoteConfigManager ?? RemoteConfigManagerImpl(
            appExpiry: appExpiry,
            appReadiness: appReadiness,
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager,
            tsAccountManager: tsAccountManager
        )

        let aciSignalProtocolStore = SignalProtocolStoreImpl(
            for: .aci,
            recipientIdFinder: recipientIdFinder,
        )
        let blockedRecipientStore = BlockedRecipientStore()
        let blockingManager = BlockingManager(
            appReadiness: appReadiness,
            blockedGroupStore: BlockedGroupStore(),
            blockedRecipientStore: blockedRecipientStore
        )
        let earlyMessageManager = EarlyMessageManager(appReadiness: appReadiness)
        let messageProcessor = MessageProcessor(appReadiness: appReadiness)

        let groupSendEndorsementStore = GroupSendEndorsementStoreImpl()

        let messageSender = testDependencies.messageSender ?? MessageSender(
            groupSendEndorsementStore: groupSendEndorsementStore
        )
        let messageSenderJobQueue = MessageSenderJobQueue(appReadiness: appReadiness)
        let modelReadCaches = testDependencies.modelReadCaches ?? ModelReadCaches(
            factory: ModelReadCacheFactory(appReadiness: appReadiness)
        )
        let ows2FAManager = OWS2FAManager(appReadiness: appReadiness)
        let paymentsHelper = testDependencies.paymentsHelper ?? PaymentsHelperImpl()
        let archivedPaymentStore = ArchivedPaymentStoreImpl()
        let pniSignalProtocolStore = SignalProtocolStoreImpl(
            for: .pni,
            recipientIdFinder: recipientIdFinder,
        )
        let profileManager = testDependencies.profileManager ?? OWSProfileManager(
            appReadiness: appReadiness,
            databaseStorage: databaseStorage
        )
        let reachabilityManager = testDependencies.reachabilityManager ?? SSKReachabilityManagerImpl(
            appReadiness: appReadiness
        )

        let receiptManager = OWSReceiptManager(appReadiness: appReadiness, databaseStorage: databaseStorage, messageSenderJobQueue: messageSenderJobQueue, notificationPresenter: notificationPresenter)
        let senderKeyStore = SenderKeyStore()
        let signalProtocolStoreManager = SignalProtocolStoreManagerImpl(
            aciProtocolStore: aciSignalProtocolStore,
            pniProtocolStore: pniSignalProtocolStore
        )
        let signalService = testDependencies.signalService ?? OWSSignalService(libsignalNet: libsignalNet)
        let signalServiceAddressCache = SignalServiceAddressCache()
        let storageServiceManager = testDependencies.storageServiceManager ?? StorageServiceManagerImpl(
            appReadiness: appReadiness
        )
        let syncManager = testDependencies.syncManager ?? OWSSyncManager(appReadiness: appReadiness)
        let udManager = OWSUDManagerImpl(appReadiness: appReadiness)
        let versionedProfiles = testDependencies.versionedProfiles ?? VersionedProfilesImpl(appReadiness: appReadiness)

        let lastVisibleInteractionStore = LastVisibleInteractionStore()
        let usernameLookupManager = UsernameLookupManagerImpl(
            searchableNameIndexer: searchableNameIndexer,
            usernameLookupRecordStore: usernameLookupRecordStore
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
            usernameLookupManager: usernameLookupManager
        )

        let authCredentialStore = AuthCredentialStore()

        let callLinkPublicParams = try! GenericServerPublicParams(contents: tsConstants.callLinkPublicParams)
        let authCredentialManager = AuthCredentialManagerImpl(
            authCredentialStore: authCredentialStore,
            callLinkPublicParams: callLinkPublicParams,
            dateProvider: dateProvider,
            db: db
        )

        let groupsV2 = testDependencies.groupsV2 ?? GroupsV2Impl(
            appReadiness: appReadiness,
            authCredentialStore: authCredentialStore,
            authCredentialManager: authCredentialManager,
            groupSendEndorsementStore: groupSendEndorsementStore
        )

        let aciProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .aci)
        let pniProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .pni)

        let mediaBandwidthPreferenceStore = MediaBandwidthPreferenceStoreImpl(
            reachabilityManager: reachabilityManager,
        )

        let interactionStore = InteractionStoreImpl()
        let storyStore = StoryStoreImpl()

        let audioWaveformManager = AudioWaveformManagerImpl()

        let attachmentStore = AttachmentStoreImpl()

        let orphanedAttachmentCleaner = OrphanedAttachmentCleanerImpl(db: databaseStorage)
        let attachmentContentValidator = AttachmentContentValidatorImpl(
            attachmentStore: attachmentStore,
            audioWaveformManager: audioWaveformManager,
            db: db,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner
        )

        let accountKeyStore = AccountKeyStore()
        let svrCredentialStorage = SVRAuthCredentialStorageImpl()
        let svrLocalStorage = SVRLocalStorageImpl()

        let accountAttributesUpdater = AccountAttributesUpdaterImpl(
            accountAttributesGenerator: AccountAttributesGenerator(
                accountKeyStore: accountKeyStore,
                ows2FAManager: ows2FAManager,
                profileManager: profileManager,
                svrLocalStorage: svrLocalStorage,
                tsAccountManager: tsAccountManager,
                udManager: udManager
            ),
            appReadiness: appReadiness,
            appVersion: appVersion,
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager,
            profileManager: profileManager,
            svrLocalStorage: svrLocalStorage,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager
        )

        let phoneNumberDiscoverabilityManager = PhoneNumberDiscoverabilityManagerImpl(
            accountAttributesUpdater: accountAttributesUpdater,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager
        )

        let svr = SecureValueRecovery2Impl(
            accountAttributesUpdater: accountAttributesUpdater,
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
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
            tsConstants: tsConstants,
            twoFAManager: SVR2.Wrappers.OWS2FAManager(ows2FAManager)
        )

        let backupSettingsStore = BackupSettingsStore()
        let backupCDNCredentialStore = BackupCDNCredentialStore()

        let backupKeyMaterial = BackupKeyMaterialImpl(
            accountKeyStore: accountKeyStore
        )
        let backupRequestManager = BackupRequestManagerImpl(
            backupAuthCredentialManager: BackupAuthCredentialManagerImpl(
                authCredentialStore: authCredentialStore,
                backupKeyMaterial: backupKeyMaterial,
                dateProvider: dateProvider,
                db: db,
                networkManager: networkManager
            ),
            backupCDNCredentialStore: backupCDNCredentialStore,
            backupKeyMaterial: backupKeyMaterial,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager
        )

        let orphanedAttachmentStore = OrphanedAttachmentStoreImpl()
        let attachmentUploadStore = AttachmentUploadStoreImpl(attachmentStore: attachmentStore)
        let attachmentDownloadStore = AttachmentDownloadStoreImpl(dateProvider: dateProvider)

        let orphanedBackupAttachmentStore = OrphanedBackupAttachmentStoreImpl()
        let orphanedBackupAttachmentManager = OrphanedBackupAttachmentManagerImpl(
            appReadiness: appReadiness,
            attachmentStore: attachmentStore,
            backupKeyMaterial: backupKeyMaterial,
            backupRequestManager: backupRequestManager,
            dateProvider: dateProvider,
            db: db,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            tsAccountManager: tsAccountManager
        )

        let attachmentThumbnailService = AttachmentThumbnailServiceImpl()
        let attachmentUploadManager = AttachmentUploadManagerImpl(
            attachmentEncrypter: Upload.Wrappers.AttachmentEncrypter(),
            attachmentStore: attachmentStore,
            attachmentUploadStore: attachmentUploadStore,
            attachmentThumbnailService: attachmentThumbnailService,
            backupKeyMaterial: backupKeyMaterial,
            backupRequestManager: backupRequestManager,
            dateProvider: dateProvider,
            db: db,
            fileSystem: Upload.Wrappers.FileSystem(),
            interactionStore: interactionStore,
            networkManager: networkManager,
            remoteConfigProvider: remoteConfigManager,
            signalService: signalService,
            sleepTimer: Upload.Wrappers.SleepTimer(),
            storyStore: storyStore
        )

        let backupAttachmentUploadEraStore = BackupAttachmentUploadEraStore()
        let backupAttachmentUploadStore = BackupAttachmentUploadStoreImpl()
        let backupAttachmentDownloadStore = BackupAttachmentDownloadStoreImpl()

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
            tsAccountManager: tsAccountManager
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
            tsAccountManager: tsAccountManager
        )

        let backupAttachmentUploadProgress = BackupAttachmentUploadProgressImpl(db: db)
        let backupAttachmentDownloadProgress = BackupAttachmentDownloadProgressImpl(
            appContext: appContext,
            appReadiness: appReadiness,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            remoteConfigProvider: remoteConfigManager
        )

        let backupAttachmentUploadScheduler = BackupAttachmentUploadSchedulerImpl(
            attachmentStore: attachmentStore,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            dateProvider: dateProvider,
            interactionStore: interactionStore,
        )

        let backupListMediaManager = BackupListMediaManagerImpl(
            attachmentStore: attachmentStore,
            attachmentUploadStore: attachmentUploadStore,
            backupAttachmentDownloadProgress: backupAttachmentDownloadProgress,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupAttachmentUploadProgress: backupAttachmentUploadProgress,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupKeyMaterial: backupKeyMaterial,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            remoteConfigManager: remoteConfigManager,
            tsAccountManager: tsAccountManager
        )

        let backupAttachmentUploadQueueRunner = BackupAttachmentUploadQueueRunnerImpl(
            appReadiness: appReadiness,
            attachmentStore: attachmentStore,
            attachmentUploadManager: attachmentUploadManager,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupKeyMaterial: backupKeyMaterial,
            backupListMediaManager: backupListMediaManager,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            progress: backupAttachmentUploadProgress,
            statusManager: backupAttachmentUploadQueueStatusManager,
            tsAccountManager: tsAccountManager
        )

        let attachmentDownloadManager = AttachmentDownloadManagerImpl(
            appReadiness: appReadiness,
            attachmentDownloadStore: attachmentDownloadStore,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
            backupAttachmentUploadQueueRunner: backupAttachmentUploadQueueRunner,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            backupKeyMaterial: backupKeyMaterial,
            backupRequestManager: backupRequestManager,
            currentCallProvider: currentCallProvider,
            dateProvider: dateProvider,
            db: db,
            interactionStore: interactionStore,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
            profileManager: AttachmentDownloadManagerImpl.Wrappers.ProfileManager(profileManager),
            remoteConfigManager: remoteConfigManager,
            signalService: signalService,
            stickerManager: AttachmentDownloadManagerImpl.Wrappers.StickerManager(),
            storyStore: storyStore,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager
        )
        let backupAttachmentDownloadManager = testDependencies.backupAttachmentDownloadManager ?? BackupAttachmentDownloadManagerImpl(
            appContext: appContext,
            appReadiness: appReadiness,
            attachmentStore: attachmentStore,
            attachmentDownloadManager: attachmentDownloadManager,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            backupListMediaManager: backupListMediaManager,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            progress: backupAttachmentDownloadProgress,
            remoteConfigProvider: remoteConfigManager,
            statusManager: backupAttachmentDownloadQueueStatusManager,
            tsAccountManager: tsAccountManager
        )

        let backupPlanManager = BackupPlanManagerImpl(
            backupAttachmentDownloadManager: backupAttachmentDownloadManager,
            backupAttachmentUploadQueueRunner: backupAttachmentUploadQueueRunner,
            backupSettingsStore: backupSettingsStore
        )

        let backupReceiptCredentialRedemptionJobQueue = BackupReceiptCredentialRedemptionJobQueue(
            authCredentialStore: authCredentialStore,
            backupPlanManager: backupPlanManager,
            db: db,
            networkManager: networkManager,
            reachabilityManager: reachabilityManager
        )
        let backupSubscriptionManager = BackupSubscriptionManager(
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupPlanManager: backupPlanManager,
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager,
            receiptCredentialRedemptionJobQueue: backupReceiptCredentialRedemptionJobQueue,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager
        )

        let backupTestFlightEntitlementManager = BackupTestFlightEntitlementManager(
            backupPlanManager: backupPlanManager,
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager
        )

        let attachmentManager = AttachmentManagerImpl(
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentStore: attachmentStore,
            backupAttachmentUploadQueueRunner: backupAttachmentUploadQueueRunner,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            dateProvider: dateProvider,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
            remoteConfigManager: remoteConfigManager,
            stickerManager: AttachmentManagerImpl.Wrappers.StickerManager()
        )
        let attachmentValidationBackfillMigrator = AttachmentValidationBackfillMigratorImpl(
            attachmentStore: attachmentStore,
            attachmentValidationBackfillStore: AttachmentValidationBackfillStore(),
            databaseStorage: databaseStorage,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            validator: attachmentContentValidator
        )

        let quotedReplyManager = QuotedReplyManagerImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
            db: db,
            tsAccountManager: tsAccountManager
        )

        let phoneNumberVisibilityFetcher = PhoneNumberVisibilityFetcherImpl(
            contactsManager: contactManager,
            tsAccountManager: tsAccountManager,
            userProfileStore: userProfileStore
        )

        let recipientManager = SignalRecipientManagerImpl(
            phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
            recipientDatabaseTable: recipientDatabaseTable,
            storageServiceManager: storageServiceManager
        )

        let pniDistributionParameterBuilder = PniDistributionParameterBuilderImpl(
            db: db,
            messageSender: PniDistributionParameterBuilderImpl.Wrappers.MessageSender(messageSender),
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            registrationIdGenerator: RegistrationIdGenerator()
        )

        let badgeCountFetcher = BadgeCountFetcherImpl()

        let identityManager = OWSIdentityManagerImpl(
            aciProtocolStore: aciProtocolStore,
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
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager
        )

        let changePhoneNumberPniManager = ChangePhoneNumberPniManagerImpl(
            db: db,
            identityManager: ChangePhoneNumberPniManagerImpl.Wrappers.IdentityManager(identityManager),
            pniDistributionParameterBuilder: pniDistributionParameterBuilder,
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            preKeyManager: ChangePhoneNumberPniManagerImpl.Wrappers.PreKeyManager(),
            registrationIdGenerator: RegistrationIdGenerator(),
            tsAccountManager: tsAccountManager
        )

        let linkPreviewSettingStore = LinkPreviewSettingStore(keyValueStore: SSKPreferences.store)
        let linkPreviewSettingManager = LinkPreviewSettingManagerImpl(
            linkPreviewSettingStore: linkPreviewSettingStore,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager
        )

        let linkPreviewManager = LinkPreviewManagerImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
            db: db,
            linkPreviewSettingStore: linkPreviewSettingStore
        )

        let editMessageStore = EditMessageStoreImpl()
        let editManager = EditManagerImpl(
            context: .init(
                attachmentStore: attachmentStore,
                dataStore: EditManagerImpl.Wrappers.DataStore(),
                editManagerAttachments: EditManagerAttachmentsImpl(
                    attachmentManager: attachmentManager,
                    attachmentStore: attachmentStore,
                    attachmentValidator: attachmentContentValidator,
                    linkPreviewManager: linkPreviewManager,
                    tsMessageStore: EditManagerAttachmentsImpl.Wrappers.TSMessageStore()
                ),
                editMessageStore: editMessageStore,
                receiptManagerShim: EditManagerImpl.Wrappers.ReceiptManager(receiptManager: receiptManager)
            )
        )

        let groupUpdateItemBuilder = GroupUpdateItemBuilderImpl(
            contactsManager: GroupUpdateItemBuilderImpl.Wrappers.ContactsManager(contactManager),
            recipientDatabaseTable: recipientDatabaseTable
        )

        let groupUpdateInfoMessageInserter = GroupUpdateInfoMessageInserterImpl(
            dateProvider: dateProvider,
            groupUpdateItemBuilder: groupUpdateItemBuilder,
            notificationPresenter: notificationPresenter
        )

        let groupMemberStore = GroupMemberStoreImpl()
        let threadAssociatedDataStore = ThreadAssociatedDataStoreImpl()
        let threadReplyInfoStore = ThreadReplyInfoStore()

        let wallpaperImageStore = WallpaperImageStoreImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
            db: db
        )
        let wallpaperStore = WallpaperStore(
            wallpaperImageStore: wallpaperImageStore
        )
        let chatColorSettingStore = ChatColorSettingStore(
            wallpaperStore: wallpaperStore
        )

        let disappearingMessagesConfigurationStore = DisappearingMessagesConfigurationStoreImpl()

        let groupMemberUpdater = GroupMemberUpdaterImpl(
            temporaryShims: GroupMemberUpdaterTemporaryShimsImpl(),
            groupMemberStore: groupMemberStore,
            signalServiceAddressCache: signalServiceAddressCache
        )

        let messageSendLog = MessageSendLog(
            db: db,
            dateProvider: { Date() }
        )

        let callLinkStore = CallLinkRecordStoreImpl()
        let deletedCallRecordStore = DeletedCallRecordStoreImpl()
        let deletedCallRecordCleanupManager = DeletedCallRecordCleanupManagerImpl(
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
            threadStore: threadStore
        )
        let outgoingCallEventSyncMessageManager = OutgoingCallEventSyncMessageManagerImpl(
            appReadiness: appReadiness,
            databaseStorage: databaseStorage,
            messageSenderJobQueue: messageSenderJobQueue,
            callRecordConversationIdAdapter: callRecordSyncMessageConversationIdAdapater
        )
        let adHocCallRecordManager = AdHocCallRecordManagerImpl(
            callRecordStore: callRecordStore,
            callLinkStore: callLinkStore,
            outgoingSyncMessageManager: outgoingCallEventSyncMessageManager
        )
        let groupCallRecordManager = GroupCallRecordManagerImpl(
            callRecordStore: callRecordStore,
            interactionStore: interactionStore,
            outgoingSyncMessageManager: outgoingCallEventSyncMessageManager
        )
        let individualCallRecordManager = IndividualCallRecordManagerImpl(
            callRecordStore: callRecordStore,
            interactionStore: interactionStore,
            outgoingSyncMessageManager: outgoingCallEventSyncMessageManager
        )
        let callRecordQuerier = CallRecordQuerierImpl()
        let callRecordMissedCallManager = CallRecordMissedCallManagerImpl(
            callRecordConversationIdAdapter: callRecordSyncMessageConversationIdAdapater,
            callRecordQuerier: callRecordQuerier,
            callRecordStore: callRecordStore,
            syncMessageSender: CallRecordMissedCallManagerImpl.Wrappers.SyncMessageSender(messageSenderJobQueue)
        )
        let callRecordDeleteManager = CallRecordDeleteManagerImpl(
            callRecordStore: callRecordStore,
            outgoingCallEventSyncMessageManager: outgoingCallEventSyncMessageManager,
            deletedCallRecordCleanupManager: deletedCallRecordCleanupManager,
            deletedCallRecordStore: deletedCallRecordStore,
            threadStore: threadStore
        )

        let deleteForMeOutgoingSyncMessageManager = DeleteForMeOutgoingSyncMessageManagerImpl(
            recipientDatabaseTable: recipientDatabaseTable,
            syncMessageSender: DeleteForMeOutgoingSyncMessageManagerImpl.Wrappers.SyncMessageSender(messageSenderJobQueue),
            threadStore: threadStore
        )
        let interactionDeleteManager = InteractionDeleteManagerImpl(
            callRecordStore: callRecordStore,
            callRecordDeleteManager: callRecordDeleteManager,
            databaseStorage: databaseStorage,
            deleteForMeOutgoingSyncMessageManager: deleteForMeOutgoingSyncMessageManager,
            interactionReadCache: modelReadCaches.interactionReadCache,
            interactionStore: interactionStore,
            messageSendLog: messageSendLog,
            tsAccountManager: tsAccountManager
        )

        let callRecordDeleteAllJobQueue = CallRecordDeleteAllJobQueue(
            callLinkStore: callLinkStore,
            callRecordConversationIdAdapter: callRecordSyncMessageConversationIdAdapater,
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordQuerier: callRecordQuerier,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
            messageSenderJobQueue: messageSenderJobQueue
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
                notificationPresenter: notificationPresenter
            ),
            recipientDatabaseTable: recipientDatabaseTable,
            threadStore: threadStore
        )
        let incomingCallLogEventSyncMessageManager = IncomingCallLogEventSyncMessageManagerImpl(
            callRecordConversationIdAdapter: callRecordSyncMessageConversationIdAdapater,
            deleteAllCallsJobQueue: IncomingCallLogEventSyncMessageManagerImpl.Wrappers.DeleteAllCallsJobQueue(
                callRecordDeleteAllJobQueue
            ),
            missedCallManager: callRecordMissedCallManager
        )

        let threadSoftDeleteManager = ThreadSoftDeleteManagerImpl(
            deleteForMeOutgoingSyncMessageManager: deleteForMeOutgoingSyncMessageManager,
            intentsManager: ThreadSoftDeleteManagerImpl.Wrappers.IntentsManager(),
            interactionDeleteManager: interactionDeleteManager,
            recipientDatabaseTable: recipientDatabaseTable,
            storyManager: ThreadSoftDeleteManagerImpl.Wrappers.StoryManager(),
            threadReplyInfoStore: threadReplyInfoStore,
            tsAccountManager: tsAccountManager
        )

        let deleteForMeAddressableMessageFinder = DeleteForMeAddressableMessageFinderImpl(
            tsAccountManager: tsAccountManager
        )
        let bulkDeleteInteractionJobQueue = BulkDeleteInteractionJobQueue(
            addressableMessageFinder: deleteForMeAddressableMessageFinder,
            db: db,
            interactionDeleteManager: interactionDeleteManager,
            threadSoftDeleteManager: threadSoftDeleteManager,
            threadStore: threadStore
        )
        let deleteForMeIncomingSyncMessageManager = DeleteForMeIncomingSyncMessageManagerImpl(
            addressableMessageFinder: deleteForMeAddressableMessageFinder,
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            bulkDeleteInteractionJobQueue: bulkDeleteInteractionJobQueue,
            interactionDeleteManager: interactionDeleteManager,
            threadSoftDeleteManager: threadSoftDeleteManager
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
            wallpaperStore: wallpaperStore
        )

        let pinnedThreadStore = PinnedThreadStoreImpl()
        let pinnedThreadManager = PinnedThreadManagerImpl(
            db: db,
            pinnedThreadStore: pinnedThreadStore,
            storageServiceManager: storageServiceManager,
            threadStore: threadStore
        )

        let storyRecipientStore = StoryRecipientStore()
        let storyRecipientManager = StoryRecipientManager(
            recipientDatabaseTable: recipientDatabaseTable,
            storyRecipientStore: storyRecipientStore,
            storageServiceManager: storageServiceManager,
            threadStore: threadStore
        )

        let authorMergeHelper = AuthorMergeHelper()
        let recipientMerger = RecipientMergerImpl(
            aciSessionStore: aciProtocolStore.sessionStore,
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
                wallpaperStore: wallpaperStore
            ),
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            searchableNameIndexer: searchableNameIndexer,
            storageServiceManager: storageServiceManager,
            storyRecipientStore: storyRecipientStore
        )

        let backupIdManager = BackupIdManagerImpl(
            accountKeyStore: accountKeyStore,
            backupRequestManager: backupRequestManager,
            db: db,
            networkManager: networkManager,
        )

        let backupDisablingManager = BackupDisablingManager(
            authCredentialStore: authCredentialStore,
            backupAttachmentDownloadQueueStatusManager: backupAttachmentDownloadQueueStatusManager,
            backupCDNCredentialStore: backupCDNCredentialStore,
            backupIdManager: backupIdManager,
            backupListMediaManager: backupListMediaManager,
            backupPlanManager: backupPlanManager,
            backupSettingsStore: backupSettingsStore,
            db: db,
            tsAccountManager: tsAccountManager,
        )

        let registrationStateChangeManager = RegistrationStateChangeManagerImpl(
            appContext: appContext,
            authCredentialStore: authCredentialStore,
            backupIdManager: backupIdManager,
            backupListMediaManager: backupListMediaManager,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            db: db,
            dmConfigurationStore: disappearingMessagesConfigurationStore,
            groupsV2: groupsV2,
            identityManager: identityManager,
            networkManager: networkManager,
            notificationPresenter: notificationPresenter,
            paymentsEvents: RegistrationStateChangeManagerImpl.Wrappers.PaymentsEvents(paymentsEvents),
            recipientManager: recipientManager,
            recipientMerger: recipientMerger,
            senderKeyStore: RegistrationStateChangeManagerImpl.Wrappers.SenderKeyStore(senderKeyStore),
            signalProtocolStoreManager: signalProtocolStoreManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
            udManager: udManager,
            versionedProfiles: versionedProfiles
        )

        let identityKeyChecker = IdentityKeyCheckerImpl(
            db: db,
            identityManager: IdentityKeyCheckerImpl.Wrappers.IdentityManager(identityManager),
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
            libsignalNet: libsignalNet,
            registrationStateChangeManager: registrationStateChangeManager,
            inactivePrimaryDeviceStore: inactivePrimaryDeviceStore,
            userDefaults: appContext.appUserDefaults()
        )

        let preKeyTaskAPIClient = PreKeyTaskAPIClientImpl(networkManager: networkManager)
        let preKeyManager = PreKeyManagerImpl(
            dateProvider: dateProvider,
            db: db,
            identityKeyMismatchManager: identityKeyMismatchManager,
            identityManager: PreKey.Wrappers.IdentityManager(identityManager),
            messageProcessor: messageProcessor,
            preKeyTaskAPIClient: preKeyTaskAPIClient,
            protocolStoreManager: signalProtocolStoreManager,
            remoteConfigProvider: remoteConfigManager,
            chatConnectionManager: chatConnectionManager,
            tsAccountManager: tsAccountManager
        )

        let registrationSessionManager = RegistrationSessionManagerImpl(
            dateProvider: dateProvider,
            db: db,
            signalService: signalService
        )

        let recipientHidingManager = RecipientHidingManagerImpl(
            profileManager: profileManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
            messageSenderJobQueue: messageSenderJobQueue
        )

        let donationReceiptCredentialResultStore = DonationReceiptCredentialResultStoreImpl()

        let usernameApiClient = UsernameApiClientImpl(
            networkManager: UsernameApiClientImpl.Wrappers.NetworkManager(networkManager: networkManager),
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
            usernameLinkManager: usernameLinkManager
        )
        let usernameValidationManager = UsernameValidationManagerImpl(context: .init(
            database: db,
            localUsernameManager: localUsernameManager,
            messageProcessor: Usernames.Validation.Wrappers.MessageProcessor(messageProcessor),
            storageServiceManager: Usernames.Validation.Wrappers.StorageServiceManager(storageServiceManager),
            usernameLinkManager: usernameLinkManager,
            whoAmIManager: whoAmIManager
        ))

        let incomingPniChangeNumberProcessor = IncomingPniChangeNumberProcessorImpl(
            identityManager: identityManager,
            pniProtocolStore: pniProtocolStore,
            preKeyManager: preKeyManager,
            registrationStateChangeManager: registrationStateChangeManager,
            tsAccountManager: tsAccountManager
        )

        let masterKeySyncManager = MasterKeySyncManagerImpl(
            dateProvider: dateProvider,
            svr: svr,
            syncManager: MasterKeySyncManagerImpl.Wrappers.SyncManager(syncManager),
            tsAccountManager: tsAccountManager
        )

        let messageStickerManager = MessageStickerManagerImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
            stickerManager: MessageStickerManagerImpl.Wrappers.StickerManager()
        )

        let contactShareManager = ContactShareManagerImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator
        )

        let sentMessageTranscriptReceiver = SentMessageTranscriptReceiverImpl(
            attachmentDownloads: attachmentDownloadManager,
            attachmentManager: attachmentManager,
            disappearingMessagesJob: SentMessageTranscriptReceiverImpl.Wrappers.DisappearingMessagesJob(),
            earlyMessageManager: SentMessageTranscriptReceiverImpl.Wrappers.EarlyMessageManager(earlyMessageManager),
            groupManager: SentMessageTranscriptReceiverImpl.Wrappers.GroupManager(),
            interactionDeleteManager: interactionDeleteManager,
            interactionStore: interactionStore,
            messageStickerManager: messageStickerManager,
            paymentsHelper: SentMessageTranscriptReceiverImpl.Wrappers.PaymentsHelper(paymentsHelper),
            signalProtocolStoreManager: signalProtocolStoreManager,
            tsAccountManager: tsAccountManager,
            viewOnceMessages: SentMessageTranscriptReceiverImpl.Wrappers.ViewOnceMessages()
        )

        let preferences = Preferences()
        let systemStoryManager = testDependencies.systemStoryManager ?? SystemStoryManager(
            appReadiness: appReadiness,
            messageProcessor: messageProcessor
        )
        let typingIndicators = TypingIndicatorsImpl()

        let privateStoryThreadDeletionManager = PrivateStoryThreadDeletionManagerImpl(
            dateProvider: dateProvider,
            remoteConfigProvider: remoteConfigManager,
            storageServiceManager: storageServiceManager,
            threadRemover: threadRemover,
            threadStore: threadStore
        )

        let reactionStore: any ReactionStore = ReactionStoreImpl()
        let disappearingMessagesJob = OWSDisappearingMessagesJob(appReadiness: appReadiness, databaseStorage: databaseStorage)

        let storageServiceRecordIkmCapabilityStore = StorageServiceRecordIkmCapabilityStoreImpl()

        let profileFetcher = ProfileFetcherImpl(
            db: db,
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            identityManager: identityManager,
            paymentsHelper: paymentsHelper,
            profileManager: profileManager,
            reachabilityManager: reachabilityManager,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientManager: recipientManager,
            recipientMerger: recipientMerger,
            storageServiceRecordIkmCapabilityStore: storageServiceRecordIkmCapabilityStore,
            storageServiceRecordIkmMigrator: StorageServiceRecordIkmMigratorImpl(
                db: db,
                storageServiceRecordIkmCapabilityStore: storageServiceRecordIkmCapabilityStore,
                storageServiceManager: storageServiceManager,
                tsAccountManager: tsAccountManager
            ),
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
            udManager: udManager,
            versionedProfiles: versionedProfiles
        )

        let messagePipelineSupervisor = MessagePipelineSupervisor()

        let backupChatStyleArchiver = BackupArchiveChatStyleArchiver(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            backupAttachmentDownloadManager: backupAttachmentDownloadManager,
            chatColorSettingStore: chatColorSettingStore,
            wallpaperStore: wallpaperStore,
        )

        let backupInteractionStore = BackupArchiveInteractionStore(interactionStore: interactionStore)
        let backupRecipientStore = BackupArchiveRecipientStore(
            recipientTable: recipientDatabaseTable,
            searchableNameIndexer: searchableNameIndexer
        )
        let backupStickerPackDownloadStore = BackupStickerPackDownloadStoreImpl()
        let backupStoryStore = BackupArchiveStoryStore(
            storyStore: storyStore,
            storyRecipientStore: storyRecipientStore
        )
        let backupThreadStore = BackupArchiveThreadStore(threadStore: threadStore)

        let backupArchiveErrorPresenter = backupArchiveErrorPresenterFactory.build(
            db: db,
            tsAccountManager: tsAccountManager
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
            tsAccountManager: tsAccountManager
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
            usernameLookupManager: usernameLookupManager
        )

        let incrementalMessageTSAttachmentMigrator = incrementalMessageTSAttachmentMigratorFactory.migrator(
            appContext: appContext,
            appReadiness: appReadiness,
            databaseStorage: databaseStorage,
            remoteConfigManager: remoteConfigManager,
            tsAccountManager: tsAccountManager
        )

        let backupArchiveManager = BackupArchiveManagerImpl(
            accountDataArchiver: BackupArchiveAccountDataArchiver(
                backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
                backupPlanManager: backupPlanManager,
                backupSubscriptionManager: backupSubscriptionManager,
                chatStyleArchiver: backupChatStyleArchiver,
                disappearingMessageConfigurationStore: disappearingMessagesConfigurationStore,
                donationSubscriptionManager: BackupArchive.Wrappers.DonationSubscriptionManager(),
                linkPreviewSettingStore: linkPreviewSettingStore,
                localUsernameManager: localUsernameManager,
                ows2FAManager: BackupArchive.Wrappers.OWS2FAManager(ows2FAManager),
                phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManager,
                preferences: BackupArchive.Wrappers.Preferences(preferences: preferences),
                profileManager: BackupArchive.Wrappers.ProfileManager(profileManager),
                receiptManager: BackupArchive.Wrappers.ReceiptManager(receiptManager: receiptManager),
                reactionManager: BackupArchive.Wrappers.ReactionManager(),
                sskPreferences: BackupArchive.Wrappers.SSKPreferences(),
                storyManager: BackupArchive.Wrappers.StoryManager(),
                systemStoryManager: BackupArchive.Wrappers.SystemStoryManager(systemStoryManager: systemStoryManager),
                typingIndicators: BackupArchive.Wrappers.TypingIndicators(typingIndicators: typingIndicators),
                udManager: BackupArchive.Wrappers.UDManager(udManager: udManager),
                usernameEducationManager: usernameEducationManager
            ),
            adHocCallArchiver: BackupArchiveAdHocCallArchiver(
                callRecordStore: callRecordStore,
                callLinkRecordStore: callLinkStore,
                adHocCallRecordManager: adHocCallRecordManager
            ),
            appVersion: appVersion,
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentUploadManager: attachmentUploadManager,
            avatarFetcher: backupArchiveAvatarFetcher,
            backupArchiveErrorPresenter: backupArchiveErrorPresenter,
            backupAttachmentDownloadManager: backupAttachmentDownloadManager,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            backupStickerPackDownloadStore: backupStickerPackDownloadStore,
            callLinkRecipientArchiver: BackupArchiveCallLinkRecipientArchiver(
                callLinkStore: callLinkStore
            ),
            chatArchiver: BackupArchiveChatArchiver(
                chatStyleArchiver: backupChatStyleArchiver,
                contactRecipientArchiver: backupContactRecipientArchiver,
                dmConfigurationStore: disappearingMessagesConfigurationStore,
                pinnedThreadStore: pinnedThreadStore,
                threadStore: backupThreadStore
            ),
            chatItemArchiver: BackupArchiveChatItemArchiver(
                attachmentManager: attachmentManager,
                attachmentStore: attachmentStore,
                backupAttachmentDownloadManager: backupAttachmentDownloadManager,
                callRecordStore: callRecordStore,
                contactManager: BackupArchive.Wrappers.ContactManager(contactManager),
                editMessageStore: editMessageStore,
                groupCallRecordManager: groupCallRecordManager,
                groupUpdateItemBuilder: groupUpdateItemBuilder,
                individualCallRecordManager: individualCallRecordManager,
                interactionStore: backupInteractionStore,
                archivedPaymentStore: archivedPaymentStore,
                reactionStore: reactionStore,
                threadStore: backupThreadStore,
            ),
            contactRecipientArchiver: backupContactRecipientArchiver,
            databaseChangeObserver: databaseStorage.databaseChangeObserver,
            dateProvider: dateProvider,
            dateProviderMonotonic: dateProviderMonotonic,
            db: db,
            dbFileSizeProvider: dbFileSizeProvider,
            disappearingMessagesJob: disappearingMessagesJob,
            distributionListRecipientArchiver: BackupArchiveDistributionListRecipientArchiver(
                privateStoryThreadDeletionManager: privateStoryThreadDeletionManager,
                storyStore: backupStoryStore,
                threadStore: backupThreadStore
            ),
            encryptedStreamProvider: BackupArchiveEncryptedProtoStreamProvider(
                backupKeyMaterial: backupKeyMaterial
            ),
            fullTextSearchIndexer: BackupArchiveFullTextSearchIndexerImpl(
                appReadiness: appReadiness,
                dateProvider: dateProviderMonotonic,
                db: db,
                fullTextSearchIndexer: BackupArchiveFullTextSearchIndexerImpl.Wrappers.FullTextSearchIndexer(),
                interactionStore: interactionStore,
                searchableNameIndexer: searchableNameIndexer
            ),
            groupRecipientArchiver: BackupArchiveGroupRecipientArchiver(
                avatarDefaultColorManager: avatarDefaultColorManager,
                avatarFetcher: backupArchiveAvatarFetcher,
                blockingManager: BackupArchive.Wrappers.BlockingManager(blockingManager),
                disappearingMessageConfigStore: disappearingMessagesConfigurationStore,
                groupsV2: groupsV2,
                profileManager: BackupArchive.Wrappers.ProfileManager(profileManager),
                storyStore: backupStoryStore,
                threadStore: backupThreadStore
            ),
            incrementalTSAttachmentMigrator: incrementalMessageTSAttachmentMigrator,
            localStorage: accountKeyStore,
            localRecipientArchiver: BackupArchiveLocalRecipientArchiver(
                avatarDefaultColorManager: avatarDefaultColorManager,
                profileManager: BackupArchive.Wrappers.ProfileManager(profileManager),
                recipientStore: backupRecipientStore
            ),
            messagePipelineSupervisor: messagePipelineSupervisor,
            plaintextStreamProvider: BackupArchivePlaintextProtoStreamProvider(),
            postFrameRestoreActionManager: BackupArchivePostFrameRestoreActionManager(
                avatarFetcher: backupArchiveAvatarFetcher,
                dateProvider: dateProvider,
                interactionStore: backupInteractionStore,
                lastVisibleInteractionStore: lastVisibleInteractionStore,
                preferences: BackupArchive.Wrappers.Preferences(preferences: preferences),
                recipientDatabaseTable: recipientDatabaseTable,
                sskPreferences: BackupArchive.Wrappers.SSKPreferences(),
                threadStore: backupThreadStore
            ),
            releaseNotesRecipientArchiver: BackupArchiveReleaseNotesRecipientArchiver(),
            remoteConfigManager: remoteConfigManager,
            stickerPackArchiver: BackupArchiveStickerPackArchiver(
                backupStickerPackDownloadStore: backupStickerPackDownloadStore
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
            udManager: udManager
        )

        let attachmentCloner = SignalAttachmentClonerImpl()

        let attachmentViewOnceManager = AttachmentViewOnceManagerImpl(
            attachmentStore: attachmentStore,
            db: db,
            interactionStore: interactionStore
        )

        let deviceManager = OWSDeviceManagerImpl()
        let deviceStore = OWSDeviceStoreImpl()
        let deviceService = OWSDeviceServiceImpl(
            db: db,
            deviceManager: deviceManager,
            deviceStore: deviceStore,
            messageSenderJobQueue: messageSenderJobQueue,
            networkManager: networkManager,
            recipientFetcher: recipientFetcher,
            recipientManager: recipientManager,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager
        )
        let inactiveLinkedDeviceFinder = InactiveLinkedDeviceFinderImpl(
            dateProvider: dateProvider,
            db: db,
            deviceNameDecrypter: InactiveLinkedDeviceFinderImpl.Wrappers.OWSDeviceNameDecrypter(identityManager: identityManager),
            deviceService: deviceService,
            deviceStore: deviceStore,
            remoteConfigProvider: remoteConfigManager,
            tsAccountManager: tsAccountManager
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
            tsAccountManager: tsAccountManager
        )

        let groupMessageProcessorManager = GroupMessageProcessorManager()

        let receiptSender = ReceiptSender(
            appReadiness: appReadiness,
            recipientDatabaseTable: recipientDatabaseTable
        )

        let messageFetcherJob = MessageFetcherJob(appReadiness: appReadiness)

        let backgroundMessageFetcherFactory = BackgroundMessageFetcherFactory(
            chatConnectionManager: chatConnectionManager,
            groupMessageProcessorManager: groupMessageProcessorManager,
            messageFetcherJob: messageFetcherJob,
            messageProcessor: messageProcessor,
            messageSenderJobQueue: messageSenderJobQueue,
            receiptSender: receiptSender,
        )

        let attachmentOffloadingManager = AttachmentOffloadingManagerImpl(
            attachmentStore: attachmentStore,
            attachmentThumbnailService: attachmentThumbnailService,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
            listMediaManager: backupListMediaManager,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore
        )
        let backupExportJob = BackupExportJobImpl(
            attachmentOffloadingManager: attachmentOffloadingManager,
            backupArchiveManager: backupArchiveManager,
            backupAttachmentUploadProgress: backupAttachmentUploadProgress,
            backupAttachmentUploadQueueRunner: backupAttachmentUploadQueueRunner,
            backupIdManager: backupIdManager,
            backupKeyMaterial: backupKeyMaterial,
            backupListMediaManager: backupListMediaManager,
            backupSettingsStore: backupSettingsStore,
            db: db,
            messageProcessor: messageProcessor,
            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
            reachabilityManager: reachabilityManager,
            tsAccountManager: tsAccountManager
        )
        let backupExportJobRunner = BackupExportJobRunnerImpl(
            backupExportJob: backupExportJob
        )

        let dependenciesBridge = DependenciesBridge(
            accountAttributesUpdater: accountAttributesUpdater,
            adHocCallRecordManager: adHocCallRecordManager,
            appExpiry: appExpiry,
            attachmentCloner: attachmentCloner,
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
            backupAttachmentDownloadManager: backupAttachmentDownloadManager,
            backupAttachmentDownloadProgress: backupAttachmentDownloadProgress,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupAttachmentDownloadQueueStatusReporter: backupAttachmentDownloadQueueStatusManager,
            backupAttachmentUploadProgress: backupAttachmentUploadProgress,
            backupAttachmentUploadQueueRunner: backupAttachmentUploadQueueRunner,
            backupAttachmentUploadQueueStatusReporter: backupAttachmentUploadQueueStatusManager,
            backupDisablingManager: backupDisablingManager,
            backupExportJob: backupExportJob,
            backupExportJobRunner: backupExportJobRunner,
            backupIdManager: backupIdManager,
            backupKeyMaterial: backupKeyMaterial,
            backupRequestManager: backupRequestManager,
            backupPlanManager: backupPlanManager,
            backupSubscriptionManager: backupSubscriptionManager,
            backupTestFlightEntitlementManager: backupTestFlightEntitlementManager,
            badgeCountFetcher: badgeCountFetcher,
            callLinkStore: callLinkStore,
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordMissedCallManager: callRecordMissedCallManager,
            callRecordQuerier: callRecordQuerier,
            callRecordStore: callRecordStore,
            changePhoneNumberPniManager: changePhoneNumberPniManager,
            chatColorSettingStore: chatColorSettingStore,
            chatConnectionManager: chatConnectionManager,
            contactShareManager: contactShareManager,
            currentCallProvider: currentCallProvider,
            databaseChangeObserver: databaseStorage.databaseChangeObserver,
            db: db,
            deletedCallRecordCleanupManager: deletedCallRecordCleanupManager,
            deletedCallRecordStore: deletedCallRecordStore,
            deleteForMeIncomingSyncMessageManager: deleteForMeIncomingSyncMessageManager,
            deleteForMeOutgoingSyncMessageManager: deleteForMeOutgoingSyncMessageManager,
            deviceManager: deviceManager,
            deviceService: deviceService,
            deviceSleepManager: deviceSleepManager,
            deviceStore: deviceStore,
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
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
            incrementalMessageTSAttachmentMigrator: incrementalMessageTSAttachmentMigrator,
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
            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            archivedPaymentStore: archivedPaymentStore,
            phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManager,
            phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
            pinnedThreadManager: pinnedThreadManager,
            pinnedThreadStore: pinnedThreadStore,
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
            storageServiceRecordIkmCapabilityStore: storageServiceRecordIkmCapabilityStore,
            storyRecipientManager: storyRecipientManager,
            storyRecipientStore: storyRecipientStore,
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
            wallpaperStore: wallpaperStore
        )
        DependenciesBridge.setShared(dependenciesBridge, isRunningTests: appContext.isRunningTests)

        let proximityMonitoringManager = OWSProximityMonitoringManagerImpl()
        let avatarBuilder = AvatarBuilder(appReadiness: appReadiness)
        let smJobQueues = SignalMessagingJobQueues(
            appReadiness: appReadiness,
            db: db,
            reachabilityManager: reachabilityManager
        )

        let pendingReceiptRecorder = testDependencies.pendingReceiptRecorder
            ?? MessageRequestPendingReceipts(appReadiness: appReadiness)
        let messageReceiver = MessageReceiver(
            callMessageHandler: callMessageHandler,
            deleteForMeSyncMessageReceiver: DeleteForMeSyncMessageReceiverImpl(
                deleteForMeIncomingSyncMessageManager: deleteForMeIncomingSyncMessageManager,
                recipientDatabaseTable: recipientDatabaseTable,
                threadStore: threadStore,
                tsAccountManager: tsAccountManager
            )
        )
        let messageDecrypter = OWSMessageDecrypter(appReadiness: appReadiness)
        let stickerManager = StickerManager(
            appReadiness: appReadiness,
            dateProvider: dateProvider
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
            libsignalNet: libsignalNet
        )
        let localUserLeaveGroupJobQueue = LocalUserLeaveGroupJobQueue(
            db: db,
            reachabilityManager: reachabilityManager
        )
        let donationReceiptCredentialRedemptionJobQueue = DonationReceiptCredentialRedemptionJobQueue(
            dateProvider: dateProvider,
            db: db,
            donationReceiptCredentialResultStore: donationReceiptCredentialResultStore,
            networkManager: networkManager,
            profileManager: profileManager,
            reachabilityManager: reachabilityManager
        )

        let groupCallPeekClient = GroupCallPeekClient(db: db, groupsV2: groupsV2)
        let groupCallManager = GroupCallManager(
            currentCallProvider: currentCallProvider,
            groupCallPeekClient: groupCallPeekClient
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
            aciSignalProtocolStore: aciSignalProtocolStore,
            pniSignalProtocolStore: pniSignalProtocolStore,
            udManager: udManager,
            messageDecrypter: messageDecrypter,
            groupMessageProcessorManager: groupMessageProcessorManager,
            ows2FAManager: ows2FAManager,
            disappearingMessagesJob: disappearingMessagesJob,
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
            backupReceiptCredentialRedemptionJobQueue: backupReceiptCredentialRedemptionJobQueue,
            donationReceiptCredentialRedemptionJobQueue: donationReceiptCredentialRedemptionJobQueue,
            preferences: preferences,
            proximityMonitoringManager: proximityMonitoringManager,
            avatarBuilder: avatarBuilder,
            smJobQueues: smJobQueues,
            groupCallManager: groupCallManager,
            profileFetcher: profileFetcher
        )
        SSKEnvironment.setShared(sskEnvironment, isRunningTests: appContext.isRunningTests)

        // Register renamed classes.
        NSKeyedUnarchiver.setClass(OWSUserProfile.self, forClassName: "OWSUserProfile")
        NSKeyedUnarchiver.setClass(TSGroupModelV2.self, forClassName: "TSGroupModelV2")
        NSKeyedUnarchiver.setClass(PendingProfileUpdate.self, forClassName: "SignalMessaging.PendingProfileUpdate")

        Sounds.performStartupTasks(appReadiness: appReadiness)

        return AppSetup.DatabaseContinuation(
            appContext: appContext,
            appReadiness: appReadiness,
            authCredentialStore: authCredentialStore,
            dependenciesBridge: dependenciesBridge,
            sskEnvironment: sskEnvironment,
            backgroundTask: backgroundTask,
            authCredentialManager: authCredentialManager,
            callLinkPublicParams: callLinkPublicParams,
            remoteConfigManager: remoteConfigManager
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
        private let appReadiness: AppReadiness
        private let authCredentialStore: AuthCredentialStore
        private let dependenciesBridge: DependenciesBridge
        private let remoteConfigManager: RemoteConfigManager
        private let sskEnvironment: SSKEnvironment
        private let backgroundTask: OWSBackgroundTask

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
            sskEnvironment: SSKEnvironment,
            backgroundTask: OWSBackgroundTask,
            authCredentialManager: any AuthCredentialManager,
            callLinkPublicParams: GenericServerPublicParams,
            remoteConfigManager: RemoteConfigManager
        ) {
            self.appContext = appContext
            self.appReadiness = appReadiness
            self.authCredentialStore = authCredentialStore
            self.dependenciesBridge = dependenciesBridge
            self.sskEnvironment = sskEnvironment
            self.backgroundTask = backgroundTask
            self.authCredentialManager = authCredentialManager
            self.callLinkPublicParams = callLinkPublicParams
            self.remoteConfigManager = remoteConfigManager
        }
    }
}

extension AppSetup.DatabaseContinuation {
    public func prepareDatabase() async -> AppSetup.FinalContinuation {
        let databaseStorage = sskEnvironment.databaseStorageRef

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
        databaseStorage.runGrdbSchemaMigrationsOnMainDatabase()
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
            sskEnvironment: self.sskEnvironment
        )
    }

    private func shouldTruncateGrdbWal() -> Bool {
        appContext.isMainApp && appContext.mainApplicationStateOnLaunch() != .background
    }
}

// MARK: - FinalContinuation

extension AppSetup {
    public class FinalContinuation {
        private let appContext: AppContext
        private let appReadiness: AppReadiness
        private let authCredentialStore: AuthCredentialStore
        public let dependenciesBridge: DependenciesBridge
        private let sskEnvironment: SSKEnvironment

        @MainActor private var didRunLaunchTasks = false

        fileprivate init(
            appContext: AppContext,
            appReadiness: AppReadiness,
            authCredentialStore: AuthCredentialStore,
            dependenciesBridge: DependenciesBridge,
            sskEnvironment: SSKEnvironment
        ) {
            self.appContext = appContext
            self.appReadiness = appReadiness
            self.authCredentialStore = authCredentialStore
            self.dependenciesBridge = dependenciesBridge
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
            versionedProfiles: sskEnvironment.versionedProfilesRef
        ).migrateIfNeeded()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { [appContext, dependenciesBridge, sskEnvironment] in
            sskEnvironment.localUserLeaveGroupJobQueueRef.start(appContext: appContext)
            sskEnvironment.callRecordDeleteAllJobQueueRef.start(appContext: appContext)
            sskEnvironment.bulkDeleteInteractionJobQueueRef.start(appContext: appContext)
            sskEnvironment.backupReceiptCredentialRedemptionJobQueue.start(appContext: appContext)
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
        canInitiateRegistration: Bool
    ) -> SetupError? {
        let storageServiceManager = sskEnvironment.storageServiceManagerRef
        let tsAccountManager = dependenciesBridge.tsAccountManager

        let registrationState = tsAccountManager.registrationStateWithMaybeSneakyTransaction
        let canInitiateReregistration = registrationState.isDeregistered && canInitiateRegistration

        if registrationState.isRegistered {
            // TODO: Enforce already-true invariant "registered means LocalIdentifiers" via the compiler.
            let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!
            storageServiceManager.setLocalIdentifiers(localIdentifiers)
        } else if !willResumeInProgressRegistration && !canInitiateReregistration {
            // We aren't registered, and we're not in the middle of registration, so
            // throw an error about corrupt registration.
            return .corruptRegistrationState
        }

        if !willResumeInProgressRegistration && !canInitiateReregistration {
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
                tx: tx
            )
        }
    }
}
