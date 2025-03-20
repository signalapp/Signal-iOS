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
    private(set) var badgeManager: BadgeManager!
    private(set) var callLinkProfileKeySharingManager: CallLinkProfileKeySharingManager!
    private(set) var callService: CallService!
    private var usernameValidationObserverRef: UsernameValidationObserver!

    init(appReadiness: AppReadiness, deviceTransferService: DeviceTransferService) {
        self.deviceTransferServiceRef = deviceTransferService
        self.pushRegistrationManagerRef = PushRegistrationManager(appReadiness: appReadiness)

        super.init()

        SwiftSingletons.register(self)
    }

    func setUp(appReadiness: AppReadiness, callService: CallService) {
        let badgeManager = BadgeManager(
            databaseStorage: SSKEnvironment.shared.databaseStorageRef,
            mainScheduler: DispatchQueue.main,
            serialScheduler: DispatchQueue.sharedUtility
        )

        self.appIconBadgeUpdater = AppIconBadgeUpdater(badgeManager: badgeManager)
        self.avatarHistoryManager = AvatarHistoryManager(
            appReadiness: appReadiness,
            db: DependenciesBridge.shared.db
        )
        self.badgeManager = badgeManager
        self.callService = callService
        self.callLinkProfileKeySharingManager = CallLinkProfileKeySharingManager(
            db: DependenciesBridge.shared.db,
            accountManager: DependenciesBridge.shared.tsAccountManager
        )
        self.usernameValidationObserverRef = UsernameValidationObserver(
            appReadiness: appReadiness,
            manager: DependenciesBridge.shared.usernameValidationManager,
            database: DependenciesBridge.shared.db
        )

        appReadiness.runNowOrWhenAppWillBecomeReady {
            self.badgeManager.startObservingChanges(in: DependenciesBridge.shared.databaseChangeObserver)
            self.appIconBadgeUpdater.startObserving()
        }

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            let isPrimaryDevice = SSKEnvironment.shared.databaseStorageRef.read { tx -> Bool in
                return DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? true
            }

            let backupSubscriptionManager = DependenciesBridge.shared.backupSubscriptionManager
            let db = DependenciesBridge.shared.db
            let deletedCallRecordCleanupManager = DependenciesBridge.shared.deletedCallRecordCleanupManager
            let groupCallRecordRingingCleanupManager = GroupCallRecordRingingCleanupManager.fromGlobals()
            let inactiveLinkedDeviceFinder = DependenciesBridge.shared.inactiveLinkedDeviceFinder
            let learnMyOwnPniManager = DependenciesBridge.shared.learnMyOwnPniManager
            let linkedDevicePniKeyManager = DependenciesBridge.shared.linkedDevicePniKeyManager
            let masterKeySyncManager = DependenciesBridge.shared.masterKeySyncManager
            let pniHelloWorldManager = DependenciesBridge.shared.pniHelloWorldManager

            if isPrimaryDevice {
                Task {
                    do {
                        try await learnMyOwnPniManager.learnMyOwnPniIfNecessary()
                        try await pniHelloWorldManager.sayHelloWorldIfNecessary()
                    } catch {
                        Logger.warn("Couldn't initialize PNI: \(error)")
                    }
                }
            } else {
                Task {
                    await linkedDevicePniKeyManager.validateLocalPniIdentityKeyIfNecessary()
                }
            }

            db.asyncWrite { tx in
                masterKeySyncManager.runStartupJobs(tx: tx)
            }

            db.asyncWrite { tx in
                groupCallRecordRingingCleanupManager.cleanupRingingCalls(tx: tx)
            }

            DispatchQueue.global().async {
                self.avatarHistoryManager.cleanupOrphanedImages()
            }

            Task {
                await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
            }

            deletedCallRecordCleanupManager.startCleanupIfNecessary()

            Task {
                do {
                    try await backupSubscriptionManager.redeemSubscriptionIfNecessary()
                } catch {
                    owsFailDebug("Failed to redeem subscription in launch job: \(error)")
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
