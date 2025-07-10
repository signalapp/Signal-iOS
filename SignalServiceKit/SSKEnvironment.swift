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

    public static func setShared(_ env: SSKEnvironment?, isRunningTests: Bool) {
        owsPrecondition((_shared == nil && env != nil) || isRunningTests)
        _shared = env
    }

    #if TESTABLE_BUILD
    private(set) public var contactManagerRef: any ContactManager
    private(set) public var messageSenderRef: MessageSender
    private(set) public var networkManagerRef: NetworkManager
    private(set) public var paymentsHelperRef: PaymentsHelperSwift
    private(set) public var groupsV2Ref: GroupsV2
    #else
    public let contactManagerRef: any ContactManager
    public let messageSenderRef: MessageSender
    public let networkManagerRef: NetworkManager
    public let paymentsHelperRef: PaymentsHelperSwift
    public let groupsV2Ref: GroupsV2
    #endif
    /// This should be deprecated.
    public var contactManagerImplRef: OWSContactsManager { contactManagerRef as! OWSContactsManager }
    @objc
    public var contactManagerObjcRef: ContactsManagerProtocol { contactManagerRef }

    public let pendingReceiptRecorderRef: PendingReceiptRecorder
    public let profileManagerRef: ProfileManager
    /// This should be deprecated.
    public var profileManagerImplRef: OWSProfileManager { profileManagerRef as! OWSProfileManager }
    public let messageReceiverRef: MessageReceiver
    public let blockingManagerRef: BlockingManager
    public let remoteConfigManagerRef: RemoteConfigManager
    public let udManagerRef: OWSUDManager
    public let messageDecrypterRef: OWSMessageDecrypter
    public let groupMessageProcessorManagerRef: GroupMessageProcessorManager
    public let ows2FAManagerRef: OWS2FAManager
    @objc
    public let disappearingMessagesJobRef: OWSDisappearingMessagesJob
    @objc
    public let receiptManagerRef: OWSReceiptManager
    @objc
    public let receiptSenderRef: ReceiptSender
    public let reachabilityManagerRef: SSKReachabilityManager
    public let syncManagerRef: SyncManagerProtocol
    public let typingIndicatorsRef: TypingIndicators
    public let stickerManagerRef: StickerManager
    @objc
    public let databaseStorageRef: SDSDatabaseStorage
    public let signalServiceAddressCacheRef: SignalServiceAddressCache
    public let signalServiceRef: OWSSignalServiceProtocol
    public let storageServiceManagerRef: StorageServiceManager
    public let sskPreferencesRef: SSKPreferences
    public let groupV2UpdatesRef: GroupV2Updates
    public let messageFetcherJobRef: MessageFetcherJob
    public let versionedProfilesRef: VersionedProfiles
    @objc
    public let modelReadCachesRef: ModelReadCaches
    public let earlyMessageManagerRef: EarlyMessageManager
    public let messagePipelineSupervisorRef: MessagePipelineSupervisor
    public let messageProcessorRef: MessageProcessor
    public let paymentsCurrenciesRef: PaymentsCurrenciesSwift
    @objc
    public let paymentsEventsRef: PaymentsEvents
    public let owsPaymentsLockRef: OWSPaymentsLock
    public let mobileCoinHelperRef: MobileCoinHelper
    public let spamChallengeResolverRef: SpamChallengeResolver
    public let senderKeyStoreRef: SenderKeyStore
    public let phoneNumberUtilRef: PhoneNumberUtil
    public let webSocketFactoryRef: WebSocketFactory
    public let systemStoryManagerRef: SystemStoryManagerProtocol
    public let contactDiscoveryManagerRef: ContactDiscoveryManager
    public let notificationPresenterRef: any NotificationPresenter
    public let messageSendLogRef: MessageSendLog
    public let preferencesRef: Preferences
    public let proximityMonitoringManagerRef: OWSProximityMonitoringManager
    public let avatarBuilderRef: AvatarBuilder
    public let smJobQueuesRef: SignalMessagingJobQueues
    public let groupCallManagerRef: GroupCallManager
    public let profileFetcherRef: any ProfileFetcher

    public let messageSenderJobQueueRef: MessageSenderJobQueue
    public let localUserLeaveGroupJobQueueRef: LocalUserLeaveGroupJobQueue
    public let callRecordDeleteAllJobQueueRef: CallRecordDeleteAllJobQueue
    public let bulkDeleteInteractionJobQueueRef: BulkDeleteInteractionJobQueue
    let backupReceiptCredentialRedemptionJobQueue: BackupReceiptCredentialRedemptionJobQueue
    let donationReceiptCredentialRedemptionJobQueue: DonationReceiptCredentialRedemptionJobQueue

    private let appExpiryRef: AppExpiry
    private let aciSignalProtocolStoreRef: SignalProtocolStore
    private let pniSignalProtocolStoreRef: SignalProtocolStore

    init(
        contactManager: any ContactManager,
        messageSender: MessageSender,
        pendingReceiptRecorder: PendingReceiptRecorder,
        profileManager: ProfileManager,
        networkManager: NetworkManager,
        messageReceiver: MessageReceiver,
        blockingManager: BlockingManager,
        remoteConfigManager: RemoteConfigManager,
        aciSignalProtocolStore: SignalProtocolStore,
        pniSignalProtocolStore: SignalProtocolStore,
        udManager: OWSUDManager,
        messageDecrypter: OWSMessageDecrypter,
        groupMessageProcessorManager: GroupMessageProcessorManager,
        ows2FAManager: OWS2FAManager,
        disappearingMessagesJob: OWSDisappearingMessagesJob,
        receiptManager: OWSReceiptManager,
        receiptSender: ReceiptSender,
        reachabilityManager: SSKReachabilityManager,
        syncManager: SyncManagerProtocol,
        typingIndicators: TypingIndicators,
        stickerManager: StickerManager,
        databaseStorage: SDSDatabaseStorage,
        signalServiceAddressCache: SignalServiceAddressCache,
        signalService: OWSSignalServiceProtocol,
        storageServiceManager: StorageServiceManager,
        sskPreferences: SSKPreferences,
        groupsV2: GroupsV2,
        groupV2Updates: GroupV2Updates,
        messageFetcherJob: MessageFetcherJob,
        versionedProfiles: VersionedProfiles,
        modelReadCaches: ModelReadCaches,
        earlyMessageManager: EarlyMessageManager,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        appExpiry: AppExpiry,
        messageProcessor: MessageProcessor,
        paymentsHelper: PaymentsHelperSwift,
        paymentsCurrencies: PaymentsCurrenciesSwift,
        paymentsEvents: PaymentsEvents,
        paymentsLock: OWSPaymentsLock,
        mobileCoinHelper: MobileCoinHelper,
        spamChallengeResolver: SpamChallengeResolver,
        senderKeyStore: SenderKeyStore,
        phoneNumberUtil: PhoneNumberUtil,
        webSocketFactory: WebSocketFactory,
        systemStoryManager: SystemStoryManagerProtocol,
        contactDiscoveryManager: ContactDiscoveryManager,
        notificationPresenter: any NotificationPresenter,
        messageSendLog: MessageSendLog,
        messageSenderJobQueue: MessageSenderJobQueue,
        localUserLeaveGroupJobQueue: LocalUserLeaveGroupJobQueue,
        callRecordDeleteAllJobQueue: CallRecordDeleteAllJobQueue,
        bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue,
        backupReceiptCredentialRedemptionJobQueue: BackupReceiptCredentialRedemptionJobQueue,
        donationReceiptCredentialRedemptionJobQueue: DonationReceiptCredentialRedemptionJobQueue,
        preferences: Preferences,
        proximityMonitoringManager: OWSProximityMonitoringManager,
        avatarBuilder: AvatarBuilder,
        smJobQueues: SignalMessagingJobQueues,
        groupCallManager: GroupCallManager,
        profileFetcher: any ProfileFetcher
    ) {
        self.contactManagerRef = contactManager
        self.messageSenderRef = messageSender
        self.pendingReceiptRecorderRef = pendingReceiptRecorder
        self.profileManagerRef = profileManager
        self.networkManagerRef = networkManager
        self.messageReceiverRef = messageReceiver
        self.blockingManagerRef = blockingManager
        self.remoteConfigManagerRef = remoteConfigManager
        self.aciSignalProtocolStoreRef = aciSignalProtocolStore
        self.pniSignalProtocolStoreRef = pniSignalProtocolStore
        self.udManagerRef = udManager
        self.messageDecrypterRef = messageDecrypter
        self.groupMessageProcessorManagerRef = groupMessageProcessorManager
        self.ows2FAManagerRef = ows2FAManager
        self.disappearingMessagesJobRef = disappearingMessagesJob
        self.receiptManagerRef = receiptManager
        self.receiptSenderRef = receiptSender
        self.syncManagerRef = syncManager
        self.reachabilityManagerRef = reachabilityManager
        self.typingIndicatorsRef = typingIndicators
        self.stickerManagerRef = stickerManager
        self.databaseStorageRef = databaseStorage
        self.signalServiceAddressCacheRef = signalServiceAddressCache
        self.signalServiceRef = signalService
        self.storageServiceManagerRef = storageServiceManager
        self.sskPreferencesRef = sskPreferences
        self.groupsV2Ref = groupsV2
        self.groupV2UpdatesRef = groupV2Updates
        self.messageFetcherJobRef = messageFetcherJob
        self.versionedProfilesRef = versionedProfiles
        self.modelReadCachesRef = modelReadCaches
        self.earlyMessageManagerRef = earlyMessageManager
        self.messagePipelineSupervisorRef = messagePipelineSupervisor
        self.appExpiryRef = appExpiry
        self.messageProcessorRef = messageProcessor
        self.paymentsHelperRef = paymentsHelper
        self.paymentsCurrenciesRef = paymentsCurrencies
        self.paymentsEventsRef = paymentsEvents
        self.owsPaymentsLockRef = paymentsLock
        self.mobileCoinHelperRef = mobileCoinHelper
        self.spamChallengeResolverRef = spamChallengeResolver
        self.senderKeyStoreRef = senderKeyStore
        self.phoneNumberUtilRef = phoneNumberUtil
        self.webSocketFactoryRef = webSocketFactory
        self.systemStoryManagerRef = systemStoryManager
        self.contactDiscoveryManagerRef = contactDiscoveryManager
        self.notificationPresenterRef = notificationPresenter
        self.messageSendLogRef = messageSendLog
        self.messageSenderJobQueueRef = messageSenderJobQueue
        self.localUserLeaveGroupJobQueueRef = localUserLeaveGroupJobQueue
        self.callRecordDeleteAllJobQueueRef = callRecordDeleteAllJobQueue
        self.bulkDeleteInteractionJobQueueRef = bulkDeleteInteractionJobQueue
        self.backupReceiptCredentialRedemptionJobQueue = backupReceiptCredentialRedemptionJobQueue
        self.donationReceiptCredentialRedemptionJobQueue = donationReceiptCredentialRedemptionJobQueue
        self.preferencesRef = preferences
        self.proximityMonitoringManagerRef = proximityMonitoringManager
        self.avatarBuilderRef = avatarBuilder
        self.smJobQueuesRef = smJobQueues
        self.groupCallManagerRef = groupCallManager
        self.profileFetcherRef = profileFetcher
    }

    public func signalProtocolStoreRef(for identity: OWSIdentity) -> SignalProtocolStore {
        switch identity {
        case .aci:
            return aciSignalProtocolStoreRef
        case .pni:
            return pniSignalProtocolStoreRef
        }
    }

    /// Warms (or re-warms) various caches throughout the app.
    ///
    /// This may be called multiple times within a single process.
    ///
    /// Re-warming helps ensure the NSE sees the same state as the Main App.
    @MainActor
    public func warmCaches(appReadiness: AppReadiness, dependenciesBridge: DependenciesBridge) {
        // Note: All of these methods must be safe to invoke repeatedly.

        dependenciesBridge.tsAccountManager.warmCaches()
        let remoteConfig = self.remoteConfigManagerRef.warmCaches()
        self.verifyPniAndPniIdentityKey(
            dependenciesBridge: dependenciesBridge,
            remoteConfig: remoteConfig,
        )
        self.fixLocalRecipientIfNeeded(dependenciesBridge: dependenciesBridge)
        SignalProxy.warmCaches(appReadiness: appReadiness)
        self.signalServiceRef.warmCaches()
        self.profileManagerRef.warmCaches()
        self.receiptManagerRef.prepareCachedValues()
        dependenciesBridge.svr.warmCaches()
        self.typingIndicatorsRef.warmCaches()
        self.paymentsHelperRef.warmCaches()
        self.paymentsCurrenciesRef.warmCaches()
        StoryManager.setup(appReadiness: appReadiness)
        DonationSubscriptionManager.warmCaches()
        dependenciesBridge.db.read { tx in appExpiryRef.warmCaches(with: tx) }
    }

    @MainActor
    private func verifyPniAndPniIdentityKey(dependenciesBridge: DependenciesBridge, remoteConfig: RemoteConfig) {
        let databaseStorage = self.databaseStorageRef
        let tsAccountManager = dependenciesBridge.tsAccountManager

        guard remoteConfig.shouldVerifyPniAndPniIdentityKeyExist else {
            return
        }

        let mustHavePni: Bool
        let mustHavePniIdentityKey: Bool
        switch tsAccountManager.registrationStateWithMaybeSneakyTransaction {
        case .provisioned:
            mustHavePni = true
            mustHavePniIdentityKey = true
        case .registered:
            mustHavePni = true
            mustHavePniIdentityKey = true
        default:
            mustHavePni = false
            mustHavePniIdentityKey = false
        }

        guard mustHavePni || mustHavePniIdentityKey else {
            return
        }

        let (hasPni, hasPniIdentityKey) = databaseStorage.read { tx -> (Bool, Bool) in
            let hasPni = tsAccountManager.localIdentifiers(tx: tx)!.pni != nil
            let hasPniIdentityKey = dependenciesBridge.identityManager.identityKeyPair(for: .pni, tx: tx) != nil
            return (hasPni, hasPniIdentityKey)
        }

        if (!hasPni && mustHavePni) || (!hasPniIdentityKey && mustHavePniIdentityKey) {
            Logger.warn("Deregistering because PNI state is missing (hasPni: \(hasPni); hasPniIdentityKey: \(hasPniIdentityKey))")
            databaseStorage.write { tx in
                dependenciesBridge.registrationStateChangeManager.setIsDeregisteredOrDelinked(true, tx: tx)
            }
        }
    }

    /// Ensures the local SignalRecipient is correct.
    ///
    /// This primarily serves to ensure the local SignalRecipient has its own
    /// Pni (a one-time migration), but it also helps ensure that the value is
    /// always consistent with TSAccountManager's values.
    private func fixLocalRecipientIfNeeded(dependenciesBridge: DependenciesBridge) {
        self.databaseStorageRef.write { tx in
            guard let localIdentifiers = dependenciesBridge.tsAccountManager.localIdentifiers(tx: tx) else {
                return  // Not registered yet.
            }
            guard let phoneNumber = E164(localIdentifiers.phoneNumber) else {
                return  // Registered with an invalid phone number.
            }
            let recipientMerger = dependenciesBridge.recipientMerger
            _ = recipientMerger.applyMergeForLocalAccount(
                aci: localIdentifiers.aci,
                phoneNumber: phoneNumber,
                pni: localIdentifiers.pni,
                tx: tx
            )
        }
    }

    #if TESTABLE_BUILD

    public func setContactManagerForUnitTests(_ contactManager: any ContactManager) {
        self.contactManagerRef = contactManager
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

    public func setGroupsV2ForUnitTests(_ groupsV2: GroupsV2) {
        self.groupsV2Ref = groupsV2
    }

    #endif
}
