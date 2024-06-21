//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wraps MediaGalleryRecordFinder for briging between legacy and v2 attachments.
public struct MediaGalleryResourceFinder {

    private var recordFinder: MediaGalleryRecordFinder
    private var attachmentFinder: MediaGalleryAttachmentFinder

    public var thread: TSThread { recordFinder.thread }
    public var threadId: Int64 { recordFinder.threadId }

    /// Media will be restricted to this type. Otherwise there is no filtering.
    public var filter: AllMediaFilter {
        get { recordFinder.filter }
        set {
            recordFinder.filter = newValue
            attachmentFinder.filter = newValue
        }
    }

    public init(thread: TSThread, filter: AllMediaFilter) {
        self.recordFinder = MediaGalleryRecordFinder(thread: thread, filter: filter)
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
        if shouldUseV2Finder(tx: tx) {
            return attachmentFinder.galleryItemIds(
                in: givenInterval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                offset: offset,
                ascending: ascending,
                tx: tx
            ).map { .v2($0) }
        } else {
            return recordFinder.rowIds(
                in: givenInterval,
                excluding: deletedAttachmentIds,
                offset: offset,
                ascending: ascending,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map { .legacy(mediaGalleryRecordId: $0) }
        }
    }

    public func galleryItemIdsAndDates(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [DatedMediaGalleryItemId] {
        if shouldUseV2Finder(tx: tx) {
            return attachmentFinder.galleryItemIdsAndDates(
                in: givenInterval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                offset: offset,
                ascending: ascending,
                tx: tx
            ).map(\.asItemId)
        } else {
            return recordFinder.rowIdsAndDates(
                in: givenInterval,
                excluding: deletedAttachmentIds,
                offset: offset,
                ascending: ascending,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map(\.asItemId)
        }
    }

    public func recentMediaAttachments(limit: Int, tx: DBReadTransaction) -> [ReferencedTSResource] {
        if shouldUseV2Finder(tx: tx) {
            return attachmentFinder.recentMediaAttachments(
                limit: limit,
                tx: tx
            ).map { $0.referencedTSResource }
        } else {
            return recordFinder.recentMediaAttachments(
                limit: limit,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            )
        }
    }

    public func enumerateMediaAttachments(
        in dateInterval: DateInterval,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        range: NSRange,
        tx: DBReadTransaction,
        block: (Int, ReferencedTSResource) -> Void
    ) {
        if shouldUseV2Finder(tx: tx) {
            return attachmentFinder.enumerateMediaAttachments(
                in: dateInterval,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                range: range,
                tx: tx,
                block: { index, referencedAttachment in
                    block(index, referencedAttachment.referencedTSResource)
                }
            )
        } else {
            return recordFinder.enumerateMediaAttachments(
                in: dateInterval,
                excluding: deletedAttachmentIds,
                range: range,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
                block: block
            )
        }
    }

    public typealias EnumerationCompletion = MediaGalleryAttachmentFinder.EnumerationCompletion

    public func enumerateTimestamps(
        before date: Date,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedMediaGalleryItemId) -> Void
    ) -> EnumerationCompletion {
        if shouldUseV2Finder(tx: tx) {
            return attachmentFinder.enumerateTimestamps(
                before: date,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                count: count,
                tx: tx,
                block: { datedId in
                    block(datedId.asItemId)
                }
            )
        } else {
            return recordFinder.enumerateTimestamps(
                before: date,
                excluding: deletedAttachmentIds,
                count: count,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
                block: { datedId in
                    block(datedId.asItemId)
                }
            )
        }
    }

    public func enumerateTimestamps(
        after date: Date,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedMediaGalleryItemId) -> Void
    ) -> EnumerationCompletion {
        if shouldUseV2Finder(tx: tx) {
            return attachmentFinder.enumerateTimestamps(
                after: date,
                excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                count: count,
                tx: tx,
                block: { datedId in
                    block(datedId.asItemId)
                }
            )
        } else {
            return recordFinder.enumerateTimestamps(
                after: date,
                excluding: deletedAttachmentIds,
                count: count,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead,
                block: { datedId in
                    block(datedId.asItemId)
                }
            )
        }
    }

    // Disregards filter.
    public func galleryItemId(
        of attachment: ReferencedTSResourceStream,
        in interval: DateInterval,
        excluding deletedAttachmentIds: Set<MediaGalleryResourceId>,
        tx: DBReadTransaction
    ) -> MediaGalleryItemId? {
        if shouldUseV2Finder(tx: tx) {
            switch (attachment.attachmentStream.concreteStreamType, attachment.reference.concreteType) {
            case (.legacy, _), (_, .legacy):
                fatalError("How do we have a TSAttachment after migrating?")
            case let (.v2(attachmentStream), .v2(reference)):
                return attachmentFinder.galleryItemId(
                    of: .init(reference: reference, attachmentStream: attachmentStream),
                    in: interval,
                    excluding: bridgeV2AttachmentIds(deletedAttachmentIds),
                    tx: tx
                ).map { .v2($0) }
            }
        } else {
            return recordFinder.rowid(
                of: attachment,
                in: interval,
                excluding: deletedAttachmentIds,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            ).map { .legacy(mediaGalleryRecordId: $0) }
        }
    }

    /// Returns the number of attachments attached to `interaction`, whether or not they are media attachments. Disregards allowedMediaType.
    public func countAllAttachments(
        of interaction: TSInteraction,
        tx: DBReadTransaction
    ) throws -> UInt {
        if shouldUseV2Finder(tx: tx) {
            return try attachmentFinder.countAllAttachments(
                of: interaction,
                tx: tx
            )
        } else {
            return try recordFinder.countAllAttachments(
                of: interaction,
                transaction: SDSDB.shimOnlyBridge(tx).unwrapGrdbRead
            )
        }
    }

    public func isEmptyOfAttachments(
        interaction: TSInteraction,
        tx: DBReadTransaction
    ) throws -> Bool {
        return try countAllAttachments(of: interaction, tx: tx) == 0
    }

    // MARK: - Helpers

    private func bridgeV2AttachmentIds(
        _ attachmentIds: Set<MediaGalleryResourceId>
    ) -> Set<AttachmentReferenceId> {
        var finalIds = Set<AttachmentReferenceId>()
        attachmentIds.forEach {
            switch $0 {
            case .legacy:
                owsFailDebug("Mixing v1 and v2 attachments!")
            case .v2(let id):
                finalIds.insert(id)
            }
        }
        return finalIds
    }

    private func shouldUseV2Finder(tx: DBReadTransaction) -> Bool {
        return DependenciesBridge.shared.tsResourceManager
            .didFinishTSAttachmentToAttachmentMigration(tx: tx)
    }
}
