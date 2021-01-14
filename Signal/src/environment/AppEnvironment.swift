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
    public var callMessageHandler: WebRTCCallMessageHandler

    @objc
    public var callService: CallService

    @objc
    public var outboundIndividualCallInitiator: OutboundIndividualCallInitiator

    @objc
    public var accountManager: AccountManager

    @objc
    public var notificationPresenter: NotificationPresenter

    @objc
    public var pushRegistrationManager: PushRegistrationManager

    @objc
    public var sessionResetJobQueue: SessionResetJobQueue

    @objc
    public var backup: OWSBackup

    @objc
    public var userNotificationActionHandler: UserNotificationActionHandler

    @objc
    public var backupLazyRestore: BackupLazyRestore

    @objc
    let deviceTransferService = DeviceTransferService()

    @objc
    let audioPlayer = CVAudioPlayer()

    private override init() {
        self.callMessageHandler = WebRTCCallMessageHandler()
        self.callService = CallService()
        self.outboundIndividualCallInitiator = OutboundIndividualCallInitiator()
        self.accountManager = AccountManager()
        self.notificationPresenter = NotificationPresenter()
        self.pushRegistrationManager = PushRegistrationManager()
        self.sessionResetJobQueue = SessionResetJobQueue()
        self.backup = OWSBackup()
        self.backupLazyRestore = BackupLazyRestore()
        self.userNotificationActionHandler = UserNotificationActionHandler()

        super.init()

        SwiftSingletons.register(self)

        YDBToGRDBMigration.add(keyStore: backup.keyValueStore, label: "backup")
        YDBToGRDBMigration.add(keyStore: AppUpdateNag.shared.keyValueStore, label: "AppUpdateNag")
        YDBToGRDBMigration.add(keyStore: ProfileViewController.keyValueStore(), label: "ProfileViewController")
    }

    @objc
    public func setup() {
        callService.individualCallService.createCallUIAdapter()

        // Hang certain singletons on SSKEnvironment too.
        SSKEnvironment.shared.notificationsManager = notificationPresenter
        SSKEnvironment.shared.callMessageHandler = callMessageHandler
    }
}
