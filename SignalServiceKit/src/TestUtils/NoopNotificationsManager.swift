//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocol {

    public func notifyUser(for incomingMessage: TSIncomingMessage, in thread: TSThread, transaction: SDSAnyReadTransaction) {
        owsFailDebug("")
    }

    public func notifyUser(for error: TSErrorMessage, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(error.description)")
    }

    public func notifyUser(for info: TSInfoMessage, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(info.description)")
    }

    public func notifyUser(forThreadlessErrorMessage error: TSErrorMessage, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(error.description)")
    }

    public func clearAllNotifications() {
        Logger.warn("clearAllNotifications")
    }
}
