//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit

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
}
