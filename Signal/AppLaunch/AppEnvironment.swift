//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Foundation
import SignalServiceKit

public class AppEnvironment: NSObject {

    private static var _shared: AppEnvironment?

    static func setSharedEnvironment(_ appEnvironment: AppEnvironment) {
        owsPrecondition(self._shared == nil)
        self._shared = appEnvironment
    }

    @objc
    public class var shared: AppEnvironment { _shared! }

    /// Objects tied to this AppEnvironment that simply need to be retained.
    @MainActor
    var ownedObjects = [AnyObject]()

    let cvAudioPlayerRef: CVAudioPlayer
    let deviceTransferRestore: DeviceTransferRestore
    let pushRegistrationManagerRef: PushRegistrationManager
    let screenLockUI: ScreenLockUI
    let speechManagerRef: SpeechManager
    let windowManagerRef: WindowManager

    private(set) var appIconBadgeUpdater: AppIconBadgeUpdater!
    private(set) var avatarHistoryManager: AvatarHistoryManager!
    private(set) var backupAttachmentDownloadTracker: BackupAttachmentDownloadTracker!
    private(set) var backupAttachmentUploadTracker: BackupAttachmentUploadTracker!
    private(set) var backupDisablingManager: BackupDisablingManager!
    private(set) var backupEnablingManager: BackupEnablingManager!
    private(set) var badgeManager: BadgeManager!
    private(set) var callLinkProfileKeySharingManager: CallLinkProfileKeySharingManager!
    private(set) var callService: CallService!
    private(set) var experienceUpgradeManager: ExperienceUpgradeManager!
    private(set) var groupSendEndorsementExpirationJob: GroupSendEndorsementExpirationJob!
    private(set) var lowDiskSpaceManager: LowDiskSpaceManager!
    private var lowDiskSpaceMonitoringManager: LowDiskSpaceMonitoringManager!
    private(set) var outgoingDeviceRestorePresenter: OutgoingDeviceRestorePresenter!
    private(set) var passwordManagerManager: PasswordManagerManager!
    private(set) var provisioningManager: ProvisioningManager!
    private(set) var quickRestoreManager: QuickRestoreManager!
    private var registrationIdMismatchManager: RegistrationIdMismatchManager!

    init(appReadiness: AppReadiness, deviceTransferRestore: DeviceTransferRestore) {
        self.cvAudioPlayerRef = CVAudioPlayer()
        self.deviceTransferRestore = deviceTransferRestore
        self.screenLockUI = ScreenLockUI(appReadiness: appReadiness)
        self.pushRegistrationManagerRef = PushRegistrationManager(appReadiness: appReadiness)
        self.speechManagerRef = SpeechManager()
        self.windowManagerRef = WindowManager()

        super.init()

    }

    func setUp(appReadiness: AppReadiness, callService: CallService) {

        // MARK: Set up singletons

        let authCredentialStore = AuthCredentialStore()
        let backupAttachmentUploadEraStore = BackupAttachmentUploadEraStore()
        let backupAttachmentDownloadStore = BackupAttachmentDownloadStore()
        let backupCDNCredentialStore = BackupCDNCredentialStore()
        let backupExportJobStore = BackupExportJobStore()
        let backupSettingsStore = BackupSettingsStore()
        let backupNonceStore = BackupNonceMetadataStore()
        let backupSubscriptionIssueStore = BackupSubscriptionIssueStore()
        let clvBackupExportProgressViewStore = CLVBackupExportProgressView.Store()

        let badgeManager = BadgeManager(
            badgeCountFetcher: DependenciesBridge.shared.badgeCountFetcher,
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
        )
        let deviceProvisioningService = DeviceProvisioningServiceImpl(
            networkManager: SSKEnvironment.shared.networkManagerRef,
        )

        self.appIconBadgeUpdater = AppIconBadgeUpdater(badgeManager: badgeManager)

        self.avatarHistoryManager = AvatarHistoryManager(
            appReadiness: appReadiness,
            db: DependenciesBridge.shared.db,
        )

        self.backupAttachmentDownloadTracker = BackupAttachmentDownloadTracker(
            backupAttachmentDownloadQueueStatusManager: DependenciesBridge.shared.backupAttachmentDownloadQueueStatusManager,
            backupAttachmentDownloadProgress: DependenciesBridge.shared.backupAttachmentDownloadProgress,
        )
        self.backupAttachmentUploadTracker = BackupAttachmentUploadTracker(
            backupAttachmentUploadQueueStatusManager: DependenciesBridge.shared.backupAttachmentUploadQueueStatusManager,
            backupAttachmentUploadProgress: DependenciesBridge.shared.backupAttachmentUploadProgress,
        )
        self.backupDisablingManager = BackupDisablingManager(
            accountEntropyPoolManager: DependenciesBridge.shared.accountEntropyPoolManager,
            authCredentialStore: authCredentialStore,
            backupAttachmentCoordinator: DependenciesBridge.shared.backupAttachmentCoordinator,
            backupAttachmentDownloadQueueStatusManager: DependenciesBridge.shared.backupAttachmentDownloadQueueStatusManager,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupCDNCredentialStore: backupCDNCredentialStore,
            backupExportJobStore: backupExportJobStore,
            backupKeyService: DependenciesBridge.shared.backupKeyService,
            backupListMediaManager: DependenciesBridge.shared.backupListMediaManager,
            backupPlanManager: DependenciesBridge.shared.backupPlanManager,
            backupSettingsStore: backupSettingsStore,
            clvBackupExportProgressViewStore: clvBackupExportProgressViewStore,
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )
        self.backupEnablingManager = BackupEnablingManager(
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupDisablingManager: self.backupDisablingManager,
            backupIdService: DependenciesBridge.shared.backupIdService,
            backupKeyService: DependenciesBridge.shared.backupKeyService,
            backupPlanManager: DependenciesBridge.shared.backupPlanManager,
            backupSettingsStore: backupSettingsStore,
            backupSubscriptionIssueStore: backupSubscriptionIssueStore,
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager,
            backupTestFlightEntitlementManager: DependenciesBridge.shared.backupTestFlightEntitlementManager,
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            notificationPresenter: SSKEnvironment.shared.notificationPresenterRef,
        )

        self.badgeManager = badgeManager

        self.callService = callService
        self.callLinkProfileKeySharingManager = CallLinkProfileKeySharingManager(
            db: DependenciesBridge.shared.db,
            accountManager: DependenciesBridge.shared.tsAccountManager,
        )

        self.experienceUpgradeManager = ExperienceUpgradeManager(
            attachmentStore: AttachmentStore(),
            backupSettingsStore: backupSettingsStore,
            db: DependenciesBridge.shared.db,
            deviceStore: DependenciesBridge.shared.deviceStore,
            donationReceiptCredentialResultStore: DependenciesBridge.shared.donationReceiptCredentialResultStore,
            experienceUpgradeStore: ExperienceUpgradeStore(),
            inactiveLinkedDeviceFinder: DependenciesBridge.shared.inactiveLinkedDeviceFinder,
            inactivePrimaryDeviceStore: DependenciesBridge.shared.inactivePrimaryDeviceStore,
            localUsernameManager: DependenciesBridge.shared.localUsernameManager,
            networkManager: SSKEnvironment.shared.networkManagerRef,
            ows2FAManager: SSKEnvironment.shared.ows2FAManagerRef,
            profileManager: SSKEnvironment.shared.profileManagerRef,
            reachabilityManager: SSKEnvironment.shared.reachabilityManagerRef,
            remoteConfigManager: SSKEnvironment.shared.remoteConfigManagerRef,
            storageServiceManager: SSKEnvironment.shared.storageServiceManagerRef,
            subscriptionConfigManager: DependenciesBridge.shared.subscriptionConfigManager,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            usernameEducationManager: DependenciesBridge.shared.usernameEducationManager,
        )

        self.groupSendEndorsementExpirationJob = GroupSendEndorsementExpirationJob(
            dateProvider: Date.provider,
            db: DependenciesBridge.shared.db,
            groupSendEndorsementStore: DependenciesBridge.shared.groupSendEndorsementStore,
        )

        self.lowDiskSpaceManager = LowDiskSpaceManager()
        self.lowDiskSpaceMonitoringManager = LowDiskSpaceMonitoringManager(
            lowDiskSpaceManager: lowDiskSpaceManager,
            monitoringInterval: 5 * .second,
        )

        self.passwordManagerManager = PasswordManagerManager()

        self.provisioningManager = ProvisioningManager(
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            db: DependenciesBridge.shared.db,
            deviceManager: DependenciesBridge.shared.deviceManager,
            deviceProvisioningService: deviceProvisioningService,
            identityManager: DependenciesBridge.shared.identityManager,
            linkAndSyncManager: DependenciesBridge.shared.linkAndSyncManager,
            profileManager: SSKEnvironment.shared.profileManagerRef,
            receiptManager: ProvisioningManager.Wrappers.ReceiptManager(SSKEnvironment.shared.receiptManagerRef),
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )

        self.quickRestoreManager = QuickRestoreManager(
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            backupNonceStore: backupNonceStore,
            backupSettingsStore: backupSettingsStore,
            db: DependenciesBridge.shared.db,
            deviceProvisioningService: deviceProvisioningService,
            identityManager: DependenciesBridge.shared.identityManager,
            networkManager: SSKEnvironment.shared.networkManagerRef,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )

        self.outgoingDeviceRestorePresenter = OutgoingDeviceRestorePresenter(
            dateProvider: Date.provider,
            db: DependenciesBridge.shared.db,
            backupSettingsStore: BackupSettingsStore(),
            deviceSleepManager: DependenciesBridge.shared.deviceSleepManager,
            quickRestoreManager: quickRestoreManager,
            registrationStateChangeManager: DependenciesBridge.shared.registrationStateChangeManager,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
        )

        self.registrationIdMismatchManager = RegistrationIdMismatchManagerImpl(
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            udManager: SSKEnvironment.shared.udManagerRef,
        )

        // MARK: Set up Cron jobs

        let cron = DependenciesBridge.shared.cron

        let usernameValidationManager = DependenciesBridge.shared.usernameValidationManager
        cron.schedulePeriodically(
            uniqueKey: .checkUsername,
            approximateInterval: .day,
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { _ = try await usernameValidationManager.validateUsername() },
        )

        let inactiveLinkedDeviceFinder = DependenciesBridge.shared.inactiveLinkedDeviceFinder
        cron.schedulePeriodically(
            uniqueKey: .fetchDevices,
            approximateInterval: .day,
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { try await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary() },
        )

        cron.schedulePeriodically(
            uniqueKey: .fetchSubscriptionConfig,
            approximateInterval: .day,
            mustBeRegistered: false,
            mustBeConnected: true,
            operation: {
                let subscriptionConfigManager = DependenciesBridge.shared.subscriptionConfigManager

                _ = try await subscriptionConfigManager.refresh()
            },
        )

        cron.schedulePeriodically(
            uniqueKey: .fetchDonationBadgeAssets,
            approximateInterval: .day,
            mustBeRegistered: false,
            mustBeConnected: true,
            operation: {
                let db = DependenciesBridge.shared.db
                let profileBadgeManager = DependenciesBridge.shared.profileBadgeManager
                let subscriptionConfigManager = DependenciesBridge.shared.subscriptionConfigManager

                let donationConfig = try await subscriptionConfigManager.donationConfiguration()

                await db.awaitableWrite { tx in
                    for profileBadge in donationConfig.allProfileBadges {
                        profileBadgeManager.createOrUpdateBadge(profileBadge, tx: tx)
                    }
                }

                try await withThrowingTaskGroup { taskGroup in
                    for profileBadge in donationConfig.allProfileBadges {
                        taskGroup.addTask {
                            try await profileBadgeManager.fetchAssetsIfNecessary(forBadge: profileBadge)
                        }
                    }

                    try await taskGroup.waitForAll()
                }
            },
        )

        let identityKeyMismatchManager = DependenciesBridge.shared.identityKeyMismatchManager
        cron.scheduleFrequently(
            mustBeRegistered: true,
            mustBeDeviceType: .linked,
            mustBeConnected: true,
            operation: { try await identityKeyMismatchManager.validateLocalPniIdentityKeyIfNecessary() },
        )

        let backupSubscriptionManager = DependenciesBridge.shared.backupSubscriptionManager
        cron.scheduleFrequently(
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { try await backupSubscriptionManager.redeemSubscriptionIfNecessary() },
            handleResult: {
                switch $0 {
                case .success, .failure(is CancellationError), .failure(is NotRegisteredError):
                    break
                case .failure(let error):
                    Logger.warn("Terminally failed to redeem Backups subscription! \(error)")
                }
            },
        )

        let backupTestFlightEntitlementManager = DependenciesBridge.shared.backupTestFlightEntitlementManager
        cron.scheduleFrequently(
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { try await backupTestFlightEntitlementManager.renewEntitlementIfNecessary() },
            handleResult: {
                switch $0 {
                case .success, .failure(is CancellationError), .failure(is NotRegisteredError):
                    break
                case .failure(let error):
                    Logger.warn("Terminally failed to redeem Backups TestFlight subscription! \(error)")
                }
            },
        )

        let donationSubscriptionManager = DependenciesBridge.shared.donationSubscriptionManager
        cron.scheduleFrequently(
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { try await donationSubscriptionManager.redeemSubscriptionIfNecessary() },
            handleResult: {
                switch $0 {
                case .success, .failure(is CancellationError), .failure(is NotRegisteredError):
                    break
                case .failure(let error):
                    Logger.warn("Terminally failed to redeem Donations subscription! \(error)")
                }
            },
        )

        // MARK: Set up non-Cron on-launch jobs

        appReadiness.runNowOrWhenAppWillBecomeReady {
            self.badgeManager.startObservingChanges(in: DependenciesBridge.shared.databaseChangeObserver)
            self.appIconBadgeUpdater.startObserving()
            self.lowDiskSpaceMonitoringManager.start()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            let accountEntropyPoolManager = DependenciesBridge.shared.accountEntropyPoolManager
            let attachmentBackfillManager = DependenciesBridge.shared.attachmentBackfillManager
            let backupExportJobRunner = DependenciesBridge.shared.backupExportJobRunner
            let backupIdService = DependenciesBridge.shared.backupIdService
            let callRecordStore = DependenciesBridge.shared.callRecordStore
            let callRecordQuerier = DependenciesBridge.shared.callRecordQuerier
            let db = DependenciesBridge.shared.db
            let groupCallPeekClient = SSKEnvironment.shared.groupCallManagerRef.groupCallPeekClient
            let interactionStore = DependenciesBridge.shared.interactionStore
            let notificationPresenter = SSKEnvironment.shared.notificationPresenterRef
            let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
            let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef
            let threadStore = DependenciesBridge.shared.threadStore
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let storageServiceRecordIkmMigrator = DependenciesBridge.shared.storageServiceRecordIkmMigrator

            let avatarDefaultColorStorageServiceMigrator = AvatarDefaultColorStorageServiceMigrator(
                db: db,
                recipientDatabaseTable: recipientDatabaseTable,
                storageServiceManager: storageServiceManager,
                threadStore: threadStore,
            )
            let groupCallRecordRingingCleanupManager = GroupCallRecordRingingCleanupManager(
                callRecordStore: callRecordStore,
                callRecordQuerier: callRecordQuerier,
                db: db,
                interactionStore: interactionStore,
                groupCallPeekClient: groupCallPeekClient,
                notificationPresenter: notificationPresenter,
                threadStore: threadStore,
            )

            let registeredState = db.read { tx in
                return try? tsAccountManager.registeredState(tx: tx)
            }

            // Things that should run on either the primary or linked devices.
            if let registeredState, registeredState.isPrimary {
                Task {
                    await avatarDefaultColorStorageServiceMigrator.performMigrationIfNecessary()
                }

                Task {
                    await storageServiceRecordIkmMigrator.migrateToManifestRecordIkmIfNecessary()
                }

                Task {
                    do {
                        try await backupIdService.registerBackupIDIfNecessary(
                            localAci: registeredState.localIdentifiers.aci,
                            auth: .implicit(),
                            logger: PrefixedLogger(prefix: "[Launch]"),
                        )
                    } catch {
                        // Do nothing, we'll try again on the next app launch.
                        Logger.warn("Error registering backup ID \(error)")
                    }
                }

                // If we had an interrupted BackupExportJob, resume it.
                backupExportJobRunner.resumeIfNecessary()

                Task {
                    await accountEntropyPoolManager.generateIfMissing()
                }

                Task {
                    // Valide the local registration ID of the primary.
                    // There was a bug in re-registration flow that could lead to a discrepancy
                    // between client and server around the registrationID
                    await self.registrationIdMismatchManager.validateRegistrationIds()
                }

                // Start any incomplete enqueued attachment backfill requests.
                attachmentBackfillManager.processEnqueuedInboundRequests(
                    registeredState: registeredState,
                )
            } else {
            }

            Task {
                await db.awaitableWrite { tx in
                    groupCallRecordRingingCleanupManager.cleanupRingingCalls(tx: tx)
                }
            }

            Task { () async -> Void in
                await self.backupDisablingManager.disableRemotelyIfNecessary()
            }

            Task {
                await self.avatarHistoryManager.cleanupOrphanedImages()
            }
        }
    }
}
