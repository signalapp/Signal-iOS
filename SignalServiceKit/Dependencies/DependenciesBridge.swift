//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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

    #if TESTABLE_BUILD
    static var hasShared: Bool {
        return _shared != nil
    }
    #endif

    static func setShared(_ dependenciesBridge: DependenciesBridge?, isRunningTests: Bool) {
        owsPrecondition((_shared == nil && dependenciesBridge != nil) || isRunningTests)
        Self._shared = dependenciesBridge
    }

    public let accountAttributesUpdater: AccountAttributesUpdater
    public let adHocCallRecordManager: any AdHocCallRecordManager
    public let appExpiry: AppExpiry
    public let attachmentCloner: SignalAttachmentCloner
    public let attachmentContentValidator: AttachmentContentValidator
    public let attachmentDownloadManager: AttachmentDownloadManager
    public let attachmentDownloadStore: AttachmentDownloadStore
    public let attachmentManager: AttachmentManager
    public let attachmentStore: AttachmentStore
    public let attachmentThumbnailService: AttachmentThumbnailService
    public let attachmentUploadManager: AttachmentUploadManager
    public let attachmentValidationBackfillMigrator: AttachmentValidationBackfillMigrator
    public let attachmentViewOnceManager: AttachmentViewOnceManager
    public let audioWaveformManager: AudioWaveformManager
    public let authorMergeHelper: AuthorMergeHelper
    public let avatarDefaultColorManager: AvatarDefaultColorManager
    public let backgroundMessageFetcherFactory: BackgroundMessageFetcherFactory
    public let backupArchiveErrorPresenter: BackupArchiveErrorPresenter
    public let backupArchiveManager: BackupArchiveManager
    public let backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    public let backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress
    public let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    public let backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter
    public let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    public let backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner
    public let backupAttachmentUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter
    public let backupDisablingManager: BackupDisablingManager
    public let backupExportJob: BackupExportJob
    public let backupExportJobRunner: BackupExportJobRunner
    public let backupIdManager: BackupIdManager
    public let backupKeyMaterial: BackupKeyMaterial
    public let backupRequestManager: BackupRequestManager
    public let backupPlanManager: BackupPlanManager
    public let backupSubscriptionManager: BackupSubscriptionManager
    public let backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager
    public let badgeCountFetcher: BadgeCountFetcher
    public let callLinkStore: any CallLinkRecordStore
    public let callRecordDeleteManager: any CallRecordDeleteManager
    public let callRecordMissedCallManager: CallRecordMissedCallManager
    public let callRecordQuerier: CallRecordQuerier
    public let callRecordStore: CallRecordStore
    public let changePhoneNumberPniManager: ChangePhoneNumberPniManager
    public let chatColorSettingStore: ChatColorSettingStore
    public let chatConnectionManager: ChatConnectionManager
    public let contactShareManager: ContactShareManager
    public let currentCallProvider: any CurrentCallProvider
    public let databaseChangeObserver: DatabaseChangeObserver
    public let db: any DB
    public let deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager
    let deletedCallRecordStore: DeletedCallRecordStore
    let deleteForMeIncomingSyncMessageManager: DeleteForMeIncomingSyncMessageManager
    public let deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager
    public let deviceManager: OWSDeviceManager
    public let deviceService: OWSDeviceService
    public let deviceStore: OWSDeviceStore
    public let deviceSleepManager: (any DeviceSleepManager)?
    public let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore
    public let donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore
    public let editManager: EditManager
    public let editMessageStore: EditMessageStore
    public let externalPendingIDEALDonationStore: ExternalPendingIDEALDonationStore
    public let groupCallRecordManager: GroupCallRecordManager
    public let groupMemberStore: GroupMemberStore
    public let groupMemberUpdater: GroupMemberUpdater
    let groupSendEndorsementStore: any GroupSendEndorsementStore
    public let groupUpdateInfoMessageInserter: GroupUpdateInfoMessageInserter
    public let identityKeyMismatchManager: IdentityKeyMismatchManager
    public let identityManager: OWSIdentityManager
    public let inactiveLinkedDeviceFinder: InactiveLinkedDeviceFinder
    public let inactivePrimaryDeviceStore: InactivePrimaryDeviceStore
    let incomingCallEventSyncMessageManager: IncomingCallEventSyncMessageManager
    let incomingCallLogEventSyncMessageManager: IncomingCallLogEventSyncMessageManager
    public let incomingPniChangeNumberProcessor: IncomingPniChangeNumberProcessor
    public let incrementalMessageTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator
    public let individualCallRecordManager: IndividualCallRecordManager
    public let interactionDeleteManager: InteractionDeleteManager
    public let interactionStore: InteractionStore
    public let lastVisibleInteractionStore: LastVisibleInteractionStore
    public let linkAndSyncManager: LinkAndSyncManager
    public let linkPreviewManager: LinkPreviewManager
    public let linkPreviewSettingStore: LinkPreviewSettingStore
    public let linkPreviewSettingManager: any LinkPreviewSettingManager
    public let accountKeyStore: AccountKeyStore
    let localProfileChecker: LocalProfileChecker
    public let localUsernameManager: LocalUsernameManager
    public let masterKeySyncManager: MasterKeySyncManager
    public let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
    public let messageStickerManager: MessageStickerManager
    public let nicknameManager: any NicknameManager
    public let orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager
    public let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
    public let archivedPaymentStore: ArchivedPaymentStore
    public let phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager
    public let phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher
    public let pinnedThreadManager: PinnedThreadManager
    public let pinnedThreadStore: PinnedThreadStore
    public let preKeyManager: PreKeyManager
    public let privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager
    public let quotedReplyManager: QuotedReplyManager
    public let reactionStore: any ReactionStore
    public let recipientDatabaseTable: RecipientDatabaseTable
    public let recipientFetcher: RecipientFetcher
    public let recipientHidingManager: RecipientHidingManager
    public let recipientIdFinder: RecipientIdFinder
    public let recipientManager: any SignalRecipientManager
    public let recipientMerger: RecipientMerger
    public let registrationSessionManager: RegistrationSessionManager
    public let registrationStateChangeManager: RegistrationStateChangeManager
    public let searchableNameIndexer: SearchableNameIndexer
    public let sentMessageTranscriptReceiver: SentMessageTranscriptReceiver
    public let signalProtocolStoreManager: SignalProtocolStoreManager
    public let storageServiceRecordIkmCapabilityStore: StorageServiceRecordIkmCapabilityStore
    public let svr: SecureValueRecovery
    public let svrCredentialStorage: SVRAuthCredentialStorage
    public let storyRecipientManager: StoryRecipientManager
    public let storyRecipientStore: StoryRecipientStore
    public let svrLocalStorage: SVRLocalStorage
    public let threadAssociatedDataStore: ThreadAssociatedDataStore
    public let threadRemover: ThreadRemover
    public let threadReplyInfoStore: ThreadReplyInfoStore
    public let threadSoftDeleteManager: ThreadSoftDeleteManager
    public let threadStore: ThreadStore
    public let tsAccountManager: TSAccountManager
    public let usernameApiClient: UsernameApiClient
    public let usernameEducationManager: UsernameEducationManager
    public let usernameLinkManager: UsernameLinkManager
    public let usernameLookupManager: UsernameLookupManager
    public let usernameValidationManager: UsernameValidationManager
    public let wallpaperImageStore: WallpaperImageStore
    public let wallpaperStore: WallpaperStore

    init(
        accountAttributesUpdater: AccountAttributesUpdater,
        adHocCallRecordManager: any AdHocCallRecordManager,
        appExpiry: AppExpiry,
        attachmentCloner: SignalAttachmentCloner,
        attachmentContentValidator: AttachmentContentValidator,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentDownloadStore: AttachmentDownloadStore,
        attachmentManager: AttachmentManager,
        attachmentStore: AttachmentStore,
        attachmentThumbnailService: AttachmentThumbnailService,
        attachmentUploadManager: AttachmentUploadManager,
        attachmentValidationBackfillMigrator: AttachmentValidationBackfillMigrator,
        attachmentViewOnceManager: AttachmentViewOnceManager,
        audioWaveformManager: AudioWaveformManager,
        authorMergeHelper: AuthorMergeHelper,
        avatarDefaultColorManager: AvatarDefaultColorManager,
        backgroundMessageFetcherFactory: BackgroundMessageFetcherFactory,
        backupArchiveErrorPresenter: BackupArchiveErrorPresenter,
        backupArchiveManager: BackupArchiveManager,
        backupAttachmentDownloadManager: BackupAttachmentDownloadManager,
        backupAttachmentDownloadProgress: BackupAttachmentDownloadProgress,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupAttachmentDownloadQueueStatusReporter: BackupAttachmentDownloadQueueStatusReporter,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner,
        backupAttachmentUploadQueueStatusReporter: BackupAttachmentUploadQueueStatusReporter,
        backupDisablingManager: BackupDisablingManager,
        backupExportJob: BackupExportJob,
        backupExportJobRunner: BackupExportJobRunner,
        backupIdManager: BackupIdManager,
        backupKeyMaterial: BackupKeyMaterial,
        backupRequestManager: BackupRequestManager,
        backupPlanManager: BackupPlanManager,
        backupSubscriptionManager: BackupSubscriptionManager,
        backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager,
        badgeCountFetcher: BadgeCountFetcher,
        callLinkStore: any CallLinkRecordStore,
        callRecordDeleteManager: CallRecordDeleteManager,
        callRecordMissedCallManager: CallRecordMissedCallManager,
        callRecordQuerier: CallRecordQuerier,
        callRecordStore: CallRecordStore,
        changePhoneNumberPniManager: ChangePhoneNumberPniManager,
        chatColorSettingStore: ChatColorSettingStore,
        chatConnectionManager: ChatConnectionManager,
        contactShareManager: ContactShareManager,
        currentCallProvider: any CurrentCallProvider,
        databaseChangeObserver: DatabaseChangeObserver,
        db: any DB,
        deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager,
        deletedCallRecordStore: DeletedCallRecordStore,
        deleteForMeIncomingSyncMessageManager: DeleteForMeIncomingSyncMessageManager,
        deleteForMeOutgoingSyncMessageManager: DeleteForMeOutgoingSyncMessageManager,
        deviceManager: OWSDeviceManager,
        deviceService: OWSDeviceService,
        deviceSleepManager: (any DeviceSleepManager)?,
        deviceStore: OWSDeviceStore,
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore,
        donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore,
        editManager: EditManager,
        editMessageStore: EditMessageStore,
        externalPendingIDEALDonationStore: ExternalPendingIDEALDonationStore,
        groupCallRecordManager: GroupCallRecordManager,
        groupMemberStore: GroupMemberStore,
        groupMemberUpdater: GroupMemberUpdater,
        groupSendEndorsementStore: any GroupSendEndorsementStore,
        groupUpdateInfoMessageInserter: GroupUpdateInfoMessageInserter,
        identityKeyMismatchManager: IdentityKeyMismatchManager,
        identityManager: OWSIdentityManager,
        inactiveLinkedDeviceFinder: InactiveLinkedDeviceFinder,
        inactivePrimaryDeviceStore: InactivePrimaryDeviceStore,
        incomingCallEventSyncMessageManager: IncomingCallEventSyncMessageManager,
        incomingCallLogEventSyncMessageManager: IncomingCallLogEventSyncMessageManager,
        incomingPniChangeNumberProcessor: IncomingPniChangeNumberProcessor,
        incrementalMessageTSAttachmentMigrator: IncrementalMessageTSAttachmentMigrator,
        individualCallRecordManager: IndividualCallRecordManager,
        interactionDeleteManager: InteractionDeleteManager,
        interactionStore: InteractionStore,
        lastVisibleInteractionStore: LastVisibleInteractionStore,
        linkAndSyncManager: LinkAndSyncManager,
        linkPreviewManager: LinkPreviewManager,
        linkPreviewSettingStore: LinkPreviewSettingStore,
        linkPreviewSettingManager: any LinkPreviewSettingManager,
        accountKeyStore: AccountKeyStore,
        localProfileChecker: LocalProfileChecker,
        localUsernameManager: LocalUsernameManager,
        masterKeySyncManager: MasterKeySyncManager,
        mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
        messageStickerManager: MessageStickerManager,
        nicknameManager: any NicknameManager,
        orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        archivedPaymentStore: ArchivedPaymentStore,
        phoneNumberDiscoverabilityManager: PhoneNumberDiscoverabilityManager,
        phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher,
        pinnedThreadManager: PinnedThreadManager,
        pinnedThreadStore: PinnedThreadStore,
        preKeyManager: PreKeyManager,
        privateStoryThreadDeletionManager: any PrivateStoryThreadDeletionManager,
        quotedReplyManager: QuotedReplyManager,
        reactionStore: any ReactionStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        recipientHidingManager: RecipientHidingManager,
        recipientIdFinder: RecipientIdFinder,
        recipientManager: any SignalRecipientManager,
        recipientMerger: RecipientMerger,
        registrationSessionManager: RegistrationSessionManager,
        registrationStateChangeManager: RegistrationStateChangeManager,
        searchableNameIndexer: SearchableNameIndexer,
        sentMessageTranscriptReceiver: SentMessageTranscriptReceiver,
        signalProtocolStoreManager: SignalProtocolStoreManager,
        storageServiceRecordIkmCapabilityStore: StorageServiceRecordIkmCapabilityStore,
        storyRecipientManager: StoryRecipientManager,
        storyRecipientStore: StoryRecipientStore,
        svr: SecureValueRecovery,
        svrCredentialStorage: SVRAuthCredentialStorage,
        svrLocalStorage: SVRLocalStorage,
        threadAssociatedDataStore: ThreadAssociatedDataStore,
        threadRemover: ThreadRemover,
        threadReplyInfoStore: ThreadReplyInfoStore,
        threadSoftDeleteManager: ThreadSoftDeleteManager,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager,
        usernameApiClient: UsernameApiClient,
        usernameEducationManager: UsernameEducationManager,
        usernameLinkManager: UsernameLinkManager,
        usernameLookupManager: UsernameLookupManager,
        usernameValidationManager: UsernameValidationManager,
        wallpaperImageStore: WallpaperImageStore,
        wallpaperStore: WallpaperStore
    ) {
        self.accountAttributesUpdater = accountAttributesUpdater
        self.adHocCallRecordManager = adHocCallRecordManager
        self.appExpiry = appExpiry
        self.attachmentCloner = attachmentCloner
        self.attachmentContentValidator = attachmentContentValidator
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentDownloadStore = attachmentDownloadStore
        self.attachmentManager = attachmentManager
        self.attachmentStore = attachmentStore
        self.attachmentThumbnailService = attachmentThumbnailService
        self.attachmentUploadManager = attachmentUploadManager
        self.attachmentValidationBackfillMigrator = attachmentValidationBackfillMigrator
        self.attachmentViewOnceManager = attachmentViewOnceManager
        self.audioWaveformManager = audioWaveformManager
        self.authorMergeHelper = authorMergeHelper
        self.avatarDefaultColorManager = avatarDefaultColorManager
        self.backgroundMessageFetcherFactory = backgroundMessageFetcherFactory
        self.backupArchiveErrorPresenter = backupArchiveErrorPresenter
        self.backupArchiveManager = backupArchiveManager
        self.backupAttachmentDownloadManager = backupAttachmentDownloadManager
        self.backupAttachmentDownloadProgress = backupAttachmentDownloadProgress
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupAttachmentDownloadQueueStatusReporter = backupAttachmentDownloadQueueStatusReporter
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.backupAttachmentUploadQueueRunner = backupAttachmentUploadQueueRunner
        self.backupAttachmentUploadQueueStatusReporter = backupAttachmentUploadQueueStatusReporter
        self.backupDisablingManager = backupDisablingManager
        self.backupExportJob = backupExportJob
        self.backupExportJobRunner = backupExportJobRunner
        self.backupIdManager = backupIdManager
        self.backupKeyMaterial = backupKeyMaterial
        self.backupRequestManager = backupRequestManager
        self.backupPlanManager = backupPlanManager
        self.backupSubscriptionManager = backupSubscriptionManager
        self.backupTestFlightEntitlementManager = backupTestFlightEntitlementManager
        self.badgeCountFetcher = badgeCountFetcher
        self.callLinkStore = callLinkStore
        self.callRecordDeleteManager = callRecordDeleteManager
        self.callRecordMissedCallManager = callRecordMissedCallManager
        self.callRecordQuerier = callRecordQuerier
        self.callRecordStore = callRecordStore
        self.changePhoneNumberPniManager = changePhoneNumberPniManager
        self.chatColorSettingStore = chatColorSettingStore
        self.chatConnectionManager = chatConnectionManager
        self.contactShareManager = contactShareManager
        self.currentCallProvider = currentCallProvider
        self.databaseChangeObserver = databaseChangeObserver
        self.db = db
        self.deletedCallRecordCleanupManager = deletedCallRecordCleanupManager
        self.deletedCallRecordStore = deletedCallRecordStore
        self.deleteForMeIncomingSyncMessageManager = deleteForMeIncomingSyncMessageManager
        self.deleteForMeOutgoingSyncMessageManager = deleteForMeOutgoingSyncMessageManager
        self.deviceManager = deviceManager
        self.deviceService = deviceService
        self.deviceSleepManager = deviceSleepManager
        self.deviceStore = deviceStore
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
        self.donationReceiptCredentialResultStore = donationReceiptCredentialResultStore
        self.editManager = editManager
        self.editMessageStore = editMessageStore
        self.externalPendingIDEALDonationStore = externalPendingIDEALDonationStore
        self.groupCallRecordManager = groupCallRecordManager
        self.groupMemberStore = groupMemberStore
        self.groupMemberUpdater = groupMemberUpdater
        self.groupSendEndorsementStore = groupSendEndorsementStore
        self.groupUpdateInfoMessageInserter = groupUpdateInfoMessageInserter
        self.identityKeyMismatchManager = identityKeyMismatchManager
        self.identityManager = identityManager
        self.inactiveLinkedDeviceFinder = inactiveLinkedDeviceFinder
        self.inactivePrimaryDeviceStore = inactivePrimaryDeviceStore
        self.incomingCallEventSyncMessageManager = incomingCallEventSyncMessageManager
        self.incomingCallLogEventSyncMessageManager = incomingCallLogEventSyncMessageManager
        self.incomingPniChangeNumberProcessor = incomingPniChangeNumberProcessor
        self.incrementalMessageTSAttachmentMigrator = incrementalMessageTSAttachmentMigrator
        self.individualCallRecordManager = individualCallRecordManager
        self.interactionDeleteManager = interactionDeleteManager
        self.interactionStore = interactionStore
        self.lastVisibleInteractionStore = lastVisibleInteractionStore
        self.linkAndSyncManager = linkAndSyncManager
        self.linkPreviewManager = linkPreviewManager
        self.linkPreviewSettingStore = linkPreviewSettingStore
        self.linkPreviewSettingManager = linkPreviewSettingManager
        self.accountKeyStore = accountKeyStore
        self.localProfileChecker = localProfileChecker
        self.localUsernameManager = localUsernameManager
        self.masterKeySyncManager = masterKeySyncManager
        self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
        self.messageStickerManager = messageStickerManager
        self.nicknameManager = nicknameManager
        self.orphanedBackupAttachmentManager = orphanedBackupAttachmentManager
        self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
        self.archivedPaymentStore = archivedPaymentStore
        self.phoneNumberDiscoverabilityManager = phoneNumberDiscoverabilityManager
        self.phoneNumberVisibilityFetcher = phoneNumberVisibilityFetcher
        self.pinnedThreadManager = pinnedThreadManager
        self.pinnedThreadStore = pinnedThreadStore
        self.preKeyManager = preKeyManager
        self.privateStoryThreadDeletionManager = privateStoryThreadDeletionManager
        self.quotedReplyManager = quotedReplyManager
        self.reactionStore = reactionStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.recipientHidingManager = recipientHidingManager
        self.recipientIdFinder = recipientIdFinder
        self.recipientManager = recipientManager
        self.recipientMerger = recipientMerger
        self.registrationSessionManager = registrationSessionManager
        self.registrationStateChangeManager = registrationStateChangeManager
        self.searchableNameIndexer = searchableNameIndexer
        self.sentMessageTranscriptReceiver = sentMessageTranscriptReceiver
        self.signalProtocolStoreManager = signalProtocolStoreManager
        self.storageServiceRecordIkmCapabilityStore = storageServiceRecordIkmCapabilityStore
        self.storyRecipientManager = storyRecipientManager
        self.storyRecipientStore = storyRecipientStore
        self.svr = svr
        self.svrCredentialStorage = svrCredentialStorage
        self.svrLocalStorage = svrLocalStorage
        self.threadAssociatedDataStore = threadAssociatedDataStore
        self.threadRemover = threadRemover
        self.threadReplyInfoStore = threadReplyInfoStore
        self.threadSoftDeleteManager = threadSoftDeleteManager
        self.threadStore = threadStore
        self.tsAccountManager = tsAccountManager
        self.usernameApiClient = usernameApiClient
        self.usernameEducationManager = usernameEducationManager
        self.usernameLinkManager = usernameLinkManager
        self.usernameLookupManager = usernameLookupManager
        self.usernameValidationManager = usernameValidationManager
        self.wallpaperImageStore = wallpaperImageStore
        self.wallpaperStore = wallpaperStore
    }
}
