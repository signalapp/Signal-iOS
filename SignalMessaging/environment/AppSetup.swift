//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SignalServiceKit

public enum AppSetupError: Error {
    // no errors for now, but some will be added in the future
}

public enum AppSetup {
    public static func setUpEnvironment(
        paymentsEvents: PaymentsEvents,
        mobileCoinHelper: MobileCoinHelper,
        webSocketFactory: WebSocketFactory,
        extensionSpecificSingletonBlock: () -> Void
    ) -> Guarantee<AppSetupError?> {

        configureUnsatisfiableConstraintLogging()

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

        // MARK: DependenciesBridge

        let accountServiceClient = AccountServiceClient()
        let identityManager = OWSIdentityManager(databaseStorage: databaseStorage)
        let messageProcessor = MessageProcessor()
        let messageSender = MessageSender()
        let networkManager = NetworkManager()
        let ows2FAManager = OWS2FAManager()
        let pniSignalProtocolStore = SignalProtocolStore(for: .pni)
        let signalService = OWSSignalService()
        let storageServiceManager = StorageServiceManagerImpl.shared
        let syncManager = OWSSyncManager(default: ())
        let tsAccountManager = TSAccountManager()

        DependenciesBridge.setupSingleton(
            accountServiceClient: accountServiceClient,
            databaseStorage: databaseStorage,
            identityManager: identityManager,
            messageProcessor: messageProcessor,
            messageSender: messageSender,
            networkManager: networkManager,
            ows2FAManager: ows2FAManager,
            pniProtocolStore: pniSignalProtocolStore,
            signalService: signalService,
            storageServiceManager: storageServiceManager,
            syncManager: syncManager,
            tsAccountManager: tsAccountManager
        )

        // MARK: SignalMessaging environment properties

        let launchJobs = LaunchJobs()
        let preferences = OWSPreferences()
        let proximityMonitoringManager = OWSProximityMonitoringManagerImpl()
        let sounds = OWSSounds()
        let orphanDataCleaner = OWSOrphanDataCleaner()
        let avatarBuilder = AvatarBuilder()
        let smJobQueues = SignalMessagingJobQueues()

        // MARK: SSK environment properties

        let contactsManager = OWSContactsManager(swiftValues: .makeWithValuesFromDependenciesBridge())
        let linkPreviewManager = OWSLinkPreviewManager()
        let pendingReceiptRecorder = MessageRequestPendingReceipts()
        let profileManager = OWSProfileManager(databaseStorage: databaseStorage)
        let messageManager = OWSMessageManager()
        let blockingManager = BlockingManager()
        let remoteConfigManager = ServiceRemoteConfigManager()
        let aciSignalProtocolStore = SignalProtocolStore(for: .aci)
        let udManager = OWSUDManagerImpl()
        let messageDecrypter = OWSMessageDecrypter()
        let groupsV2MessageProcessor = GroupsV2MessageProcessor()
        let socketManager = SocketManager()
        let disappearingMessagesJob = OWSDisappearingMessagesJob()
        let receiptManager = OWSReceiptManager()
        let outgoingReceiptManager = OWSOutgoingReceiptManager()
        let reachabilityManager = SSKReachabilityManagerImpl()
        let typingIndicators = TypingIndicatorsImpl()
        let attachmentDownloads = OWSAttachmentDownloads()
        let stickerManager = StickerManager()
        let signalServiceAddressCache = SignalServiceAddressCache()
        let sskPreferences = SSKPreferences()
        let groupsV2 = GroupsV2Impl()
        let groupV2Updates = GroupV2UpdatesImpl()
        let messageFetcherJob = MessageFetcherJob()
        let bulkProfileFetch = BulkProfileFetch()
        let versionedProfiles = VersionedProfilesImpl()
        let modelReadCaches = ModelReadCaches(factory: ModelReadCacheFactory())
        let earlyMessageManager = EarlyMessageManager()
        let messagePipelineSupervisor = MessagePipelineSupervisor.createStandardSupervisor()
        let appExpiry = AppExpiry()
        let paymentsHelper = PaymentsHelperImpl()
        let paymentsCurrencies = PaymentsCurrenciesImpl()
        let spamChallengeResolver = SpamChallengeResolver()
        let senderKeyStore = SenderKeyStore()
        let phoneNumberUtil = PhoneNumberUtil()
        let legacyChangePhoneNumber = LegacyChangePhoneNumber()
        let subscriptionManager = SubscriptionManagerImpl()
        let systemStoryManager = SystemStoryManager()
        let remoteMegaphoneFetcher = RemoteMegaphoneFetcher()
        let sskJobQueues = SSKJobQueues()
        let contactDiscoveryManager = ContactDiscoveryManagerImpl()

        Environment.shared = Environment(
            launchJobs: launchJobs,
            preferences: preferences,
            proximityMonitoringManager: proximityMonitoringManager,
            sounds: sounds,
            orphanDataCleaner: orphanDataCleaner,
            avatarBuilder: avatarBuilder,
            smJobQueues: smJobQueues
        )

        SSKEnvironment.setShared(SSKEnvironment(
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
            contactDiscoveryManager: contactDiscoveryManager
        ))

        extensionSpecificSingletonBlock()

        owsAssertDebug(SSKEnvironment.shared.isComplete())

        // Register renamed classes.
        NSKeyedUnarchiver.setClass(OWSUserProfile.self, forClassName: OWSUserProfile.collection())
        NSKeyedUnarchiver.setClass(OWSGroupInfoRequestMessage.self, forClassName: "OWSSyncGroupsRequestMessage")
        NSKeyedUnarchiver.setClass(TSGroupModelV2.self, forClassName: "TSGroupModelV2")

        // Prevent device from sleeping during migrations.
        // This protects long migrations from the iOS 13 background crash.
        //
        // We can use any object.
        let sleepBlockObject = NSObject()
        DeviceSleepManager.shared.addBlock(blockObject: sleepBlockObject)

        let (guarantee, future) = Guarantee<AppSetupError?>.pending()
        DispatchQueue.global().async {
            if shouldTruncateGrdbWal() {
                // Try to truncate GRDB WAL before any readers or writers are active.
                do {
                    try databaseStorage.grdbStorage.syncTruncatingCheckpoint()
                } catch {
                    owsFailDebug("Failed to truncate database: \(error)")
                }
            }

            databaseStorage.runGrdbSchemaMigrationsOnMainDatabase {
                AssertIsOnMainThread()

                DeviceSleepManager.shared.removeBlock(blockObject: sleepBlockObject)
                SSKEnvironment.shared.warmCaches()
                future.resolve(nil)
                backgroundTask.end()

                // Do this after we've finished running database migrations.
                if DebugFlags.internalLogging {
                    DispatchQueue.global().async { SDSKeyValueStore.logCollectionStatistics() }
                }
            }
        }
        return guarantee
    }

    private static func configureUnsatisfiableConstraintLogging() {
        UserDefaults.standard.setValue(DebugFlags.internalLogging, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
    }

    private static func shouldTruncateGrdbWal() -> Bool {
        guard CurrentAppContext().isMainApp else {
            return false
        }
        guard CurrentAppContext().mainApplicationStateOnLaunch() != .background else {
            return false
        }
        return true
    }
}
