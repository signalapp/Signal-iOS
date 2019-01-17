//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol NotificationsAdaptee: NotificationsProtocol, OWSCallNotificationsAdaptee { }

extension NotificationsManager: NotificationsAdaptee { }

/**
 * Present call related notifications to the user.
 */
@objc(OWSNotificationsAdapter)
public class NotificationsAdapter: NSObject, NotificationsProtocol {
    private let adaptee: NotificationsAdaptee

    @objc public override init() {
        self.adaptee = NotificationsManager()

        super.init()

        SwiftSingletons.register(self)
    }

    func presentIncomingCall(_ call: SignalCall, callerName: String) {
        Logger.debug("")
        adaptee.presentIncomingCall(call, callerName: callerName)
    }

    func presentMissedCall(_ call: SignalCall, callerName: String) {
        Logger.debug("")
        adaptee.presentMissedCall(call, callerName: callerName)
    }

    public func presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: SignalCall, callerName: String) {
        adaptee.presentMissedCallBecauseOfNoLongerVerifiedIdentity(call: call, callerName: callerName)
    }

    public func presentMissedCallBecauseOfNewIdentity(call: SignalCall, callerName: String) {
       adaptee.presentMissedCallBecauseOfNewIdentity(call: call, callerName: callerName)
    }

    // MJK TODO DI contactsManager
    public func notifyUser(for incomingMessage: TSIncomingMessage, in thread: TSThread, contactsManager: ContactsManagerProtocol, transaction: YapDatabaseReadTransaction) {
        adaptee.notifyUser(for: incomingMessage, in: thread, contactsManager: contactsManager, transaction: transaction)
    }

    public func notifyUser(for error: TSErrorMessage, thread: TSThread, transaction: YapDatabaseReadWriteTransaction) {
        adaptee.notifyUser(for: error, thread: thread, transaction: transaction)
    }

    public func notifyUser(forThreadlessErrorMessage error: TSErrorMessage, transaction: YapDatabaseReadWriteTransaction) {
        adaptee.notifyUser(forThreadlessErrorMessage: error, transaction: transaction)
    }

    public func clearAllNotifications() {
        adaptee.clearAllNotifications()
    }
}
