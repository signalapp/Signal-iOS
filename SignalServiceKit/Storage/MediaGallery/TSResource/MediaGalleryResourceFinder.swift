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

    public func rowIds(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<String>,
        offset: Int,
        ascending: Bool,
        transaction: GRDBReadTransaction
    ) -> [Int64] {
        return recordFinder.rowIds(
            in: givenInterval,
            excluding: deletedAttachmentIds,
            offset: offset,
            ascending: ascending,
            transaction: transaction
        )
    }

    public func rowIdsAndDates(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<String>,
        offset: Int,
        ascending: Bool,
        transaction: GRDBReadTransaction
    ) -> [DatedMediaGalleryRecordId] {
        return recordFinder.rowIdsAndDates(
            in: givenInterval,
            excluding: deletedAttachmentIds,
            offset: offset,
            ascending: ascending,
            transaction: transaction
        )
    }

    public func recentMediaAttachments(limit: Int, transaction: GRDBReadTransaction) -> [TSAttachment] {
        return recordFinder.recentMediaAttachments(limit: limit, transaction: transaction)
    }

    public func enumerateMediaAttachments(
        in dateInterval: DateInterval,
        excluding deletedAttachmentIds: Set<String>,
        range: NSRange,
        transaction: GRDBReadTransaction,
        block: (Int, TSAttachment) -> Void
    ) {
        recordFinder.enumerateMediaAttachments(
            in: dateInterval,
            excluding: deletedAttachmentIds,
            range: range,
            transaction: transaction,
            block: block
        )
    }

    public typealias EnumerationCompletion = MediaGalleryRecordFinder.EnumerationCompletion

    public func enumerateTimestamps(
        before date: Date,
        excluding deletedAttachmentIds: Set<String>,
        count: Int,
        transaction: GRDBReadTransaction,
        block: (Date, Int64) -> Void
    ) -> EnumerationCompletion {
        return recordFinder.enumerateTimestamps(
            before: date,
            excluding: deletedAttachmentIds,
            count: count,
            transaction: transaction,
            block: block
        )
    }

    public func enumerateTimestamps(
        after date: Date,
        excluding deletedAttachmentIds: Set<String>,
        count: Int,
        transaction: GRDBReadTransaction,
        block: (Date, Int64) -> Void
    ) -> EnumerationCompletion {
        return recordFinder.enumerateTimestamps(
            after: date,
            excluding: deletedAttachmentIds,
            count: count,
            transaction: transaction,
            block: block
        )
    }

    // Disregards filter.
    public func rowid(
        of attachment: TSAttachmentStream,
        in interval: DateInterval,
        excluding deletedAttachmentIds: Set<String>,
        transaction: GRDBReadTransaction
    ) -> Int64? {
        return recordFinder.rowid(
            of: attachment,
            in: interval,
            excluding: deletedAttachmentIds,
            transaction: transaction
        )
    }

    /// Returns the number of attachments attached to `interaction`, whether or not they are media attachments. Disregards allowedMediaType.
    public func countAllAttachments(
        of interaction: TSInteraction,
        transaction: GRDBReadTransaction
    ) throws -> UInt {
        return try recordFinder.countAllAttachments(of: interaction, transaction: transaction)
    }
}
