//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class SSKEnvironment: NSObject {

    private static var _shared: SSKEnvironment?

    public static var hasShared: Bool { _shared != nil }

    @objc
    public static var shared: SSKEnvironment { _shared! }

    public static func setShared(_ env: SSKEnvironment, isRunningTests: Bool) {
        owsAssert(_shared == nil || isRunningTests)
        _shared = env
    }

    #if TESTABLE_BUILD
    private(set) public var contactsManagerRef: ContactsManagerProtocol
    private(set) public var messageSenderRef: MessageSender
    private(set) public var networkManagerRef: NetworkManager
    private(set) public var paymentsHelperRef: PaymentsHelperSwift
    private(set) public var groupsV2Ref: GroupsV2Swift
    #else
    public let contactsManagerRef: ContactsManagerProtocol
    public let messageSenderRef: MessageSender
    public let networkManagerRef: NetworkManager
    public let paymentsHelperRef: PaymentsHelperSwift
    public let tsAccountManagerRef: TSAccountManager
    public let groupsV2Ref: GroupsV2Swift
    #endif

    public let linkPreviewManagerRef: OWSLinkPreviewManager
    public let pendingReceiptRecorderRef: PendingReceiptRecorder
    public let profileManagerRef: ProfileManagerProtocol
    public let messageManagerRef: OWSMessageManager
    public let blockingManagerRef: BlockingManager
    public let remoteConfigManagerRef: RemoteConfigManager
    public let udManagerRef: OWSUDManager
    public let messageDecrypterRef: OWSMessageDecrypter
    public let groupsV2MessageProcessorRef: GroupsV2MessageProcessor
    public let socketManagerRef: SocketManager
    public let ows2FAManagerRef: OWS2FAManager
    public let disappearingMessagesJobRef: OWSDisappearingMessagesJob
    public let receiptManagerRef: OWSReceiptManager
    public let outgoingReceiptManagerRef: OWSOutgoingReceiptManager
    public let reachabilityManagerRef: SSKReachabilityManager
    public let syncManagerRef: SyncManagerProtocol
    public let typingIndicatorsRef: TypingIndicators
    public let attachmentDownloadsRef: OWSAttachmentDownloads
    public let stickerManagerRef: StickerManager
    public let databaseStorageRef: SDSDatabaseStorage
    public let signalServiceAddressCacheRef: SignalServiceAddressCache
    public let signalServiceRef: OWSSignalServiceProtocol
    public let accountServiceClientRef: AccountServiceClient
    public let storageServiceManagerRef: StorageServiceManager
    public let storageCoordinatorRef: StorageCoordinator
    public let sskPreferencesRef: SSKPreferences
    public let groupV2UpdatesRef: GroupV2UpdatesSwift
    public let messageFetcherJobRef: MessageFetcherJob
    public let bulkProfileFetchRef: BulkProfileFetch
    public let versionedProfilesRef: VersionedProfilesSwift
    public let modelReadCachesRef: ModelReadCaches
    public let earlyMessageManagerRef: EarlyMessageManager
    public let messagePipelineSupervisorRef: MessagePipelineSupervisor
    public let messageProcessorRef: MessageProcessor
    public let paymentsCurrenciesRef: PaymentsCurrenciesSwift
    public let paymentsEventsRef: PaymentsEvents
    public let mobileCoinHelperRef: MobileCoinHelper
    public let spamChallengeResolverRef: SpamChallengeResolver
    public let senderKeyStoreRef: SenderKeyStore
    public let phoneNumberUtilRef: PhoneNumberUtil
    public let webSocketFactoryRef: WebSocketFactory
    public let legacyChangePhoneNumberRef: LegacyChangePhoneNumber
    public let subscriptionManagerRef: SubscriptionManager
    public let systemStoryManagerRef: SystemStoryManagerProtocol
    public let remoteMegaphoneFetcherRef: RemoteMegaphoneFetcher
    public let sskJobQueuesRef: SSKJobQueues
    public let contactDiscoveryManagerRef: ContactDiscoveryManager
    public let callMessageHandlerRef: OWSCallMessageHandler
    public let notificationsManagerRef: NotificationsProtocol
    public let messageSendLogRef: MessageSendLog

    private let appExpiryRef: AppExpiry
    private let aciSignalProtocolStoreRef: SignalProtocolStore
    private let pniSignalProtocolStoreRef: SignalProtocolStore

    public init(
        contactsManager: ContactsManagerProtocol,
        linkPreviewManager: OWSLinkPreviewManager,
        messageSender: MessageSender,
        pendingReceiptRecorder: PendingReceiptRecorder,
        profileManager: ProfileManagerProtocol,
        networkManager: NetworkManager,
        messageManager: OWSMessageManager,
        blockingManager: BlockingManager,
        remoteConfigManager: RemoteConfigManager,
        aciSignalProtocolStore: SignalProtocolStore,
        pniSignalProtocolStore: SignalProtocolStore,
        udManager: OWSUDManager,
        messageDecrypter: OWSMessageDecrypter,
        groupsV2MessageProcessor: GroupsV2MessageProcessor,
        socketManager: SocketManager,
        ows2FAManager: OWS2FAManager,
        disappearingMessagesJob: OWSDisappearingMessagesJob,
        receiptManager: OWSReceiptManager,
        outgoingReceiptManager: OWSOutgoingReceiptManager,
        reachabilityManager: SSKReachabilityManager,
        syncManager: SyncManagerProtocol,
        typingIndicators: TypingIndicators,
        attachmentDownloads: OWSAttachmentDownloads,
        stickerManager: StickerManager,
        databaseStorage: SDSDatabaseStorage,
        signalServiceAddressCache: SignalServiceAddressCache,
        signalService: OWSSignalServiceProtocol,
        accountServiceClient: AccountServiceClient,
        storageServiceManager: StorageServiceManager,
        storageCoordinator: StorageCoordinator,
        sskPreferences: SSKPreferences,
        groupsV2: GroupsV2Swift,
        groupV2Updates: GroupV2UpdatesSwift,
        messageFetcherJob: MessageFetcherJob,
        bulkProfileFetch: BulkProfileFetch,
        versionedProfiles: VersionedProfilesSwift,
        modelReadCaches: ModelReadCaches,
        earlyMessageManager: EarlyMessageManager,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        appExpiry: AppExpiry,
        messageProcessor: MessageProcessor,
        paymentsHelper: PaymentsHelperSwift,
        paymentsCurrencies: PaymentsCurrenciesSwift,
        paymentsEvents: PaymentsEvents,
        mobileCoinHelper: MobileCoinHelper,
        spamChallengeResolver: SpamChallengeResolver,
        senderKeyStore: SenderKeyStore,
        phoneNumberUtil: PhoneNumberUtil,
        webSocketFactory: WebSocketFactory,
        legacyChangePhoneNumber: LegacyChangePhoneNumber,
        subscriptionManager: SubscriptionManager,
        systemStoryManager: SystemStoryManagerProtocol,
        remoteMegaphoneFetcher: RemoteMegaphoneFetcher,
        sskJobQueues: SSKJobQueues,
        contactDiscoveryManager: ContactDiscoveryManager,
        callMessageHandler: OWSCallMessageHandler,
        notificationsManager: NotificationsProtocol,
        messageSendLog: MessageSendLog
    ) {
        self.contactsManagerRef = contactsManager
        self.linkPreviewManagerRef = linkPreviewManager
        self.messageSenderRef = messageSender
        self.pendingReceiptRecorderRef = pendingReceiptRecorder
        self.profileManagerRef = profileManager
        self.networkManagerRef = networkManager
        self.messageManagerRef = messageManager
        self.blockingManagerRef = blockingManager
        self.remoteConfigManagerRef = remoteConfigManager
        self.aciSignalProtocolStoreRef = aciSignalProtocolStore
        self.pniSignalProtocolStoreRef = pniSignalProtocolStore
        self.udManagerRef = udManager
        self.messageDecrypterRef = messageDecrypter
        self.groupsV2MessageProcessorRef = groupsV2MessageProcessor
        self.socketManagerRef = socketManager
        self.ows2FAManagerRef = ows2FAManager
        self.disappearingMessagesJobRef = disappearingMessagesJob
        self.receiptManagerRef = receiptManager
        self.outgoingReceiptManagerRef = outgoingReceiptManager
        self.syncManagerRef = syncManager
        self.reachabilityManagerRef = reachabilityManager
        self.typingIndicatorsRef = typingIndicators
        self.attachmentDownloadsRef = attachmentDownloads
        self.stickerManagerRef = stickerManager
        self.databaseStorageRef = databaseStorage
        self.signalServiceAddressCacheRef = signalServiceAddressCache
        self.signalServiceRef = signalService
        self.accountServiceClientRef = accountServiceClient
        self.storageServiceManagerRef = storageServiceManager
        self.storageCoordinatorRef = storageCoordinator
        self.sskPreferencesRef = sskPreferences
        self.groupsV2Ref = groupsV2
        self.groupV2UpdatesRef = groupV2Updates
        self.messageFetcherJobRef = messageFetcherJob
        self.bulkProfileFetchRef = bulkProfileFetch
        self.versionedProfilesRef = versionedProfiles
        self.modelReadCachesRef = modelReadCaches
        self.earlyMessageManagerRef = earlyMessageManager
        self.messagePipelineSupervisorRef = messagePipelineSupervisor
        self.appExpiryRef = appExpiry
        self.messageProcessorRef = messageProcessor
        self.paymentsHelperRef = paymentsHelper
        self.paymentsCurrenciesRef = paymentsCurrencies
        self.paymentsEventsRef = paymentsEvents
        self.mobileCoinHelperRef = mobileCoinHelper
        self.spamChallengeResolverRef = spamChallengeResolver
        self.senderKeyStoreRef = senderKeyStore
        self.phoneNumberUtilRef = phoneNumberUtil
        self.webSocketFactoryRef = webSocketFactory
        self.legacyChangePhoneNumberRef = legacyChangePhoneNumber
        self.subscriptionManagerRef = subscriptionManager
        self.systemStoryManagerRef = systemStoryManager
        self.remoteMegaphoneFetcherRef = remoteMegaphoneFetcher
        self.sskJobQueuesRef = sskJobQueues
        self.contactDiscoveryManagerRef = contactDiscoveryManager
        self.callMessageHandlerRef = callMessageHandler
        self.notificationsManagerRef = notificationsManager
        self.messageSendLogRef = messageSendLog
    }

    public func signalProtocolStoreRef(for identity: OWSIdentity) -> SignalProtocolStore {
        switch identity {
        case .aci:
            return aciSignalProtocolStoreRef
        case .pni:
            return pniSignalProtocolStoreRef
        }
    }

    public static let warmCachesNotification = Notification.Name("WarmCachesNotification")

    public func warmCaches() {
        let warmCachesForObject: (String, () -> Void) -> Void = { name, action in
            InstrumentsMonitor.measure(category: "appstart", parent: "caches", name: name, block: action)
        }
        warmCachesForObject("signalProxy", SignalProxy.warmCaches)
        warmCachesForObject("newTSAccountManager", DependenciesBridge.shared.tsAccountManager.warmCaches)
        warmCachesForObject("fixLocalRecipient", fixLocalRecipientIfNeeded)
        warmCachesForObject("signalServiceAddressCache", signalServiceAddressCache.warmCaches)
        warmCachesForObject("signalService", signalService.warmCaches)
        warmCachesForObject("remoteConfigManager", remoteConfigManager.warmCaches)
        warmCachesForObject("blockingManager", blockingManager.warmCaches)
        warmCachesForObject("profileManager", profileManager.warmCaches)
        warmCachesForObject("receiptManager", receiptManager.prepareCachedValues)
        warmCachesForObject("OWSKeyBackupService", DependenciesBridge.shared.svr.warmCaches)
        warmCachesForObject("PinnedThreadManager", PinnedThreadManager.warmCaches)
        warmCachesForObject("typingIndicatorsImpl", typingIndicatorsImpl.warmCaches)
        warmCachesForObject("paymentsHelper", paymentsHelper.warmCaches)
        warmCachesForObject("paymentsCurrencies", paymentsCurrencies.warmCaches)
        warmCachesForObject("storyManager", StoryManager.setup)
        warmCachesForObject("deviceManager", DependenciesBridge.shared.deviceManager.warmCaches)
        warmCachesForObject("appExpiry") {
            DependenciesBridge.shared.db.read { tx in
                self.appExpiryRef.warmCaches(with: tx)
            }
        }

        NotificationCenter.default.post(name: SSKEnvironment.warmCachesNotification, object: nil)
    }

    /// Ensures the local SignalRecipient is correct.
    ///
    /// This primarily serves to ensure the local SignalRecipient has its own
    /// Pni (a one-time migration), but it also helps ensure that the value is
    /// always consistent with TSAccountManager's values.
    private func fixLocalRecipientIfNeeded() {
        databaseStorage.write { tx in
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: tx.asV2Read) else {
                return  // Not registered yet.
            }
            guard let phoneNumber = E164(localIdentifiers.phoneNumber) else {
                return  // Registered with an invalid phone number.
            }
            let recipientMerger = DependenciesBridge.shared.recipientMerger
            _ = recipientMerger.applyMergeForLocalAccount(
                aci: localIdentifiers.aci,
                phoneNumber: phoneNumber,
                pni: localIdentifiers.pni,
                tx: tx.asV2Write
            )
        }
    }

    #if TESTABLE_BUILD

    public func setContactsManagerForUnitTests(_ contactsManager: ContactsManagerProtocol) {
        self.contactsManagerRef = contactsManager
    }

    public func setMessageSenderForUnitTests(_ messageSender: MessageSender) {
        self.messageSenderRef = messageSender
    }

    public func setNetworkManagerForUnitTests(_ networkManager: NetworkManager) {
        self.networkManagerRef = networkManager
    }

    public func setPaymentsHelperForUnitTests(_ paymentsHelper: PaymentsHelperSwift) {
        self.paymentsHelperRef = paymentsHelper
    }

    @objc
    public func setGroupsV2ForUnitTests(_ groupsV2: GroupsV2) {
        self.groupsV2Ref = groupsV2 as! GroupsV2Swift
    }

    #endif
}
