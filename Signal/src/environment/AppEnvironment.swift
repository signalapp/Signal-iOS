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

    @objc
    public var callMessageHandlerRef: WebRTCCallMessageHandler

    @objc
    public var callServiceRef: CallService

    @objc
    public var accountManagerRef: AccountManager

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

    private override init() {
        self.callMessageHandlerRef = WebRTCCallMessageHandler()
        self.callServiceRef = CallService()
        self.accountManagerRef = AccountManager()
        self.notificationPresenterRef = NotificationPresenter()
        self.pushRegistrationManagerRef = PushRegistrationManager()

        super.init()

        SwiftSingletons.register(self)
    }

    @objc
    public func setup() {
        callService.createCallUIAdapter()

        // Hang certain singletons on SSKEnvironment too.
        SSKEnvironment.shared.notificationsManagerRef = notificationPresenterRef
        SSKEnvironment.shared.callMessageHandlerRef = callMessageHandlerRef
        Environment.shared.lightweightCallManagerRef = callServiceRef
    }
}
