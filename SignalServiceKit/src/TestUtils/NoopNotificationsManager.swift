//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocol {

    public func notifyUser(for incomingMessage: TSIncomingMessage, in thread: TSThread, transaction: SDSAnyReadTransaction) {
        Logger.warn("skipping notification for: \(incomingMessage.description)")
    }

    public func notifyUser(for errorMessage: TSErrorMessage, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(errorMessage.description)")
    }

    public func notifyUser(for infoMessage: TSInfoMessage, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(infoMessage.description)")
    }

    public func notifyUser(for errorMessage: ThreadlessErrorMessage, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(errorMessage.description)")
    }

    public func clearAllNotifications() {
        Logger.warn("clearAllNotifications")
    }
}
