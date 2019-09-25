//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalServiceKit
import SignalMessaging

@objc public class AppEnvironment: NSObject {

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
    public var outboundCallInitiator: OutboundCallInitiator

    @objc
    public var messageFetcherJob: MessageFetcherJob

    @objc
    public var accountManager: AccountManager

    @objc
    public var notificationPresenter: NotificationPresenter

    @objc
    public var pushRegistrationManager: PushRegistrationManager

    @objc
    public var sessionResetJobQueue: SessionResetJobQueue

    @objc
    public var broadcastMediaMessageJobQueue: BroadcastMediaMessageJobQueue

    @objc
    public var backup: OWSBackup

    private var _legacyNotificationActionHandler: LegacyNotificationActionHandler
    @objc
    public var legacyNotificationActionHandler: LegacyNotificationActionHandler {
        get {
            if #available(iOS 10, *) {
                owsFailDebug("shouldn't user legacyNotificationActionHandler on modern iOS")
            }
            return _legacyNotificationActionHandler
        }
        set {
            _legacyNotificationActionHandler = newValue
        }
    }

    // Stored properties cannot be marked as `@available`, only classes and functions.
    // Instead, store a private `Any` and wrap it with a public `@available` getter
    private var _userNotificationActionHandler: Any?

    @objc
    @available(iOS 10.0, *)
    public var userNotificationActionHandler: UserNotificationActionHandler {
        return _userNotificationActionHandler as! UserNotificationActionHandler
    }

    @objc
    public var backupLazyRestore: BackupLazyRestore

    private override init() {
        self.callMessageHandler = WebRTCCallMessageHandler()
        self.callService = CallService()
        self.outboundCallInitiator = OutboundCallInitiator()
        self.messageFetcherJob = MessageFetcherJob()
        self.accountManager = AccountManager()
        self.notificationPresenter = NotificationPresenter()
        self.pushRegistrationManager = PushRegistrationManager()
        self.sessionResetJobQueue = SessionResetJobQueue()
        self.broadcastMediaMessageJobQueue = BroadcastMediaMessageJobQueue()
        self.backup = OWSBackup()
        self.backupLazyRestore = BackupLazyRestore()
        if #available(iOS 10.0, *) {
            self._userNotificationActionHandler = UserNotificationActionHandler()
        }
        self._legacyNotificationActionHandler = LegacyNotificationActionHandler()

        super.init()

        SwiftSingletons.register(self)

        YDBToGRDBMigration.add(keyStore: backup.keyValueStore, label: "backup")
        YDBToGRDBMigration.add(keyStore: AppUpdateNag.shared.keyValueStore, label: "AppUpdateNag")
        YDBToGRDBMigration.add(keyStore: ProfileViewController.keyValueStore(), label: "ProfileViewController")
    }

    @objc
    public func setup() {
        callService.createCallUIAdapter()

        // Hang certain singletons on SSKEnvironment too.
        SSKEnvironment.shared.notificationsManager = notificationPresenter
        SSKEnvironment.shared.callMessageHandler = callMessageHandler
    }
}
