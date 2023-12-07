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

    public var accountAttributesUpdater: AccountAttributesUpdater

    public let appExpiry: AppExpiry
    public let authorMergeHelper: AuthorMergeHelper

    public let callRecordStatusTransitionManager: CallRecordStatusTransitionManager
    public let callRecordStore: CallRecordStore
    public let groupCallRecordManager: GroupCallRecordManager
    public let individualCallRecordManager: IndividualCallRecordManager
    let callRecordIncomingSyncMessageManager: CallRecordIncomingSyncMessageManager

    public let changePhoneNumberPniManager: ChangePhoneNumberPniManager
    public let chatColorSettingStore: ChatColorSettingStore

    public let cloudBackupManager: CloudBackupManager

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
    public let localUsernameManager: LocalUsernameManager

    public let masterKeySyncManager: MasterKeySyncManager

    public var phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager

    public let pniHelloWorldManager: PniHelloWorldManager
    public let preKeyManager: PreKeyManager

    public let recipientDatabaseTable: RecipientDatabaseTable
    public let recipientFetcher: RecipientFetcher
    public let recipientHidingManager: RecipientHidingManager
    public let recipientIdFinder: RecipientIdFinder
    public let recipientMerger: RecipientMerger
    public let registrationSessionManager: RegistrationSessionManager

    public var registrationStateChangeManager: RegistrationStateChangeManager

    public let signalProtocolStoreManager: SignalProtocolStoreManager
    public let socketManager: SocketManager

    public let subscriptionReceiptCredentialResultStore: SubscriptionReceiptCredentialResultStore

    public let svr: SecureValueRecovery
    public let svrCredentialStorage: SVRAuthCredentialStorage

    public let threadAssociatedDataStore: ThreadAssociatedDataStore
    public let threadRemover: ThreadRemover
    public let threadReplyInfoStore: ThreadReplyInfoStore

    public var tsAccountManager: TSAccountManager

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
        databaseStorage: SDSDatabaseStorage,
        dateProvider: @escaping DateProvider,
        groupsV2: GroupsV2Swift,
        jobQueues: SSKJobQueues,
        keyValueStoreFactory: KeyValueStoreFactory,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        modelReadCaches: ModelReadCaches,
        networkManager: NetworkManager,
        notificationsManager: NotificationsProtocolSwift,
        ows2FAManager: OWS2FAManager,
        paymentsEvents: PaymentsEvents,
        profileManager: ProfileManagerProtocol,
        receiptManager: OWSReceiptManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        recipientIdFinder: RecipientIdFinder,
        senderKeyStore: SenderKeyStore,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        signalService: OWSSignalServiceProtocol,
        signalServiceAddressCache: SignalServiceAddressCache,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocol,
        udManager: OWSUDManager,
        versionedProfiles: VersionedProfilesSwift,
        websocketFactory: WebSocketFactory
    ) -> DependenciesBridge {
        let result = DependenciesBridge(
            accountServiceClient: accountServiceClient,
            appContext: appContext,
            appVersion: appVersion,
            blockingManager: blockingManager,
            databaseStorage: databaseStorage,
            dateProvider: dateProvider,
            groupsV2: groupsV2,
            jobQueues: jobQueues,
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
            tsConstants: TSConstants.shared, // This is safe to hard-code.
            udManager: udManager,
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
        databaseStorage: SDSDatabaseStorage,
        dateProvider: @escaping DateProvider,
        groupsV2: GroupsV2Swift,
        jobQueues: SSKJobQueues,
        keyValueStoreFactory: KeyValueStoreFactory,
        messageProcessor: MessageProcessor,
        messageSender: MessageSender,
        modelReadCaches: ModelReadCaches,
        networkManager: NetworkManager,
        notificationsManager: NotificationsProtocolSwift,
        ows2FAManager: OWS2FAManager,
        paymentsEvents: PaymentsEvents,
        profileManager: ProfileManagerProtocol,
        receiptManager: OWSReceiptManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        recipientIdFinder: RecipientIdFinder,
        senderKeyStore: SenderKeyStore,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        signalService: OWSSignalServiceProtocol,
        signalServiceAddressCache: SignalServiceAddressCache,
        storageServiceManager: StorageServiceManager,
        syncManager: SyncManagerProtocol,
        tsConstants: TSConstantsProtocol,
        udManager: OWSUDManager,
        versionedProfiles: VersionedProfilesSwift,
        websocketFactory: WebSocketFactory
    ) {
        self.schedulers = DispatchQueueSchedulers()
        self.db = SDSDB(databaseStorage: databaseStorage)
        self.keyValueStoreFactory = keyValueStoreFactory

        let aciProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .aci)
        let pniProtocolStore = signalProtocolStoreManager.signalProtocolStore(for: .pni)

        let tsAccountManager = TSAccountManagerImpl(
            appReadiness: TSAccountManagerImpl.Wrappers.AppReadiness(),
            dateProvider: dateProvider,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            schedulers: schedulers
        )
        self.tsAccountManager = tsAccountManager

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

        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.recipientIdFinder = recipientIdFinder

        self.identityManager = OWSIdentityManagerImpl(
            aciProtocolStore: aciProtocolStore,
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            messageSenderJobQueue: jobQueues.messageSenderJobQueue,
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
                receiptManagerShim: EditManager.Wrappers.ReceiptManager(receiptManager: receiptManager)
            )
        )

        self.groupUpdateInfoMessageInserter = GroupUpdateInfoMessageInserterImpl(
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
        let threadStore = ThreadStoreImpl()
        self.wallpaperStore = WallpaperStore(
            keyValueStoreFactory: self.keyValueStoreFactory,
            notificationScheduler: self.schedulers.main
        )
        let userProfileStore = UserProfileStoreImpl()

        self.disappearingMessagesConfigurationStore = DisappearingMessagesConfigurationStoreImpl()

        self.threadRemover = ThreadRemoverImpl(
            chatColorSettingStore: self.chatColorSettingStore,
            databaseStorage: ThreadRemoverImpl.Wrappers.DatabaseStorage(databaseStorage),
            disappearingMessagesConfigurationStore: disappearingMessagesConfigurationStore,
            fullTextSearchFinder: ThreadRemoverImpl.Wrappers.FullTextSearchFinder(),
            interactionRemover: ThreadRemoverImpl.Wrappers.InteractionRemover(),
            sdsThreadRemover: ThreadRemoverImpl.Wrappers.SDSThreadRemover(),
            threadAssociatedDataStore: self.threadAssociatedDataStore,
            threadReadCache: ThreadRemoverImpl.Wrappers.ThreadReadCache(modelReadCaches.threadReadCache),
            threadReplyInfoStore: self.threadReplyInfoStore,
            threadStore: threadStore,
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
                messageSenderJobQueue: jobQueues.messageSenderJobQueue,
                recipientDatabaseTable: self.recipientDatabaseTable
            )

            self.callRecordStatusTransitionManager = CallRecordStatusTransitionManagerImpl()
            self.callRecordStore = CallRecordStoreImpl(
                statusTransitionManager: self.callRecordStatusTransitionManager
            )
            self.groupCallRecordManager = GroupCallRecordManagerImpl(
                callRecordStore: self.callRecordStore,
                interactionStore: interactionStore,
                outgoingSyncMessageManager: outgoingSyncMessageManager,
                tsAccountManager: tsAccountManager
            )
            self.individualCallRecordManager = IndividualCallRecordManagerImpl(
                callRecordStore: self.callRecordStore,
                interactionStore: interactionStore,
                outgoingSyncMessageManager: outgoingSyncMessageManager
            )
            self.callRecordIncomingSyncMessageManager = CallRecordIncomingSyncMessageManagerImpl(
                callRecordStore: self.callRecordStore,
                groupCallRecordManager: self.groupCallRecordManager,
                individualCallRecordManager: self.individualCallRecordManager,
                interactionStore: interactionStore,
                markAsReadShims: CallRecordIncomingSyncMessageManagerImpl.ShimsImpl.MarkAsRead(
                    notificationPresenter: notificationsManager
                ),
                recipientDatabaseTable: self.recipientDatabaseTable,
                threadStore: threadStore
            )
        }

        self.authorMergeHelper = AuthorMergeHelper(keyValueStoreFactory: keyValueStoreFactory)
        self.recipientMerger = RecipientMergerImpl(
            aciSessionStore: aciProtocolStore.sessionStore,
            identityManager: self.identityManager,
            observers: RecipientMergerImpl.buildObservers(
                authorMergeHelper: self.authorMergeHelper,
                callRecordStore: self.callRecordStore,
                chatColorSettingStore: self.chatColorSettingStore,
                disappearingMessagesConfigurationStore: self.disappearingMessagesConfigurationStore,
                groupMemberUpdater: self.groupMemberUpdater,
                groupMemberStore: groupMemberStore,
                interactionStore: interactionStore,
                profileManager: profileManager,
                recipientMergeNotifier: RecipientMergeNotifier(scheduler: schedulers.main),
                signalServiceAddressCache: signalServiceAddressCache,
                threadAssociatedDataStore: self.threadAssociatedDataStore,
                threadRemover: self.threadRemover,
                threadReplyInfoStore: self.threadReplyInfoStore,
                threadStore: threadStore,
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
            identityManager: PniHelloWorldManagerImpl.Wrappers.IdentityManager(identityManager),
            keyValueStoreFactory: keyValueStoreFactory,
            networkManager: PniHelloWorldManagerImpl.Wrappers.NetworkManager(networkManager),
            pniDistributionParameterBuilder: pniDistributionParameterBuilder,
            pniSignedPreKeyStore: pniProtocolStore.signedPreKeyStore,
            pniKyberPreKeyStore: pniProtocolStore.kyberPreKeyStore,
            profileManager: PniHelloWorldManagerImpl.Wrappers.ProfileManager(profileManager),
            schedulers: schedulers,
            signalRecipientStore: PniHelloWorldManagerImpl.Wrappers.SignalRecipientStore(),
            tsAccountManager: tsAccountManager
        )

        let preKeyOperationFactory: PreKeyOperationFactory = PreKeyOperationFactoryImpl(
            context: .init(
                dateProvider: dateProvider,
                db: db,
                identityManager: PreKey.Operation.Wrappers.IdentityManager(identityManager: identityManager),
                linkedDevicePniKeyManager: linkedDevicePniKeyManager,
                messageProcessor: PreKey.Operation.Wrappers.MessageProcessor(messageProcessor: messageProcessor),
                protocolStoreManager: signalProtocolStoreManager,
                schedulers: schedulers,
                serviceClient: accountServiceClient,
                tsAccountManager: tsAccountManager
            )
        )
        self.preKeyManager = PreKeyManagerImpl(
            db: db,
            identityManager: PreKey.Manager.Wrappers.IdentityManager(identityManager),
            messageProcessor: PreKey.Manager.Wrappers.MessageProcessor(messageProcessor: messageProcessor),
            preKeyOperationFactory: preKeyOperationFactory,
            protocolStoreManager: signalProtocolStoreManager
        )

        self.learnMyOwnPniManager = LearnMyOwnPniManagerImpl(
            accountServiceClient: LearnMyOwnPniManagerImpl.Wrappers.AccountServiceClient(accountServiceClient),
            db: db,
            keyValueStoreFactory: keyValueStoreFactory,
            pniIdentityKeyChecker: pniIdentityKeyChecker,
            preKeyManager: preKeyManager,
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
            jobQueues: jobQueues
        )

        self.signalProtocolStoreManager = signalProtocolStoreManager

        self.subscriptionReceiptCredentialResultStore = SubscriptionReceiptCredentialResultStoreImpl(
            kvStoreFactory: keyValueStoreFactory
        )

        self.usernameApiClient = UsernameApiClientImpl(
            networkManager: UsernameApiClientImpl.Wrappers.NetworkManager(networkManager: networkManager),
            schedulers: schedulers
        )
        self.usernameLookupManager = UsernameLookupManagerImpl()
        self.usernameEducationManager = UsernameEducationManagerImpl(keyValueStoreFactory: keyValueStoreFactory)
        self.usernameLinkManager = UsernameLinkManagerImpl(
            db: db,
            apiClient: usernameApiClient,
            schedulers: schedulers
        )
        self.localUsernameManager = LocalUsernameManagerImpl(
            db: db,
            kvStoreFactory: keyValueStoreFactory,
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

        self.cloudBackupManager = CloudBackupManagerImpl(
            chatArchiver: CloudBackupChatArchiverImpl(
                dmConfigurationStore: disappearingMessagesConfigurationStore,
                threadFetcher: CloudBackup.Wrappers.TSThreadFetcher()
            ),
            dateProvider: dateProvider,
            db: db,
            dmConfigurationStore: disappearingMessagesConfigurationStore,
            recipientArchiver: CloudBackupRecipientArchiverImpl(
                blockingManager: CloudBackup.Wrappers.BlockingManager(blockingManager),
                groupsV2: groupsV2,
                profileManager: CloudBackup.Wrappers.ProfileManager(profileManager),
                recipientHidingManager: recipientHidingManager,
                signalRecipientFetcher: CloudBackup.Wrappers.SignalRecipientFetcher(),
                storyFinder: CloudBackup.Wrappers.StoryFinder(),
                tsAccountManager: tsAccountManager,
                tsThreadFetcher: CloudBackup.Wrappers.TSThreadFetcher()
            ),
            streamProvider: CloudBackupProtoStreamProviderImpl(),
            tsAccountManager: tsAccountManager,
            tsInteractionFetcher: CloudBackup.Wrappers.TSInteractionFetcher(),
            tsThreadFetcher: CloudBackup.Wrappers.TSThreadFetcher()
        )

        self.socketManager = SocketManagerImpl(appExpiry: appExpiry, db: db)
    }
}
