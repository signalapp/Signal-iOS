//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Fulfills the contract of MediaGallery, driven entirely by the AttachmentReferences table.
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

    public let threadId: Int64

    /// Media will be restricted to this type. Otherwise there is no filtering.
    public var filter: AllMediaFilter

    public init(threadId: Int64, filter: AllMediaFilter) {
        self.threadId = threadId
        self.filter = filter
    }

    // MARK: - Public Methods

    public func galleryItemIds(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [AttachmentReferenceId] {
        let query = galleryItemQuery(
            in: givenInterval,
            excluding: deletedAttachmentIds,
            offset: offset,
            ascending: ascending
        )

        do {
            return try query
                .fetchAll(tx.databaseConnection)
                .map { (record) -> AttachmentReferenceId in
                    let reference = try AttachmentReference(record: record)
                    return .init(
                        ownerId: reference.owner.id,
                        orderInOwner: record.orderInMessage
                    )
                }
        } catch {
            owsFailDebug("Error fetching media gallery records: \(error)")
            return []
        }
    }

    public func galleryItemIdsAndDates(
        in givenInterval: DateInterval? = nil,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        offset: Int,
        ascending: Bool,
        tx: DBReadTransaction
    ) -> [DatedAttachmentReferenceId] {
        let query = galleryItemQuery(
            in: givenInterval,
            excluding: deletedAttachmentIds,
            offset: offset,
            ascending: ascending
        )

        do {
            return try query
                .fetchAll(tx.databaseConnection)
                .map { (record) -> DatedAttachmentReferenceId in
                    let reference = try AttachmentReference(record: record)
                    return .init(
                        id: .init(
                            ownerId: reference.owner.id,
                            orderInOwner: record.orderInMessage
                        ),
                        receivedAtTimestamp: record.receivedAtTimestamp
                    )
                }
        } catch {
            owsFailDebug("Error fetching media gallery records: \(error)")
            return []
        }
    }

    public func recentMediaAttachments(limit: Int, tx: DBReadTransaction) -> [ReferencedAttachment] {
        do {
            let references = try recentMediaAttachmentsQuery(limit: limit)
                .fetchAll(tx.databaseConnection)
                .map(AttachmentReference.init(record:))

            let attachments = DependenciesBridge.shared.attachmentStore.fetch(
                ids: references.map(\.attachmentRowId),
                tx: tx
            )
            let attachmentsMap = Dictionary(grouping: attachments, by: \.id)
            return references.compactMap { (reference) -> ReferencedAttachment? in
                guard let attachment = attachmentsMap[reference.attachmentRowId]?.first else {
                    return nil
                }
                return .init(reference: reference, attachment: attachment)
            }
        } catch {
            owsFailDebug("Error fetching media gallery records: \(error)")
            return []
        }
    }

    public func enumerateMediaAttachments(
        in dateInterval: DateInterval,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        range: NSRange,
        tx: DBReadTransaction,
        block: (Int, ReferencedAttachment) -> Void
    ) {
        let query = enumerateMediaAttachmentsQuery(
            in: dateInterval,
            excluding: deletedAttachmentIds,
            range: range
        )

        do {
            let cursor = try query
                .fetchCursor(tx.databaseConnection)

            var index = range.lowerBound
            while let referenceRecord = try cursor.next() {
                defer { index += 1 }
                let reference = try AttachmentReference(record: referenceRecord)
                let attachment = DependenciesBridge.shared.attachmentStore.fetch(
                    id: reference.attachmentRowId,
                    tx: tx
                )
                guard let attachment else {
                    continue
                }
                block(index, .init(reference: reference, attachment: attachment))
            }
        } catch {
            owsFailDebug("Error fetching media gallery records: \(error)")
            return
        }
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
        return self.enumerateTimestamps(
            beforeDate: date,
            afterDate: nil,
            excluding: deletedAttachmentIds,
            count: count,
            ascending: false,
            tx: tx,
            block: block
        )
    }

    public func enumerateTimestamps(
        after date: Date,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        count: Int,
        tx: DBReadTransaction,
        block: (DatedAttachmentReferenceId) -> Void
    ) -> EnumerationCompletion {
        return self.enumerateTimestamps(
            beforeDate: nil,
            afterDate: date,
            excluding: deletedAttachmentIds,
            count: count,
            ascending: true,
            tx: tx,
            block: block
        )
    }

    private func enumerateTimestamps(
        beforeDate: Date?,
        afterDate: Date?,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        count: Int,
        ascending: Bool,
        tx: DBReadTransaction,
        block: (DatedAttachmentReferenceId) -> Void
    ) -> EnumerationCompletion {
        let query = enumerateTimestampsQuery(
            beforeDate: beforeDate,
            afterDate: afterDate,
            excluding: deletedAttachmentIds,
            count: count,
            ascending: ascending
        )

        do {
            let cursor = try query
                .fetchCursor(tx.databaseConnection)

            var countSoFar = 0
            while let record = try cursor.next() {
                let reference = try AttachmentReference(record: record)
                block(.init(
                    id: .init(ownerId: reference.owner.id, orderInOwner: record.orderInMessage),
                    receivedAtTimestamp: record.receivedAtTimestamp
                ))
                countSoFar += 1
            }
            if countSoFar < count {
                return .reachedEnd
            } else {
                return .finished
            }
        } catch {
            owsFailDebug("Error fetching media gallery records: \(error)")
            return .finished
        }
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

    // MARK: - Private

    internal typealias RecordType = AttachmentReference.MessageAttachmentReferenceRecord

    private func baseQuery() -> QueryInterfaceRequest<RecordType> {
        let threadIdColumn = Column(RecordType.CodingKeys.threadRowId)
        let renderingFlagColumn = Column(RecordType.CodingKeys.renderingFlag)
        let contentTypeColumn = Column(RecordType.CodingKeys.contentType)
        let ownerTypeColumn = Column(RecordType.CodingKeys.ownerType)
        let isViewOnceColumn = Column(RecordType.CodingKeys.isViewOnce)
        let isPastEditRevisionColumn = Column(RecordType.CodingKeys.ownerIsPastEditRevision)

        var query: QueryInterfaceRequest<RecordType> = RecordType
            // All finders are thread-scoped; filter to this thread.
            .filter(threadIdColumn == self.threadId)
            // Media gallery only shows body attachments; always filter to that owner type.
            .filter(ownerTypeColumn == AttachmentReference.MessageOwnerTypeRaw.bodyAttachment.rawValue)
            // Never show view once media in the gallery
            .filter(isViewOnceColumn == false)
            // Never show past edit revisions in the gallery
            .filter(isPastEditRevisionColumn == false)

        switch filter {
        case .allPhotoVideoCategory:
            query = query.filter(literal: "isVisualMediaContentType = \(true)")
        case .allAudioCategory:
            query = query
                .filter(contentTypeColumn == AttachmentReference.ContentType.audio.rawValue)
        case .otherFiles:
            query = query.filter(literal: "isInvalidOrFileContentType = \(true)")
        case .gifs:
            // NOTE: this query will not make complete use of an index; it has to combine the results
            // of two indexes and use a temp b-tree for sorting. This is suboptimal but fine in practice
            // as it will use two indexes to filter to only gifs/looping videos within the thread.
            query = query
                .filter(
                    contentTypeColumn == AttachmentReference.ContentType.animatedImage.rawValue
                    || (
                        contentTypeColumn == AttachmentReference.ContentType.video.rawValue
                        && renderingFlagColumn == AttachmentReference.RenderingFlag.shouldLoop.rawValue
                    )
                )
        case .videos:
            query = query
                .filter(contentTypeColumn == AttachmentReference.ContentType.video.rawValue)
        case .photos:
            query = query
                .filter(contentTypeColumn == AttachmentReference.ContentType.image.rawValue)
        case .voiceMessages:
            query = query
                .filter(contentTypeColumn == AttachmentReference.ContentType.audio.rawValue)
                // Whether an audio attachment is a "voice message" is encoded in the rendering flag.
                .filter(renderingFlagColumn == AttachmentReference.RenderingFlag.voiceMessage.rawValue)
        case .audioFiles:
            query = query
                .filter(contentTypeColumn == AttachmentReference.ContentType.audio.rawValue)
                // Whether an audio attachment is a "voice message" is encoded in the rendering flag.
                .filter(renderingFlagColumn != AttachmentReference.RenderingFlag.voiceMessage.rawValue)
        }
        return query
    }

    private func applyDateInterval(
        _ dateInterval: DateInterval?,
        to query: QueryInterfaceRequest<RecordType>
    ) -> QueryInterfaceRequest<RecordType> {
        if let dateInterval {
            // Both DateInterval and SQL BETWEEN are closed ranges, but rounding to millisecond precision loses range
            // at the boundaries, leading to the first millisecond of a month being considered part of the previous
            // month as well. Subtract 1ms from the end timestamp to avoid this.
            let endMillis = dateInterval.end.ows_millisecondsSince1970 - 1
            let dateColumn = Column(RecordType.CodingKeys.receivedAtTimestamp)
            return query
                .filter(dateColumn >= dateInterval.start.ows_millisecondsSince1970)
                .filter(dateColumn <= endMillis)
        } else {
            return query
        }
    }

    private func applySort(
        ascending: Bool = true,
        to query: QueryInterfaceRequest<RecordType>
    ) -> QueryInterfaceRequest<RecordType> {
        // Sort by timestamp (of the owning message)
        // Break ties between messages of the same timestamp by sqlite row id.
        // Sort attachments _within_ a given message by orderInMessage.
        let dateColumn = Column(RecordType.CodingKeys.receivedAtTimestamp)
        let ownerIdColumn = Column(RecordType.CodingKeys.ownerRowId)
        let orderInMessageColumn = Column(RecordType.CodingKeys.orderInMessage)
        if ascending {
            return query.order(dateColumn.asc, ownerIdColumn.asc, orderInMessageColumn.asc)
        } else {
            return query.order(dateColumn.desc, ownerIdColumn.desc, orderInMessageColumn.desc)
        }
    }

    private func filterOut(
        attachmentIds: Set<AttachmentReferenceId>,
        on query: QueryInterfaceRequest<RecordType>
    ) -> QueryInterfaceRequest<RecordType> {
        var query = query
        for attachmentId in attachmentIds {
            let ownerIdColumn = Column(RecordType.CodingKeys.ownerRowId)
            let orderInMessageColumn = Column(RecordType.CodingKeys.orderInMessage)

            let ownerId: Int64
            switch attachmentId.ownerId {
            case .messageBodyAttachment(let messageRowId):
                ownerId = messageRowId
            case .messageOversizeText, .messageLinkPreview, .quotedReplyAttachment, .messageSticker, .messageContactAvatar:
                // These message owner types are already filtered out.
                continue
            case .storyMessageMedia, .storyMessageLinkPreview, .threadWallpaperImage, .globalThreadWallpaperImage:
                owsFailDebug("Invalid owner type for media gallery")
                continue
            }

            if let orderInOwner = attachmentId.orderInOwner {
                query = query.filter(!(ownerIdColumn == ownerId && orderInMessageColumn == orderInOwner))
            } else {
                query = query.filter(ownerIdColumn != ownerId)
            }
        }
        return query
    }

    // MARK: Internal exposed for testing

    internal func galleryItemQuery(
        in givenInterval: DateInterval?,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        offset: Int,
        ascending: Bool
    ) -> QueryInterfaceRequest<RecordType> {
        var query = baseQuery()
            .limit(Int.max, offset: offset)

        query = applySort(ascending: ascending, to: query)
        query = applyDateInterval(givenInterval, to: query)
        query = filterOut(attachmentIds: deletedAttachmentIds, on: query)

        return query
    }

    internal func recentMediaAttachmentsQuery(
        limit: Int
    ) -> QueryInterfaceRequest<RecordType> {
        var query = baseQuery()
            .limit(limit)
        query = applySort(ascending: false, to: query)
        return query
    }

    internal func enumerateMediaAttachmentsQuery(
        in dateInterval: DateInterval,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        range: NSRange
    ) -> QueryInterfaceRequest<RecordType> {
        var query = baseQuery()
            .limit(range.length, offset: range.lowerBound)

        query = applySort(to: query)
        query = applyDateInterval(dateInterval, to: query)
        query = filterOut(attachmentIds: deletedAttachmentIds, on: query)

        return query
    }

    internal func enumerateTimestampsQuery(
        beforeDate: Date?,
        afterDate: Date?,
        excluding deletedAttachmentIds: Set<AttachmentReferenceId>,
        count: Int,
        ascending: Bool
    ) -> QueryInterfaceRequest<RecordType> {
        let dateColumn = Column(RecordType.CodingKeys.receivedAtTimestamp)

        var query = baseQuery()
            .limit(count)

        if let beforeDate {
            query = query.filter(dateColumn <= beforeDate.ows_millisecondsSince1970)
        }
        if let afterDate {
            query = query.filter(dateColumn >= afterDate.ows_millisecondsSince1970)
        }

        query = applySort(ascending: ascending, to: query)
        query = filterOut(attachmentIds: deletedAttachmentIds, on: query)

        return query
    }
}
