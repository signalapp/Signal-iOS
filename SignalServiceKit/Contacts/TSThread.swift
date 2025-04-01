//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension TSThread {
    public typealias RowId = Int64

    public var logString: String {
        return (self as? TSGroupThread)?.groupId.toHex() ?? self.uniqueId
    }

    // MARK: - updateWith...

    public func updateWithDraft(
        draftMessageBody: MessageBody?,
        replyInfo: ThreadReplyInfo?,
        editTargetTimestamp: UInt64?,
        transaction tx: DBWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.messageDraft = draftMessageBody?.text
            thread.messageDraftBodyRanges = draftMessageBody?.ranges
            thread.editTargetTimestamp = editTargetTimestamp.map { NSNumber(value: $0) }
        }

        if let replyInfo {
            DependenciesBridge.shared.threadReplyInfoStore
                .save(replyInfo, for: uniqueId, tx: tx)
        } else {
            DependenciesBridge.shared.threadReplyInfoStore
                .remove(for: uniqueId, tx: tx)
        }
    }

    public func updateWithMentionNotificationMode(
        _ mentionNotificationMode: TSThreadMentionNotificationMode,
        wasLocallyInitiated: Bool,
        transaction tx: DBWriteTransaction
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
    public func updateWithShouldThreadBeVisible(
        _ shouldThreadBeVisible: Bool,
        transaction tx: DBWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            thread.shouldThreadBeVisible = true
        }
    }

    public func updateWithLastSentStoryTimestamp(
        _ lastSentStoryTimestamp: UInt64,
        transaction tx: DBWriteTransaction
    ) {
        anyUpdate(transaction: tx) { thread in
            if lastSentStoryTimestamp > (thread.lastSentStoryTimestamp?.uint64Value ?? 0) {
                thread.lastSentStoryTimestamp = NSNumber(value: lastSentStoryTimestamp)
            }
        }
    }

    // MARK: -

    @objc
    func scheduleTouchFinalization(transaction tx: DBWriteTransaction) {
        tx.addFinalizationBlock(key: uniqueId) { tx in
            let databaseStorage = SSKEnvironment.shared.databaseStorageRef

            guard let selfThread = Self.anyFetch(uniqueId: self.uniqueId, transaction: tx) else {
                return
            }

            databaseStorage.touch(thread: selfThread, shouldReindex: false, tx: tx)
        }
    }
}
