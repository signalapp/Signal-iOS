//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocol {
    public var expectErrors: Bool = false

    public func notifyUser(forIncomingMessage incomingMessage: TSIncomingMessage,
                           thread: TSThread,
                           transaction: SDSAnyReadTransaction) {
        Logger.warn("skipping notification for: \(incomingMessage.description)")
    }

    public func notifyUser(forReaction reaction: OWSReaction,
                           onOutgoingMessage message: TSOutgoingMessage,
                           thread: TSThread,
                           transaction: SDSAnyReadTransaction) {
        Logger.warn("skipping notification for: \(reaction.description)")
    }

    public func notifyUser(forErrorMessage errorMessage: TSErrorMessage,
                           thread: TSThread,
                           transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(errorMessage.description)")
    }

    public func notifyUser(forPreviewableInteraction previewableInteraction: TSInteraction & OWSPreviewText,
                           thread: TSThread,
                           wantsSound: Bool,
                           transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(previewableInteraction.description)")
    }

    public func notifyUser(forThreadlessErrorMessage errorMessage: ThreadlessErrorMessage,
                           transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(errorMessage.description)")
    }

    public func notifyTestPopulation(ofErrorMessage errorString: String) {
        owsAssertDebug(expectErrors, "Internal error message: \(errorString)")
        Logger.warn("Skipping internal error notification: \(errorString)")
    }

    public func clearAllNotifications() {
        Logger.warn("clearAllNotifications")
    }

    public func cancelNotifications(threadId: String) {
        Logger.warn("cancelNotifications for threadId: \(threadId)")
    }

    public func cancelNotifications(messageIds: [String]) {
        Logger.warn("cancelNotifications for messageIds: \(messageIds)")
    }

    public func cancelNotifications(reactionId: String) {
        Logger.warn("cancelNotifications for reactionId: \(reactionId)")
    }

    public func cancelNotificationsForMissedCalls(threadUniqueId: String) {
        Logger.warn("cancelNotificationsForMissedCalls for threadId: \(threadUniqueId)")
    }
}
