//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents the Release Notes thread.
public final class TSReleaseNotesThread: TSThread {
    override public class var recordType: SDSRecordType { .releaseNotesThread }

    @objc
    public class var releaseNotesUniqueId: String {
        "00000000-0000-5000-8000-00000000000A"
    }

    public class func createReleaseNotes(transaction: DBWriteTransaction) -> TSReleaseNotesThread {
        let releaseNotes = TSReleaseNotesThread(uniqueId: releaseNotesUniqueId)
        releaseNotes.shouldThreadBeVisible = true
        releaseNotes.anyInsert(transaction: transaction)
        return releaseNotes
    }

    override func deepCopy() -> TSThread {
        return TSReleaseNotesThread(
            id: self.id,
            uniqueId: self.uniqueId,
            creationDate: self.creationDate,
            editTargetTimestamp: self.editTargetTimestamp,
            isArchivedObsolete: self.isArchivedObsolete,
            isMarkedUnreadObsolete: self.isMarkedUnreadObsolete,
            lastDraftInteractionRowId: self.lastDraftInteractionRowId,
            lastDraftUpdateTimestamp: self.lastDraftUpdateTimestamp,
            lastInteractionRowId: self.lastInteractionRowId,
            lastSentStoryTimestamp: self.lastSentStoryTimestamp,
            mentionNotificationMode: self.mentionNotificationMode,
            messageDraft: self.messageDraft,
            messageDraftBodyRanges: self.messageDraftBodyRanges,
            mutedUntilTimestampObsolete: self.mutedUntilTimestampObsolete,
            shouldThreadBeVisible: self.shouldThreadBeVisible,
            storyViewMode: self.storyViewMode,
        )
    }

    @objc
    override public func recipientAddresses(with tx: DBReadTransaction) -> [SignalServiceAddress] {
        return []
    }
}
