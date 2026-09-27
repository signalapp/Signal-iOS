//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents the Release Notes thread.
public final class TSReleaseNotesThread: TSThread {
    override public class var recordType: TSThreadType { .releaseNotesThread }

    @objc
    public class var releaseNotesUniqueId: String {
        "00000000-0000-5000-8000-00000000000A"
    }

    public class func createReleaseNotes(transaction: DBWriteTransaction) -> TSReleaseNotesThread {
        let releaseNotes = TSReleaseNotesThread(uniqueId: releaseNotesUniqueId)
        releaseNotes.shouldThreadBeVisible = false
        releaseNotes.anyInsert(transaction: transaction)

        // Mute release notes thread by default.
        releaseNotes.updateWith(
            mutedUntilTimestamp: TSThread.alwaysMutedTimestamp,
            updateStorageService: false,
            transaction: transaction,
        )
        return releaseNotes
    }

    override func deepCopy() -> TSThread {
        return TSReleaseNotesThread(
            id: self.id,
            uniqueId: self.uniqueId,
            creationDate: self.creationDate,
            editTargetTimestamp: self.editTargetTimestamp,
            isArchived: self.isArchived,
            isMarkedUnread: self.isMarkedUnread,
            lastDraftInteractionRowId: self.lastDraftInteractionRowId,
            lastDraftUpdateTimestamp: self.lastDraftUpdateTimestamp,
            lastInteractionRowId: self.lastInteractionRowId,
            lastSentStoryTimestamp: self.lastSentStoryTimestamp,
            shouldNotifyForMentionsWhenMutedLegacy: self.shouldNotifyForMentionsWhenMutedLegacy,
            shouldNotifyForMentionsWhenMuted: self.shouldNotifyForMentionsWhenMuted,
            shouldNotifyForRepliesWhenMuted: self.shouldNotifyForRepliesWhenMuted,
            shouldNotifyForCallsWhenMuted: self.shouldNotifyForCallsWhenMuted,
            messageDraft: self.messageDraft,
            messageDraftBodyRanges: self.messageDraftBodyRanges,
            mutedUntilTimestamp: self.mutedUntilTimestamp,
            shouldThreadBeVisible: self.shouldThreadBeVisible,
            storyViewMode: self.storyViewMode,
            audioPlaybackRate: self.audioPlaybackRate,
        )
    }

    override func recordPendingUpdates(storageServiceManager: any StorageServiceManager) {
        storageServiceManager.recordPendingLocalAccountUpdates()
    }

    @objc
    override public func recipientAddresses(with tx: DBReadTransaction) -> [SignalServiceAddress] {
        return []
    }
}
