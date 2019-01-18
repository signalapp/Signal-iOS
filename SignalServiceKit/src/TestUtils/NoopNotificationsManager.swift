//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocol {

    public func notifyUser(for incomingMessage: TSIncomingMessage, in thread: TSThread, contactsManager: ContactsManagerProtocol, transaction: YapDatabaseReadTransaction) {
        owsFailDebug("")
    }

    public func notifyUser(for error: TSErrorMessage, thread: TSThread, transaction: YapDatabaseReadWriteTransaction) {
        Logger.warn("skipping notification for: \(error.description)")
    }

    public func notifyUser(forThreadlessErrorMessage error: TSErrorMessage, transaction: YapDatabaseReadWriteTransaction) {
        Logger.warn("skipping notification for: \(error.description)")
    }

    public func clearAllNotifications() {
        Logger.warn("clearAllNotifications")
    }
}
