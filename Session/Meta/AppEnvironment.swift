// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SignalUtilitiesKit

public class AppEnvironment {

    private static var _shared: AppEnvironment = AppEnvironment()

    public class var shared: AppEnvironment {
        get { return _shared }
        set {
            guard CurrentAppContext().isRunningTests else {
                owsFailDebug("Can only switch environments in tests.")
                return
            }

            _shared = newValue
        }
    }

    public var callManager: SessionCallManager
    public var notificationPresenter: NotificationPresenter
    public var pushRegistrationManager: PushRegistrationManager
    public var fileLogger: DDFileLogger

    // Stored properties cannot be marked as `@available`, only classes and functions.
    // Instead, store a private `Any` and wrap it with a public `@available` getter
    private var _userNotificationActionHandler: Any?

    public var userNotificationActionHandler: UserNotificationActionHandler {
        return _userNotificationActionHandler as! UserNotificationActionHandler
    }

    private init() {
        self.callManager = SessionCallManager()
        self.notificationPresenter = NotificationPresenter()
        self.pushRegistrationManager = PushRegistrationManager()
        self._userNotificationActionHandler = UserNotificationActionHandler()
        self.fileLogger = DDFileLogger()
        
        SwiftSingletons.register(self)
    }

    public func setup() {
        // Hang certain singletons on Environment too.
        Environment.shared?.callManager.mutate {
            $0 = callManager
        }
        Environment.shared?.notificationsManager.mutate {
            $0 = notificationPresenter
        }
        setupLogFiles()
    }
    
    private func setupLogFiles() {
        fileLogger.rollingFrequency = kDayInterval // Refresh everyday
        fileLogger.logFileManager.maximumNumberOfLogFiles = 3 // Save 3 days' log files
        DDLog.add(fileLogger)
    }
}
