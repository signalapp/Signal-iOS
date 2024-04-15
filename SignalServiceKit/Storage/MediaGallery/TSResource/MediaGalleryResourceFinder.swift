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
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [MediaGalleryItemId] {
        return recordFinder.rowIds(
            in: givenInterval,
            excluding: bridgeDeletedAttachmentIds(deletedAttachmentIds),
            offset: offset,
            ascending: ascending,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        ).map { .legacy(mediaGalleryRecordId: $0) }
    }

    public func galleryItemIdsAndDates(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [DatedMediaGalleryItemId] {
        return recordFinder.rowIdsAndDates(
            in: givenInterval,
            excluding: bridgeDeletedAttachmentIds(deletedAttachmentIds),
            offset: offset,
            ascending: ascending,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        ).map(\.asItemId)
    }

    public func recentMediaAttachments(limit: Int, tx: DBReadTransaction) -> [TSAttachment] {
        return recordFinder.recentMediaAttachments(
            limit: limit,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
        )
    }

    public func enumerateMediaAttachments(
        in dateInterval: DateInterval,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        range: NSRange,
        tx: DBReadTransaction,
        block: (Int, ReferencedTSResource) -> Void
    ) {
        recordFinder.enumerateMediaAttachments(
            in: dateInterval,
            excluding: bridgeDeletedAttachmentIds(deletedAttachmentIds),
            range: range,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
            block: { index, attachment in
                block(index, attachment.bridgeReferenced)
            }
        )
    }

    public typealias EnumerationCompletion = MediaGalleryRecordFinder.EnumerationCompletion

    public func enumerateTimestamps(
        before date: Date,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedMediaGalleryItemId) -> Void
    ) -> EnumerationCompletion {
        return recordFinder.enumerateTimestamps(
            before: date,
            excluding: bridgeDeletedAttachmentIds(deletedAttachmentIds),
            count: count,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
            block: { datedId in
                block(datedId.asItemId)
            }
        )
    }

    public func enumerateTimestamps(
        after date: Date,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedMediaGalleryItemId) -> Void
    ) -> EnumerationCompletion {
        return recordFinder.enumerateTimestamps(
            after: date,
            excluding: bridgeDeletedAttachmentIds(deletedAttachmentIds),
            count: count,
            transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
            block: { datedId in
                block(datedId.asItemId)
            }
        )
    }

    // Disregards filter.
    public func galleryItemId(
        of attachment: TSResourceStream,
        in interval: DateInterval,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        tx: DBReadTransaction
    ) -> MediaGalleryItemId? {
        switch attachment.concreteStreamType {
        case .legacy(let attachment):
            return recordFinder.rowid(
                of: attachment,
                in: interval,
                excluding: bridgeDeletedAttachmentIds(deletedAttachmentIds),
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map { .legacy(mediaGalleryRecordId: $0) }
        case .v2:
            fatalError("Unimplemented!")
        }

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

    // MARK: - Helpers

    private func bridgeDeletedAttachmentIds(
        _ deletedAttachmentIds: Set<MediaGalleryResourceId>
    ) -> Set<String> {
        var deletedLegacyAttachmentIds = Set<String>()
        deletedAttachmentIds.forEach {
            switch $0 {
            case .legacy(let uniqueId):
                deletedLegacyAttachmentIds.insert(uniqueId)
            case .v2:
                fatalError("Unimplemented!")
            }
        }
        return deletedLegacyAttachmentIds
    }
}
