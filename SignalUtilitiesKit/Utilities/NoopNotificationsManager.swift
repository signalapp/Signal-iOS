//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocol {

    public func notifyUser(for incomingMessage: TSIncomingMessage, in thread: TSThread, transaction: YapDatabaseReadTransaction) {
        owsFailDebug("")
    }
    
    public func cancelNotification(_ identifier: String) {
        owsFailDebug("")
    }

    public func clearAllNotifications() {
        Logger.warn("clearAllNotifications")
    }
}
