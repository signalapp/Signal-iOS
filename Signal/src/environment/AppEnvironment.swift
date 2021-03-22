//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
    public var outboundIndividualCallInitiatorRef: OutboundIndividualCallInitiator

    @objc
    public var accountManagerRef: AccountManager

    @objc
    public var notificationPresenterRef: NotificationPresenter

    @objc
    public var pushRegistrationManagerRef: PushRegistrationManager

    @objc
    public var sessionResetJobQueueRef: SessionResetJobQueue

    @objc
    public var backupRef: OWSBackup

    @objc
    public var userNotificationActionHandlerRef: UserNotificationActionHandler

    @objc
    public var backupLazyRestoreRef: BackupLazyRestore

    @objc
    let deviceTransferServiceRef = DeviceTransferService()

    @objc
    let cvAudioPlayerRef = CVAudioPlayer()

    private override init() {
        self.callMessageHandlerRef = WebRTCCallMessageHandler()
        self.callServiceRef = CallService()
        self.outboundIndividualCallInitiatorRef = OutboundIndividualCallInitiator()
        self.accountManagerRef = AccountManager()
        self.notificationPresenterRef = NotificationPresenter()
        self.pushRegistrationManagerRef = PushRegistrationManager()
        self.sessionResetJobQueueRef = SessionResetJobQueue()
        self.backupRef = OWSBackup()
        self.backupLazyRestoreRef = BackupLazyRestore()
        self.userNotificationActionHandlerRef = UserNotificationActionHandler()

        super.init()

        SwiftSingletons.register(self)

        YDBToGRDBMigration.add(keyStore: backupRef.keyValueStore, label: "backup")
        YDBToGRDBMigration.add(keyStore: AppUpdateNag.shared.keyValueStore, label: "AppUpdateNag")
    }

    @objc
    public func setup() {
        callService.individualCallService.createCallUIAdapter()

        // Hang certain singletons on SSKEnvironment too.
        SSKEnvironment.shared.notificationsManagerRef = notificationPresenterRef
        SSKEnvironment.shared.callMessageHandlerRef = callMessageHandlerRef
    }
}
