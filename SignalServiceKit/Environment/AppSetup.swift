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
        let svrKeyDeriver: SVRKeyDeriver?
        let syncManager: (any SyncManagerProtocol)?
        let systemStoryManager: (any SystemStoryManagerProtocol)?
        let versionedProfiles: (any VersionedProfilesSwift)?
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
            svrKeyDeriver: SVRKeyDeriver? = nil,
            syncManager: (any SyncManagerProtocol)? = nil,
            systemStoryManager: (any SystemStoryManagerProtocol)? = nil,
            versionedProfiles: (any VersionedProfilesSwift)? = nil,
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
            self.svrKeyDeriver = svrKeyDeriver
            self.syncManager = syncManager
            self.systemStoryManager = systemStoryManager
            self.versionedProfiles = versionedProfiles
            self.webSocketFactory = webSocketFactory
        }
    }

    public func start(
        appContext: AppContext,
        appReadiness: AppReadiness,
        databaseStorage: SDSDatabaseStorage,
        paymentsEvents: PaymentsEvents,
        mobileCoinHelper: MobileCoinHelper,
        callMessageHandler: CallMessageHandler,
        currentCallProvider: any CurrentCallProvider,
        notificationPresenter: any NotificationPresenter,
        incrementalMessageTSAttachmentMigratorFactory: IncrementalMessageTSAttachmentMigratorFactory,
        messageBackupErrorPresenterFactory: MessageBackupErrorPresenterFactory,
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

        let libsignalNet = Net(
            env: TSConstants.isUsingProductionService ? .production : .staging,
            userAgent: OWSHttpHeaders.userAgentHeaderValueSignalIos
        )

        let recipientDatabaseTable = RecipientDatabaseTableImpl()
        let recipientFetcher = RecipientFetcherImpl(recipientDatabaseTable: recipientDatabaseTable)
        let recipientIdFinder = RecipientIdFinder(recipientDatabaseTable: recipientDatabaseTable, recipientFetcher: recipientFetcher)

        let dateProvider = testDependencies.dateProvider ?? Date.provider
        let schedulers = DispatchQueueSchedulers()

        let appExpiry = AppExpiryImpl(
            dateProvider: dateProvider,
            appVersion: appVersion,
            schedulers: schedulers
        )

        let db = SDSDB(databaseStorage: databaseStorage)

        let tsAccountManager = TSAccountManagerImpl(
            appReadiness: appReadiness,
            dateProvider: dateProvider,
            databaseChangeObserver: databaseStorage.databaseChangeObserver,
            db: db,
            schedulers: schedulers
        )

        let networkManager = testDependencies.networkManager ?? NetworkManager(libsignalNet: libsignalNet)
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
            remoteConfigProvider: remoteConfigManager
        )
        let blockedRecipientStore = BlockedRecipientStoreImpl()
        let blockingManager = BlockingManager(
            appReadiness: appReadiness,
            blockedRecipientStore: blockedRecipientStore
        )
        let earlyMessageManager = EarlyMessageManager(appReadiness: appReadiness)
        let messageProcessor = MessageProcessor(appReadiness: appReadiness)
        let messageSender = testDependencies.messageSender ?? MessageSender()
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
            remoteConfigProvider: remoteConfigManager
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

        let signalAccountStore = SignalAccountStoreImpl()
        let threadStore = ThreadStoreImpl()
        let lastVisibleInteractionStore = LastVisibleInteractionStore()
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
            dbForReadTx: { SDSDB.shimOnlyBridge($0).unwrapGrdbRead.database },
            dbForWriteTx: { SDSDB.shimOnlyBridge($0).unwrapGrdbWrite.database }
        )
        let usernameLookupManager = UsernameLookupManagerImpl(
            searchableNameIndexer: searchableNameIndexer,
            usernameLookupRecordStore: usernameLookupRecordStore
        )

        let nicknameManager = NicknameManagerImpl(
            nicknameRecordStore: nicknameRecordStore,
            searchableNameIndexer: searchableNameIndexer,
            storageServiceManager: storageServiceManager,
            schedulers: schedulers
        )
        let contactManager = testDependencies.contactManager ?? OWSContactsManager(
            appReadiness: appReadiness,
            nicknameManager: nicknameManager,
            recipientDatabaseTable: recipientDatabaseTable,
            usernameLookupManager: usernameLookupManager
        )

        let authCredentialStore = AuthCredentialStore()

        let callLinkPublicParams = try! GenericServerPublicParams(contents: [UInt8](tsConstants.callLinkPublicParams))
        let authCredentialManager = AuthCredentialManagerImpl(
            authCredentialStore: authCredentialStore,
            callLinkPublicParams: callLinkPublicParams,
            dateProvider: dateProvider,
            db: db
        )

        let groupsV2 = testDependencies.groupsV2 ?? GroupsV2Impl(
            appReadiness: appReadiness,
            authCredentialStore: authCredentialStore,
            authCredentialManager: authCredentialManager
        )

        let aciProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .aci)
        let pniProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .pni)

        let mediaBandwidthPreferenceStore = MediaBandwidthPreferenceStoreImpl(
            reachabilityManager: reachabilityManager,
            schedulers: schedulers
        )

        let interactionStore = InteractionStoreImpl()
        let storyStore = StoryStoreImpl()

        let audioWaveformManager = AudioWaveformManagerImpl()
        let orphanedAttachmentCleaner = OrphanedAttachmentCleanerImpl(db: databaseStorage)
        let attachmentContentValidator = AttachmentContentValidatorImpl(
            audioWaveformManager: audioWaveformManager,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner
        )

        let svrCredentialStorage = SVRAuthCredentialStorageImpl()
        let svrLocalStorage = SVRLocalStorageImpl()
        let svrKeyDeriver = testDependencies.svrKeyDeriver ?? SVRKeyDeriverImpl(
            localStorage: svrLocalStorage
        )

        let accountAttributesUpdater = AccountAttributesUpdaterImpl(
            accountAttributesGenerator: AccountAttributesGenerator(
                ows2FAManager: ows2FAManager,
                profileManager: profileManager,
                svrKeyDeriver: svrKeyDeriver,
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
            schedulers: schedulers,
            svrLocalStorage: svrLocalStorage,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager
        )

        let phoneNumberDiscoverabilityManager = PhoneNumberDiscoverabilityManagerImpl(
            accountAttributesUpdater: accountAttributesUpdater,
            schedulers: schedulers,
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
            schedulers: schedulers,
            storageServiceManager: storageServiceManager,
            svrKeyDeriver: svrKeyDeriver,
            svrLocalStorage: svrLocalStorage,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
            tsConstants: tsConstants,
            twoFAManager: SVR2.Wrappers.OWS2FAManager(ows2FAManager)
        )

        let mrbkStore = MediaRootBackupKeyStore()
        let messageBackupKeyMaterial = MessageBackupKeyMaterialImpl(
            mrbkStore: mrbkStore,
            svrKeyDeriver: svrKeyDeriver
        )
        let messageBackupRequestManager = MessageBackupRequestManagerImpl(
            dateProvider: dateProvider,
            db: db,
            messageBackupAuthCredentialManager: MessageBackupAuthCredentialManagerImpl(
                authCredentialStore: authCredentialStore,
                dateProvider: dateProvider,
                db: db,
                messageBackupKeyMaterial: messageBackupKeyMaterial,
                networkManager: networkManager
            ),
            messageBackupKeyMaterial: messageBackupKeyMaterial,
            networkManager: networkManager
        )

        let attachmentStore = AttachmentStoreImpl()
        let orphanedAttachmentStore = OrphanedAttachmentStoreImpl()
        let attachmentUploadStore = AttachmentUploadStoreImpl(attachmentStore: attachmentStore)
        let attachmentDownloadStore = AttachmentDownloadStoreImpl(dateProvider: dateProvider)

        let orphanedBackupAttachmentStore = OrphanedBackupAttachmentStoreImpl()
        let orphanedBackupAttachmentManager = OrphanedBackupAttachmentManagerImpl(
            appReadiness: appReadiness,
            attachmentStore: attachmentStore,
            dateProvider: dateProvider,
            db: db,
            messageBackupKeyMaterial: messageBackupKeyMaterial,
            messageBackupRequestManager: messageBackupRequestManager,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            tsAccountManager: tsAccountManager
        )

        let attachmentDownloadManager = AttachmentDownloadManagerImpl(
            appReadiness: appReadiness,
            attachmentDownloadStore: attachmentDownloadStore,
            attachmentStore: attachmentStore,
            attachmentValidator: attachmentContentValidator,
            currentCallProvider: currentCallProvider,
            dateProvider: dateProvider,
            db: db,
            interactionStore: interactionStore,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            messageBackupKeyMaterial: messageBackupKeyMaterial,
            messageBackupRequestManager: messageBackupRequestManager,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
            profileManager: AttachmentDownloadManagerImpl.Wrappers.ProfileManager(profileManager),
            signalService: signalService,
            stickerManager: AttachmentDownloadManagerImpl.Wrappers.StickerManager(),
            storyStore: storyStore,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager
        )
        let attachmentManager = AttachmentManagerImpl(
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentStore: attachmentStore,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
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

        let attachmentThumbnailService = AttachmentThumbnailServiceImpl()

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
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            registrationIdGenerator: RegistrationIdGenerator(),
            schedulers: schedulers
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
            recipientFetcher: recipientFetcher,
            recipientIdFinder: recipientIdFinder,
            schedulers: schedulers,
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
            schedulers: schedulers,
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
            notificationScheduler: schedulers.main,
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
            schedulers: schedulers
        )
        let callRecordStore = CallRecordStoreImpl(
            deletedCallRecordStore: deletedCallRecordStore,
            schedulers: schedulers
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
                recipientMergeNotifier: RecipientMergeNotifier(scheduler: schedulers.main),
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
            storageServiceManager: storageServiceManager
        )

        let registrationStateChangeManager = RegistrationStateChangeManagerImpl(
            appContext: appContext,
            authCredentialStore: authCredentialStore,
            groupsV2: groupsV2,
            identityManager: identityManager,
            notificationPresenter: notificationPresenter,
            paymentsEvents: RegistrationStateChangeManagerImpl.Wrappers.PaymentsEvents(paymentsEvents),
            recipientManager: recipientManager,
            recipientMerger: recipientMerger,
            schedulers: schedulers,
            senderKeyStore: RegistrationStateChangeManagerImpl.Wrappers.SenderKeyStore(senderKeyStore),
            signalProtocolStoreManager: signalProtocolStoreManager,
            signalService: signalService,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
            udManager: udManager,
            versionedProfiles: versionedProfiles
        )

        let pniIdentityKeyChecker = PniIdentityKeyCheckerImpl(
            db: db,
            identityManager: PniIdentityKeyCheckerImpl.Wrappers.IdentityManager(identityManager),
            profileFetcher: PniIdentityKeyCheckerImpl.Wrappers.ProfileFetcher(schedulers: schedulers),
            schedulers: schedulers
        )
        let linkedDevicePniKeyManager = LinkedDevicePniKeyManagerImpl(
            db: db,
            messageProcessor: LinkedDevicePniKeyManagerImpl.Wrappers.MessageProcessor(messageProcessor),
            pniIdentityKeyChecker: pniIdentityKeyChecker,
            registrationStateChangeManager: registrationStateChangeManager,
            schedulers: schedulers,
            tsAccountManager: tsAccountManager
        )
        let pniHelloWorldManager = PniHelloWorldManagerImpl(
            database: db,
            identityManager: identityManager,
            networkManager: PniHelloWorldManagerImpl.Wrappers.NetworkManager(networkManager),
            pniDistributionParameterBuilder: pniDistributionParameterBuilder,
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            recipientDatabaseTable: recipientDatabaseTable,
            schedulers: schedulers,
            tsAccountManager: tsAccountManager
        )

        let chatConnectionManager = ChatConnectionManagerImpl(
            accountManager: tsAccountManager,
            appExpiry: appExpiry,
            appReadiness: appReadiness,
            currentCallProvider: currentCallProvider,
            db: db,
            libsignalNet: libsignalNet,
            registrationStateChangeManager: registrationStateChangeManager,
            userDefaults: appContext.appUserDefaults()
        )

        let preKeyTaskAPIClient = PreKeyTaskAPIClientImpl(networkManager: networkManager)
        let preKeyManager = PreKeyManagerImpl(
            dateProvider: dateProvider,
            db: db,
            identityManager: PreKey.Wrappers.IdentityManager(identityManager),
            linkedDevicePniKeyManager: linkedDevicePniKeyManager,
            messageProcessor: PreKey.Wrappers.MessageProcessor(messageProcessor: messageProcessor),
            preKeyTaskAPIClient: preKeyTaskAPIClient,
            protocolStoreManager: signalProtocolStoreManager,
            chatConnectionManager: chatConnectionManager,
            tsAccountManager: tsAccountManager
        )

        let learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            db: db,
            registrationStateChangeManager: registrationStateChangeManager,
            tsAccountManager: tsAccountManager,
            whoAmIManager: whoAmIManager
        )

        let registrationSessionManager = RegistrationSessionManagerImpl(
            dateProvider: dateProvider,
            db: db,
            schedulers: schedulers,
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
            schedulers: schedulers
        )
        let usernameEducationManager = UsernameEducationManagerImpl()
        let usernameLinkManager = UsernameLinkManagerImpl(
            db: db,
            apiClient: usernameApiClient,
            schedulers: schedulers
        )
        let localUsernameManager = LocalUsernameManagerImpl(
            db: db,
            reachabilityManager: reachabilityManager,
            schedulers: schedulers,
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

        let attachmentUploadManager = AttachmentUploadManagerImpl(
            attachmentEncrypter: Upload.Wrappers.AttachmentEncrypter(),
            attachmentStore: attachmentStore,
            attachmentUploadStore: attachmentUploadStore,
            attachmentThumbnailService: attachmentThumbnailService,
            chatConnectionManager: chatConnectionManager,
            dateProvider: dateProvider,
            db: db,
            fileSystem: Upload.Wrappers.FileSystem(),
            interactionStore: interactionStore,
            messageBackupKeyMaterial: messageBackupKeyMaterial,
            messageBackupRequestManager: messageBackupRequestManager,
            networkManager: networkManager,
            remoteConfigProvider: remoteConfigManager,
            signalService: signalService,
            storyStore: storyStore
        )

        let privateStoryThreadDeletionManager = PrivateStoryThreadDeletionManagerImpl(
            dateProvider: dateProvider,
            remoteConfigProvider: remoteConfigManager,
            storageServiceManager: storageServiceManager,
            threadRemover: threadRemover,
            threadStore: threadStore
        )

        let backupAttachmentDownloadStore = BackupAttachmentDownloadStoreImpl()
        let backupAttachmentDownloadManager = testDependencies.backupAttachmentDownloadManager
            ?? BackupAttachmentDownloadManagerImpl(
                appReadiness: appReadiness,
                attachmentStore: attachmentStore,
                attachmentDownloadManager: attachmentDownloadManager,
                attachmentUploadStore: attachmentUploadStore,
                backupAttachmentDownloadStore: backupAttachmentDownloadStore,
                dateProvider: dateProvider,
                db: db,
                mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
                messageBackupKeyMaterial: messageBackupKeyMaterial,
                messageBackupRequestManager: messageBackupRequestManager,
                orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
                reachabilityManager: reachabilityManager,
                remoteConfigProvider: remoteConfigManager,
                svr: svr,
                tsAccountManager: tsAccountManager
            )
        let backupAttachmentUploadStore = BackupAttachmentUploadStoreImpl()
        let backupAttachmentUploadManager = BackupAttachmentUploadManagerImpl(
            attachmentStore: attachmentStore,
            attachmentUploadManager: attachmentUploadManager,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            dateProvider: dateProvider,
            db: db,
            messageBackupRequestManager: messageBackupRequestManager,
            tsAccountManager: tsAccountManager
        )

        let backupReceiptCredentialRedemptionJobQueue = BackupReceiptCredentialRedemptionJobQueue(
            db: db,
            networkManager: networkManager,
            reachabilityManager: reachabilityManager
        )
        let backupSubscriptionManager = BackupSubscriptionManagerImpl(
            dateProvider: dateProvider,
            db: db,
            networkManager: networkManager,
            receiptCredentialRedemptionJobQueue: backupReceiptCredentialRedemptionJobQueue,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager
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

        let messageBackupChatStyleArchiver = MessageBackupChatStyleArchiver(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            backupAttachmentDownloadManager: backupAttachmentDownloadManager,
            chatColorSettingStore: chatColorSettingStore,
            dateProvider: dateProvider,
            wallpaperStore: wallpaperStore
        )

        let backupStickerPackDownloadStore = BackupStickerPackDownloadStoreImpl()
        let backupThreadStore = MessageBackupThreadStore(threadStore: threadStore)
        let backupInteractionStore = MessageBackupInteractionStore(interactionStore: interactionStore)
        let backupStoryStore = MessageBackupStoryStore(storyStore: storyStore)

        let messageBackupErrorPresenter = messageBackupErrorPresenterFactory.build(
            db: db,
            tsAccountManager: tsAccountManager
        )
        let messageBackupAvatarFetcher = MessageBackupAvatarFetcher(
            appReadiness: appReadiness,
            dateProvider: dateProvider,
            db: db,
            groupsV2: groupsV2,
            profileFetcher: profileFetcher,
            reachabilityManager: reachabilityManager,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager
        )
        let messageBackupContactRecipientArchiver = MessageBackupContactRecipientArchiver(
            avatarFetcher: messageBackupAvatarFetcher,
            blockingManager: MessageBackup.Wrappers.BlockingManager(blockingManager),
            dateProvider: dateProvider,
            profileManager: MessageBackup.Wrappers.ProfileManager(profileManager),
            recipientHidingManager: recipientHidingManager,
            recipientManager: recipientManager,
            recipientStore: MessageBackupRecipientStore(
                recipientTable: recipientDatabaseTable,
                searchableNameIndexer: searchableNameIndexer
            ),
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

        let messageBackupManager = MessageBackupManagerImpl(
            accountDataArchiver: MessageBackupAccountDataArchiverImpl(
                chatStyleArchiver: messageBackupChatStyleArchiver,
                disappearingMessageConfigurationStore: disappearingMessagesConfigurationStore,
                donationSubscriptionManager: MessageBackup.AccountData.Wrappers.DonationSubscriptionManager(),
                linkPreviewSettingStore: linkPreviewSettingStore,
                localUsernameManager: localUsernameManager,
                phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManager,
                preferences: MessageBackup.AccountData.Wrappers.Preferences(preferences: preferences),
                profileManager: MessageBackup.Wrappers.ProfileManager(profileManager),
                receiptManager: MessageBackup.AccountData.Wrappers.ReceiptManager(receiptManager: receiptManager),
                reactionManager: MessageBackup.AccountData.Wrappers.ReactionManager(),
                sskPreferences: MessageBackup.AccountData.Wrappers.SSKPreferences(),
                storyManager: MessageBackup.AccountData.Wrappers.StoryManager(),
                systemStoryManager: MessageBackup.AccountData.Wrappers.SystemStoryManager(systemStoryManager: systemStoryManager),
                typingIndicators: MessageBackup.AccountData.Wrappers.TypingIndicators(typingIndicators: typingIndicators),
                udManager: MessageBackup.AccountData.Wrappers.UDManager(udManager: udManager),
                usernameEducationManager: usernameEducationManager
            ),
            appVersion: appVersion,
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentUploadManager: attachmentUploadManager,
            backupAttachmentDownloadManager: backupAttachmentDownloadManager,
            backupAttachmentUploadManager: backupAttachmentUploadManager,
            backupRequestManager: messageBackupRequestManager,
            backupStickerPackDownloadStore: backupStickerPackDownloadStore,
            callLinkRecipientArchiver: MessageBackupCallLinkRecipientArchiver(
                callLinkStore: callLinkStore
            ),
            chatArchiver: MessageBackupChatArchiverImpl(
                chatStyleArchiver: messageBackupChatStyleArchiver,
                contactRecipientArchiver: messageBackupContactRecipientArchiver,
                dmConfigurationStore: disappearingMessagesConfigurationStore,
                pinnedThreadStore: pinnedThreadStore,
                threadStore: backupThreadStore
            ),
            chatItemArchiver: MessageBackupChatItemArchiverImpl(
                attachmentManager: attachmentManager,
                attachmentStore: attachmentStore,
                backupAttachmentDownloadManager: backupAttachmentDownloadManager,
                callRecordStore: callRecordStore,
                contactManager: MessageBackup.Wrappers.ContactManager(contactManager),
                dateProvider: dateProvider,
                editMessageStore: editMessageStore,
                groupCallRecordManager: groupCallRecordManager,
                groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelperImpl(),
                groupUpdateItemBuilder: groupUpdateItemBuilder,
                individualCallRecordManager: individualCallRecordManager,
                interactionStore: backupInteractionStore,
                archivedPaymentStore: archivedPaymentStore,
                reactionStore: reactionStore,
                threadStore: backupThreadStore
            ),
            contactRecipientArchiver: messageBackupContactRecipientArchiver,
            databaseChangeObserver: databaseStorage.databaseChangeObserver,
            dateProvider: dateProvider,
            db: db,
            disappearingMessagesJob: disappearingMessagesJob,
            distributionListRecipientArchiver: MessageBackupDistributionListRecipientArchiver(
                privateStoryThreadDeletionManager: privateStoryThreadDeletionManager,
                storyStore: backupStoryStore,
                threadStore: backupThreadStore
            ),
            encryptedStreamProvider: MessageBackupEncryptedProtoStreamProviderImpl(
                backupKeyMaterial: messageBackupKeyMaterial
            ),
            errorPresenter: messageBackupErrorPresenter,
            fullTextSearchIndexer: MessageBackupFullTextSearchIndexerImpl(
                appReadiness: appReadiness,
                dateProvider: dateProvider,
                db: db,
                fullTextSearchIndexer: MessageBackupFullTextSearchIndexerImpl.Wrappers.FullTextSearchIndexer(),
                interactionStore: interactionStore,
                searchableNameIndexer: searchableNameIndexer
            ),
            groupRecipientArchiver: MessageBackupGroupRecipientArchiver(
                avatarFetcher: messageBackupAvatarFetcher,
                disappearingMessageConfigStore: disappearingMessagesConfigurationStore,
                groupsV2: groupsV2,
                profileManager: MessageBackup.Wrappers.ProfileManager(profileManager),
                storyStore: backupStoryStore,
                threadStore: backupThreadStore
            ),
            incrementalTSAttachmentMigrator: incrementalMessageTSAttachmentMigrator,
            localRecipientArchiver: MessageBackupLocalRecipientArchiver(
                profileManager: MessageBackup.Wrappers.ProfileManager(profileManager)
            ),
            messageBackupKeyMaterial: messageBackupKeyMaterial,
            messagePipelineSupervisor: messagePipelineSupervisor,
            mrbkStore: mrbkStore,
            plaintextStreamProvider: MessageBackupPlaintextProtoStreamProviderImpl(),
            postFrameRestoreActionManager: MessageBackupPostFrameRestoreActionManager(
                avatarFetcher: messageBackupAvatarFetcher,
                dateProvider: dateProvider,
                interactionStore: backupInteractionStore,
                lastVisibleInteractionStore: lastVisibleInteractionStore,
                recipientDatabaseTable: recipientDatabaseTable,
                sskPreferences: MessageBackupPostFrameRestoreActionManager.Wrappers.SSKPreferences(),
                threadStore: backupThreadStore
            ),
            releaseNotesRecipientArchiver: MessageBackupReleaseNotesRecipientArchiver(),
            stickerPackArchiver: MessageBackupStickerPackArchiverImpl(
                backupStickerPackDownloadStore: backupStickerPackDownloadStore
            ),
            adHocCallArchiver: MessageBackupAdHocCallArchiverImpl(
                callRecordStore: callRecordStore,
                callLinkRecordStore: callLinkStore,
                adHocCallRecordManager: adHocCallRecordManager
            )
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
            threadStore: threadStore
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
            db: db,
            messageBackupManager: messageBackupManager,
            messagePipelineSupervisor: messagePipelineSupervisor,
            networkManager: networkManager,
            tsAccountManager: tsAccountManager
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
            backupAttachmentDownloadManager: backupAttachmentDownloadManager,
            backupAttachmentUploadManager: backupAttachmentUploadManager,
            backupSubscriptionManager: backupSubscriptionManager,
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
            deviceStore: deviceStore,
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            donationReceiptCredentialResultStore: donationReceiptCredentialResultStore,
            editManager: editManager,
            editMessageStore: editMessageStore,
            externalPendingIDEALDonationStore: externalPendingIDEALDonationStore,
            groupCallRecordManager: groupCallRecordManager,
            groupMemberStore: groupMemberStore,
            groupMemberUpdater: groupMemberUpdater,
            groupUpdateInfoMessageInserter: groupUpdateInfoMessageInserter,
            identityManager: identityManager,
            inactiveLinkedDeviceFinder: inactiveLinkedDeviceFinder,
            incomingCallEventSyncMessageManager: incomingCallEventSyncMessageManager,
            incomingCallLogEventSyncMessageManager: incomingCallLogEventSyncMessageManager,
            incomingPniChangeNumberProcessor: incomingPniChangeNumberProcessor,
            incrementalMessageTSAttachmentMigrator: incrementalMessageTSAttachmentMigrator,
            individualCallRecordManager: individualCallRecordManager,
            interactionDeleteManager: interactionDeleteManager,
            interactionStore: interactionStore,
            lastVisibleInteractionStore: lastVisibleInteractionStore,
            learnMyOwnPniManager: learnMyOwnPniManager,
            linkedDevicePniKeyManager: linkedDevicePniKeyManager,
            linkAndSyncManager: linkAndSyncManager,
            linkPreviewManager: linkPreviewManager,
            linkPreviewSettingStore: linkPreviewSettingStore,
            linkPreviewSettingManager: linkPreviewSettingManager,
            localProfileChecker: localProfileChecker,
            localUsernameManager: localUsernameManager,
            masterKeySyncManager: masterKeySyncManager,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            messageBackupErrorPresenter: messageBackupErrorPresenter,
            messageBackupKeyMaterial: messageBackupKeyMaterial,
            messageBackupManager: messageBackupManager,
            messageStickerManager: messageStickerManager,
            mrbkStore: mrbkStore,
            nicknameManager: nicknameManager,
            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            archivedPaymentStore: archivedPaymentStore,
            phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManager,
            phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
            pinnedThreadManager: pinnedThreadManager,
            pinnedThreadStore: pinnedThreadStore,
            pniHelloWorldManager: pniHelloWorldManager,
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
            schedulers: schedulers,
            searchableNameIndexer: searchableNameIndexer,
            sentMessageTranscriptReceiver: sentMessageTranscriptReceiver,
            signalProtocolStoreManager: signalProtocolStoreManager,
            storageServiceRecordIkmCapabilityStore: storageServiceRecordIkmCapabilityStore,
            svr: svr,
            svrCredentialStorage: svrCredentialStorage,
            svrKeyDeriver: svrKeyDeriver,
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
        DependenciesBridge.setShared(dependenciesBridge)

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
        let groupsV2MessageProcessor = GroupsV2MessageProcessor(appReadiness: appReadiness)
        let receiptSender = ReceiptSender(
            appReadiness: appReadiness,
            recipientDatabaseTable: recipientDatabaseTable
        )
        let stickerManager = StickerManager(
            appReadiness: appReadiness,
            dateProvider: dateProvider
        )
        let sskPreferences = SSKPreferences()
        let groupV2Updates = testDependencies.groupV2Updates ?? GroupV2UpdatesImpl(appReadiness: appReadiness)
        let messageFetcherJob = MessageFetcherJob(appReadiness: appReadiness)
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
            db: db,
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
            groupsV2MessageProcessor: groupsV2MessageProcessor,
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
            incrementalTSAttachmentMigrator: incrementalMessageTSAttachmentMigrator,
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
        private let incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator
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
            incrementalTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator,
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
            self.incrementalTSAttachmentMigrator = incrementalTSAttachmentMigrator
            self.remoteConfigManager = remoteConfigManager
        }
    }
}

extension AppSetup.DatabaseContinuation {
    public func prepareDatabase(
        backgroundScheduler: Scheduler = DispatchQueue.global(),
        mainScheduler: Scheduler = DispatchQueue.main
    ) -> Guarantee<AppSetup.FinalContinuation> {
        let databaseStorage = sskEnvironment.databaseStorageRef

        let (guarantee, future) = Guarantee<AppSetup.FinalContinuation>.pending()
        backgroundScheduler.async {
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
            databaseStorage.runGrdbSchemaMigrationsOnMainDatabase(completionScheduler: mainScheduler) {
                do {
                    try databaseStorage.grdbStorage.setupDatabaseChangeObserver()
                } catch {
                    owsFail("Couldn't set up change observer: \(error.grdbErrorForLogging)")
                }
                self.sskEnvironment.warmCaches(appReadiness: self.appReadiness)

                let finish = {
                    self.backgroundTask.end()
                    future.resolve(AppSetup.FinalContinuation(
                        appReadiness: self.appReadiness,
                        authCredentialStore: self.authCredentialStore,
                        dependenciesBridge: self.dependenciesBridge,
                        sskEnvironment: self.sskEnvironment
                    ))
                }

                if FeatureFlags.runTSAttachmentMigrationBlockingOnLaunch {
                    Task {
                        await self.incrementalTSAttachmentMigrator.runUntilFinished(ignorePastFailures: false)
                        await MainActor.run {
                            finish()
                        }
                    }
                } else {
                    finish()
                }

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
        private let appReadiness: AppReadiness
        private let authCredentialStore: AuthCredentialStore
        private let dependenciesBridge: DependenciesBridge
        private let sskEnvironment: SSKEnvironment

        fileprivate init(
            appReadiness: AppReadiness,
            authCredentialStore: AuthCredentialStore,
            dependenciesBridge: DependenciesBridge,
            sskEnvironment: SSKEnvironment
        ) {
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

    public func finish(willResumeInProgressRegistration: Bool) -> SetupError? {
        AssertIsOnMainThread()

        ZkParamsMigrator(
            appReadiness: appReadiness,
            authCredentialStore: authCredentialStore,
            db: dependenciesBridge.db,
            profileManager: sskEnvironment.profileManagerRef,
            tsAccountManager: dependenciesBridge.tsAccountManager,
            versionedProfiles: sskEnvironment.versionedProfilesRef
        ).migrateIfNeeded()

        guard setUpLocalIdentifiers(willResumeInProgressRegistration: willResumeInProgressRegistration) else {
            return .corruptRegistrationState
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync { [dependenciesBridge] in
            let preKeyManager = dependenciesBridge.preKeyManager
            Task {
                // Rotate ACI keys first since PNI keys may block on incoming messages.
                // TODO: Don't block ACI operations if PNI operations are blocked.
                await preKeyManager.rotatePreKeysOnUpgradeIfNecessary(for: .aci)
                await preKeyManager.rotatePreKeysOnUpgradeIfNecessary(for: .pni)
            }
        }

        return nil
    }

    private func setUpLocalIdentifiers(willResumeInProgressRegistration: Bool) -> Bool {
        let databaseStorage = sskEnvironment.databaseStorageRef
        let storageServiceManager = sskEnvironment.storageServiceManagerRef
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        if
            tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
            && !willResumeInProgressRegistration
        {
            let localIdentifiers = databaseStorage.read { tsAccountManager.localIdentifiers(tx: $0.asV2Read) }
            guard let localIdentifiers else {
                return false
            }
            storageServiceManager.setLocalIdentifiers(localIdentifiers)
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
