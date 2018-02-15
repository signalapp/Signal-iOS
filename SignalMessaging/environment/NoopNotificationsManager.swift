//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import SignalServiceKit

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocol {

    public func notifyUser(for incomingMessage: TSIncomingMessage!, in thread: TSThread!, contactsManager: ContactsManagerProtocol!, transaction: YapDatabaseReadTransaction!) {
        owsFail("\(self.logTag) in \(#function).")
    }

    public func notifyUser(for error: TSErrorMessage!, in thread: TSThread!) {
        Logger.warn("\(self.logTag) in \(#function), skipping notification for: \(error.description)")
    }
}
