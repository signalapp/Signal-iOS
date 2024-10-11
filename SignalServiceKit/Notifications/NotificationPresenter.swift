//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol NotificationPresenter {
    func notifyUser(forIncomingMessage: TSIncomingMessage, thread: TSThread, transaction: SDSAnyReadTransaction)

    func notifyUser(forIncomingMessage: TSIncomingMessage, editTarget: TSIncomingMessage, thread: TSThread, transaction: SDSAnyReadTransaction)

    func notifyUser(forReaction: OWSReaction, onOutgoingMessage: TSOutgoingMessage, thread: TSThread, transaction: SDSAnyReadTransaction)

    func notifyUser(forErrorMessage: TSErrorMessage, thread: TSThread, transaction: SDSAnyWriteTransaction)

    func notifyUser(forTSMessage: TSMessage, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction)

    func notifyUser(forPreviewableInteraction: TSInteraction & OWSPreviewText, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction)

    func notifyTestPopulation(ofErrorMessage errorString: String)

    func notifyUser(forFailedStorySend: StoryMessage, to: TSThread, transaction: SDSAnyWriteTransaction)

    /// Notify user to relaunch the app after we deliberately terminate when an incoming device transfer completes.
    func notifyUserToRelaunchAfterTransfer(completion: @escaping () -> Void)

    /// Notify user of an auth error that has caused their device to be logged out (e.g. a 403 from the chat server).
    func notifyUserOfDeregistration(transaction: SDSAnyWriteTransaction)

    func clearAllNotifications()

    func cancelNotifications(threadId: String)

    func cancelNotifications(messageIds: [String])

    func cancelNotifications(reactionId: String)

    func cancelNotificationsForMissedCalls(threadUniqueId: String)

    func cancelNotifications(for storyMessage: StoryMessage)

    func notifyUserOfDeregistration(tx: DBWriteTransaction)
}

/// Which notifications should be suppressed (based on which view is currently visible).
enum NotificationSuppressionRule {
    /// Includes reactions to messages in the thread.
    case messagesInThread(threadUniqueId: String)
    case groupStoryReplies(threadUniqueId: String?, storyMessageTimestamp: UInt64)
    case failedStorySends
    case none
}

@objc
class NotificationPresenterObjC: NSObject {
    @objc(cancelNotificationsForMessageId:)
    static func cancelNotifications(for messageId: String) {
        SSKEnvironment.shared.notificationPresenterRef.cancelNotifications(messageIds: [messageId])
    }
}
