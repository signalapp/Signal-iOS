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
    private var usernameValidationObserver: UsernameValidationObserver!

    init(appReadiness: AppReadiness, deviceTransferService: DeviceTransferService) {
        self.deviceTransferServiceRef = deviceTransferService
        self.pushRegistrationManagerRef = PushRegistrationManager(appReadiness: appReadiness)

        super.init()

        SwiftSingletons.register(self)
    }

    func setUp(appReadiness: AppReadiness, callService: CallService) {
        let backupSettingsStore = BackupSettingsStore()
        let backupAttachmentUploadEraStore = BackupAttachmentUploadEraStore()

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
            backupIdManager: DependenciesBridge.shared.backupIdManager,
            backupPlanManager: DependenciesBridge.shared.backupPlanManager,
            backupSubscriptionManager: DependenciesBridge.shared.backupSubscriptionManager,
            backupTestFlightEntitlementManager: DependenciesBridge.shared.backupTestFlightEntitlementManager,
            db: DependenciesBridge.shared.db,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager,
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
            profileManager: ProvisioningManager.Wrappers.ProfileManager(SSKEnvironment.shared.profileManagerRef),
            receiptManager: ProvisioningManager.Wrappers.ReceiptManager(SSKEnvironment.shared.receiptManagerRef),
            tsAccountManager: DependenciesBridge.shared.tsAccountManager
        )
        self.quickRestoreManager = QuickRestoreManager(
            accountKeyStore: DependenciesBridge.shared.accountKeyStore,
            backupSettingsStore: backupSettingsStore,
            db: DependenciesBridge.shared.db,
            deviceProvisioningService: deviceProvisioningService,
            identityManager: DependenciesBridge.shared.identityManager,
            networkManager: SSKEnvironment.shared.networkManagerRef,
            tsAccountManager: DependenciesBridge.shared.tsAccountManager
        )
        self.usernameValidationObserver = UsernameValidationObserver(
            appReadiness: appReadiness,
            manager: DependenciesBridge.shared.usernameValidationManager,
            database: DependenciesBridge.shared.db
        )

        self.outgoingDeviceRestorePresenter = OutgoingDeviceRestorePresenter(
            deviceTransferService: deviceTransferServiceRef,
            quickRestoreManager: quickRestoreManager
        )

        appReadiness.runNowOrWhenAppWillBecomeReady {
            self.badgeManager.startObservingChanges(in: DependenciesBridge.shared.databaseChangeObserver)
            self.appIconBadgeUpdater.startObserving()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            let backupDisablingManager = DependenciesBridge.shared.backupDisablingManager
            let backupSubscriptionManager = DependenciesBridge.shared.backupSubscriptionManager
            let backupTestFlightEntitlementManager = DependenciesBridge.shared.backupTestFlightEntitlementManager
            let callRecordStore = DependenciesBridge.shared.callRecordStore
            let callRecordQuerier = DependenciesBridge.shared.callRecordQuerier
            let db = DependenciesBridge.shared.db
            let deletedCallRecordCleanupManager = DependenciesBridge.shared.deletedCallRecordCleanupManager
            let groupCallPeekClient = SSKEnvironment.shared.groupCallManagerRef.groupCallPeekClient
            let identityKeyMismatchManager = DependenciesBridge.shared.identityKeyMismatchManager
            let inactiveLinkedDeviceFinder = DependenciesBridge.shared.inactiveLinkedDeviceFinder
            let interactionStore = DependenciesBridge.shared.interactionStore
            let masterKeySyncManager = DependenciesBridge.shared.masterKeySyncManager
            let notificationPresenter = SSKEnvironment.shared.notificationPresenterRef
            let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
            let storageServiceManager = SSKEnvironment.shared.storageServiceManagerRef
            let threadStore = DependenciesBridge.shared.threadStore
            let tsAccountManager = DependenciesBridge.shared.tsAccountManager

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

            let isPrimaryDevice = db.read { tx -> Bool in
                return tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice
            }

            // Things that should run on only the primary *or* linked devices.
            if isPrimaryDevice {
                Task {
                    do {
                        try await avatarDefaultColorStorageServiceMigrator.performMigrationIfNecessary()
                    } catch {
                        Logger.warn("Couldn't perform avatar default color migration: \(error)")
                    }
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

            Task {
                await deletedCallRecordCleanupManager.startCleanupIfNecessary()
            }

            Task { () async -> Void in
                await backupDisablingManager.disableRemotelyIfNecessary()
            }

            Task {
                await self.avatarHistoryManager.cleanupOrphanedImages()
            }

            Task {
                await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
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
