//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wraps MediaGalleryRecordFinder for briging between legacy and v2 attachments.
public struct MediaGalleryResourceFinder {

    private var attachmentFinder: MediaGalleryAttachmentFinder

    public var thread: TSThread { attachmentFinder.thread }
    public var threadId: Int64 { attachmentFinder.threadId }

    /// Media will be restricted to this type. Otherwise there is no filtering.
    public var filter: AllMediaFilter {
        get { attachmentFinder.filter }
        set {
            attachmentFinder.filter = newValue
        }
    }

    public init(thread: TSThread, filter: AllMediaFilter) {
        self.attachmentFinder = MediaGalleryAttachmentFinder(thread: thread, filter: filter)
    }

    // MARK: -

    public func galleryItemIds(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [MediaGalleryItemId] {
        return attachmentFinder.galleryItemIds(
            in: givenInterval,
            excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
            offset: offset,
            ascending: ascending,
            tx: tx
        ).map { .v2($0) }
    }

    public func galleryItemIdsAndDates(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [DatedMediaGalleryItemId] {
        return attachmentFinder.galleryItemIdsAndDates(
            in: givenInterval,
            excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
            offset: offset,
            ascending: ascending,
            tx: tx
        ).map(\.asItemId)
    }

    public func recentMediaAttachments(limit: Int, tx: DBReadTransaction) -> [ReferencedAttachment] {
        var v2Items = [ReferencedAttachment]()
        v2Items = attachmentFinder.recentMediaAttachments(
            limit: limit,
            tx: tx
        )
        return v2Items
    }

    public func enumerateMediaAttachments(
        in dateInterval: DateInterval,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        range: NSRange,
        tx: DBReadTransaction,
        block: (Int, ReferencedAttachment) -> Void
    ) {
        return attachmentFinder.enumerateMediaAttachments(
            in: dateInterval,
            excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
            range: range,
            tx: tx,
            block: { index, referencedAttachment in
                block(index, referencedAttachment)
            }
        )
    }

    public typealias EnumerationCompletion = MediaGalleryAttachmentFinder.EnumerationCompletion

    public func enumerateTimestamps(
        before date: Date,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedMediaGalleryItemId) -> Void
    ) -> EnumerationCompletion {
        return attachmentFinder.enumerateTimestamps(
            before: date,
            excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
            count: count,
            tx: tx,
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
        return attachmentFinder.enumerateTimestamps(
            after: date,
            excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
            count: count,
            tx: tx,
            block: { datedId in
                block(datedId.asItemId)
            }
        )
    }

    // Disregards filter.
    public func galleryItemId(
        of attachment: ReferencedAttachmentStream,
        in interval: DateInterval,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        tx: DBReadTransaction
    ) -> MediaGalleryItemId? {
        let attachmentStream = attachment.attachmentStream
        let reference = attachment.reference
        return attachmentFinder.galleryItemId(
            of: .init(reference: reference, attachmentStream: attachmentStream),
            in: interval,
            excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
            tx: tx
        ).map { .v2($0) }
    }

    /// Returns the number of attachments attached to `interaction`, whether or not they are media attachments. Disregards allowedMediaType.
    public func countAllAttachments(
        of interaction: TSInteraction,
        tx: DBReadTransaction
    ) throws -> UInt {
        return try attachmentFinder.countAllAttachments(
            of: interaction,
            tx: tx
        )
    }

    public func isEmptyOfAttachments(
        interaction: TSInteraction,
        tx: DBReadTransaction
    ) throws -> Bool {
        return try countAllAttachments(of: interaction, tx: tx) == 0
    }

    // MARK: - Helpers

    private func bridgeLegacyAttachmentIds(
        _ attachmentIds: Set<MediaGalleryResourceId>
    ) -> Set<String> {
        return []
    }

    private func bridgeV2AttachmentIds(
        _ attachmentIds: Set<MediaGalleryResourceId>
    ) -> Set<AttachmentReferenceId> {
        var finalIds = Set<AttachmentReferenceId>()
        attachmentIds.forEach {
            switch $0 {
            case .v2(let id):
                finalIds.insert(id)
            }
        }
        return finalIds
    }
}
