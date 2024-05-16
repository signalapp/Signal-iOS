//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public class AppEnvironment: NSObject {

    private static var _shared: AppEnvironment?

    static func setSharedEnvironment(_ appEnvironment: AppEnvironment) {
        owsAssert(self._shared == nil)
        self._shared = appEnvironment
    }

    @objc
    public class var shared: AppEnvironment { _shared! }

    let pushRegistrationManagerRef: PushRegistrationManager

    var callService: CallService!

    let deviceTransferServiceRef: DeviceTransferService

    let avatarHistorManagerRef = AvatarHistoryManager()

    let cvAudioPlayerRef = CVAudioPlayer()

    let speechManagerRef = SpeechManager()

    let windowManagerRef = WindowManager()

    private(set) var appIconBadgeUpdater: AppIconBadgeUpdater!
    private(set) var badgeManager: BadgeManager!
    private var usernameValidationObserverRef: UsernameValidationObserver?

    init(deviceTransferService: DeviceTransferService) {
        self.deviceTransferServiceRef = deviceTransferService
        self.pushRegistrationManagerRef = PushRegistrationManager()

        super.init()

        SwiftSingletons.register(self)
    }

    func setUp(callService: CallService) {
        self.callService = callService

        self.badgeManager = BadgeManager(
            databaseStorage: databaseStorage,
            mainScheduler: DispatchQueue.main,
            serialScheduler: DispatchQueue.sharedUtility
        )
        self.appIconBadgeUpdater = AppIconBadgeUpdater(badgeManager: badgeManager)
        self.usernameValidationObserverRef = UsernameValidationObserver(
            manager: DependenciesBridge.shared.usernameValidationManager,
            database: DependenciesBridge.shared.db
        )

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.badgeManager.startObservingChanges(in: self.databaseStorage)
            self.appIconBadgeUpdater.startObserving()
        }

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            let isPrimaryDevice = self.databaseStorage.read { tx -> Bool in
                return DependenciesBridge.shared.tsAccountManager.registrationState(tx: tx.asV2Read).isPrimaryDevice ?? true
            }

            let db = DependenciesBridge.shared.db
            let deletedCallRecordCleanupManager = DependenciesBridge.shared.deletedCallRecordCleanupManager
            let groupCallRecordRingingCleanupManager = GroupCallRecordRingingCleanupManager.fromGlobals()
            let inactiveLinkedDeviceFinder = DependenciesBridge.shared.inactiveLinkedDeviceFinder
            let learnMyOwnPniManager = DependenciesBridge.shared.learnMyOwnPniManager
            let linkedDevicePniKeyManager = DependenciesBridge.shared.linkedDevicePniKeyManager
            let masterKeySyncManager = DependenciesBridge.shared.masterKeySyncManager
            let pniHelloWorldManager = DependenciesBridge.shared.pniHelloWorldManager
            let schedulers = DependenciesBridge.shared.schedulers

            if isPrimaryDevice {
                firstly(on: schedulers.sync) { () -> Promise<Void> in
                    learnMyOwnPniManager.learnMyOwnPniIfNecessary()
                }
                .done(on: schedulers.global()) {
                    db.write { tx in
                        pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
                    }
                }
                .cauterize()
            } else {
                db.read { tx in
                    linkedDevicePniKeyManager.validateLocalPniIdentityKeyIfNecessary(tx: tx)
                }
            }

            db.asyncWrite { tx in
                masterKeySyncManager.runStartupJobs(tx: tx)
            }

            db.asyncWrite { tx in
                groupCallRecordRingingCleanupManager.cleanupRingingCalls(tx: tx)
            }

            Task {
                await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
            }

            deletedCallRecordCleanupManager.startCleanupIfNecessary()
        }
    }
}
