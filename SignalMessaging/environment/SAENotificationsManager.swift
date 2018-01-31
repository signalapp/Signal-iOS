//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit

@objc
public class SAENotificationsManager: NSObject, NotificationsProtocol {

    @objc
    override public required init() {
        AssertIsOnMainThread()

        super.init()

        SwiftSingletons.register(self)
    }

    @objc
    public func notifyUser(for incomingMessage: TSIncomingMessage!, in thread: TSThread!, contactsManager: ContactsManagerProtocol!, transaction: YapDatabaseReadTransaction!) {
        owsFail("\(self.logTag) in \(#function).")
    }

    @objc
    public func notifyUser(for error: TSErrorMessage!, in thread: TSThread!) {
        Logger.error("\(self.logTag) in \(#function).")
        guard let message = NotificationUtils.alertMessage(forErrorMessage: error, inThread: thread, notificationType: .namePreview) else {
            owsFail("\(self.logTag) in \(#function).")
            return
        }
        OWSAlerts.showAlert(withTitle: NSLocalizedString("ALERT_ERROR_TITLE",
                                                         comment: ""),
                            message: message)
    }
}
