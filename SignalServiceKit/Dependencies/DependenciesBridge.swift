//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

/// Temporary bridge between [legacy code that uses global accessors for manager instances]
/// and [new code that expects references to instances to be explicitly passed around].
///
/// Ideally, all references to dependencies (singletons or otherwise) are passed to a class
/// in its initializer. Most existing code is not written that way, and expects to pull dependencies
/// from global static state (e.g. `SSKEnvironment` and `Dependencies`)
///
/// This lets you put off piping through references many layers deep to the usage site,
/// and access global state but with a few advantages over legacy methods:
/// 1) Not a protocol + extension; you must explicitly access members via the shared instance
/// 2) Swift-only, no need for @objc
/// 3) Classes within this container should themselves adhere to modern design principles: NOT accessing
///   global state or `Dependencies`, being protocolized, taking all dependencies
///   explicitly on initialization, and encapsulated for easy testing.
///
/// It is preferred **NOT** to use this class, and to take dependencies on init instead, but it is
/// better to use this class than to use `Dependencies`.
public class DependenciesBridge {

    /// Only available after calling `setupSingleton(...)`.
    public static var shared: DependenciesBridge {
        guard let _shared else {
            owsFail("DependenciesBridge has not yet been set up!")
        }

        return _shared
    }
    private static var _shared: DependenciesBridge?

    public let db: DB
    public let schedulers: Schedulers

    public let accountAttributesUpdater: AccountAttributesUpdater

    public let appExpiry: AppExpiry

    public let attachmentDownloadManager: AttachmentDownloadManager
    public let attachmentManager: AttachmentManager
    public let attachmentStore: AttachmentStore

    public let authorMergeHelper: AuthorMergeHelper

    public let badgeCountFetcher: BadgeCountFetcher

    let deletedCallRecordStore: DeletedCallRecordStore
    public let deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager

    public let callRecordStore: CallRecordStore
    public let callRecordDeleteManager: CallRecordDeleteManager
    public let callRecordMissedCallManager: CallRecordMissedCallManager
    public let callRecordQuerier: CallRecordQuerier

    public let groupCallRecordManager: GroupCallRecordManager
    public let individualCallRecordManager: IndividualCallRecordManager
    let callRecordIncomingSyncMessageManager: CallRecordIncomingSyncMessageManager

    public let changePhoneNumberPniManager: ChangePhoneNumberPniManager
    public let chatColorSettingStore: ChatColorSettingStore

    public let messageBackupManager: MessageBackupManager

    public let deviceManager: OWSDeviceManager
    public let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore

    public let editManager: EditManager

    public let groupMemberStore: GroupMemberStore
    public let groupMemberUpdater: GroupMemberUpdater
    public let groupUpdateInfoMessageInserter: GroupUpdateInfoMessageInserter

    public let identityManager: OWSIdentityManager

    public let incomingPniChangeNumberProcessor: IncomingPniChangeNumberProcessor

    public let interactionStore: InteractionStore

    public let keyValueStoreFactory: KeyValueStoreFactory

    public let learnMyOwnPniManager: LearnMyOwnPniManager
    public let linkedDevicePniKeyManager: LinkedDevicePniKeyManager
    let localProfileChecker: LocalProfileChecker
    public let localUsernameManager: LocalUsernameManager

    public let masterKeySyncManager: MasterKeySyncManager

    public let phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager
    public let phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher

    public let pinnedThreadStore: PinnedThreadStore
    public let pinnedThreadManager: PinnedThreadManager

    public let pniHelloWorldManager: PniHelloWorldManager
    public let preKeyManager: PreKeyManager

    public let recipientDatabaseTable: RecipientDatabaseTable
    public let recipientFetcher: RecipientFetcher
    public let recipientHidingManager: RecipientHidingManager
    public let recipientIdFinder: RecipientIdFinder
    public let recipientManager: any SignalRecipientManager
    public let recipientMerger: RecipientMerger
    public let registrationSessionManager: RegistrationSessionManager

    public let registrationStateChangeManager: RegistrationStateChangeManager

    public let searchableNameIndexer: SearchableNameIndexer
    public let signalProtocolStoreManager: SignalProtocolStoreManager
    public let socketManager: SocketManager

    public let externalPendingIDEALDonationStore: ExternalPendingIDEALDonationStore
    public let receiptCredentialResultStore: ReceiptCredentialResultStore

    public let sentMessageTranscriptReceiver: SentMessageTranscriptReceiver

    public let svr: SecureValueRecovery
    public let svrCredentialStorage: SVRAuthCredentialStorage

    public let threadAssociatedDataStore: ThreadAssociatedDataStore
    public let threadRemover: ThreadRemover
    public let threadStore: ThreadStore
    public let threadReplyInfoStore: ThreadReplyInfoStore

    public let tsAccountManager: TSAccountManager

    public let tsResourceDownloadManager: TSResourceDownloadManager
    public let tsResourceManager: TSResourceManager
    public let tsResourceStore: TSResourceStore

    public let uploadManager: UploadManager

    public let usernameApiClient: UsernameApiClient
    public let usernameEducationManager: UsernameEducationManager
    public let usernameLinkManager: UsernameLinkManager
    public let usernameLookupManager: UsernameLookupManager
    public let usernameValidationManager: UsernameValidationManager

    public let wallpaperStore: WallpaperStore

    /// Initialize and configure the ``DependenciesBridge`` singleton.
    public static func setUpSingleton(
        accountServiceClient: AccountServiceClient,
        appContext: AppContext,
        appVersion: AppVersion,
        blockingManager: BlockingManager,
        contactManager: any ContactManager,
        databaseStorage: SDSDatabaseStorage,
        dateProvider: @escaping DateProvider,
        earlyMessageManager: EarlyMessageManager,
        groupsV2: GroupsV2,
        keyValueStoreFactory: KeyValueStoreFactory,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        messageSenderJobQueue: MessageSenderJobQueue,
        modelReadCaches: ModelReadCaches,
        networkManager: NetworkManager,
        notificationsManager: NotificationsProtocolSwift,
        ows2FAManager: OWS2FAManager,
        paymentsEvents: PaymentsEvents,
        paymentsHelper: PaymentsHelper,
        profileManager: ProfileManager,
        reachabilityManager: SSKReachabilityManager,
        receiptManager: OWSReceiptManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        recipientIdFinder: RecipientIdFinder,
        searchableNameIndexer: any SearchableNameIndexer,
        senderKeyStore: SenderKeyStore,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        signalService: OWSSignalServiceProtocol,
        signalServiceAddressCache: SignalServiceAddressCache,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocol,
        threadStore: any ThreadStore,
        udManager: OWSUDManager,
        usernameLookupManager: UsernameLookupManager,
        userProfileStore: any UserProfileStore,
        versionedProfiles: VersionedProfilesSwift,
        websocketFactory: WebSocketFactory
    ) -> DependenciesBridge {
        let result = DependenciesBridge(
            accountServiceClient: accountServiceClient,
            appContext: appContext,
            appVersion: appVersion,
            blockingManager: blockingManager,
            contactManager: contactManager,
            databaseStorage: databaseStorage,
            dateProvider: dateProvider,
            earlyMessageManager: earlyMessageManager,
            groupsV2: groupsV2,
            keyValueStoreFactory: keyValueStoreFactory,
            messageProcessor: messageProcessor,
            messageSender: messageSender,
            messageSenderJobQueue: messageSenderJobQueue,
            modelReadCaches: modelReadCaches,
            networkManager: networkManager,
            notificationsManager: notificationsManager,
            ows2FAManager: ows2FAManager,
            paymentsEvents: paymentsEvents,
            paymentsHelper: paymentsHelper,
            profileManager: profileManager,
            reachabilityManager: reachabilityManager,
            receiptManager: receiptManager,
            recipientDatabaseTable: recipientDatabaseTable,
            recipientFetcher: recipientFetcher,
            recipientIdFinder: recipientIdFinder,
            searchableNameIndexer: searchableNameIndexer,
            senderKeyStore: senderKeyStore,
            signalProtocolStoreManager: signalProtocolStoreManager,
            signalService: signalService,
            signalServiceAddressCache: signalServiceAddressCache,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            threadStore: threadStore,
            tsConstants: TSConstants.shared, // This is safe to hard-code.
            udManager: udManager,
            usernameLookupManager: usernameLookupManager,
            userProfileStore: userProfileStore,
            versionedProfiles: versionedProfiles,
            websocketFactory: websocketFactory
        )
        _shared = result
        return result
    }

    private init(
        accountServiceClient: AccountServiceClient,
        appContext: AppContext,
        appVersion: AppVersion,
        blockingManager: BlockingManager,
        contactManager: any ContactManager,
        databaseStorage: SDSDatabaseStorage,
        dateProvider: @escaping DateProvider,
        earlyMessageManager: EarlyMessageManager,
        groupsV2: GroupsV2,
        keyValueStoreFactory: KeyValueStoreFactory,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        messageSenderJobQueue: MessageSenderJobQueue,
        modelReadCaches: ModelReadCaches,
        networkManager: NetworkManager,
        notificationsManager: NotificationsProtocolSwift,
        ows2FAManager: OWS2FAManager,
        paymentsEvents: PaymentsEvents,
        paymentsHelper: PaymentsHelper,
        profileManager: ProfileManager,
        reachabilityManager: SSKReachabilityManager,
        receiptManager: OWSReceiptManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        recipientIdFinder: RecipientIdFinder,
        searchableNameIndexer: any SearchableNameIndexer,
        senderKeyStore: SenderKeyStore,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        signalService: OWSSignalServiceProtocol,
        signalServiceAddressCache: SignalServiceAddressCache,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocol,
        threadStore: any ThreadStore,
        tsConstants: TSConstantsProtocol,
        udManager: OWSUDManager,
        usernameLookupManager: UsernameLookupManager,
        userProfileStore: any UserProfileStore,
        versionedProfiles: VersionedProfilesSwift,
        websocketFactory: WebSocketFactory
    ) {
        self.schedulers = DispatchQueueSchedulers()
        self.db = SDSDB(databaseStorage: databaseStorage)
        self.keyValueStoreFactory = keyValueStoreFactory

        let aciProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .aci)
        let pniProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .pni)

        let attachmentStore = AttachmentStoreImpl()
        let attachmentManager = AttachmentManagerImpl(attachmentStore: attachmentStore)
        self.attachmentStore = attachmentStore
        self.attachmentManager = attachmentManager

        let tsResourceStore = TSResourceStoreImpl(attachmentStore: attachmentStore)
        self.tsResourceManager = TSResourceManagerImpl(attachmentManager: attachmentManager)
        self.tsResourceStore = tsResourceStore
        let attachmentDownloadManager = AttachmentDownloadManagerImpl()
        self.attachmentDownloadManager = attachmentDownloadManager
        self.tsResourceDownloadManager = TSResourceDownloadManagerImpl(
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
        self.tsAccountManager = tsAccountManager

        let phoneNumberVisibilityFetcher = PhoneNumberVisibilityFetcherImpl(
            contactsManager: contactManager,
            tsAccountManager: tsAccountManager,
            userProfileStore: userProfileStore
        )
        self.phoneNumberVisibilityFetcher = phoneNumberVisibilityFetcher

        let recipientManager = SignalRecipientManagerImpl(
            phoneNumberVisibilityFetcher: phoneNumberVisibilityFetcher,
            recipientDatabaseTable: recipientDatabaseTable,
            storageServiceManager: storageServiceManager
        )
        self.recipientManager = recipientManager

        let pniDistributionParameterBuilder = PniDistributionParameterBuilderImpl(
            db: db,
            messageSender: PniDistributionParameterBuilderImpl.Wrappers.MessageSender(messageSender),
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            registrationIdGenerator: RegistrationIdGenerator(),
            schedulers: schedulers
        )

        self.appExpiry = AppExpiryImpl(
            keyValueStoreFactory: keyValueStoreFactory,
            dateProvider: dateProvider,
            appVersion: appVersion,
            schedulers: schedulers
        )

        self.badgeCountFetcher = BadgeCountFetcherImpl()

        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.recipientIdFinder = recipientIdFinder

        self.identityManager = OWSIdentityManagerImpl(
            aciProtocolStore: aciProtocolStore,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            messageSenderJobQueue: messageSenderJobQueue,
            networkManager: networkManager,
            notificationsManager: notificationsManager,
            pniProtocolStore: pniProtocolStore,
            recipientFetcher: self.recipientFetcher,
            recipientIdFinder: self.recipientIdFinder,
            schedulers: self.schedulers,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager
        )

        self.changePhoneNumberPniManager = ChangePhoneNumberPniManagerImpl(
            db: self.db,
            identityManager: ChangePhoneNumberPniManagerImpl.Wrappers.IdentityManager(identityManager),
            pniDistributionParameterBuilder: pniDistributionParameterBuilder,
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            preKeyManager: ChangePhoneNumberPniManagerImpl.Wrappers.PreKeyManager(),
            registrationIdGenerator: RegistrationIdGenerator(),
            schedulers: schedulers,
            tsAccountManager: tsAccountManager
        )

        self.deviceManager = OWSDeviceManagerImpl(
            databaseStorage: db,
            keyValueStoreFactory: keyValueStoreFactory
        )

        self.editManager = EditManager(
            context: .init(
                dataStore: EditManager.Wrappers.DataStore(),
                groupsShim: EditManager.Wrappers.Groups(groupsV2: groupsV2),
                keyValueStoreFactory: keyValueStoreFactory,
                linkPreviewShim: EditManager.Wrappers.LinkPreview(),
                receiptManagerShim: EditManager.Wrappers.ReceiptManager(receiptManager: receiptManager),
                tsResourceStore: tsResourceStore
            )
        )

        let groupUpdateItemBuilder = GroupUpdateItemBuilderImpl(
            contactsManager: GroupUpdateItemBuilderImpl.Wrappers.ContactsManager(contactManager),
            recipientDatabaseTable: recipientDatabaseTable
        )

        self.groupUpdateInfoMessageInserter = GroupUpdateInfoMessageInserterImpl(
            dateProvider: dateProvider,
            groupUpdateItemBuilder: groupUpdateItemBuilder,
            notificationsManager: notificationsManager
        )

        self.svrCredentialStorage = SVRAuthCredentialStorageImpl(keyValueStoreFactory: keyValueStoreFactory)
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
        self.accountAttributesUpdater = accountAttributesUpdater

        self.svr = SecureValueRecovery2Impl(
            accountAttributesUpdater: accountAttributesUpdater,
            appReadiness: SVR2.Wrappers.AppReadiness(),
            appVersion: appVersion,
            connectionFactory: SgxWebsocketConnectionFactoryImpl(websocketFactory: websocketFactory),
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
        self.interactionStore = interactionStore

        self.chatColorSettingStore = ChatColorSettingStore(keyValueStoreFactory: self.keyValueStoreFactory)
        let groupMemberStore = GroupMemberStoreImpl()
        self.groupMemberStore = groupMemberStore
        self.threadAssociatedDataStore = ThreadAssociatedDataStoreImpl()
        self.threadReplyInfoStore = ThreadReplyInfoStore(keyValueStoreFactory: self.keyValueStoreFactory)
        self.threadStore = threadStore
        self.wallpaperStore = WallpaperStore(
            keyValueStoreFactory: self.keyValueStoreFactory,
            notificationScheduler: self.schedulers.main
        )

        self.disappearingMessagesConfigurationStore = DisappearingMessagesConfigurationStoreImpl()

        self.threadRemover = ThreadRemoverImpl(
            chatColorSettingStore: self.chatColorSettingStore,
            databaseStorage: ThreadRemoverImpl.Wrappers.DatabaseStorage(databaseStorage),
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            interactionRemover: ThreadRemoverImpl.Wrappers.InteractionRemover(),
            sdsThreadRemover: ThreadRemoverImpl.Wrappers.SDSThreadRemover(),
            threadAssociatedDataStore: self.threadAssociatedDataStore,
            threadReadCache: ThreadRemoverImpl.Wrappers.ThreadReadCache(modelReadCaches.threadReadCache),
            threadReplyInfoStore: self.threadReplyInfoStore,
            threadStore: self.threadStore,
            wallpaperStore: self.wallpaperStore
        )

        self.groupMemberUpdater = GroupMemberUpdaterImpl(
            temporaryShims: GroupMemberUpdaterTemporaryShimsImpl(),
            groupMemberStore: groupMemberStore,
            signalServiceAddressCache: signalServiceAddressCache
        )

        do {
            let outgoingSyncMessageManager = CallRecordOutgoingSyncMessageManagerImpl(
                databaseStorage: databaseStorage,
                messageSenderJobQueue: messageSenderJobQueue,
                recipientDatabaseTable: self.recipientDatabaseTable
            )

            self.deletedCallRecordStore = DeletedCallRecordStoreImpl()
            self.deletedCallRecordCleanupManager = DeletedCallRecordCleanupManagerImpl(
                dateProvider: dateProvider,
                db: self.db,
                deletedCallRecordStore: self.deletedCallRecordStore,
                schedulers: self.schedulers
            )
            self.callRecordStore = CallRecordStoreImpl(
                deletedCallRecordStore: self.deletedCallRecordStore,
                schedulers: self.schedulers
            )
            self.callRecordDeleteManager = CallRecordDeleteManagerImpl(
                callRecordStore: self.callRecordStore,
                callRecordOutgoingSyncMessageManager: outgoingSyncMessageManager,
                deletedCallRecordCleanupManager: self.deletedCallRecordCleanupManager,
                deletedCallRecordStore: self.deletedCallRecordStore,
                interactionStore: self.interactionStore,
                threadStore: self.threadStore
            )
            self.callRecordQuerier = CallRecordQuerierImpl()

            self.callRecordMissedCallManager = CallRecordMissedCallManagerImpl(
                callRecordQuerier: self.callRecordQuerier,
                callRecordStore: self.callRecordStore,
                messageSenderJobQueue: messageSenderJobQueue,
                threadStore: self.threadStore
            )

            self.groupCallRecordManager = GroupCallRecordManagerImpl(
                callRecordStore: self.callRecordStore,
                interactionStore: interactionStore,
                outgoingSyncMessageManager: outgoingSyncMessageManager
            )
            self.individualCallRecordManager = IndividualCallRecordManagerImpl(
                callRecordStore: self.callRecordStore,
                interactionStore: interactionStore,
                outgoingSyncMessageManager: outgoingSyncMessageManager
            )
            self.callRecordIncomingSyncMessageManager = CallRecordIncomingSyncMessageManagerImpl(
                callRecordStore: self.callRecordStore,
                callRecordDeleteManager: self.callRecordDeleteManager,
                groupCallRecordManager: self.groupCallRecordManager,
                individualCallRecordManager: self.individualCallRecordManager,
                interactionStore: interactionStore,
                markAsReadShims: CallRecordIncomingSyncMessageManagerImpl.ShimsImpl.MarkAsRead(
                    notificationPresenter: notificationsManager
                ),
                recipientDatabaseTable: self.recipientDatabaseTable,
                threadStore: self.threadStore
            )
        }

        let pinnedThreadStore = PinnedThreadStoreImpl(keyValueStoreFactory: keyValueStoreFactory)
        self.pinnedThreadStore = pinnedThreadStore
        self.pinnedThreadManager = PinnedThreadManagerImpl(
            db: db,
            pinnedThreadStore: pinnedThreadStore,
            storageServiceManager: storageServiceManager,
            threadStore: threadStore
        )

        self.authorMergeHelper = AuthorMergeHelper(keyValueStoreFactory: keyValueStoreFactory)
        self.recipientMerger = RecipientMergerImpl(
            aciSessionStore: aciProtocolStore.sessionStore,
            identityManager: self.identityManager,
            observers: RecipientMergerImpl.buildObservers(
                authorMergeHelper: self.authorMergeHelper,
                callRecordStore: self.callRecordStore,
                chatColorSettingStore: self.chatColorSettingStore,
                deletedCallRecordStore: self.deletedCallRecordStore,
                disappearingMessagesConfigurationStore: self.disappearingMessagesConfigurationStore,
                groupMemberUpdater: self.groupMemberUpdater,
                groupMemberStore: groupMemberStore,
                interactionStore: interactionStore,
                pinnedThreadManager: pinnedThreadManager,
                profileManager: profileManager,
                recipientMergeNotifier: RecipientMergeNotifier(scheduler: schedulers.main),
                signalServiceAddressCache: signalServiceAddressCache,
                threadAssociatedDataStore: self.threadAssociatedDataStore,
                threadRemover: self.threadRemover,
                threadReplyInfoStore: self.threadReplyInfoStore,
                threadStore: self.threadStore,
                userProfileStore: userProfileStore,
                wallpaperStore: self.wallpaperStore
            ),
            recipientDatabaseTable: self.recipientDatabaseTable,
            recipientFetcher: self.recipientFetcher,
            storageServiceManager: storageServiceManager
        )

        self.registrationStateChangeManager = RegistrationStateChangeManagerImpl(
            appContext: appContext,
            groupsV2: groupsV2,
            identityManager: identityManager,
            notificationPresenter: notificationsManager,
            paymentsEvents: RegistrationStateChangeManagerImpl.Wrappers.PaymentsEvents(paymentsEvents),
            recipientManager: self.recipientManager,
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
        self.linkedDevicePniKeyManager = LinkedDevicePniKeyManagerImpl(
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            messageProcessor: LinkedDevicePniKeyManagerImpl.Wrappers.MessageProcessor(messageProcessor),
            pniIdentityKeyChecker: pniIdentityKeyChecker,
            registrationStateChangeManager: registrationStateChangeManager,
            schedulers: schedulers,
            tsAccountManager: tsAccountManager
        )
        self.pniHelloWorldManager = PniHelloWorldManagerImpl(
            database: db,
            identityManager: identityManager,
            keyValueStoreFactory: keyValueStoreFactory,
            networkManager: PniHelloWorldManagerImpl.Wrappers.NetworkManager(networkManager),
            pniDistributionParameterBuilder: pniDistributionParameterBuilder,
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            recipientDatabaseTable: self.recipientDatabaseTable,
            schedulers: schedulers,
            tsAccountManager: tsAccountManager
        )

        self.socketManager = SocketManagerImpl(appExpiry: appExpiry, db: db)
        self.preKeyManager = PreKeyManagerImpl(
            dateProvider: dateProvider,
            db: db,
            identityManager: PreKey.Wrappers.IdentityManager(identityManager),
            keyValueStoryFactory: keyValueStoreFactory,
            linkedDevicePniKeyManager: linkedDevicePniKeyManager,
            messageProcessor: PreKey.Wrappers.MessageProcessor(messageProcessor: messageProcessor),
            protocolStoreManager: signalProtocolStoreManager,
            serviceClient: accountServiceClient,
            socketManager: self.socketManager,
            tsAccountManager: tsAccountManager
        )

        self.learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            accountServiceClient: LearnMyOwnPniManagerImpl.Wrappers.AccountServiceClient(accountServiceClient),
            db: db,
            registrationStateChangeManager: registrationStateChangeManager,
            schedulers: schedulers,
            tsAccountManager: tsAccountManager
        )

        self.registrationSessionManager = RegistrationSessionManagerImpl(
            dateProvider: dateProvider,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: schedulers,
            signalService: signalService
        )

        self.recipientHidingManager = RecipientHidingManagerImpl(
            profileManager: profileManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager,
            messageSenderJobQueue: messageSenderJobQueue
        )

        self.signalProtocolStoreManager = signalProtocolStoreManager

        self.receiptCredentialResultStore = ReceiptCredentialResultStoreImpl(
            kvStoreFactory: keyValueStoreFactory
        )

        self.usernameApiClient = UsernameApiClientImpl(
            networkManager: UsernameApiClientImpl.Wrappers.NetworkManager(networkManager: networkManager),
            schedulers: schedulers
        )
        self.usernameLookupManager = usernameLookupManager
        self.usernameEducationManager = UsernameEducationManagerImpl(keyValueStoreFactory: keyValueStoreFactory)
        self.usernameLinkManager = UsernameLinkManagerImpl(
            db: db,
            apiClient: usernameApiClient,
            schedulers: schedulers
        )
        self.localUsernameManager = LocalUsernameManagerImpl(
            db: db,
            kvStoreFactory: keyValueStoreFactory,
            reachabilityManager: reachabilityManager,
            schedulers: schedulers,
            storageServiceManager: storageServiceManager,
            usernameApiClient: usernameApiClient,
            usernameLinkManager: usernameLinkManager
        )
        self.usernameValidationManager = UsernameValidationManagerImpl(context: .init(
            accountServiceClient: Usernames.Validation.Wrappers.AccountServiceClient(accountServiceClient),
            database: db,
            keyValueStoreFactory: keyValueStoreFactory,
            localUsernameManager: localUsernameManager,
            messageProcessor: Usernames.Validation.Wrappers.MessageProcessor(messageProcessor),
            schedulers: schedulers,
            storageServiceManager: Usernames.Validation.Wrappers.StorageServiceManager(storageServiceManager),
            usernameLinkManager: usernameLinkManager
        ))

        self.phoneNumberDiscoverabilityManager = PhoneNumberDiscoverabilityManagerImpl(
            accountAttributesUpdater: accountAttributesUpdater,
            schedulers: schedulers,
            storageServiceManager: storageServiceManager,
            tsAccountManager: tsAccountManager
        )

        self.incomingPniChangeNumberProcessor = IncomingPniChangeNumberProcessorImpl(
            identityManager: identityManager,
            pniProtocolStore: pniProtocolStore,
            preKeyManager: preKeyManager,
            registrationStateChangeManager: registrationStateChangeManager,
            tsAccountManager: tsAccountManager
        )

        self.masterKeySyncManager = MasterKeySyncManagerImpl(
            dateProvider: dateProvider,
            keyValueStoreFactory: keyValueStoreFactory,
            svr: svr,
            syncManager: MasterKeySyncManagerImpl.Wrappers.SyncManager(syncManager),
            tsAccountManager: tsAccountManager
        )

        self.sentMessageTranscriptReceiver = SentMessageTranscriptReceiverImpl(
            attachmentDownloads: tsResourceDownloadManager,
            disappearingMessagesJob: SentMessageTranscriptReceiverImpl.Wrappers.DisappearingMessagesJob(),
            earlyMessageManager: SentMessageTranscriptReceiverImpl.Wrappers.EarlyMessageManager(earlyMessageManager),
            groupManager: SentMessageTranscriptReceiverImpl.Wrappers.GroupManager(),
            interactionStore: InteractionStoreImpl(),
            paymentsHelper: SentMessageTranscriptReceiverImpl.Wrappers.PaymentsHelper(paymentsHelper),
            signalProtocolStoreManager: signalProtocolStoreManager,
            tsAccountManager: tsAccountManager,
            tsResourceManager: tsResourceManager,
            viewOnceMessages: SentMessageTranscriptReceiverImpl.Wrappers.ViewOnceMessages()
        )

        self.messageBackupManager = MessageBackupManagerImpl(
            chatArchiver: MessageBackupChatArchiverImpl(
                dmConfigurationStore: disappearingMessagesConfigurationStore,
                pinnedThreadManager: pinnedThreadManager,
                threadStore: threadStore
            ),
            chatItemArchiver: MessageBackupChatItemArchiverImp(
                dateProvider: dateProvider,
                groupUpdateHelper: GroupUpdateInfoMessageInserterBackupHelperImpl(),
                groupUpdateItemBuilder: groupUpdateItemBuilder,
                interactionStore: InteractionStoreImpl(),
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
                recipientDatabaseTable: self.recipientDatabaseTable,
                recipientHidingManager: recipientHidingManager,
                recipientManager: self.recipientManager,
                storyStore: StoryStoreImpl(),
                threadStore: threadStore,
                tsAccountManager: tsAccountManager
            ),
            streamProvider: MessageBackupProtoStreamProviderImpl(),
            tsAccountManager: tsAccountManager
        )

        self.externalPendingIDEALDonationStore = ExternalPendingIDEALDonationStoreImpl(keyStoreFactory: keyValueStoreFactory)

        // TODO: Move this into ProfileFetcherJob.
        // Ideally, this would be a private implementation detail of that class.
        // However, that class is currently implemented mostly as static methods,
        // so there's no place to store it. Once it's protocolized, this type
        // should be initialized in its initializer.
        self.localProfileChecker = LocalProfileChecker(
            db: self.db,
            messageProcessor: messageProcessor,
            profileManager: profileManager,
            storageServiceManager: storageServiceManager,
            tsAccountManager: self.tsAccountManager,
            udManager: udManager
        )

        self.uploadManager = UploadManagerImpl(
            db: db,
            interactionStore: InteractionStoreImpl(),
            networkManager: networkManager,
            socketManager: socketManager,
            signalService: signalService,
            attachmentEncrypter: Upload.Wrappers.AttachmentEncrypter(),
            blurHash: Upload.Wrappers.BlurHash(),
            fileSystem: Upload.Wrappers.FileSystem(),
            tsResourceStore: tsResourceStore
        )

        self.searchableNameIndexer = searchableNameIndexer
    }
}
