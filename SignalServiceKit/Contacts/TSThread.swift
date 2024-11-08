//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

// MARK: - updateWith...

extension TSThread {
    public func updateWithDraft(
        draftMessageBody: MessageBody?,
        replyInfo: ThreadReplyInfo?,
        editTargetTimestamp: UInt64?,
        transaction tx: SDSAnyWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.messageDraft = draftMessageBody?.text
            thread.messageDraftBodyRanges = draftMessageBody?.ranges
            thread.editTargetTimestamp = editTargetTimestamp.map { NSNumber(value: $0) }
        }

        if let replyInfo {
            DependenciesBridge.shared.threadReplyInfoStore
                .save(replyInfo, for: uniqueId, tx: tx.asV2Write)
        } else {
            DependenciesBridge.shared.threadReplyInfoStore
                .remove(for: uniqueId, tx: tx.asV2Write)
        }
    }

    public func updateWithMentionNotificationMode(
        _ mentionNotificationMode: TSThreadMentionNotificationMode,
        wasLocallyInitiated: Bool,
        transaction tx: SDSAnyWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.mentionNotificationMode = mentionNotificationMode
        }

        if
            wasLocallyInitiated,
            let groupThread = self as? TSGroupThread,
            groupThread.isGroupV2Thread
        {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(
                groupModel: groupThread.groupModel
            )
        }
    }

    /// Updates `shouldThreadBeVisible`.
    ///
    /// This method needs to be `@objc` since it is both declared in an
    /// extension and is overridden by `TSPrivateStoryThread`.
    @objc
    public func updateWithShouldThreadBeVisible(
        _ shouldThreadBeVisible: Bool,
        transaction tx: SDSAnyWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.shouldThreadBeVisible = true
        }
    }

    public func updateWithLastSentStoryTimestamp(
        _ lastSentStoryTimestamp: UInt64,
        transaction tx: SDSAnyWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            if lastSentStoryTimestamp > (thread.lastSentStoryTimestamp?.uint64Value ?? 0) {
                thread.lastSentStoryTimestamp = NSNumber(value: lastSentStoryTimestamp)
            }
        }
    }

    public func updateWithStoryViewMode(
        _ storyViewMode: TSThreadStoryViewMode,
        transaction tx: SDSAnyWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.storyViewMode = storyViewMode
        }
    }
}
