//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@objc
public class NoopNotificationsManager: NSObject, NotificationsProtocolSwift {
    public var expectErrors: Bool = false

    public func notifyUser(forIncomingMessage incomingMessage: TSIncomingMessage,
                           thread: TSThread,
                           transaction: SDSAnyReadTransaction) {
        Logger.warn("skipping notification for: \(incomingMessage.description)")
    }

    public func notifyUser(forIncomingMessage incomingMessage: TSIncomingMessage,
                           editTarget: TSIncomingMessage,
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

    public func notifyUser(
        forTSMessage message: TSMessage,
        thread: TSThread,
        wantsSound: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.warn("skipping notification for: \(message.description)")
    }

    public func notifyUser(forPreviewableInteraction previewableInteraction: TSInteraction & OWSPreviewText,
                           thread: TSThread,
                           wantsSound: Bool,
                           transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping notification for: \(previewableInteraction.description)")
    }

    public func notifyTestPopulation(ofErrorMessage errorString: String) {
        owsAssertDebug(expectErrors, "Internal error message: \(errorString)")
        Logger.warn("Skipping internal error notification: \(errorString)")
    }

    public func notifyUser(forFailedStorySend storyMessage: StoryMessage, to thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping failed story send notification")
    }

    public func notifyUserToRelaunchAfterTransfer(completion: (() -> Void)? = nil) {
        Logger.warn("skipping transfer relaunch notification")
    }

    public func notifyUserOfDeregistration(tx: DBWriteTransaction) {
        Logger.warn("skipping deregistration notification")
    }

    public func notifyUserOfDeregistration(transaction: SDSAnyWriteTransaction) {
        Logger.warn("skipping deregistration notification")
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

    public func cancelNotifications(for storyMessage: StoryMessage) {
        Logger.warn("cancelNotifications(for storyMessage:) \(storyMessage.uniqueId)")
    }
}
