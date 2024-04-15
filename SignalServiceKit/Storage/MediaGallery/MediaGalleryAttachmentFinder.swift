//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Fulfills the contract of MediaGalleryResourceFinder for v2 attachments only.,
/// driven entirely by the AttachmentReferences table.
///
/// Even this is still a stepping stone. The API contract for the MediaGalleryFinder
/// classes as written assumes that the thing being iterated over (MediaGalleryRecord)
/// and the attachment information itself (on TSMessage/TSAttachment) are not the same
/// table. Thus they are built around a two-step fetch: first we fetch sorted Ids, then we
/// fetch the attachment itself and its metadata.
///
/// After legacy attachments are _entirely_ out of the picture, this class can be updated
/// to do this more cleanly. We still need a second fetch for the Attachment, but instead
/// of returning AttachmentReferenceIds we can just return the full AttachmentReference,
/// and save the trouble of re-fetching it by id later.
/// That is left as an exercise for some future developer.
public struct MediaGalleryAttachmentFinder {

    public let thread: TSThread

    /// Media will be restricted to this type. Otherwise there is no filtering.
    public var filter: AllMediaFilter

    public init(thread: TSThread, filter: AllMediaFilter) {
        owsAssertDebug(thread.grdbId != 0, "only supports GRDB")
        self.thread = thread
        self.filter = filter
    }

    // MARK: -

    public var threadId: Int64 {
        guard let rowId = thread.grdbId else {
            owsFailDebug("thread.grdbId was unexpectedly nil")
            return 0
        }
        return rowId.int64Value
    }

    // MARK: - Public Methods

    public func galleryItemIds(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [AttachmentReferenceId] {
        // TODO: fetch from the AttachmentReferences table
        fatalError("Unimplemented")
    }

    public func galleryItemIdsAndDates(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [DatedAttachmentReferenceId] {
        // TODO: fetch from the AttachmentReferences table
        fatalError("Unimplemented")
    }

    public func recentMediaAttachments(limit: Int, tx: DBReadTransaction) -> [ReferencedAttachment] {
        // TODO: fetch from the AttachmentReferences table
        fatalError("Unimplemented")
    }

    public func enumerateMediaAttachments(
        in dateInterval: DateInterval,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        range: NSRange,
        tx: DBReadTransaction,
        block: (Int, ReferencedAttachment) -> Void
    ) {
        // TODO: iterate over the AttachmentReferences table
        fatalError("Unimplemented")
    }

    public enum EnumerationCompletion {
        /// Enumeration completed normally.
        case finished
        /// The query ran out of items.
        case reachedEnd
    }

    public func enumerateTimestamps(
        before date: Date,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedAttachmentReferenceId) -> Void
    ) -> EnumerationCompletion {
        // TODO: iterate over the AttachmentReferences table
        fatalError("Unimplemented")
    }

    public func enumerateTimestamps(
        after date: Date,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedAttachmentReferenceId) -> Void
    ) -> EnumerationCompletion {
        // TODO: iterate over the AttachmentReferences table
        fatalError("Unimplemented")
    }

    // Disregards filter.
    public func galleryItemId(
        of attachment: ReferencedAttachmentStream,
        in interval: DateInterval,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        tx: DBReadTransaction
    ) -> AttachmentReferenceId? {
        let id = attachment.reference.referenceId
        if deletedAttachmentIds.contains(id) {
            return nil
        }
        return id
    }

    /// Returns the number of attachments attached to `interaction`, whether or not they are media attachments. Disregards allowedMediaType.
    public func countAllAttachments(
        of interaction: TSInteraction,
        tx: DBReadTransaction
    ) throws -> UInt {
        guard let rowId = interaction.sqliteRowId else {
            owsFailDebug("Counting attachments for uninserted message!")
            return 0
        }
        return UInt(DependenciesBridge.shared.attachmentStore.fetchReferences(
            owner: .messageBodyAttachment(messageRowId: rowId),
            tx: tx
        ).count)
    }
}
