//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public class NoopNotificationPresenterImpl: NotificationPresenter {
    public func registerNotificationSettings() async {
        Logger.warn("")
    }

    public var expectErrors: Bool = false

    public init() {}

    public func notifyUser(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        Logger.warn("")
    }

    public func notifyUser(
        forIncomingMessage incomingMessage: TSIncomingMessage,
        editTarget: TSIncomingMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        Logger.warn("")
    }

    public func notifyUser(
        forReaction reaction: OWSReaction,
        onOutgoingMessage message: TSOutgoingMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        Logger.warn("")
    }

    public func notifyUser(
        forErrorMessage errorMessage: TSErrorMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        Logger.warn("")
    }

    public func notifyUser(
        forTSMessage message: TSMessage,
        thread: TSThread,
        wantsSound: Bool,
        transaction: DBWriteTransaction,
    ) {
        Logger.warn("")
    }

    public func notifyUser(
        forPreviewableInteraction previewableInteraction: TSInteraction & OWSPreviewText,
        thread: TSThread,
        wantsSound: Bool,
        transaction: DBWriteTransaction,
    ) {
        Logger.warn("")
    }

    public func notifyUserOfPollEnd(
        forMessage message: TSIncomingMessage,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        Logger.warn("")
    }

    public func notifyUserOfPollVote(
        forMessage message: TSOutgoingMessage,
        voteAuthor: Aci,
        thread: TSThread,
        transaction: DBWriteTransaction,
    ) {
        Logger.warn("")
    }

    public func notifyTestPopulation(ofErrorMessage errorString: String) {
        owsAssertDebug(expectErrors, "Internal error message: \(errorString)")
        Logger.warn("")
    }

    public func notifyUser(forFailedStorySend storyMessage: StoryMessage, to thread: TSThread, transaction: DBWriteTransaction) {
        Logger.warn("")
    }

    public func notifyUserOfFailedSend(inThread thread: TSThread) {
        Logger.warn("")
    }

    public func notifyUserOfMissedCall(notificationInfo: CallNotificationInfo, offerMediaType: TSRecentCallOfferType, sentAt timestamp: Date, tx: DBReadTransaction) {
        Logger.warn("")
    }

    public func notifyUserOfMissedCallBecauseOfNewIdentity(notificationInfo: CallNotificationInfo, tx: DBWriteTransaction) {
        Logger.warn("")
    }

    public func notifyUserOfMissedCallBecauseOfNoLongerVerifiedIdentity(notificationInfo: CallNotificationInfo, tx: DBWriteTransaction) {
        Logger.warn("")
    }

    public func notifyForGroupCallSafetyNumberChange(callTitle: String, threadUniqueId: String?, roomId: Data?, presentAtJoin: Bool) {
        Logger.warn("")
    }

    public func scheduleNotifyForNewLinkedDevice(deviceLinkTimestamp: Date) {
        Logger.warn("")
    }

    public func scheduleNotifyForBackupsEnabled(backupsTimestamp: Date) {
        Logger.warn("")
    }

    public func notifyUserOfMediaTierQuotaConsumed() {
        Logger.warn("")
    }

    public func notifyUserOfListMediaIntegrityCheckFailure() {
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

    public func clearNotificationsForAppActivate() {
        Logger.warn("")
    }

    public func clearDeliveredNewLinkedDevicesNotifications() {
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
