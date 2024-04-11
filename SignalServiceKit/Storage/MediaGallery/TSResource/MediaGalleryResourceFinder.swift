//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wraps MediaGalleryRecordFinder for briging between legacy and v2 attachments.
public struct MediaGalleryResourceFinder {

    private var recordFinder: MediaGalleryRecordFinder

    public var thread: TSThread { recordFinder.thread }
    public var threadId: Int64 { recordFinder.threadId }

    /// Media will be restricted to this type. Otherwise there is no filtering.
    public var filter: AllMediaFilter {
        get { recordFinder.filter }
        set { recordFinder.filter = newValue }
    }

    public init(thread: TSThread, filter: AllMediaFilter) {
        self.recordFinder = MediaGalleryRecordFinder(thread: thread, filter: filter)
    }

    // MARK: -

    public func galleryItemIds(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<String>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [Int64] {
        return recordFinder.rowIds(
            in: givenInterval,
            excluding: deletedAttachmentIds,
            offset: offset,
            ascending: ascending,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )
    }

    public func galleryItemIdsAndDates(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<String>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [DatedMediaGalleryRecordId] {
        return recordFinder.rowIdsAndDates(
            in: givenInterval,
            excluding: deletedAttachmentIds,
            offset: offset,
            ascending: ascending,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )
    }

    public func recentMediaAttachments(limit: Int, tx: DBReadTransaction) -> [TSAttachment] {
        return recordFinder.recentMediaAttachments(
            limit: limit,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )
    }

    public func enumerateMediaAttachments(
        in dateInterval: DateInterval,
        excluding deletedAttachmentIds: Set<String>,
        range: NSRange,
        tx: DBReadTransaction,
        block: (Int, TSAttachment) -> Void
    ) {
        recordFinder.enumerateMediaAttachments(
            in: dateInterval,
            excluding: deletedAttachmentIds,
            range: range,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
            block: block
        )
    }

    public typealias EnumerationCompletion = MediaGalleryRecordFinder.EnumerationCompletion

    public func enumerateTimestamps(
        before date: Date,
        excluding deletedAttachmentIds: Set<String>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedMediaGalleryRecordId) -> Void
    ) -> EnumerationCompletion {
        return recordFinder.enumerateTimestamps(
            before: date,
            excluding: deletedAttachmentIds,
            count: count,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
            block: block
        )
    }

    public func enumerateTimestamps(
        after date: Date,
        excluding deletedAttachmentIds: Set<String>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedMediaGalleryRecordId) -> Void
    ) -> EnumerationCompletion {
        return recordFinder.enumerateTimestamps(
            after: date,
            excluding: deletedAttachmentIds,
            count: count,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
            block: block
        )
    }

    // Disregards filter.
    public func galleryItemId(
        of attachment: TSAttachmentStream,
        in interval: DateInterval,
        excluding deletedAttachmentIds: Set<String>,
        tx: DBReadTransaction
    ) -> Int64? {
        return recordFinder.rowid(
            of: attachment,
            in: interval,
            excluding: deletedAttachmentIds,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )
    }

    /// Returns the number of attachments attached to `interaction`, whether or not they are media attachments. Disregards allowedMediaType.
    public func countAllAttachments(
        of interaction: TSInteraction,
        tx: DBReadTransaction
    ) throws -> UInt {
        return try recordFinder.countAllAttachments(
            of: interaction,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )
    }
}
