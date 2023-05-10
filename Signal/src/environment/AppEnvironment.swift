//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc
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

    @objc
    public var callMessageHandlerRef: WebRTCCallMessageHandler

    @objc
    public var callServiceRef: CallService

    @objc
    public var accountManagerRef: AccountManager

    // A temporary hack until `.shared` goes away and this can be provided to `init`.
    static let sharedNotificationPresenter = NotificationPresenter()

    @objc
    public var notificationPresenterRef: NotificationPresenter

    @objc
    public var pushRegistrationManagerRef: PushRegistrationManager

    @objc
    let deviceTransferServiceRef = DeviceTransferService()

    @objc
    let avatarHistorManagerRef = AvatarHistoryManager()

    @objc
    let cvAudioPlayerRef = CVAudioPlayer()

    @objc
    let speechManagerRef = SpeechManager()

    @objc
    public var windowManagerRef: OWSWindowManager = OWSWindowManager()

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

    @objc
    public func setup() {
        callService.createCallUIAdapter()

        self.usernameValidationObserverRef = UsernameValidationObserver(
            manager: DependenciesBridge.shared.usernameValidationManager,
            database: DependenciesBridge.shared.db
        )

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            DependenciesBridge.shared.db.read { tx in
                DependenciesBridge.shared.learnMyOwnPniManager.learnMyOwnPniIfNecessary(tx: tx)
            }
        }

        // Hang certain singletons on Environment too.
        Environment.shared.lightweightCallManagerRef = callServiceRef
    }
}
