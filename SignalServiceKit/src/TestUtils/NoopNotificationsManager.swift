//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocol {

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
        owsFailDebug("Internal error message: \(errorString)")
        Logger.warn("Skipping internal error notification: \(errorString)")
    }

    public func clearAllNotifications() {
        Logger.warn("clearAllNotifications")
    }

    public func cancelNotifications(messageId: String) {
        Logger.warn("cancelNotifications for messageId: \(messageId)")
    }

    public func cancelNotifications(reactionId: String) {
        Logger.warn("cancelNotifications for reactionId: \(reactionId)")
    }
}
