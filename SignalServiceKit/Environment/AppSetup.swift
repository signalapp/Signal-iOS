//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

public class AppSetup {
    public init() {}

    public struct TestDependencies {
        let accountServiceClient: AccountServiceClient
        let contactManager: any ContactManager
        let groupV2Updates: any GroupV2Updates
        let groupsV2: any GroupsV2
        let keyValueStoreFactory: any KeyValueStoreFactory
        let messageSender: MessageSender
        let modelReadCaches: ModelReadCaches
        let networkManager: NetworkManager
        let paymentsCurrencies: any PaymentsCurrenciesSwift
        let paymentsHelper: any PaymentsHelperSwift
        let pendingReceiptRecorder: any PendingReceiptRecorder
        let profileManager: any ProfileManager
        let reachabilityManager: any SSKReachabilityManager
        let remoteConfigManager: any RemoteConfigManager
        let signalService: any OWSSignalServiceProtocol
        let storageServiceManager: any StorageServiceManager
        let subscriptionManager: any SubscriptionManager
        let syncManager: any SyncManagerProtocol
        let systemStoryManager: any SystemStoryManagerProtocol
        let versionedProfiles: any VersionedProfilesSwift
        let webSocketFactory: any WebSocketFactory
    }

    public func start(
        appContext: AppContext,
        databaseStorage: SDSDatabaseStorage,
        paymentsEvents: PaymentsEvents,
        mobileCoinHelper: MobileCoinHelper,
        callMessageHandler: CallMessageHandler,
        lightweightGroupCallManagerBuilder: (GroupCallPeekClient) -> LightweightGroupCallManager,
        notificationPresenter: NotificationsProtocol,
        testDependencies: TestDependencies? = nil
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

        let appVersion = AppVersionImpl.shared
        let webSocketFactory = testDependencies?.webSocketFactory ?? WebSocketFactoryNative()

        // AFNetworking (via CFNetworking) spools its attachments in
        // NSTemporaryDirectory(). If you receive a media message while the device
        // is locked, the download will fail if the temporary directory is
        // NSFileProtectionComplete.
        let temporaryDirectory = NSTemporaryDirectory()
        owsAssert(OWSFileSystem.ensureDirectoryExists(temporaryDirectory))
        owsAssert(OWSFileSystem.protectFileOrFolder(atPath: temporaryDirectory, fileProtectionType: .completeUntilFirstUserAuthentication))

        let tsConstants = TSConstants.shared
        let keyValueStoreFactory = testDependencies?.keyValueStoreFactory ?? SDSKeyValueStoreFactory()

        let recipientDatabaseTable = RecipientDatabaseTableImpl()
        let recipientFetcher = RecipientFetcherImpl(recipientDatabaseTable: recipientDatabaseTable)
        let recipientIdFinder = RecipientIdFinder(recipientDatabaseTable: recipientDatabaseTable, recipientFetcher: recipientFetcher)

        let accountServiceClient = testDependencies?.accountServiceClient ?? AccountServiceClient()
        let aciSignalProtocolStore = SignalProtocolStoreImpl(
            for: .aci,
            keyValueStoreFactory: keyValueStoreFactory,
            recipientIdFinder: recipientIdFinder
        )
        let blockingManager = BlockingManager()
        let dateProvider = Date.provider
        let earlyMessageManager = EarlyMessageManager()
        let messageProcessor = MessageProcessor()
        let messageSender = testDependencies?.messageSender ?? MessageSender()
        let messageSenderJobQueue = MessageSenderJobQueue()
        let modelReadCaches = testDependencies?.modelReadCaches ?? ModelReadCaches(factory: ModelReadCacheFactory())
        let networkManager = testDependencies?.networkManager ?? NetworkManager()
        let ows2FAManager = OWS2FAManager()
        let paymentsHelper = testDependencies?.paymentsHelper ?? PaymentsHelperImpl()
        let pniSignalProtocolStore = SignalProtocolStoreImpl(
            for: .pni,
            keyValueStoreFactory: keyValueStoreFactory,
            recipientIdFinder: recipientIdFinder
        )
        let profileManager = testDependencies?.profileManager ?? OWSProfileManager(
            databaseStorage: databaseStorage,
            swiftValues: OWSProfileManagerSwiftValues()
        )
        let reachabilityManager = testDependencies?.reachabilityManager ?? SSKReachabilityManagerImpl()
        let receiptManager = OWSReceiptManager()
        let senderKeyStore = SenderKeyStore()
        let signalProtocolStoreManager = SignalProtocolStoreManagerImpl(
            aciProtocolStore: aciSignalProtocolStore,
            pniProtocolStore: pniSignalProtocolStore
        )
        let signalService = testDependencies?.signalService ?? OWSSignalService()
        let signalServiceAddressCache = SignalServiceAddressCache()
        let storageServiceManager = testDependencies?.storageServiceManager ?? StorageServiceManagerImpl.shared
        let syncManager = testDependencies?.syncManager ?? OWSSyncManager(default: ())
        let udManager = OWSUDManagerImpl()
        let versionedProfiles = testDependencies?.versionedProfiles ?? VersionedProfilesImpl()

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
            dbForReadTx: { SDSDB.shimOnlyBridge($0).unwrapGrdbRead.database },
            dbForWriteTx: { SDSDB.shimOnlyBridge($0).unwrapGrdbWrite.database }
        )
        let usernameLookupManager = UsernameLookupManagerImpl(
            searchableNameIndexer: searchableNameIndexer,
            usernameLookupRecordStore: usernameLookupRecordStore
        )

        let schedulers = DispatchQueueSchedulers()
        let nicknameManager = NicknameManagerImpl(
            nicknameRecordStore: nicknameRecordStore,
            searchableNameIndexer: searchableNameIndexer,
            storageServiceManager: storageServiceManager,
            schedulers: schedulers
        )
        let contactManager = testDependencies?.contactManager ?? OWSContactsManager(swiftValues: OWSContactsManagerSwiftValues(
            usernameLookupManager: usernameLookupManager,
            recipientDatabaseTable: recipientDatabaseTable,
            nicknameManager: nicknameManager
        ))

        let db = SDSDB(databaseStorage: databaseStorage)

        let authCredentialStore = AuthCredentialStore(keyValueStoreFactory: keyValueStoreFactory)

        let authCredentialManager = AuthCredentialManagerImpl(
            authCredentialStore: authCredentialStore,
            callLinkPublicParams: tsConstants.callLinkPublicParams,
            dateProvider: dateProvider,
            db: db
        )

        let groupsV2 = testDependencies?.groupsV2 ?? GroupsV2Impl(
            authCredentialStore: authCredentialStore,
            authCredentialManager: authCredentialManager
        )

        let aciProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .aci)
        let pniProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .pni)

        let attachmentStore = AttachmentStoreImpl()
        let attachmentManager = AttachmentManagerImpl(attachmentStore: attachmentStore)

        let mediaBandwidthPreferenceStore = MediaBandwidthPreferenceStoreImpl(
            keyValueStoreFactory: keyValueStoreFactory,
            reachabilityManager: reachabilityManager,
            schedulers: schedulers
        )

        let tsResourceStore = TSResourceStoreImpl(attachmentStore: attachmentStore)
        let tsResourceManager = TSResourceManagerImpl(
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            tsResourceStore: tsResourceStore
        )
        let attachmentDownloadManager = AttachmentDownloadManagerImpl(
            schedulers: schedulers,
            signalService: signalService
        )
        let tsResourceDownloadManager = TSResourceDownloadManagerImpl(
            attachmentDownloadManager: attachmentDownloadManager,
            tsResourceStore: tsResourceStore
        )

        let tsAccountManager = TSAccountManagerImpl(
            appReadiness: TSAccountManagerImpl.Wrappers.AppReadiness(),
            dateProvider: dateProvider,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: schedulers
        )

        let quotedReplyManager = QuotedReplyManagerImpl(
            attachmentManager: tsResourceManager,
            attachmentStore: tsResourceStore,
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

        let appExpiry = AppExpiryImpl(
            keyValueStoreFactory: keyValueStoreFactory,
            dateProvider: dateProvider,
            appVersion: appVersion,
            schedulers: schedulers
        )

        let badgeCountFetcher = BadgeCountFetcherImpl()

        let identityManager = OWSIdentityManagerImpl(
            aciProtocolStore: aciProtocolStore,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            messageSenderJobQueue: messageSenderJobQueue,
            networkManager: networkManager,
            notificationsManager: notificationPresenter,
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

        let deviceManager = OWSDeviceManagerImpl(
            databaseStorage: db,
            keyValueStoreFactory: keyValueStoreFactory
        )

        let linkPreviewManager = LinkPreviewManagerImpl(
            attachmentManager: tsResourceManager,
            attachmentStore: tsResourceStore,
            db: db,
            groupsV2: LinkPreviewManagerImpl.Wrappers.GroupsV2(groupsV2),
            sskPreferences: LinkPreviewManagerImpl.Wrappers.SSKPreferences()
        )

        let editMessageStore = EditMessageStoreImpl()
        let editManager = EditManagerImpl(
            context: .init(
                dataStore: EditManagerImpl.Wrappers.DataStore(),
                editManagerAttachments: EditManagerTSResourcesImpl(
                    editManagerAttachments: EditManagerAttachmentsImpl(
                        attachmentManager: attachmentManager,
                        attachmentStore: attachmentStore,
                        linkPreviewManager: linkPreviewManager,
                        tsMessageStore: EditManagerAttachmentsImpl.Wrappers.TSMessageStore(),
                        tsResourceManager: tsResourceManager,
                        tsResourceStore: tsResourceStore
                    ),
                    linkPreviewManager: linkPreviewManager,
                    tsMessageStore: EditManagerAttachmentsImpl.Wrappers.TSMessageStore()
                ),
                editMessageStore: editMessageStore,
                groupsShim: EditManagerImpl.Wrappers.Groups(groupsV2: groupsV2),
                keyValueStoreFactory: keyValueStoreFactory,
                receiptManagerShim: EditManagerImpl.Wrappers.ReceiptManager(receiptManager: receiptManager),
                tsResourceStore: tsResourceStore
            )
        )

        let groupUpdateItemBuilder = GroupUpdateItemBuilderImpl(
            contactsManager: GroupUpdateItemBuilderImpl.Wrappers.ContactsManager(contactManager),
            recipientDatabaseTable: recipientDatabaseTable
        )

        let groupUpdateInfoMessageInserter = GroupUpdateInfoMessageInserterImpl(
            dateProvider: dateProvider,
            groupUpdateItemBuilder: groupUpdateItemBuilder,
            notificationsManager: notificationPresenter
        )

        let svrCredentialStorage = SVRAuthCredentialStorageImpl(keyValueStoreFactory: keyValueStoreFactory)
        let svrLocalStorage = SVRLocalStorageImpl(keyValueStoreFactory: keyValueStoreFactory)

        let accountAttributesUpdater = AccountAttributesUpdaterImpl(
            appReadiness: AccountAttributesUpdaterImpl.Wrappers.AppReadiness(),
            appVersion: appVersion,
            dateProvider: dateProvider,
            db: db,
            profileManager: profileManager,
            keyValueStoreFactory: keyValueStoreFactory,
            serviceClient: SignalServiceRestClient(),
            schedulers: schedulers,
            svrLocalStorage: svrLocalStorage,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager
        )

        let svr = SecureValueRecovery2Impl(
            accountAttributesUpdater: accountAttributesUpdater,
            appReadiness: SVR2.Wrappers.AppReadiness(),
            appVersion: appVersion,
            connectionFactory: SgxWebsocketConnectionFactoryImpl(websocketFactory: webSocketFactory),
            credentialStorage: svrCredentialStorage,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: schedulers,
            storageServiceManager: storageServiceManager,
            svrLocalStorage: svrLocalStorage,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager,
            tsConstants: tsConstants,
            twoFAManager: SVR2.Wrappers.OWS2FAManager(ows2FAManager)
        )

        let interactionStore = InteractionStoreImpl()

        let chatColorSettingStore = ChatColorSettingStore(keyValueStoreFactory: keyValueStoreFactory)
        let groupMemberStore = GroupMemberStoreImpl()
        let threadAssociatedDataStore = ThreadAssociatedDataStoreImpl()
        let threadReplyInfoStore = ThreadReplyInfoStore(keyValueStoreFactory: keyValueStoreFactory)
        let wallpaperStore = WallpaperStore(
            keyValueStoreFactory: keyValueStoreFactory,
            notificationScheduler: schedulers.main
        )

        let disappearingMessagesConfigurationStore = DisappearingMessagesConfigurationStoreImpl()

        let threadRemover = ThreadRemoverImpl(
            chatColorSettingStore: chatColorSettingStore,
            databaseStorage: ThreadRemoverImpl.Wrappers.DatabaseStorage(databaseStorage),
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            interactionRemover: ThreadRemoverImpl.Wrappers.InteractionRemover(),
            sdsThreadRemover: ThreadRemoverImpl.Wrappers.SDSThreadRemover(),
            threadAssociatedDataStore: threadAssociatedDataStore,
            threadReadCache: ThreadRemoverImpl.Wrappers.ThreadReadCache(modelReadCaches.threadReadCache),
            threadReplyInfoStore: threadReplyInfoStore,
            threadStore: threadStore,
            wallpaperStore: wallpaperStore
        )

        let groupMemberUpdater = GroupMemberUpdaterImpl(
            temporaryShims: GroupMemberUpdaterTemporaryShimsImpl(),
            groupMemberStore: groupMemberStore,
            signalServiceAddressCache: signalServiceAddressCache
        )

        let deletedCallRecordStore = DeletedCallRecordStoreImpl()
        let deletedCallRecordCleanupManager = DeletedCallRecordCleanupManagerImpl(
            dateProvider: dateProvider,
            db: db,
            deletedCallRecordStore: deletedCallRecordStore,
            schedulers: schedulers
        )
        let callRecordStore = CallRecordStoreImpl(
            deletedCallRecordStore: deletedCallRecordStore,
            schedulers: schedulers
        )
        let outgoingCallEventSyncMessageManager = OutgoingCallEventSyncMessageManagerImpl(
            databaseStorage: databaseStorage,
            messageSenderJobQueue: messageSenderJobQueue,
            recipientDatabaseTable: recipientDatabaseTable
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
        let callRecordSyncMessageConversationIdAdapater = CallRecordSyncMessageConversationIdAdapterImpl(
            callRecordStore: callRecordStore,
            recipientDatabaseTable: recipientDatabaseTable,
            threadStore: threadStore
        )
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
            interactionStore: interactionStore,
            threadStore: threadStore
        )
        let callRecordDeleteAllJobQueue = CallRecordDeleteAllJobQueue(
            callRecordConversationIdAdapter: callRecordSyncMessageConversationIdAdapater,
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordQuerier: callRecordQuerier,
            callRecordStore: callRecordStore,
            db: db,
            messageSenderJobQueue: messageSenderJobQueue
        )
        let incomingCallEventSyncMessageManager = IncomingCallEventSyncMessageManagerImpl(
            callRecordStore: callRecordStore,
            callRecordDeleteManager: callRecordDeleteManager,
            groupCallRecordManager: groupCallRecordManager,
            individualCallRecordManager: individualCallRecordManager,
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

        let pinnedThreadStore = PinnedThreadStoreImpl(keyValueStoreFactory: keyValueStoreFactory)
        let pinnedThreadManager = PinnedThreadManagerImpl(
            db: db,
            pinnedThreadStore: pinnedThreadStore,
            storageServiceManager: storageServiceManager,
            threadStore: threadStore
        )

        let authorMergeHelper = AuthorMergeHelper(keyValueStoreFactory: keyValueStoreFactory)
        let recipientMerger = RecipientMergerImpl(
            aciSessionStore: aciProtocolStore.sessionStore,
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
            keyValueStoreFactory: keyValueStoreFactory,
            messageProcessor: LinkedDevicePniKeyManagerImpl.Wrappers.MessageProcessor(messageProcessor),
            pniIdentityKeyChecker: pniIdentityKeyChecker,
            registrationStateChangeManager: registrationStateChangeManager,
            schedulers: schedulers,
            tsAccountManager: tsAccountManager
        )
        let pniHelloWorldManager = PniHelloWorldManagerImpl(
            database: db,
            identityManager: identityManager,
            keyValueStoreFactory: keyValueStoreFactory,
            networkManager: PniHelloWorldManagerImpl.Wrappers.NetworkManager(networkManager),
            pniDistributionParameterBuilder: pniDistributionParameterBuilder,
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            recipientDatabaseTable: recipientDatabaseTable,
            schedulers: schedulers,
            tsAccountManager: tsAccountManager
        )

        let libsignalNet = Net(env: TSConstants.isUsingProductionService ? .production : .staging)
        let chatConnectionManager = ChatConnectionManagerImpl(appExpiry: appExpiry, db: db, libsignalNet: libsignalNet)
        let preKeyManager = PreKeyManagerImpl(
            dateProvider: dateProvider,
            db: db,
            identityManager: PreKey.Wrappers.IdentityManager(identityManager),
            keyValueStoryFactory: keyValueStoreFactory,
            linkedDevicePniKeyManager: linkedDevicePniKeyManager,
            messageProcessor: PreKey.Wrappers.MessageProcessor(messageProcessor: messageProcessor),
            protocolStoreManager: signalProtocolStoreManager,
            serviceClient: accountServiceClient,
            chatConnectionManager: chatConnectionManager,
            tsAccountManager: tsAccountManager
        )

        let learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            accountServiceClient: LearnMyOwnPniManagerImpl.Wrappers.AccountServiceClient(accountServiceClient),
            db: db,
            registrationStateChangeManager: registrationStateChangeManager,
            schedulers: schedulers,
            tsAccountManager: tsAccountManager
        )

        let registrationSessionManager = RegistrationSessionManagerImpl(
            dateProvider: dateProvider,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: schedulers,
            signalService: signalService
        )

        let recipientHidingManager = RecipientHidingManagerImpl(
            profileManager: profileManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
            messageSenderJobQueue: messageSenderJobQueue
        )

        let receiptCredentialResultStore = ReceiptCredentialResultStoreImpl(
            kvStoreFactory: keyValueStoreFactory
        )

        let usernameApiClient = UsernameApiClientImpl(
            networkManager: UsernameApiClientImpl.Wrappers.NetworkManager(networkManager: networkManager),
            schedulers: schedulers
        )
        let usernameEducationManager = UsernameEducationManagerImpl(keyValueStoreFactory: keyValueStoreFactory)
        let usernameLinkManager = UsernameLinkManagerImpl(
            db: db,
            apiClient: usernameApiClient,
            schedulers: schedulers
        )
        let localUsernameManager = LocalUsernameManagerImpl(
            db: db,
            kvStoreFactory: keyValueStoreFactory,
            reachabilityManager: reachabilityManager,
            schedulers: schedulers,
            storageServiceManager: storageServiceManager,
            usernameApiClient: usernameApiClient,
            usernameLinkManager: usernameLinkManager
        )
        let usernameValidationManager = UsernameValidationManagerImpl(context: .init(
            accountServiceClient: Usernames.Validation.Wrappers.AccountServiceClient(accountServiceClient),
            database: db,
            keyValueStoreFactory: keyValueStoreFactory,
            localUsernameManager: localUsernameManager,
            messageProcessor: Usernames.Validation.Wrappers.MessageProcessor(messageProcessor),
            schedulers: schedulers,
            storageServiceManager: Usernames.Validation.Wrappers.StorageServiceManager(storageServiceManager),
            usernameLinkManager: usernameLinkManager
        ))

        let phoneNumberDiscoverabilityManager = PhoneNumberDiscoverabilityManagerImpl(
            accountAttributesUpdater: accountAttributesUpdater,
            schedulers: schedulers,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager
        )

        let incomingPniChangeNumberProcessor = IncomingPniChangeNumberProcessorImpl(
            identityManager: identityManager,
            pniProtocolStore: pniProtocolStore,
            preKeyManager: preKeyManager,
            registrationStateChangeManager: registrationStateChangeManager,
            tsAccountManager: tsAccountManager
        )

        let masterKeySyncManager = MasterKeySyncManagerImpl(
            dateProvider: dateProvider,
            keyValueStoreFactory: keyValueStoreFactory,
            svr: svr,
            syncManager: MasterKeySyncManagerImpl.Wrappers.SyncManager(syncManager),
            tsAccountManager: tsAccountManager
        )

        let messageStickerManager = MessageStickerManagerImpl(
            attachmentManager: tsResourceManager,
            attachmentStore: tsResourceStore,
            stickerManager: MessageStickerManagerImpl.Wrappers.StickerManager()
        )

        let contactShareManager = ContactShareManagerImpl(
            attachmentManager: tsResourceManager,
            attachmentStore: tsResourceStore
        )

        let sentMessageTranscriptReceiver = SentMessageTranscriptReceiverImpl(
            attachmentDownloads: tsResourceDownloadManager,
            disappearingMessagesJob: SentMessageTranscriptReceiverImpl.Wrappers.DisappearingMessagesJob(),
            earlyMessageManager: SentMessageTranscriptReceiverImpl.Wrappers.EarlyMessageManager(earlyMessageManager),
            groupManager: SentMessageTranscriptReceiverImpl.Wrappers.GroupManager(),
            interactionStore: interactionStore,
            messageStickerManager: messageStickerManager,
            paymentsHelper: SentMessageTranscriptReceiverImpl.Wrappers.PaymentsHelper(paymentsHelper),
            signalProtocolStoreManager: signalProtocolStoreManager,
            tsAccountManager: tsAccountManager,
            tsResourceManager: tsResourceManager,
            viewOnceMessages: SentMessageTranscriptReceiverImpl.Wrappers.ViewOnceMessages()
        )

        let preferences = Preferences()
        let storyStore = StoryStoreImpl()
        let subscriptionManager = testDependencies?.subscriptionManager ?? SubscriptionManagerImpl()
        let systemStoryManager = testDependencies?.systemStoryManager ?? SystemStoryManager()
        let typingIndicators = TypingIndicatorsImpl()

        let messageBackupManager = MessageBackupManagerImpl(
            accountDataArchiver: MessageBackupAccountDataArchiverImpl(
                disappearingMessageConfigurationStore: disappearingMessagesConfigurationStore,
                localUsernameManager: localUsernameManager,
                phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManager,
                preferences: MessageBackup.AccountData.Wrappers.Preferences(preferences: preferences),
                receiptManager: MessageBackup.AccountData.Wrappers.ReceiptManager(receiptManager: receiptManager),
                reactionManager: MessageBackup.AccountData.Wrappers.ReactionManager(),
                sskPreferences: MessageBackup.AccountData.Wrappers.SSKPreferences(),
                subscriptionManager: MessageBackup.AccountData.Wrappers.SubscriptionManager(subscriptionManager: subscriptionManager),
                storyManager: MessageBackup.AccountData.Wrappers.StoryManager(),
                systemStoryManager: MessageBackup.AccountData.Wrappers.SystemStoryManager(systemStoryManager: systemStoryManager),
                typingIndicators: MessageBackup.AccountData.Wrappers.TypingIndicators(typingIndicators: typingIndicators),
                udManager: MessageBackup.AccountData.Wrappers.UDManager(udManager: udManager),
                usernameEducationManager: usernameEducationManager,
                userProfile: MessageBackup.AccountData.Wrappers.UserProfile()
            ),
            chatArchiver: MessageBackupChatArchiverImpl(
                dmConfigurationStore: disappearingMessagesConfigurationStore,
                pinnedThreadManager: pinnedThreadManager,
                threadStore: threadStore
            ),
            chatItemArchiver: MessageBackupChatItemArchiverImp(
                dateProvider: dateProvider,
                groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelperImpl(),
                groupUpdateItemBuilder: groupUpdateItemBuilder,
                interactionStore: interactionStore,
                reactionStore: ReactionStoreImpl(),
                sentMessageTranscriptReceiver: sentMessageTranscriptReceiver,
                threadStore: threadStore
            ),
            dateProvider: dateProvider,
            db: db,
            localRecipientArchiver: MessageBackupLocalRecipientArchiverImpl(),
            recipientArchiver: MessageBackupRecipientArchiverImpl(
                blockingManager: MessageBackup.Wrappers.BlockingManager(blockingManager),
                groupsV2: groupsV2,
                profileManager: MessageBackup.Wrappers.ProfileManager(profileManager),
                recipientDatabaseTable: recipientDatabaseTable,
                recipientHidingManager: recipientHidingManager,
                recipientManager: recipientManager,
                signalServiceAddressCache: signalServiceAddressCache,
                storyStore: storyStore,
                threadStore: threadStore,
                tsAccountManager: tsAccountManager,
                usernameLookupManager: usernameLookupManager
            ),
            streamProvider: MessageBackupProtoStreamProviderImpl(
                backupKeyMaterial: MessageBackupKeyMaterialImpl(svr: svr)
            )
        )

        let externalPendingIDEALDonationStore = ExternalPendingIDEALDonationStoreImpl(keyStoreFactory: keyValueStoreFactory)

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

        let tsAttachmentUploadManager = TSAttachmentUploadManagerImpl(
            db: db,
            interactionStore: interactionStore,
            networkManager: networkManager,
            chatConnectionManager: chatConnectionManager,
            signalService: signalService,
            attachmentEncrypter: Upload.Wrappers.AttachmentEncrypter(),
            blurHash: TSAttachmentUpload.Wrappers.BlurHash(),
            fileSystem: Upload.Wrappers.FileSystem(),
            tsResourceStore: tsResourceStore
        )
        let attachmentUploadManager = AttachmentUploadManagerImpl(
            attachmentEncrypter: Upload.Wrappers.AttachmentEncrypter(),
            attachmentStore: attachmentStore,
            chatConnectionManager: chatConnectionManager,
            dateProvider: dateProvider,
            db: db,
            fileSystem: Upload.Wrappers.FileSystem(),
            interactionStore: interactionStore,
            networkManager: networkManager,
            signalService: signalService,
            storyStore: storyStore
        )
        let tsResourceUploadManager = TSResourceUploadManagerImpl(
            attachmentUploadManager: attachmentUploadManager,
            tsAttachmentUploadManager: tsAttachmentUploadManager
        )

        let dependenciesBridge = DependenciesBridge(
            accountAttributesUpdater: accountAttributesUpdater,
            appExpiry: appExpiry,
            attachmentDownloadManager: attachmentDownloadManager,
            attachmentManager: attachmentManager,
            attachmentStore: attachmentStore,
            authorMergeHelper: authorMergeHelper,
            badgeCountFetcher: badgeCountFetcher,
            callRecordDeleteManager: callRecordDeleteManager,
            callRecordMissedCallManager: callRecordMissedCallManager,
            callRecordQuerier: callRecordQuerier,
            callRecordStore: callRecordStore,
            changePhoneNumberPniManager: changePhoneNumberPniManager,
            chatColorSettingStore: chatColorSettingStore,
            chatConnectionManager: chatConnectionManager,
            contactShareManager: contactShareManager,
            db: db,
            deletedCallRecordCleanupManager: deletedCallRecordCleanupManager,
            deletedCallRecordStore: deletedCallRecordStore,
            deviceManager: deviceManager,
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            editManager: editManager,
            editMessageStore: editMessageStore,
            externalPendingIDEALDonationStore: externalPendingIDEALDonationStore,
            groupCallRecordManager: groupCallRecordManager,
            groupMemberStore: groupMemberStore,
            groupMemberUpdater: groupMemberUpdater,
            groupUpdateInfoMessageInserter: groupUpdateInfoMessageInserter,
            identityManager: identityManager,
            incomingCallEventSyncMessageManager: incomingCallEventSyncMessageManager,
            incomingCallLogEventSyncMessageManager: incomingCallLogEventSyncMessageManager,
            incomingPniChangeNumberProcessor: incomingPniChangeNumberProcessor,
            individualCallRecordManager: individualCallRecordManager,
            interactionStore: interactionStore,
            keyValueStoreFactory: keyValueStoreFactory,
            learnMyOwnPniManager: learnMyOwnPniManager,
            linkedDevicePniKeyManager: linkedDevicePniKeyManager,
            linkPreviewManager: linkPreviewManager,
            localProfileChecker: localProfileChecker,
            localUsernameManager: localUsernameManager,
            masterKeySyncManager: masterKeySyncManager,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            messageBackupManager: messageBackupManager,
            messageStickerManager: messageStickerManager,
            nicknameManager: nicknameManager,
            phoneNumberDiscoverabilityManager: phoneNumberDiscoverabilityManager,
            phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
            pinnedThreadManager: pinnedThreadManager,
            pinnedThreadStore: pinnedThreadStore,
            pniHelloWorldManager: pniHelloWorldManager,
            preKeyManager: preKeyManager,
            quotedReplyManager: quotedReplyManager,
            receiptCredentialResultStore: receiptCredentialResultStore,
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
            svr: svr,
            svrCredentialStorage: svrCredentialStorage,
            threadAssociatedDataStore: threadAssociatedDataStore,
            threadRemover: threadRemover,
            threadReplyInfoStore: threadReplyInfoStore,
            threadStore: threadStore,
            tsAccountManager: tsAccountManager,
            tsResourceDownloadManager: tsResourceDownloadManager,
            tsResourceManager: tsResourceManager,
            tsResourceStore: tsResourceStore,
            tsResourceUploadManager: tsResourceUploadManager,
            usernameApiClient: usernameApiClient,
            usernameEducationManager: usernameEducationManager,
            usernameLinkManager: usernameLinkManager,
            usernameLookupManager: usernameLookupManager,
            usernameValidationManager: usernameValidationManager,
            wallpaperStore: wallpaperStore
        )
        DependenciesBridge.setShared(dependenciesBridge)

        let proximityMonitoringManager = OWSProximityMonitoringManagerImpl()
        let avatarBuilder = AvatarBuilder()
        let smJobQueues = SignalMessagingJobQueues(
            db: db,
            reachabilityManager: reachabilityManager
        )

        let pendingReceiptRecorder = testDependencies?.pendingReceiptRecorder ?? MessageRequestPendingReceipts()
        let messageReceiver = MessageReceiver(callMessageHandler: callMessageHandler)
        let remoteConfigManager = testDependencies?.remoteConfigManager ?? RemoteConfigManagerImpl(
            appExpiry: appExpiry,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            tsAccountManager: tsAccountManager,
            serviceClient: SignalServiceRestClient.shared
        )
        let messageDecrypter = OWSMessageDecrypter()
        let groupsV2MessageProcessor = GroupsV2MessageProcessor()
        let disappearingMessagesJob = OWSDisappearingMessagesJob()
        let receiptSender = ReceiptSender(
            kvStoreFactory: keyValueStoreFactory,
            recipientDatabaseTable: recipientDatabaseTable
        )
        let stickerManager = StickerManager()
        let sskPreferences = SSKPreferences()
        let groupV2Updates = testDependencies?.groupV2Updates ?? GroupV2UpdatesImpl()
        let messageFetcherJob = MessageFetcherJob()
        let bulkProfileFetch = BulkProfileFetch(
            reachabilityManager: reachabilityManager,
            tsAccountManager: tsAccountManager
        )
        let messagePipelineSupervisor = MessagePipelineSupervisor()
        let paymentsCurrencies = testDependencies?.paymentsCurrencies ?? PaymentsCurrenciesImpl()
        let spamChallengeResolver = SpamChallengeResolver()
        let phoneNumberUtil = PhoneNumberUtil(swiftValues: PhoneNumberUtilSwiftValues())
        let legacyChangePhoneNumber = LegacyChangePhoneNumber()
        let remoteMegaphoneFetcher = RemoteMegaphoneFetcher()
        let contactDiscoveryManager = ContactDiscoveryManagerImpl(
            db: db,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            recipientManager: recipientManager,
            recipientMerger: recipientMerger,
            tsAccountManager: tsAccountManager,
            udManager: udManager,
            websocketFactory: webSocketFactory,
            libsignalNet: libsignalNet
        )
        let messageSendLog = MessageSendLog(
            db: db,
            dateProvider: { Date() }
        )
        let localUserLeaveGroupJobQueue = LocalUserLeaveGroupJobQueue(
            db: db,
            reachabilityManager: reachabilityManager
        )

        let groupCallPeekClient = GroupCallPeekClient(db: db, groupsV2: groupsV2)
        let lightweightGroupCallManager = lightweightGroupCallManagerBuilder(groupCallPeekClient)

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
            accountServiceClient: accountServiceClient,
            storageServiceManager: storageServiceManager,
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
            notificationsManager: notificationPresenter,
            messageSendLog: messageSendLog,
            messageSenderJobQueue: messageSenderJobQueue,
            localUserLeaveGroupJobQueue: localUserLeaveGroupJobQueue,
            callRecordDeleteAllJobQueue: callRecordDeleteAllJobQueue,
            preferences: preferences,
            proximityMonitoringManager: proximityMonitoringManager,
            avatarBuilder: avatarBuilder,
            smJobQueues: smJobQueues,
            lightweightGroupCallManager: lightweightGroupCallManager
        )
        SSKEnvironment.setShared(sskEnvironment, isRunningTests: appContext.isRunningTests)

        // Register renamed classes.
        NSKeyedUnarchiver.setClass(OWSUserProfile.self, forClassName: OWSUserProfile.collection())
        NSKeyedUnarchiver.setClass(TSGroupModelV2.self, forClassName: "TSGroupModelV2")
        NSKeyedUnarchiver.setClass(PendingProfileUpdate.self, forClassName: "SignalMessaging.PendingProfileUpdate")

        Sounds.performStartupTasks()

        return AppSetup.DatabaseContinuation(
            appContext: appContext,
            authCredentialStore: authCredentialStore,
            dependenciesBridge: dependenciesBridge,
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
        private let authCredentialStore: AuthCredentialStore
        private let dependenciesBridge: DependenciesBridge
        private let sskEnvironment: SSKEnvironment
        private let backgroundTask: OWSBackgroundTask

        fileprivate init(
            appContext: AppContext,
            authCredentialStore: AuthCredentialStore,
            dependenciesBridge: DependenciesBridge,
            sskEnvironment: SSKEnvironment,
            backgroundTask: OWSBackgroundTask
        ) {
            self.appContext = appContext
            self.authCredentialStore = authCredentialStore
            self.dependenciesBridge = dependenciesBridge
            self.sskEnvironment = sskEnvironment
            self.backgroundTask = backgroundTask
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
                self.sskEnvironment.warmCaches()
                self.backgroundTask.end()
                future.resolve(AppSetup.FinalContinuation(
                    authCredentialStore: self.authCredentialStore,
                    dependenciesBridge: self.dependenciesBridge,
                    sskEnvironment: self.sskEnvironment
                ))
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
        private let authCredentialStore: AuthCredentialStore
        private let dependenciesBridge: DependenciesBridge
        private let sskEnvironment: SSKEnvironment

        fileprivate init(
            authCredentialStore: AuthCredentialStore,
            dependenciesBridge: DependenciesBridge,
            sskEnvironment: SSKEnvironment
        ) {
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
            authCredentialStore: authCredentialStore,
            db: dependenciesBridge.db,
            keyValueStoreFactory: dependenciesBridge.keyValueStoreFactory,
            profileManager: sskEnvironment.profileManagerRef,
            tsAccountManager: dependenciesBridge.tsAccountManager,
            versionedProfiles: sskEnvironment.versionedProfilesRef
        ).migrateIfNeeded()

        guard setUpLocalIdentifiers(willResumeInProgressRegistration: willResumeInProgressRegistration) else {
            return .corruptRegistrationState
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync { [dependenciesBridge] in
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
