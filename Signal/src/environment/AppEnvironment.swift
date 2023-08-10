//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalMessaging

public class AppEnvironment: NSObject {

    private static var _shared: AppEnvironment = AppEnvironment()

    @objc
    public class var shared: AppEnvironment {
        get {
            return _shared
        }
        set {
            guard CurrentAppContext().isRunningTests else {
                owsFailDebug("Can only switch environments in tests.")
                return
            }

            _shared = newValue
        }
    }

    // A temporary hack until `.shared` goes away and this can be provided to `init`.
    static let sharedCallMessageHandler = WebRTCCallMessageHandler()

    public var callMessageHandlerRef: WebRTCCallMessageHandler

    public var callServiceRef: CallService

    public var accountManagerRef: AccountManager

    // A temporary hack until `.shared` goes away and this can be provided to `init`.
    static let sharedNotificationPresenter = NotificationPresenter()

    public var notificationPresenterRef: NotificationPresenter

    public var pushRegistrationManagerRef: PushRegistrationManager

    let deviceTransferServiceRef = DeviceTransferService()

    let avatarHistorManagerRef = AvatarHistoryManager()

    let cvAudioPlayerRef = CVAudioPlayer()

    let speechManagerRef = SpeechManager()

    let windowManagerRef = WindowManager()

    private(set) var appIconBadgeUpdater: AppIconBadgeUpdater!
    private(set) var badgeManager: BadgeManager!
    private var usernameValidationObserverRef: UsernameValidationObserver?

    private override init() {
        self.callMessageHandlerRef = Self.sharedCallMessageHandler
        self.callServiceRef = CallService()
        self.accountManagerRef = AccountManager()
        self.notificationPresenterRef = Self.sharedNotificationPresenter
        self.pushRegistrationManagerRef = PushRegistrationManager()

        super.init()

        SwiftSingletons.register(self)
    }

    func setup() {
        callService.createCallUIAdapter()

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
            let db = DependenciesBridge.shared.db
            let learnMyOwnPniManager = DependenciesBridge.shared.learnMyOwnPniManager
            let pniHelloWorldManager = DependenciesBridge.shared.pniHelloWorldManager
            let schedulers = DependenciesBridge.shared.schedulers

            learnMyOwnPniManager.learnMyOwnPniIfNecessary()
                .done(on: schedulers.global()) { () -> Void in
                    db.write { tx in
                        pniHelloWorldManager.sayHelloWorldIfNecessary(tx: tx)
                    }
                }
                .cauterize()
        }

        // Hang certain singletons on SMEnvironment too.
        SMEnvironment.shared.lightweightCallManagerRef = callServiceRef
    }
}
