//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocol {

    public func notifyUser(for incomingMessage: TSIncomingMessage, thread: TSThread, transaction: SDSAnyReadTransaction) {
        Logger.warn("skipping notification for: \(incomingMessage.description)")
    }

    public func notifyUser(for reaction: OWSReaction, on message: TSOutgoingMessage, thread: TSThread, transaction: SDSAnyReadTransaction) {
        Logger.warn("skipping notification for: \(reaction.description)")
    }

    public func notifyUser(for errorMessage: TSErrorMessage, thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(errorMessage.description)")
    }

    public func notifyUser(for previewableInteraction: TSInteraction & OWSPreviewText, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(previewableInteraction.description)")
    }

    public func notifyUser(for errorMessage: ThreadlessErrorMessage, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(errorMessage.description)")
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

    public func notifyUserForGRDBMigration() {
        Logger.warn("notifyUserForGRDBMigration")
    }
}
