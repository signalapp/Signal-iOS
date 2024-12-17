//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public protocol NotificationPresenter {
    func registerNotificationSettings() async

    func notifyUser(forIncomingMessage: TSIncomingMessage, thread: TSThread, transaction: SDSAnyReadTransaction)

    func notifyUser(forIncomingMessage: TSIncomingMessage, editTarget: TSIncomingMessage, thread: TSThread, transaction: SDSAnyReadTransaction)

    func notifyUser(forReaction: OWSReaction, onOutgoingMessage: TSOutgoingMessage, thread: TSThread, transaction: SDSAnyReadTransaction)

    func notifyUser(forErrorMessage: TSErrorMessage, thread: TSThread, transaction: SDSAnyWriteTransaction)

    func notifyUser(forTSMessage: TSMessage, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction)

    func notifyUser(forPreviewableInteraction: TSInteraction & OWSPreviewText, thread: TSThread, wantsSound: Bool, transaction: SDSAnyWriteTransaction)

    func notifyTestPopulation(ofErrorMessage errorString: String)

    func notifyUser(forFailedStorySend: StoryMessage, to: TSThread, transaction: SDSAnyWriteTransaction)

    func notifyUserOfFailedSend(inThread thread: TSThread)

    func notifyUserOfMissedCall(
        notificationInfo: CallNotificationInfo,
        offerMediaType: TSRecentCallOfferType,
        sentAt timestamp: Date,
        tx: SDSAnyReadTransaction
    )

    func notifyUserOfMissedCallBecauseOfNewIdentity(
        notificationInfo: CallNotificationInfo,
        tx: SDSAnyReadTransaction
    )

    func notifyUserOfMissedCallBecauseOfNoLongerVerifiedIdentity(
        notificationInfo: CallNotificationInfo,
        tx: SDSAnyReadTransaction
    )

    func notifyForGroupCallSafetyNumberChange(
        callTitle: String,
        threadUniqueId: String?,
        roomId: Data?,
        presentAtJoin: Bool
    )

    func scheduleNotifyForNewLinkedDevice()

    /// Notify user to relaunch the app after we deliberately terminate when an incoming device transfer completes.
    func notifyUserToRelaunchAfterTransfer(completion: @escaping () -> Void)

    /// Notify user of an auth error that has caused their device to be logged out (e.g. a 403 from the chat server).
    func notifyUserOfDeregistration(tx: DBWriteTransaction)

    func clearAllNotifications()
    func clearAllNotificationsExceptNewLinkedDevices()
    static func clearAllNotificationsExceptNewLinkedDevices()

    func cancelNotifications(threadId: String)

    func cancelNotifications(messageIds: [String])

    func cancelNotifications(reactionId: String)

    func cancelNotificationsForMissedCalls(threadUniqueId: String)

    func cancelNotifications(for storyMessage: StoryMessage)
}

@objc
class NotificationPresenterObjC: NSObject {
    @objc(cancelNotificationsForMessageId:)
    static func cancelNotifications(for messageId: String) {
        SSKEnvironment.shared.notificationPresenterRef.cancelNotifications(messageIds: [messageId])
    }
}

// MARK: -

public struct CallNotificationInfo {
    /// Basically a per-call unique identifier. When posting multiple
    /// notifications with the same `groupingId`, only the latest notification
    /// will be shown.
    let groupingId: UUID

    /// The thread that was called.
    let thread: TSContactThread

    /// The user who called the thread.
    let caller: Aci

    public init(groupingId: UUID, thread: TSContactThread, caller: Aci) {
        self.groupingId = groupingId
        self.thread = thread
        self.caller = caller
    }
}

// MARK: -

/// Which notifications should be suppressed (based on which view is currently visible).
enum NotificationSuppressionRule {
    /// Includes reactions to messages in the thread.
    case messagesInThread(threadUniqueId: String)
    case groupStoryReplies(threadUniqueId: String?, storyMessageTimestamp: UInt64)
    case failedStorySends
    case none
}
