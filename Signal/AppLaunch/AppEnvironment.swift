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

    let deviceTransferServiceRef: DeviceTransferService
    let pushRegistrationManagerRef: PushRegistrationManager

    let cvAudioPlayerRef = CVAudioPlayer()
    let speechManagerRef = SpeechManager()
    let windowManagerRef = WindowManager()

    private(set) var appIconBadgeUpdater: AppIconBadgeUpdater!
    private(set) var avatarHistoryManager: AvatarHistoryManager!
    private(set) var backupEnablingManager: BackupEnablingManager!
    private(set) var badgeManager: BadgeManager!
    private(set) var callLinkProfileKeySharingManager: CallLinkProfileKeySharingManager!
    private(set) var callService: CallService!
    private(set) var outgoingDeviceRestorePresenter: OutgoingDeviceRestorePresenter!
    private(set) var provisioningManager: ProvisioningManager!
    private(set) var quickRestoreManager: QuickRestoreManager!
    private var registrationIdMismatchManager: RegistrationIdMismatchManager!

    init(appReadiness: AppReadiness, deviceTransferService: DeviceTransferService) {
        self.deviceTransferServiceRef = deviceTransferService
        self.pushRegistrationManagerRef = PushRegistrationManager(appReadiness: appReadiness)

        super.init()

        SwiftSingletons.register(self)
    }

    func setUp(appReadiness: AppReadiness, callService: CallService) {
        let dependenciesBridge = DependenciesBridge.shared
        let cron = dependenciesBridge.cron

        let backupAttachmentUploadEraStore = BackupAttachmentUploadEraStore()
        let backupNonceStore = BackupNonceMetadataStore()
        let backupSettingsStore = BackupSettingsStore()
        let backupSubscriptionIssueStore = BackupSubscriptionIssueStore()

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
            db: DependenciesBridge.shared.db
        )
        self.badgeManager = badgeManager
        self.backupEnablingManager = BackupEnablingManager(
            backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
            backupDisablingManager: DependenciesBridge.shared.backupDisablingManager,
            backupKeyService: DependenciesBridge.shared.backupKeyService,
            backupPlanManager: DependenciesBridge.shared.backupPlanManager,
            backupSettingsStore: backupSettingsStore,
            backupSubscriptionIssueStore: backupSubscriptionIssueStore,
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager,
            backupTestFlightEntitlementManager: DependenciesBridge.shared.backupTestFlightEntitlementManager,
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            notificationPresenter: SSKEnvironment.shared.notificationPresenterRef
        )
        self.callService = callService
        self.callLinkProfileKeySharingManager = CallLinkProfileKeySharingManager(
            db: DependenciesBridge.shared.db,
            accountManager: DependenciesBridge.shared.tsAccountManager
        )
        self.provisioningManager = ProvisioningManager(
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            db: DependenciesBridge.shared.db,
            deviceManager: DependenciesBridge.shared.deviceManager,
            deviceProvisioningService: deviceProvisioningService,
            identityManager: DependenciesBridge.shared.identityManager,
            linkAndSyncManager: DependenciesBridge.shared.linkAndSyncManager,
            profileManager: SSKEnvironment.shared.profileManagerRef,
            receiptManager: ProvisioningManager.Wrappers.ReceiptManager(SSKEnvironment.shared.receiptManagerRef),
            tsAccountManager: DependenciesBridge.shared.tsAccountManager
        )
        self.quickRestoreManager = QuickRestoreManager(
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            backupNonceStore: backupNonceStore,
            backupSettingsStore: backupSettingsStore,
            db: DependenciesBridge.shared.db,
            deviceProvisioningService: deviceProvisioningService,
            identityManager: DependenciesBridge.shared.identityManager,
            networkManager: SSKEnvironment.shared.networkManagerRef,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager
        )

        let usernameValidationManager = DependenciesBridge.shared.usernameValidationManager
        cron.schedulePeriodically(
            uniqueKey: .checkUsername,
            approximateInterval: .day,
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { _ = try await usernameValidationManager.validateUsername() },
        )

        self.outgoingDeviceRestorePresenter = OutgoingDeviceRestorePresenter(
            deviceTransferService: deviceTransferServiceRef,
            quickRestoreManager: quickRestoreManager
        )

        self.registrationIdMismatchManager = RegistrationIdMismatchManagerImpl(
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
            udManager: SSKEnvironment.shared.udManagerRef
        )

        let inactiveLinkedDeviceFinder = DependenciesBridge.shared.inactiveLinkedDeviceFinder
        cron.schedulePeriodically(
            uniqueKey: .fetchDevices,
            approximateInterval: .day,
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { try await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary() },
        )

        let subscriptionConfigManager = DependenciesBridge.shared.subscriptionConfigManager
        cron.schedulePeriodically(
            uniqueKey: .fetchSubscriptionConfig,
            approximateInterval: .day,
            mustBeRegistered: false,
            mustBeConnected: true,
            operation: { try await subscriptionConfigManager.refresh() },
        )

        appReadiness.runNowOrWhenAppWillBecomeReady {
            self.badgeManager.startObservingChanges(in: DependenciesBridge.shared.databaseChangeObserver)
            self.appIconBadgeUpdater.startObserving()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            let accountEntropyPoolManager = DependenciesBridge.shared.accountEntropyPoolManager
            let backupDisablingManager = DependenciesBridge.shared.backupDisablingManager
            let backupIdService = DependenciesBridge.shared.backupIdService
            let backupSubscriptionManager = DependenciesBridge.shared.backupSubscriptionManager
            let backupTestFlightEntitlementManager = DependenciesBridge.shared.backupTestFlightEntitlementManager
            let callRecordStore = DependenciesBridge.shared.callRecordStore
            let callRecordQuerier = DependenciesBridge.shared.callRecordQuerier
            let db = DependenciesBridge.shared.db
            let groupCallPeekClient = SSKEnvironment.shared.groupCallManagerRef.groupCallPeekClient
            let identityKeyMismatchManager = DependenciesBridge.shared.identityKeyMismatchManager
            let interactionStore = DependenciesBridge.shared.interactionStore
            let masterKeySyncManager = DependenciesBridge.shared.masterKeySyncManager
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
                threadStore: threadStore
            )
            let groupCallRecordRingingCleanupManager = GroupCallRecordRingingCleanupManager(
                callRecordStore: callRecordStore,
                callRecordQuerier: callRecordQuerier,
                db: db,
                interactionStore: interactionStore,
                groupCallPeekClient: groupCallPeekClient,
                notificationPresenter: notificationPresenter,
                threadStore: threadStore
            )

            let (
                isRegisteredPrimaryDevice,
                localIdentifiers
            ) = db.read { tx in
                (
                    tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
                    tsAccountManager.localIdentifiers(tx: tx),
                )
            }

            // Things that should run on only the primary *or* linked devices.
            if isRegisteredPrimaryDevice, let localIdentifiers {
                Task {
                    do {
                        try await avatarDefaultColorStorageServiceMigrator.performMigrationIfNecessary()
                    } catch {
                        Logger.warn("Couldn't perform avatar default color migration: \(error)")
                    }
                }

                Task {
                    await storageServiceRecordIkmMigrator.migrateToManifestRecordIkmIfNecessary()
                }

                Task {
                    do {
                        try await backupIdService.registerBackupIDIfNecessary(
                            localAci: localIdentifiers.aci,
                            auth: .implicit()
                        )
                    } catch {
                        // Do nothing, we'll try again on the next app launch.
                        owsFailDebug("Error registering backup ID \(error)")
                    }
                }

                Task {
                    await accountEntropyPoolManager.generateIfMissing()
                }

                Task {
                    // Valide the local registration ID of the primary.
                    // There was a bug in re-registration flow that could lead to a discrepancy
                    // between client and server around the registrationID
                    await self.registrationIdMismatchManager.validateRegistrationIds()
                }
            } else {
                Task {
                    await identityKeyMismatchManager.validateLocalPniIdentityKeyIfNecessary()
                }
            }

            Task {
                await db.awaitableWrite { tx in
                    masterKeySyncManager.runStartupJobs(tx: tx)
                }
            }

            Task {
                await db.awaitableWrite { tx in
                    groupCallRecordRingingCleanupManager.cleanupRingingCalls(tx: tx)
                }
            }

            Task { () async -> Void in
                await backupDisablingManager.disableRemotelyIfNecessary()
            }

            Task {
                await self.avatarHistoryManager.cleanupOrphanedImages()
            }

            Task {
                do {
                    try await backupSubscriptionManager.redeemSubscriptionIfNecessary()
                } catch {
                    owsFailDebug("Failed to redeem Backup subscription in launch job: \(error)")
                }
            }

            Task {
                do {
                    try await backupTestFlightEntitlementManager.renewEntitlementIfNecessary()
                } catch {
                    owsFailDebug("Failed to renew Backup entitlement for TestFlight in launch job: \(error)")
                }
            }

            Task {
                await DonationSubscriptionManager.performMigrationToStorageServiceIfNecessary()
                do {
                    try await DonationSubscriptionManager.redeemSubscriptionIfNecessary()
                } catch {
                    owsFailDebug("Failed to redeem subscription in launch job: \(error)")
                }
            }
        }
    }
}
