//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public class NoopNotificationPresenterImpl: NotificationPresenter {
    public func registerNotificationSettings() async {
        Logger.warn("")
    }

    public var expectErrors: Bool = false

    public init() {}

    public func notifyUser(forIncomingMessage incomingMessage: TSIncomingMessage,
                           thread: TSThread,
                           transaction: SDSAnyReadTransaction) {
        Logger.warn("")
    }

    public func notifyUser(forIncomingMessage incomingMessage: TSIncomingMessage,
                           editTarget: TSIncomingMessage,
                           thread: TSThread,
                           transaction: SDSAnyReadTransaction) {
        Logger.warn("")
    }

    public func notifyUser(forReaction reaction: OWSReaction,
                           onOutgoingMessage message: TSOutgoingMessage,
                           thread: TSThread,
                           transaction: SDSAnyReadTransaction) {
        Logger.warn("")
    }

    public func notifyUser(forErrorMessage errorMessage: TSErrorMessage,
                           thread: TSThread,
                           transaction: SDSAnyWriteTransaction) {
        Logger.warn("")
    }

    public func notifyUser(
        forTSMessage message: TSMessage,
        thread: TSThread,
        wantsSound: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        Logger.warn("")
    }

    public func notifyUser(forPreviewableInteraction previewableInteraction: TSInteraction & OWSPreviewText,
                           thread: TSThread,
                           wantsSound: Bool,
                           transaction: SDSAnyWriteTransaction) {
        Logger.warn("")
    }

    public func notifyTestPopulation(ofErrorMessage errorString: String) {
        owsAssertDebug(expectErrors, "Internal error message: \(errorString)")
        Logger.warn("")
    }

    public func notifyUser(forFailedStorySend storyMessage: StoryMessage, to thread: TSThread, transaction: SDSAnyWriteTransaction) {
        Logger.warn("")
    }

    public func notifyUserOfFailedSend(inThread thread: TSThread) {
        Logger.warn("")
    }

    public func notifyUserOfMissedCall(notificationInfo: CallNotificationInfo, offerMediaType: TSRecentCallOfferType, sentAt timestamp: Date, tx: SDSAnyReadTransaction) {
        Logger.warn("")
    }

    public func notifyUserOfMissedCallBecauseOfNewIdentity(notificationInfo: CallNotificationInfo, tx: SDSAnyReadTransaction) {
        Logger.warn("")
    }

    public func notifyUserOfMissedCallBecauseOfNoLongerVerifiedIdentity(notificationInfo: CallNotificationInfo, tx: SDSAnyReadTransaction) {
        Logger.warn("")
    }

    public func notifyForGroupCallSafetyNumberChange(callTitle: String, threadUniqueId: String?, roomId: Data?, presentAtJoin: Bool) {
        Logger.warn("")
    }

    public func scheduleNotifyForNewLinkedDevice() {
        Logger.warn("")
    }

    public func notifyUserToRelaunchAfterTransfer(completion: @escaping () -> Void) {
        Logger.warn("")
    }

    public func notifyUserOfDeregistration(tx: DBWriteTransaction) {
        Logger.warn("")
    }

    public func clearAllNotifications() {
        Logger.warn("")
    }

    public func clearAllNotificationsExceptNewLinkedDevices() {
        Logger.warn("")
    }

    public static func clearAllNotificationsExceptNewLinkedDevices() {
        Logger.warn("")
    }

    public func cancelNotifications(threadId: String) {
        Logger.warn("")
    }

    public func cancelNotifications(messageIds: [String]) {
        Logger.warn("")
    }

    public func cancelNotifications(reactionId: String) {
        Logger.warn("")
    }

    public func cancelNotificationsForMissedCalls(threadUniqueId: String) {
        Logger.warn("")
    }

    public func cancelNotifications(for storyMessage: StoryMessage) {
        Logger.warn("")
    }
}
